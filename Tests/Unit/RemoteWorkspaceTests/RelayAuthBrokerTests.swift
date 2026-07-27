// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayAuthBrokerTests.swift - Tests for relay wire protocol handshake.

import Foundation
import Network
import Testing
@testable import CocxyTerminal

private final class RelayNetworkContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

@MainActor
private final class RelayLoopbackEchoServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: .any
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<UInt16, any Error>) in
            let gate = RelayNetworkContinuationGate()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    guard let port = listener.port?.rawValue, port > 0 else {
                        continuation.resume(throwing: RelayAuthBrokerError.listenerPortUnavailable)
                        return
                    }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard gate.claim() else { return }
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        echoNextPayload(on: connection)
    }

    private func echoNextPayload(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let data, !data.isEmpty else {
                if isComplete || error != nil {
                    connection.cancel()
                }
                return
            }
            connection.send(content: data, completion: .contentProcessed { sendError in
                guard sendError == nil else {
                    connection.cancel()
                    return
                }
                Task { @MainActor [weak self] in
                    self?.echoNextPayload(on: connection)
                }
            })
        }
    }
}

@MainActor
private func sendRelayTestPayload(_ data: Data, to port: UInt16) async throws {
    let connection = NWConnection(
        host: .ipv4(.loopback),
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )

    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let gate = RelayNetworkContinuationGate()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(
                    content: data,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { error in
                        guard gate.claim() else { return }
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                )
            case .failed(let error):
                guard gate.claim() else { return }
                continuation.resume(throwing: error)
            case .cancelled:
                guard gate.claim() else { return }
                continuation.resume(throwing: CancellationError())
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    try await Task.sleep(nanoseconds: 50_000_000)
    connection.cancel()
}

@MainActor
private func waitForRelayEffect(
    within timeout: Duration = .seconds(5),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    // These effects come from tasks the scheduler must place, so a fixed sleep
    // can expire while the behaviour is perfectly correct. Waiting for the
    // effect keeps the assertion honest: it still fails if it never happens.
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
private func connectIdleRelayTestClient(to port: UInt16) async throws -> NWConnection {
    let connection = NWConnection(
        host: .ipv4(.loopback),
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )

    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let gate = RelayNetworkContinuationGate()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard gate.claim() else { return }
                continuation.resume()
            case .failed(let error):
                guard gate.claim() else { return }
                continuation.resume(throwing: error)
            case .cancelled:
                guard gate.claim() else { return }
                continuation.resume(throwing: CancellationError())
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    return connection
}

@MainActor
private func relayTestConnectionObservedClosure(_ connection: NWConnection) async -> Bool {
    await withCheckedContinuation { continuation in
        let gate = RelayNetworkContinuationGate()
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) {
            data, _, isComplete, error in
            guard gate.claim() else { return }
            continuation.resume(returning: error != nil || isComplete || data == nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard gate.claim() else { return }
            continuation.resume(returning: false)
        }
    }
}

@MainActor
private func exchangeThroughRelay(
    handshake: Data,
    payload: Data,
    port: UInt16
) async throws -> Data {
    let (connection, response) = try await openAuthenticatedRelayConnection(
        handshake: handshake,
        payload: payload,
        port: port
    )
    connection.cancel()
    return response
}

@MainActor
private func openAuthenticatedRelayConnection(
    handshake: Data,
    payload: Data,
    port: UInt16
) async throws -> (NWConnection, Data) {
    let connection = NWConnection(
        host: .ipv4(.loopback),
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )

    let response: Data = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Data, any Error>) in
        let gate = RelayNetworkContinuationGate()

        func finish(_ result: Result<Data, any Error>) {
            guard gate.claim() else { return }
            continuation.resume(with: result)
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: handshake, completion: .contentProcessed { error in
                    if let error {
                        finish(.failure(error))
                        return
                    }
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                            return
                        }
                        connection.receive(
                            minimumIncompleteLength: 1,
                            maximumLength: 65_536
                        ) { data, _, _, error in
                            if let error {
                                finish(.failure(error))
                            } else if let data {
                                finish(.success(data))
                            } else {
                                finish(.failure(CancellationError()))
                            }
                        }
                    })
                })
            case .failed(let error):
                finish(.failure(error))
            case .cancelled:
                finish(.failure(CancellationError()))
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    return (connection, response)
}

