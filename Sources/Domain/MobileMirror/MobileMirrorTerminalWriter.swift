// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorTerminalWriter.swift - Exact privileged writes from paired devices.

import CocxyShared
import Foundation

@MainActor
struct MobileMirrorTerminalTarget {
    let sendText: (String) -> Bool
    let sendKeyEvent: (KeyEvent) -> Bool
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
    }

    private let grantProvider: GrantProvider
    private let targetProvider: TargetProvider

    init(
        grantProvider: @escaping GrantProvider,
        targetProvider: @escaping TargetProvider
    ) {
        self.grantProvider = grantProvider
        self.targetProvider = targetProvider
    }

    func write(
        action: MobileMirrorAction,
        to tabID: TabID,
        surfaceID: SurfaceID
    ) async throws {
        guard action.kind == .terminalControl else {
            throw MobileMirrorError.invalidAction
        }
        try await authorizeAndApply(
            effect: try Self.effect(for: action),
            tabID: tabID,
            surfaceID: surfaceID
        )
    }

    func respond(_ text: String, to tabID: TabID, surfaceID: SurfaceID) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 8_192 else {
            throw MobileMirrorError.invalidAction
        }
        try await authorizeAndApply(
            effect: .text(text + "\r"),
            tabID: tabID,
            surfaceID: surfaceID
        )
    }

    private func authorizeAndApply(
        effect: Effect,
        tabID: TabID,
        surfaceID: SurfaceID
    ) async throws {
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

        let delivered: Bool
        switch effect {
        case .text(let text):
            delivered = target.sendText(text)
        case .key(_, let event):
            delivered = target.sendKeyEvent(event)
        }
        guard delivered else {
            throw MobileMirrorError.targetUnavailable
        }
    }

    private static func effect(for action: MobileMirrorAction) throws -> Effect {
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
