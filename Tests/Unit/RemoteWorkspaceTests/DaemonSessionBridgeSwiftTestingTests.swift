// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DaemonSessionBridge", .serialized)
@MainActor
struct DaemonSessionBridgeSwiftTestingTests {
    @Test("session identifiers match the remote daemon contract")
    func sessionIdentifierValidation() {
        #expect(DaemonSessionBridge.isValidSessionIdentifier("build_1.2@$"))
        #expect(DaemonSessionBridge.isValidSessionIdentifier(String(repeating: "a", count: 128)))
        #expect(!DaemonSessionBridge.isValidSessionIdentifier("-option"))
        #expect(!DaemonSessionBridge.isValidSessionIdentifier("build session"))
        #expect(!DaemonSessionBridge.isValidSessionIdentifier("sesión"))
        #expect(!DaemonSessionBridge.isValidSessionIdentifier(String(repeating: "a", count: 129)))
    }

    @Test("snapshot repaint normalizes line endings, tracks cursor, and deduplicates state")
    func attachedSessionRoutesBidirectionalIO() async throws {
        let connection = RecordingDaemonSessionConnection()
        let snapshot = Data("prompt\nready\r\n".utf8)
        connection.outputResults = [
            .success(.success(data: [
                "data": snapshot.base64EncodedString(),
                "mode": "snapshot",
                "cursor_x": 4,
                "cursor_y": 1,
            ])),
            .success(.success(data: [
                "data": snapshot.base64EncodedString(),
                "mode": "snapshot",
                "cursor_x": 4,
                "cursor_y": 1,
            ])),
            .success(.success(data: [
                "data": snapshot.base64EncodedString(),
                "mode": "snapshot",
                "cursor_x": 5,
                "cursor_y": 1,
            ])),
        ]
        let bridge = DaemonSessionBridge(
            connection: connection,
            activePollIntervalNanoseconds: 1_000_000,
            idlePollIntervalNanoseconds: 1_000_000
        )
        var outputs: [Data] = []
        bridge.onOutput = { outputs.append($0) }

        try await bridge.attach(sessionID: "session-a")
        try await waitForDaemonBridgeCondition { outputs.count == 2 }

        #expect(outputs[0] == Data("\u{1B}[2J\u{1B}[Hprompt\r\nready\r\u{1B}[2;5H".utf8))
        #expect(outputs[1] == Data("\u{1B}[2J\u{1B}[Hprompt\r\nready\r\u{1B}[2;6H".utf8))
        #expect(!outputs[0].starts(with: Data("\u{1B}[3J".utf8)))
        #expect(bridge.enqueueInput(Data("a".utf8)))
        #expect(bridge.enqueueInput(Data("b".utf8)))

        bridge.enqueueResize(.init(
            columns: 132,
            rows: 42,
            pixelWidth: 1_320,
            pixelHeight: 840
        ))
        try await waitForDaemonBridgeCondition {
            connection.calls.filter { $0.command == DaemonCommand.sessionInput.rawValue }.count == 2
                && connection.calls.contains { $0.command == DaemonCommand.sessionResize.rawValue }
        }

        let inputCalls = connection.calls.filter {
            $0.command == DaemonCommand.sessionInput.rawValue
        }
        #expect(inputCalls.compactMap { call in
            call.arguments?["data"].flatMap { Data(base64Encoded: $0) }
        } == [Data("a".utf8), Data("b".utf8)])
        let resize = try #require(connection.calls.last {
            $0.command == DaemonCommand.sessionResize.rawValue
        })
        #expect(resize.arguments?["id"] == "session-a")
        #expect(resize.arguments?["cols"] == "132")
        #expect(resize.arguments?["rows"] == "42")
        #expect(outputs.count == 2)

        await bridge.detach()
        #expect(!bridge.isAttached)
        #expect(connection.calls.last?.command == DaemonCommand.sessionDetach.rawValue)
    }

    @Test("stream output remains byte-for-byte compatible")
    func streamOutputIsNotReframed() async throws {
        let connection = RecordingDaemonSessionConnection()
        let stream = Data("prompt\n\u{1B}[4mready\u{1B}[0m".utf8)
        connection.outputResults = [
            .success(.success(data: [
                "data": stream.base64EncodedString(),
                "mode": "stream",
                "cursor_x": 8,
                "cursor_y": 3,
            ])),
        ]
        let bridge = DaemonSessionBridge(
            connection: connection,
            activePollIntervalNanoseconds: 1_000_000,
            idlePollIntervalNanoseconds: 1_000_000
        )
        var outputs: [Data] = []
        bridge.onOutput = { outputs.append($0) }

        try await bridge.attach(sessionID: "session-stream")
        try await waitForDaemonBridgeCondition { outputs.count == 1 }

        #expect(outputs == [stream])
        await bridge.detach()
    }

    @Test("input queue rejects overflow before any bytes can be dropped silently")
    func inputQueueIsBounded() async throws {
        let connection = RecordingDaemonSessionConnection()
        let bridge = DaemonSessionBridge(
            connection: connection,
            activePollIntervalNanoseconds: 1_000_000,
            idlePollIntervalNanoseconds: 1_000_000
        )
        try await bridge.attach(sessionID: "session-b")

        let maximum = Data(repeating: 0x61, count: DaemonSessionBridge.maximumQueuedInputBytes)
        #expect(bridge.enqueueInput(maximum))
        #expect(!bridge.enqueueInput(Data([0x62])))

        await bridge.detach()
    }

    @Test("three consecutive output failures disconnect exactly once")
    func repeatedOutputFailuresDisconnect() async throws {
        let connection = RecordingDaemonSessionConnection()
        connection.outputResults = [
            .failure(DaemonProtocolError.timeout),
            .failure(DaemonProtocolError.timeout),
            .failure(DaemonProtocolError.connectionLost),
        ]
        let bridge = DaemonSessionBridge(
            connection: connection,
            activePollIntervalNanoseconds: 1_000_000,
            idlePollIntervalNanoseconds: 1_000_000
        )
        var disconnectCount = 0
        bridge.onDisconnect = { disconnectCount += 1 }

        try await bridge.attach(sessionID: "session-c")
        try await waitForDaemonBridgeCondition { !bridge.isAttached }

        #expect(disconnectCount == 1)
        #expect(bridge.attachedSessionID == nil)
    }

    @Test("invalid output responses count as failures and disconnect once")
    func invalidOutputResponsesDisconnect() async throws {
        let connection = RecordingDaemonSessionConnection()
        connection.outputResults = [
            .success(DaemonResponse(ok: false, id: "test", data: nil, error: "missing")),
            .success(.success(data: ["data": "not-base64"])),
            .success(.success(data: [:])),
        ]
        let bridge = DaemonSessionBridge(
            connection: connection,
            activePollIntervalNanoseconds: 1_000_000,
            idlePollIntervalNanoseconds: 1_000_000
        )
        var disconnectCount = 0
        bridge.onDisconnect = { disconnectCount += 1 }

        try await bridge.attach(sessionID: "session-d")
        try await waitForDaemonBridgeCondition { !bridge.isAttached }

        #expect(disconnectCount == 1)
    }

    @Test("resize failure disconnects once")
    func resizeFailureDisconnects() async throws {
        let connection = RecordingDaemonSessionConnection()
        connection.responses[DaemonCommand.sessionResize.rawValue] = DaemonResponse(
            ok: false,
            id: "test",
            data: nil,
            error: "unsupported"
        )
        let bridge = DaemonSessionBridge(
            connection: connection,
            activePollIntervalNanoseconds: 1_000_000,
            idlePollIntervalNanoseconds: 1_000_000
        )
        var disconnectCount = 0
        bridge.onDisconnect = { disconnectCount += 1 }
        try await bridge.attach(sessionID: "session-e")

        bridge.enqueueResize(.init(
            columns: 80,
            rows: 24,
            pixelWidth: 800,
            pixelHeight: 480
        ))
        try await waitForDaemonBridgeCondition { !bridge.isAttached }

        #expect(disconnectCount == 1)
    }
}

@MainActor
private final class RecordingDaemonSessionConnection: DaemonSessionRPCSending {
    struct Call: Equatable {
        let command: String
        let arguments: [String: String]?
    }

    var isConnected = true
    var outputResults: [Result<DaemonResponse, any Error>] = []
    var responses: [String: DaemonResponse] = [:]
    private(set) var calls: [Call] = []

    func sendSessionRPC(
        cmd: String,
        args: [String: String]?
    ) async throws -> DaemonResponse {
        calls.append(Call(command: cmd, arguments: args))
        if cmd == DaemonCommand.sessionOutput.rawValue, !outputResults.isEmpty {
            return try outputResults.removeFirst().get()
        }
        if cmd == DaemonCommand.sessionOutput.rawValue {
            return .success(data: ["data": "", "mode": "stream"])
        }
        if let response = responses[cmd] {
            return response
        }
        return .success(data: [:])
    }
}

private extension DaemonResponse {
    static func success(data: [String: Any]) -> DaemonResponse {
        DaemonResponse(ok: true, id: "test", data: data, error: nil)
    }
}

@MainActor
private func waitForDaemonBridgeCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(condition())
}
