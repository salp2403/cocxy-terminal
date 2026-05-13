// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyDRemoteSessionRPC")
struct CocxyDRemoteSessionRPCSwiftTestingTests {

    @Test("open sends session.open with command and terminal size")
    @MainActor func openSendsSessionOpen() async throws {
        let sender = RecordingRemoteRPCSender()
        sender.responses = [["sessionID": "s1"]]
        let rpc = CocxyDRemoteSessionRPC(sender: sender)

        let id = try await rpc.open(command: "zsh", cols: 120, rows: 40)

        #expect(id == "s1")
        #expect(sender.calls == [
            .init(method: "session.open", params: ["command": "zsh", "cols": "120", "rows": "40"])
        ])
    }

    @Test("attach sends session.attach with client id")
    @MainActor func attachSendsSessionAttach() async throws {
        let sender = RecordingRemoteRPCSender()
        let rpc = CocxyDRemoteSessionRPC(sender: sender)

        try await rpc.attach(sessionID: "s1", clientID: "c1")

        #expect(sender.calls.last == .init(method: "session.attach", params: ["sessionID": "s1", "clientID": "c1"]))
    }

    @Test("resize sends session.resize")
    @MainActor func resizeSendsSessionResize() async throws {
        let sender = RecordingRemoteRPCSender()
        let rpc = CocxyDRemoteSessionRPC(sender: sender)

        try await rpc.resize(sessionID: "s1", clientID: "c1", cols: 100, rows: 24)

        #expect(sender.calls.last == .init(
            method: "session.resize",
            params: ["sessionID": "s1", "clientID": "c1", "cols": "100", "rows": "24"]
        ))
    }

    @Test("write base64 encodes payload for session.write")
    @MainActor func writeBase64EncodesPayload() async throws {
        let sender = RecordingRemoteRPCSender()
        let rpc = CocxyDRemoteSessionRPC(sender: sender)

        try await rpc.write(sessionID: "s1", data: Data([0x00, 0x41, 0xff]))

        #expect(sender.calls.last == .init(
            method: "session.write",
            params: ["sessionID": "s1", "data": "AEH/"]
        ))
    }

    @Test("detach and close send separate RPC methods")
    @MainActor func detachAndCloseSendSeparateMethods() async throws {
        let sender = RecordingRemoteRPCSender()
        let rpc = CocxyDRemoteSessionRPC(sender: sender)

        try await rpc.detach(sessionID: "s1", clientID: "c1")
        try await rpc.close(sessionID: "s1")

        #expect(sender.calls.map(\.method) == ["session.detach", "session.close"])
    }

    @Test("resize coordinator uses smallest attached client size")
    func resizeCoordinatorUsesSmallestSize() {
        var coordinator = CocxyDRemoteResizeCoordinator()

        #expect(coordinator.update(clientID: "wide", cols: 160, rows: 50) == .init(cols: 160, rows: 50))
        #expect(coordinator.update(clientID: "narrow", cols: 90, rows: 30) == .init(cols: 90, rows: 30))
        #expect(coordinator.update(clientID: "tiny", cols: 120, rows: 20) == .init(cols: 90, rows: 20))
        #expect(coordinator.remove(clientID: "narrow") == .init(cols: 120, rows: 20))
    }
}
