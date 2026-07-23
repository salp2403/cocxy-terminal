// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonManagerTests.swift - Tests for daemon manager state machine.

import Foundation
import Testing
@testable import CocxyTerminal

private final class DaemonTestTransport: ProxyUpstreamTransport, @unchecked Sendable {
    typealias ReceiveCompletion = @Sendable (Result<Data?, any Error>) -> Void

    let processIdentifier: Int32 = 74_001
    let diagnosticOutput = ""

    private let lock = NSLock()
    private var runningStorage = true
    private var readyStorage: Bool
    private var readyContinuations: [CheckedContinuation<Void, any Error>] = []
    private var pendingReceive: ReceiveCompletion?
    private var queuedResponses: [Data] = []
    private var sentFramesStorage: [Data] = []
    private let automaticallyRespond: Bool

    init(ready: Bool = true, automaticallyRespond: Bool = true) {
        self.readyStorage = ready
        self.automaticallyRespond = automaticallyRespond
    }

    var isRunning: Bool { lock.withLock { runningStorage } }
    var sentFrames: [Data] { lock.withLock { sentFramesStorage } }

    func waitUntilReady() async throws {
        if lock.withLock({ readyStorage && runningStorage }) { return }
        try await withCheckedThrowingContinuation { continuation in
            let outcome: Result<Bool, any Error> = lock.withLock {
                guard runningStorage else {
                    return .failure(DaemonProtocolError.connectionLost)
                }
                if readyStorage { return .success(true) }
                readyContinuations.append(continuation)
                return .success(false)
            }
            switch outcome {
            case .success(true):
                continuation.resume()
            case .success(false):
                break
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    func makeReady() {
        let continuations: [CheckedContinuation<Void, any Error>] = lock.withLock {
            readyStorage = true
            let continuations = readyContinuations
            readyContinuations.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume() }
    }

    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        let running = lock.withLock {
            sentFramesStorage.append(data)
            return runningStorage
        }
        guard running else {
            completion(.failure(DaemonProtocolError.connectionLost))
            return
        }
        completion(.success(()))
        guard automaticallyRespond, let response = Self.response(to: data) else { return }
        deliver(response)
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    ) {
        _ = maximumLength
        let queued: Data? = lock.withLock {
            if !queuedResponses.isEmpty {
                return queuedResponses.removeFirst()
            }
            pendingReceive = completion
            return nil
        }
        if let queued {
            completion(.success(queued))
        }
    }

    func closeWrite() {}

    func cancel() {
        let continuations: [CheckedContinuation<Void, any Error>] = lock.withLock {
            runningStorage = false
            let continuations = readyContinuations
            readyContinuations.removeAll()
            pendingReceive = nil
            queuedResponses.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume(throwing: DaemonProtocolError.connectionLost) }
    }

    private func deliver(_ data: Data) {
        let receiver: ReceiveCompletion? = lock.withLock {
            if let receiver = pendingReceive {
                pendingReceive = nil
                return receiver
            }
            queuedResponses.append(data)
            return nil
        }
        receiver?(.success(data))
    }

    private static func response(to frame: Data) -> Data? {
        guard let tab = frame.firstIndex(of: UInt8(ascii: "\t")) else { return nil }
        let jsonData = Data(frame[(tab + 1)...])
        guard let request = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let id = request["id"] as? String else { return nil }
        let response: [String: Any] = [
            "ok": true,
            "id": id,
            "data": ["pong": true]
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: response) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
    }
}

@MainActor
private final class MockDaemonTransportProvider: DaemonTransportProviding {
    var leases: [UUID: UUID] = [:]
    var transports: [UUID: DaemonTestTransport] = [:]
    private(set) var openings: [(profileID: UUID, leaseID: UUID, port: Int)] = []

    func connectionLeaseID(for profileID: UUID) -> UUID? {
        leases[profileID]
    }

    func openDaemonTransport(
        remotePort: Int,
        profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> DaemonTransportBinding {
        guard leases[profileID] == expectedConnectionLeaseID,
              let transport = transports[profileID] else {
            throw DaemonProtocolError.connectionLost
        }
        openings.append((profileID, expectedConnectionLeaseID, remotePort))
        return DaemonTransportBinding(
            profileID: profileID,
            connectionLeaseID: expectedConnectionLeaseID,
            transport: transport
        )
    }
}

@Suite("DaemonManager")
struct DaemonManagerTests {

    @Test("Initial state is notDeployed")
    @MainActor func initialState() {
        let executor = MockDeployExecutor()
        let deployer = DaemonDeployer(executor: executor)
        let provider = MockDaemonTransportProvider()
        let profileID = UUID()
        let manager = DaemonManagerImpl(deployer: deployer, transportProvider: provider)
        #expect(manager.state(for: profileID) == .notDeployed)
    }

    @Test("Profiles retain isolated daemon state and SSH leases")
    @MainActor func profileIsolation() async throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let executor = configuredExecutor(profileIDs: [firstProfileID, secondProfileID])
        let deployer = DaemonDeployer(executor: executor)
        let provider = MockDaemonTransportProvider()
        let firstLeaseID = UUID()
        let secondLeaseID = UUID()
        provider.leases = [firstProfileID: firstLeaseID, secondProfileID: secondLeaseID]
        provider.transports = [
            firstProfileID: DaemonTestTransport(),
            secondProfileID: DaemonTestTransport()
        ]
        let manager = DaemonManagerImpl(deployer: deployer, transportProvider: provider)

        try await manager.connect(profileID: firstProfileID)
        try await manager.connect(profileID: secondProfileID)

        #expect(manager.state(for: firstProfileID) == .running(version: "1.1.0", uptime: 0))
        #expect(manager.state(for: secondProfileID) == .running(version: "1.1.0", uptime: 0))
        #expect(provider.openings.map(\.profileID) == [firstProfileID, secondProfileID])
        #expect(provider.openings.allSatisfy { $0.port == 45_321 })

        manager.invalidate(
            profileID: firstProfileID,
            expectedConnectionLeaseID: firstLeaseID
        )

        #expect(manager.state(for: firstProfileID) == .unreachable)
        #expect(manager.state(for: secondProfileID) == .running(version: "1.1.0", uptime: 0))
        #expect(try manager.connection(for: secondProfileID).connectionLeaseID == secondLeaseID)
    }

    @Test("Running is published only after transport readiness and authenticated ping")
    @MainActor func waitsForReadyAuthenticatedPing() async throws {
        let profileID = UUID()
        let executor = configuredExecutor(profileIDs: [profileID])
        let deployer = DaemonDeployer(executor: executor)
        let provider = MockDaemonTransportProvider()
        let leaseID = UUID()
        let transport = DaemonTestTransport(ready: false)
        provider.leases[profileID] = leaseID
        provider.transports[profileID] = transport
        let manager = DaemonManagerImpl(deployer: deployer, transportProvider: provider)

        let connectionTask = Task { try await manager.connect(profileID: profileID) }
        for _ in 0..<20 where provider.openings.isEmpty {
            await Task.yield()
        }
        #expect(provider.openings.count == 1)
        #expect(manager.state(for: profileID) == .deploying)

        transport.makeReady()
        try await connectionTask.value

        #expect(manager.state(for: profileID) == .running(version: "1.1.0", uptime: 0))
        let firstFrame = try #require(transport.sentFrames.first)
        #expect(String(decoding: firstFrame, as: UTF8.self).hasPrefix("\(Self.capability)\t"))
    }

    @Test("Daemon handshake times out and tears down a silent transport")
    @MainActor func handshakeTimeout() async throws {
        let profileID = UUID()
        let leaseID = UUID()
        let transport = DaemonTestTransport(automaticallyRespond: false)
        let connection = DaemonConnection(
            profileID: profileID,
            connectionLeaseID: leaseID,
            requestTimeout: 0.1,
            authorizationIsCurrent: { true }
        )
        let clock = ContinuousClock()
        let started = clock.now

        do {
            try await connection.connect(transport: transport, capability: Self.capability)
            Issue.record("Expected a silent daemon handshake to time out")
        } catch {
            #expect(error as? DaemonProtocolError == .timeout)
        }

        #expect(started.duration(to: clock.now) < .seconds(1))
        #expect(!connection.isConnected)
        #expect(!transport.isRunning)
    }

    @Test("DaemonState equality")
    func stateEquality() {
        #expect(DaemonState.notDeployed == DaemonState.notDeployed)
        #expect(DaemonState.deploying == DaemonState.deploying)
        #expect(DaemonState.stopped == DaemonState.stopped)
        #expect(DaemonState.upgrading == DaemonState.upgrading)
        #expect(DaemonState.unreachable == DaemonState.unreachable)
        #expect(DaemonState.running(version: "1.0", uptime: 0) == DaemonState.running(version: "1.0", uptime: 0))
        #expect(DaemonState.running(version: "1.0", uptime: 0) != DaemonState.running(version: "2.0", uptime: 0))
    }

    @Test("DaemonProtocolError equality")
    func errorEquality() {
        #expect(DaemonProtocolError.invalidResponse == DaemonProtocolError.invalidResponse)
        #expect(DaemonProtocolError.connectionLost == DaemonProtocolError.connectionLost)
        #expect(DaemonProtocolError.timeout == DaemonProtocolError.timeout)
        #expect(DaemonProtocolError.daemonNotRunning == DaemonProtocolError.daemonNotRunning)
        #expect(DaemonProtocolError.encodingFailed == DaemonProtocolError.encodingFailed)
        #expect(DaemonProtocolError.authenticationFailed == DaemonProtocolError.authenticationFailed)
    }

    @Test("DaemonSessionInfo parsing from dict")
    func sessionInfoParsing() {
        let dict: [String: Any] = [
            "id": "sess-1",
            "title": "my-session",
            "pid": 12345,
            "age": 60.0,
            "status": "running"
        ]
        let info = DaemonSessionInfo.from(dict: dict)
        #expect(info?.id == "sess-1")
        #expect(info?.title == "my-session")
        #expect(info?.pid == 12345)
        #expect(info?.status == "running")
    }

    @Test("DaemonSessionInfo returns nil for invalid dict")
    func sessionInfoInvalid() {
        let dict: [String: Any] = ["foo": "bar"]
        let info = DaemonSessionInfo.from(dict: dict)
        #expect(info == nil)
    }

    @Test("FileChangeEvent parsing from dict")
    func fileChangeEventParsing() {
        let dict: [String: Any] = [
            "path": "/home/user/file.txt",
            "type": "modified"
        ]
        let event = FileChangeEvent.from(dict: dict)
        #expect(event?.path == "/home/user/file.txt")
        #expect(event?.type == .modified)
    }

    @Test("FileChangeEvent returns nil for invalid type")
    func fileChangeEventInvalidType() {
        let dict: [String: Any] = [
            "path": "/home/user/file.txt",
            "type": "invalid"
        ]
        let event = FileChangeEvent.from(dict: dict)
        #expect(event == nil)
    }

    @Test("All FileChangeEvent types are parseable")
    func allChangeTypes() {
        for type in ["modified", "created", "deleted"] {
            let dict: [String: Any] = ["path": "/test", "type": type]
            let event = FileChangeEvent.from(dict: dict)
            #expect(event != nil)
        }
    }

    private static let capability = String(repeating: "a1", count: 32)

    @MainActor
    private func configuredExecutor(profileIDs: [UUID]) -> MockDeployExecutor {
        let executor = MockDeployExecutor()
        for profileID in profileIDs {
            executor.responses[DaemonDeployer.pingCommand(profileID: profileID)] =
                #"{"ok":true,"data":{"pong":true}}"#
            executor.responses[
                DaemonDeployer.readRemotePortCommand(profileID: profileID)
            ] = "45321\n"
            executor.responses[
                DaemonDeployer.readRemoteCapabilityCommand(profileID: profileID)
            ] = Self.capability + "\n"
        }
        executor.responses[
            "grep '^COCXYD_VERSION=' \(DaemonDeployer.remotePath) 2>/dev/null | cut -d'\"' -f2"
        ] = "1.1.0\n"
        return executor
    }
}