private struct RelayBootstrapProcessError: Error {
    let status: Int32
    let stderr: String
}

@MainActor
private func runRelayBootstrap(
    command: String,
    token: RelayToken,
    input: Data
) async throws -> Data {
    let process = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    var environment = ProcessInfo.processInfo.environment
    environment["COCXY_RELAY_TOKEN"] = token.secret.base64EncodedString()
    process.environment = environment
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    let timeoutTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if process.isRunning {
            process.terminate()
        }
    }
    defer { timeoutTask.cancel() }

    let status = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Int32, any Error>) in
        process.terminationHandler = { process in
            continuation.resume(returning: process.terminationStatus)
        }
        do {
            try process.run()
            stdinPipe.fileHandleForWriting.write(input)
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            continuation.resume(throwing: error)
        }
    }

    let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    guard status == 0 else {
        throw RelayBootstrapProcessError(
            status: status,
            stderr: String(decoding: errorData, as: UTF8.self)
        )
    }
    return output
}

@Suite("RelayAuthBroker")
struct RelayAuthBrokerTests {

    @Test("Broker binds an ephemeral loopback listener and rejects duplicate starts")
    @MainActor func listenerLifecycle() async throws {
        let broker = RelayAuthBroker(
            channelID: UUID(),
            token: RelayToken.generate(),
            acl: RelayACL(),
            targetPort: 9
        )

        let port = try await broker.startOnEphemeralLoopbackPort()

        #expect(port > 0)
        #expect(broker.listeningPort == port)
        do {
            _ = try await broker.startOnEphemeralLoopbackPort()
            Issue.record("Expected duplicate start to fail")
        } catch {
            #expect(error as? RelayAuthBrokerError == .alreadyRunning)
        }

        broker.stop()
        #expect(broker.listeningPort == nil)
        #expect(broker.activeConnections == 0)
    }

    @Test("Failed-port quarantine synchronously owns the exact loopback port")
    @MainActor func failedPortQuarantineOwnsPort() async throws {
        let quarantine = RelayPortQuarantine()
        let port = try #require(quarantine.start(on: 0))
        let competingQuarantine = RelayPortQuarantine()
        defer {
            quarantine.stop()
            competingQuarantine.stop()
        }

        #expect(port > 0)
        #expect(quarantine.listeningPort == port)
        #expect(competingQuarantine.start(on: port) == nil)

        quarantine.stop()
        // `stop()` releases the descriptor from a DispatchSource cancel handler
        // the scheduler must place on `.main`, so the rebind is retried until it
        // succeeds instead of guessing a fixed delay. Retrying is safe because
        // `start` records state only on its success path, leaving a failed
        // attempt without side effects.
        var rebound: UInt16?
        _ = await waitForRelayEffect {
            rebound = competingQuarantine.start(on: port)
            return rebound != nil
        }

        #expect(rebound == port)
    }

    @Test("Ordinary service bytes are rejected before the local target")
    @MainActor func ordinaryBytesRejected() async throws {
        let writer = MockAuditLogWriter()
        let channelID = UUID()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: RelayToken.generate(),
            acl: RelayACL(),
            targetPort: 9,
            auditLog: RelayAuditLog(writer: writer)
        )
        let port = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let request = Data(
            ("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
                + String(repeating: "x", count: 64)).prefix(RelayHandshake.totalSize).utf8
        )

        try await sendRelayTestPayload(request, to: port)

