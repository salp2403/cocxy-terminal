// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror privileged terminal writes")
@MainActor
struct MobileMirrorTerminalWriterSwiftTestingTests {
    @Test("one MiB paste uses a digest-bound grant and bracketed delivery")
    func largePasteUsesSafeAuthorizedDelivery() async throws {
        let tabID = TabID()
        let surfaceID = SurfaceID()
        let channelID = UUID()
        let identity = MobileMirrorTerminalAuthorizationIdentity()
        let capture = MobileMirrorTerminalWriteCapture()
        let context = SocketPrivilegedCommandContext(
            scope: .terminalSurface,
            windowControllerIdentifier: ObjectIdentifier(identity),
            tabID: tabID.rawValue,
            workingDirectory: "/tmp",
            surfaceID: surfaceID.rawValue,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "Paired terminal"
        )
        let active = MobileMirrorActivePairing(
            channelID: channelID,
            identity: MobileMirrorClientIdentity(remoteAddress: "127.0.0.1", userAgent: "Phone"),
            pairedAt: Date(),
            expiresAt: Date().addingTimeInterval(60)
        )
        let timing = TerminalPasteDeliveryTiming(
            standardChunkMaxUTF8Bytes: 64 * 1_024,
            agentChunkMaxUTF8Bytes: 64 * 1_024,
            standardDelayNanoseconds: 0,
            agentDelayNanoseconds: 0
        )
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                capture.requests.append(request)
                return MobileMirrorPrivilegedAuthorization.grant(
                    for: request,
                    channelID: channelID,
                    activePairing: active,
                    tabID: tabID,
                    context: context
                )
            },
            targetProvider: { _ in capture.pasteTarget },
            pasteDeliveryCoordinator: TerminalPasteDeliveryCoordinator(timing: timing)
        )
        let payload = String(
            repeating: "p",
            count: MobileMirrorTerminalControl.maximumPasteUTF8Bytes
        )
        let action = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "paste",
            text: payload
        )

        try await writer.write(action: action, to: tabID, surfaceID: surfaceID)

        let request = try #require(capture.requests.first)
        #expect(request.params["text"] == nil)
        #expect(request.params["pasteByteCount"] == String(payload.utf8.count))
        #expect(request.params["pasteDigest"] == MobileMirrorPairingAuthority.digest(Data(payload.utf8)))
        #expect(capture.texts.first?.hasPrefix(TerminalPasteDelivery.bracketedPasteStart) == true)
        #expect(capture.texts.last == TerminalPasteDelivery.bracketedPasteEnd)
        let delivered = capture.texts.enumerated().map { index, chunk in
            if index == 0 { return String(chunk.dropFirst(TerminalPasteDelivery.bracketedPasteStart.count)) }
            if index == capture.texts.count - 1 { return "" }
            return chunk
        }.joined()
        #expect(delivered == payload)
        _ = identity
    }

    @Test("terminal writer reaches the target through the real paired-session authority")
    func writerUsesRealAuthorityEndToEnd() async throws {
        let tabID = TabID()
        let surfaceID = SurfaceID()
        let channelID = UUID()
        let identity = MobileMirrorTerminalAuthorizationIdentity()
        let capture = MobileMirrorTerminalWriteCapture()
        let active = MobileMirrorActivePairing(
            channelID: channelID,
            identity: MobileMirrorClientIdentity(remoteAddress: "127.0.0.1", userAgent: "Phone"),
            pairedAt: Date(),
            expiresAt: Date().addingTimeInterval(60)
        )
        let context = SocketPrivilegedCommandContext(
            scope: .terminalSurface,
            windowControllerIdentifier: ObjectIdentifier(identity),
            tabID: tabID.rawValue,
            workingDirectory: "/tmp",
            surfaceID: surfaceID.rawValue,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "Paired terminal"
        )
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                MobileMirrorPrivilegedAuthorization.grant(
                    for: request,
                    channelID: channelID,
                    activePairing: active,
                    tabID: tabID,
                    context: context
                )
            },
            targetProvider: { authorizedContext in
                authorizedContext == context ? capture.target : nil
            }
        )

        try await writer.write(
            action: Self.characterAction("x"),
            to: tabID,
            surfaceID: surfaceID
        )

        #expect(capture.texts == ["x"])
        #expect(capture.requests.isEmpty)
        _ = identity
    }

    @Test("terminal bytes are not sent when desktop authorization is denied")
    func deniedAuthorizationDoesNotWrite() async {
        let surfaceID = SurfaceID()
        let capture = MobileMirrorTerminalWriteCapture()
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { _ in nil },
            targetProvider: { _ in
                capture.targetRequests += 1
                return capture.target
            }
        )

        await #expect(throws: MobileMirrorError.authorizationDenied) {
            try await writer.write(
                action: Self.characterAction("x"),
                to: TabID(),
                surfaceID: surfaceID
            )
        }
        #expect(capture.targetRequests == 0)
        #expect(capture.texts.isEmpty)
        #expect(capture.keyCodes.isEmpty)
    }

    @Test("arrow input consumes one exact grant and stays on the mode-aware key path")
    func arrowUsesModeAwareKeyPath() async throws {
        let tabID = TabID()
        let surfaceID = SurfaceID()
        let capture = MobileMirrorTerminalWriteCapture()
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                capture.requests.append(request)
                return SocketPrivilegedCommandAuthorizationGrant(
                    request: request,
                    context: Self.context(tabID: tabID, surfaceID: surfaceID)
                )
            },
            targetProvider: { _ in capture.target }
        )
        let action = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "key",
            key: "left",
            ctrl: true
        )

        try await writer.write(action: action, to: tabID, surfaceID: surfaceID)

        #expect(capture.requests.count == 1)
        #expect(capture.requests.first?.command == .sendKey)
        #expect(capture.requests.first?.params["tabId"] == tabID.rawValue.uuidString)
        #expect(capture.requests.first?.params["surfaceId"] == surfaceID.rawValue.uuidString)
        #expect(capture.requests.first?.params["key"] == "left")
        #expect(capture.texts.isEmpty)
        #expect(capture.keyCodes == [123])
        #expect(capture.modifierValues == [KeyModifiers.control.rawValue])
    }

    @Test("agent response is bound with return and a grant cannot authorize another request")
    func responseIsExactAndGrantIsOneUse() async throws {
        let tabID = TabID()
        let surfaceID = SurfaceID()
        let capture = MobileMirrorTerminalWriteCapture()
        var retainedGrant: SocketPrivilegedCommandAuthorizationGrant?
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                capture.requests.append(request)
                if retainedGrant == nil {
                    retainedGrant = SocketPrivilegedCommandAuthorizationGrant(
                        request: request,
                        context: Self.context(tabID: tabID, surfaceID: surfaceID)
                    )
                }
                return retainedGrant
            },
            targetProvider: { _ in capture.target }
        )

        try await writer.respond("continue", to: tabID, surfaceID: surfaceID)
        await #expect(throws: MobileMirrorError.authorizationDenied) {
            try await writer.respond("again", to: tabID, surfaceID: surfaceID)
        }

        #expect(capture.requests.first?.command == .send)
        #expect(capture.requests.first?.params["text"] == "continue\r")
        #expect(capture.texts == ["continue\r"])
    }

    @Test("a grant for another surface cannot authorize terminal input")
    func grantForAnotherSurfaceFailsClosed() async {
        let tabID = TabID()
        let requestedSurfaceID = SurfaceID()
        let capture = MobileMirrorTerminalWriteCapture()
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                SocketPrivilegedCommandAuthorizationGrant(
                    request: request,
                    context: Self.context(tabID: tabID, surfaceID: SurfaceID())
                )
            },
            targetProvider: { _ in capture.target }
        )

        await #expect(throws: MobileMirrorError.authorizationDenied) {
            try await writer.write(
                action: Self.characterAction("x"),
                to: tabID,
                surfaceID: requestedSurfaceID
            )
        }
        #expect(capture.texts.isEmpty)
    }

    @Test("failed engine delivery is reported instead of acknowledged")
    func failedEngineDeliveryIsReported() async {
        let tabID = TabID()
        let surfaceID = SurfaceID()
        let capture = MobileMirrorTerminalWriteCapture()
        capture.deliversText = false
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                SocketPrivilegedCommandAuthorizationGrant(
                    request: request,
                    context: Self.context(tabID: tabID, surfaceID: surfaceID)
                )
            },
            targetProvider: { _ in capture.target }
        )

        await #expect(throws: MobileMirrorError.targetUnavailable) {
            try await writer.write(
                action: Self.characterAction("x"),
                to: tabID,
                surfaceID: surfaceID
            )
        }
        #expect(capture.texts == ["x"])
    }

    private static func characterAction(_ text: String) -> MobileMirrorAction {
        MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "key",
            text: text
        )
    }

    private static func context(
        tabID: TabID,
        surfaceID: SurfaceID
    ) -> SocketPrivilegedCommandContext {
        SocketPrivilegedCommandContext(
            scope: .terminalSurface,
            windowControllerIdentifier: nil,
            tabID: tabID.rawValue,
            workingDirectory: "/tmp",
            surfaceID: surfaceID.rawValue,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "Test terminal"
        )
    }
}

private final class MobileMirrorTerminalAuthorizationIdentity {}

@MainActor
private final class MobileMirrorTerminalWriteCapture {
    var requests: [SocketPrivilegedCommandAuthorizationRequest] = []
    var texts: [String] = []
    var keyCodes: [UInt16] = []
    var modifierValues: [UInt] = []
    var targetRequests = 0
    var deliversText = true
    var deliversKeyEvent = true

    var target: MobileMirrorTerminalTarget {
        MobileMirrorTerminalTarget(
            sendText: { [weak self] text in
                self?.texts.append(text)
                return self?.deliversText == true
            },
            sendKeyEvent: { [weak self] event in
                self?.keyCodes.append(event.keyCode)
                self?.modifierValues.append(event.modifiers.rawValue)
                return self?.deliversKeyEvent == true
            }
        )
    }

    var pasteTarget: MobileMirrorTerminalTarget {
        MobileMirrorTerminalTarget(
            sendText: { [weak self] text in
                self?.texts.append(text)
                return self?.deliversText == true
            },
            sendKeyEvent: { _ in false },
            pasteConfiguration: {
                TerminalPasteDeliveryConfiguration(
                    usesBracketedPaste: true,
                    agentPaced: false
                )
            }
        )
    }
}
