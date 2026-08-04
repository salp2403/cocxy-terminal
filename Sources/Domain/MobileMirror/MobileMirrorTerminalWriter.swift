// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorTerminalWriter.swift - Exact privileged writes from paired devices.

import CocxyShared
import Foundation

@MainActor
struct MobileMirrorTerminalTarget {
    let sendText: (String) -> Bool
    let sendKeyEvent: (KeyEvent) -> Bool
    let pasteConfiguration: () -> TerminalPasteDeliveryConfiguration?
    let isAvailable: () -> Bool

    init(
        sendText: @escaping (String) -> Bool,
        sendKeyEvent: @escaping (KeyEvent) -> Bool,
        pasteConfiguration: @escaping () -> TerminalPasteDeliveryConfiguration? = { nil },
        isAvailable: @escaping () -> Bool = { true }
    ) {
        self.sendText = sendText
        self.sendKeyEvent = sendKeyEvent
        self.pasteConfiguration = pasteConfiguration
        self.isAvailable = isAvailable
    }
}

@MainActor
final class MobileMirrorTerminalWriter {
    typealias GrantProvider = @MainActor (
        SocketPrivilegedCommandAuthorizationRequest
    ) async -> SocketPrivilegedCommandAuthorizationGrant?
    typealias TargetProvider = @MainActor (
        SocketPrivilegedCommandContext
    ) -> MobileMirrorTerminalTarget?

    private enum Effect {
        case text(String)
        case key(name: String, event: KeyEvent)
        case paste(String)
    }

    struct PreparedWrite {
        let execute: @MainActor () async throws -> TerminalPasteDeliveryResult
    }

    private let grantProvider: GrantProvider
    private let targetProvider: TargetProvider
    private let pasteDeliveryCoordinator: TerminalPasteDeliveryCoordinator

    init(
        grantProvider: @escaping GrantProvider,
        targetProvider: @escaping TargetProvider,
        pasteDeliveryCoordinator: TerminalPasteDeliveryCoordinator = TerminalPasteDeliveryCoordinator()
    ) {
        self.grantProvider = grantProvider
        self.targetProvider = targetProvider
        self.pasteDeliveryCoordinator = pasteDeliveryCoordinator
    }

    func write(
        action: MobileMirrorAction,
        to tabID: TabID,
        surfaceID: SurfaceID
    ) async throws {
        let prepared = try await prepare(
            action: action,
            tabID: tabID,
            surfaceID: surfaceID
        )
        _ = try await prepared.execute()
    }

    func respond(_ text: String, to tabID: TabID, surfaceID: SurfaceID) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 8_192 else {
            throw MobileMirrorError.invalidAction
        }
        let prepared = try await authorize(
            effect: .text(text + "\r"),
            tabID: tabID,
            surfaceID: surfaceID
        )
        _ = try await prepared.execute()
    }

    func prepare(
        action: MobileMirrorAction,
        tabID: TabID,
        surfaceID: SurfaceID
    ) async throws -> PreparedWrite {
        guard action.kind == .terminalControl,
              action.surfaceID == surfaceID.rawValue.uuidString else {
            throw MobileMirrorError.invalidAction
        }
        return try await authorize(
            effect: try Self.effect(for: action),
            tabID: tabID,
            surfaceID: surfaceID
        )
    }

    private func authorize(
        effect: Effect,
        tabID: TabID,
        surfaceID: SurfaceID
    ) async throws -> PreparedWrite {
        let command: CLICommandName
        let params: [String: String]
        switch effect {
        case .text(let text):
            command = .send
            params = [
                "tabId": tabID.rawValue.uuidString,
                "surfaceId": surfaceID.rawValue.uuidString,
                "text": text,
            ]
        case .key(let name, _):
            command = .sendKey
            params = [
                "tabId": tabID.rawValue.uuidString,
                "surfaceId": surfaceID.rawValue.uuidString,
                "key": name,
            ]
        case .paste(let text):
            command = .send
            params = [
                "pasteByteCount": String(text.utf8.count),
                "pasteDigest": MobileMirrorPairingAuthority.digest(Data(text.utf8)),
                "surfaceId": surfaceID.rawValue.uuidString,
                "tabId": tabID.rawValue.uuidString,
            ]
        }
        let socketRequest = SocketRequest(
            id: UUID().uuidString,
            command: command.rawValue,
            params: params
        )
        guard let request = SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: socketRequest
        ), let grant = await grantProvider(request), grant.consume(for: request),
              grant.context.tabID == tabID.rawValue,
              grant.context.surfaceID == surfaceID.rawValue,
              let target = targetProvider(grant.context) else {
            throw MobileMirrorError.authorizationDenied
        }

        switch effect {
        case .text(let text):
            return PreparedWrite {
                guard target.sendText(text) else {
                    throw MobileMirrorError.targetUnavailable
                }
                return .completed
            }
        case .key(_, let event):
            return PreparedWrite {
                guard target.sendKeyEvent(event) else {
                    throw MobileMirrorError.targetUnavailable
                }
                return .completed
            }
        case .paste(let text):
            guard let configuration = target.pasteConfiguration() else {
                throw MobileMirrorError.targetUnavailable
            }
            return PreparedWrite { [pasteDeliveryCoordinator] in
                let result = await pasteDeliveryCoordinator.deliverReportingProgress(
                    text,
                    to: surfaceID,
                    configuration: configuration,
                    isAvailable: target.isAvailable,
                    sendText: target.sendText
                )
                guard result != .notDelivered else {
                    throw MobileMirrorError.targetUnavailable
                }
                return result
            }
        }
    }

    private static func effect(for action: MobileMirrorAction) throws -> Effect {
        if action.controlType == "paste" {
            guard let text = action.text, !text.isEmpty,
                  text.utf8.count <= MobileMirrorTerminalControl.maximumPasteUTF8Bytes else {
                throw MobileMirrorError.invalidAction
            }
            return .paste(text)
        }
        let modifiers = keyModifiers(for: action)
        if let name = action.key?.lowercased() {
            guard let keyCode = keyCode(for: name) else {
                throw MobileMirrorError.invalidAction
            }
            return .key(
                name: name,
                event: KeyEvent(
                    characters: characters(for: name),
                    keyCode: keyCode,
                    modifiers: modifiers,
                    isKeyDown: true
                )
            )
        }

        guard let text = action.text, !text.isEmpty else {
            throw MobileMirrorError.invalidAction
        }
        if action.ctrl {
            guard text.count == 1,
                  let controlText = ControlCharacterMapper.controlCharacterText(forLetter: text) else {
                throw MobileMirrorError.invalidAction
            }
            return .text((action.alt ? "\u{1B}" : "") + controlText)
        }
        return .text((action.alt ? "\u{1B}" : "") + text)
    }

    private static func keyModifiers(for action: MobileMirrorAction) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if action.shift { modifiers.insert(.shift) }
        if action.alt { modifiers.insert(.option) }
        if action.ctrl { modifiers.insert(.control) }
        return modifiers
    }

    private static func keyCode(for name: String) -> UInt16? {
        switch name {
        case "escape": return 53
        case "tab": return 48
        case "enter": return 36
        case "backspace": return 51
        case "left": return 123
        case "right": return 124
        case "down": return 125
        case "up": return 126
        default: return nil
        }
    }

    private static func characters(for name: String) -> String? {
        switch name {
        case "escape": return "\u{1B}"
        case "tab": return "\t"
        case "enter": return "\r"
        case "backspace": return "\u{7F}"
        default: return nil
        }
    }
}