        #expect(await waitForRelayEffect {
            writer.entries.contains { entry in
                entry.contains("connectionRejected") && entry.contains(channelID.uuidString)
            }
        })
        #expect(broker.activeConnections == 0)
    }

    @Test("Idle clients are rejected when the handshake deadline expires")
    @MainActor func handshakeTimeout() async throws {
        let writer = MockAuditLogWriter()
        let broker = RelayAuthBroker(
            channelID: UUID(),
            token: RelayToken.generate(),
            acl: RelayACL(),
            targetPort: 9,
            auditLog: RelayAuditLog(writer: writer),
            handshakeTimeoutNanoseconds: 20_000_000
        )
        let port = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let connection = try await connectIdleRelayTestClient(to: port)
        defer { connection.cancel() }

        let rejected = await waitForRelayEffect {
            writer.entries.contains { entry in
                entry.contains("connectionRejected") && entry.contains("Handshake timed out")
            }
        }

        #expect(rejected)
        #expect(await waitForRelayEffect { broker.activeConnections == 0 })
    }

    @Test("Deactivation denies traffic while retaining the quarantine listener")
    @MainActor func deactivationRetainsListener() async throws {
        let channelID = UUID()
        let token = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: token,
            acl: RelayACL(),
            targetPort: 9
        )
        let port = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        broker.deactivate()
        let handshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: token
        )

        _ = try? await sendRelayTestPayload(handshake, to: port)

        #expect(broker.listeningPort == port)
        #expect(broker.activeConnections == 0)
    }

    @Test("Deactivation revokes an authenticated relay immediately")
    @MainActor func deactivationRevokesAuthenticatedRelay() async throws {
        let target = RelayLoopbackEchoServer()
        let targetPort = try await target.start()
        defer { target.stop() }
        let channelID = UUID()
        let token = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: token,
            acl: RelayACL(),
            targetHost: "127.0.0.1",
            targetPort: targetPort
        )
        let brokerPort = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let handshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: token
        )
        let (connection, response) = try await openAuthenticatedRelayConnection(
            handshake: handshake,
            payload: Data("before-deactivation".utf8),
            port: brokerPort
        )
        defer { connection.cancel() }
        #expect(response == Data("before-deactivation".utf8))
        #expect(broker.activeConnections == 1)

        broker.deactivate()

        #expect(broker.listeningPort == brokerPort)
        #expect(broker.activeConnections == 0)
        #expect(await relayTestConnectionObservedClosure(connection))
    }

    @Test("A valid channel handshake reaches the broker acceptance boundary")
    @MainActor func validHandshakeAcceptedByLiveBroker() async throws {
        let writer = MockAuditLogWriter()
        let channelID = UUID()
        let token = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: token,
            acl: RelayACL(),
            targetPort: 9,
            auditLog: RelayAuditLog(writer: writer)
        )
        let port = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let handshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: token
        )

        try await sendRelayTestPayload(handshake, to: port)

        #expect(await waitForRelayEffect {
            writer.entries.contains { entry in
                entry.contains("connectionAccepted") && entry.contains(channelID.uuidString)
            }
        })
    }

    @Test("Authenticated traffic is relayed bidirectionally to the configured service")
    @MainActor func authenticatedTrafficReachesTarget() async throws {
        let target = RelayLoopbackEchoServer()
        let targetPort = try await target.start()
        defer { target.stop() }
        let channelID = UUID()
        let token = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: token,
            acl: RelayACL(),
            targetHost: "127.0.0.1",
            targetPort: targetPort
        )
        let brokerPort = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let handshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: token
        )
        let payload = Data("relay-target-reached".utf8)

        let response = try await exchangeThroughRelay(
            handshake: handshake,
            payload: payload,
            port: brokerPort
        )

        #expect(response == payload)
    }

    @Test("Token rotation revokes connections authenticated by the prior token")
    @MainActor func tokenRotationRevokesActiveConnections() async throws {
        let target = RelayLoopbackEchoServer()
        let targetPort = try await target.start()
        defer { target.stop() }
        let channelID = UUID()
        let oldToken = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: oldToken,
            acl: RelayACL(),
            targetHost: "127.0.0.1",
            targetPort: targetPort
        )
        let brokerPort = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let handshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: oldToken
        )
        let (connection, response) = try await openAuthenticatedRelayConnection(
            handshake: handshake,
            payload: Data("before-rotation".utf8),
            port: brokerPort
        )
        defer { connection.cancel() }
        #expect(response == Data("before-rotation".utf8))
        #expect(broker.activeConnections == 1)

        let newToken = RelayToken.generate()
        broker.updateAuthorization(token: newToken, acl: RelayACL())

        #expect(broker.activeConnections == 0)

        let newHandshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: newToken
        )
        let (newConnection, newResponse) = try await openAuthenticatedRelayConnection(
            handshake: newHandshake,
            payload: Data("after-rotation".utf8),
            port: brokerPort
        )
        defer { newConnection.cancel() }
        #expect(newResponse == Data("after-rotation".utf8))

        #expect(await waitForRelayEffect { broker.activeConnections == 1 })
    }

    @Test("Provisioned remote client authenticates and relays real bytes")
    @MainActor func provisionedClientEndToEnd() async throws {
        let target = RelayLoopbackEchoServer()
        let targetPort = try await target.start()
        defer { target.stop() }
        let channelID = UUID()
        let token = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: token,
            acl: RelayACL(),
            targetHost: "127.0.0.1",
            targetPort: targetPort
        )
        let brokerPort = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let command = RelayClientBootstrap(
            channelID: channelID,
            remotePort: Int(brokerPort)
        ).shellCommand()
        let payload = Data("provisioned-client-ok".utf8)

        let response = try await runRelayBootstrap(
            command: command,
            token: token,
            input: payload
        )

        #expect(response == payload)
    }

    @Test("ACL updates preserve replay history for the current token")
    @MainActor func aclUpdatePreservesReplayHistory() async throws {
        let writer = MockAuditLogWriter()
        let channelID = UUID()
        let token = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: token,
            acl: RelayACL(),
            targetPort: 9,
            auditLog: RelayAuditLog(writer: writer)
        )
        let port = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let handshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: token
        )

        try await sendRelayTestPayload(handshake, to: port)
        broker.updateAuthorization(
            token: token,
            acl: RelayACL(maxConnections: 2)
        )
        try await sendRelayTestPayload(handshake, to: port)

        #expect(await waitForRelayEffect {
            writer.entries.contains { entry in
                entry.contains("connectionRejected") && entry.contains("replayDetected")
            }
        })
    }

    // MARK: - Handshake Building

    @Test("Build valid handshake produces correct format")
    func buildHandshake() {
        let channelID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        // 4 length + 16 UUID + 8 timestamp + 16 nonce + 32 HMAC.
        #expect(data.count == 76)
    }

    // MARK: - Handshake Validation

    @Test("Valid handshake is accepted")
    func validHandshake() throws {
        let channelID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: nil
        )
        #expect(result == .accepted)
    }

    @Test("Wrong channel ID is rejected")
    func wrongChannelID() throws {
        let channelID = UUID()
        let wrongID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: wrongID,
            token: token,
            replayTracker: nil
        )
        #expect(result == .rejected(.channelMismatch))
    }

    @Test("Invalid HMAC is rejected")
    func invalidHMAC() throws {
        let channelID = UUID()
        let token = RelayToken.generate()
        let wrongToken = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: wrongToken,
            replayTracker: nil
        )
        #expect(result == .rejected(.invalidSignature))
    }

    @Test("Expired timestamp is rejected")
    func expiredTimestamp() throws {
        let channelID = UUID()
        let token = RelayToken.generate()
        let oldTimestamp = UInt64(Date().timeIntervalSince1970) - 120

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: oldTimestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: nil
        )
        #expect(result == .rejected(.timestampExpired))
    }

    @Test("Truncated data is rejected")
    func truncatedData() throws {
        let data = Data(repeating: 0, count: 10)
        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: UUID(),
            token: RelayToken.generate(),
            replayTracker: nil
        )
        #expect(result == .rejected(.malformed))
    }

    @Test("Replay is rejected via tracker")
    func replayRejected() {
        let channelID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        var tracker = ReplayTracker(windowSeconds: 60)

        let first = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: &tracker
        )
        #expect(first == .accepted)

        let second = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: &tracker
        )
        #expect(second == .rejected(.replayDetected))
    }

    @Test("Same-second handshakes with distinct nonces are both accepted")
    func concurrentHandshakesAccepted() {
        let channelID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)
        let firstData = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )
        let secondData = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )
        var tracker = ReplayTracker(windowSeconds: 60)

        let first = RelayHandshake.validate(
            data: firstData,
            expectedChannelID: channelID,
            token: token,
            replayTracker: &tracker
        )
        let second = RelayHandshake.validate(
            data: secondData,
            expectedChannelID: channelID,
            token: token,
            replayTracker: &tracker
        )

        #expect(first == .accepted)
        #expect(second == .accepted)
    }

    // MARK: - Validation Result

    @Test("ValidationResult equality")
    func resultEquality() {
        #expect(RelayHandshake.ValidationResult.accepted == .accepted)
        #expect(RelayHandshake.ValidationResult.rejected(.invalidSignature)
                == .rejected(.invalidSignature))
        #expect(RelayHandshake.ValidationResult.rejected(.invalidSignature)
                != .rejected(.timestampExpired))
    }
}
