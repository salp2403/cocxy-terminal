// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror privileged terminal writes")
@MainActor
struct MobileMirrorTerminalWriterSwiftTestingTests {
    @Test("terminal bytes are not sent when desktop authorization is denied")
    func deniedAuthorizationDoesNotWrite() async {
        let capture = MobileMirrorTerminalWriteCapture()
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { _ in nil },
            targetProvider: { _ in
                capture.targetRequests += 1
                return capture.target
            }
        )

        await #expect(throws: MobileMirrorError.authorizationDenied) {
            try await writer.write(action: Self.characterAction("x"), to: TabID())
        }
        #expect(capture.targetRequests == 0)
        #expect(capture.texts.isEmpty)
        #expect(capture.keyCodes.isEmpty)
    }

    @Test("arrow input consumes one exact grant and stays on the mode-aware key path")
    func arrowUsesModeAwareKeyPath() async throws {
        let tabID = TabID()
        let capture = MobileMirrorTerminalWriteCapture()
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                capture.requests.append(request)
                return SocketPrivilegedCommandAuthorizationGrant(
                    request: request,
                    context: Self.context(tabID: tabID)
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

        try await writer.write(action: action, to: tabID)

        #expect(capture.requests.count == 1)
        #expect(capture.requests.first?.command == .sendKey)
        #expect(capture.requests.first?.params["tabId"] == tabID.rawValue.uuidString)
        #expect(capture.requests.first?.params["key"] == "left")
        #expect(capture.texts.isEmpty)
        #expect(capture.keyCodes == [123])
        #expect(capture.modifierValues == [KeyModifiers.control.rawValue])
    }

    @Test("agent response is bound with return and a grant cannot authorize another request")
    func responseIsExactAndGrantIsOneUse() async throws {
        let tabID = TabID()
        let capture = MobileMirrorTerminalWriteCapture()
        var retainedGrant: SocketPrivilegedCommandAuthorizationGrant?
        let writer = MobileMirrorTerminalWriter(
            grantProvider: { request in
                capture.requests.append(request)
                if retainedGrant == nil {
                    retainedGrant = SocketPrivilegedCommandAuthorizationGrant(
                        request: request,
                        context: Self.context(tabID: tabID)
                    )
                }
                return retainedGrant
            },
            targetProvider: { _ in capture.target }
        )

        try await writer.respond("continue", to: tabID)
        await #expect(throws: MobileMirrorError.authorizationDenied) {
            try await writer.respond("again", to: tabID)
        }

        #expect(capture.requests.first?.command == .send)
        #expect(capture.requests.first?.params["text"] == "continue\r")
        #expect(capture.texts == ["continue\r"])
    }

    private static func characterAction(_ text: String) -> MobileMirrorAction {
        MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "key",
            text: text
        )
    }

    private static func context(tabID: TabID) -> SocketPrivilegedCommandContext {
        SocketPrivilegedCommandContext(
            scope: .terminalSurface,
            windowControllerIdentifier: nil,
            tabID: tabID.rawValue,
            workingDirectory: "/tmp",
            surfaceID: UUID(),
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "Test terminal"
        )
    }
}

@MainActor
private final class MobileMirrorTerminalWriteCapture {
    var requests: [SocketPrivilegedCommandAuthorizationRequest] = []
    var texts: [String] = []
    var keyCodes: [UInt16] = []
    var modifierValues: [UInt] = []
    var targetRequests = 0

    var target: MobileMirrorTerminalTarget {
        MobileMirrorTerminalTarget(
            sendText: { [weak self] in self?.texts.append($0) },
            sendKeyEvent: { [weak self] event in
                self?.keyCodes.append(event.keyCode)
                self?.modifierValues.append(event.modifiers.rawValue)
            }
        )
    }
}
