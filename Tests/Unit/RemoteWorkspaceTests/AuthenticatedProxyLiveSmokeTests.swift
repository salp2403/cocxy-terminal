// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Network
import Testing
@testable import CocxyTerminal

private final class LiveProxyContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

@MainActor
private final class LiveSSHProxyForwarder: PortForwarding {
    let leaseID = UUID()
    private let profile: RemoteConnectionProfile
    private let multiplexer: SSHMultiplexer
    private let identity: SSHControlMasterIdentity
    private(set) var openedTargets: [ProxyTarget] = []

    init(
        profile: RemoteConnectionProfile,
        multiplexer: SSHMultiplexer,
        identity: SSHControlMasterIdentity
    ) {
        self.profile = profile
        self.multiplexer = multiplexer
        self.identity = identity
    }

    func connectionLeaseID(for profileID: UUID) -> UUID? {
        profileID == profile.id ? leaseID : nil
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        _ = forward
        _ = profileID
    }

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        for profileID: UUID
    ) throws {
        _ = forward
        _ = profileID
    }

    func openProxyTransport(
        to target: ProxyTarget,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> any ProxyUpstreamTransport {
        guard profileID == profile.id,
              expectedConnectionLeaseID == leaseID else {
            throw SSHMultiplexerError.notConnected
        }
        let transport = try multiplexer.openDirectTCPTransport(
            to: target,
            on: profile,
            expectedControlMaster: identity
        )
        openedTargets.append(target)
        return transport
    }
}

@MainActor
private func connectLiveProxyClient(to port: Int) async throws -> NWConnection {
    let connection = NWConnection(
        host: .ipv4(.loopback),
        port: NWEndpoint.Port(rawValue: UInt16(port))!,
        using: .tcp
    )
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let gate = LiveProxyContinuationGate()
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
private func sendLiveProxyData(_ data: Data, on connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        })
    }
}

@MainActor
private func finishLiveProxyWrites(_ data: Data, on connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.send(
            content: data,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        )
    }
}

@MainActor
private func receiveLiveProxyData(count: Int, on connection: NWConnection) async throws -> Data {
    var result = Data()
    while result.count < count {
        let next = try await receiveLiveProxyChunk(
            maximumLength: count - result.count,
            on: connection
        )
        result.append(next)
    }
    return result
}

@MainActor
private func receiveLiveProxyResponse(
    containing marker: Data,
    on connection: NWConnection
) async throws -> Data {
    var response = Data()
    while response.range(of: marker) == nil, response.count < 65_536 {
        response.append(try await receiveLiveProxyChunk(maximumLength: 4_096, on: connection))
    }
    guard response.range(of: marker) != nil else {
        throw ProxyUpstreamTransportError.closed
    }
    return response
}

@MainActor
private func receiveLiveProxyChunk(
    maximumLength: Int,
    on connection: NWConnection
) async throws -> Data {
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Data, any Error>) in
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: maximumLength
        ) { data, _, isComplete, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data, !data.isEmpty {
                continuation.resume(returning: data)
            } else if isComplete {
                continuation.resume(throwing: ProxyUpstreamTransportError.closed)
            } else {
                continuation.resume(returning: Data())
            }
        }
    }
}

@Suite("Authenticated proxy real SSH smoke", .serialized)
struct AuthenticatedProxyLiveSmokeTests {
    private static func availableLoopbackPort() throws -> Int {
        try LoopbackTestPortAllocator.freshPort()
    }

    @Test("Wrong credentials fail closed and valid credentials relay through attested MUX")
    @MainActor func authenticatedBrokersRelayThroughRealSSH() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COCXY_RUN_SUPERVISED_SSH_SMOKE"] == "1" else { return }
        let sshPort = try #require(Int(environment["COCXY_SSH_SMOKE_PORT"] ?? ""))
        let user = try #require(environment["COCXY_SSH_SMOKE_USER"])
        let identityFile = try #require(environment["COCXY_SSH_SMOKE_IDENTITY"])
        let knownHostsFile = try #require(environment["COCXY_SSH_SMOKE_KNOWN_HOSTS"])
        let targetHTTPPort = try #require(Int(environment["COCXY_SSH_SMOKE_HTTP_PORT"] ?? ""))
        let profile = RemoteConnectionProfile(
            name: "authenticated-proxy-smoke",
            host: "127.0.0.1",
            user: user,
            port: sshPort,
            identityFile: identityFile,
            strictHostKeyChecking: "no",
            knownHostsFile: knownHostsFile,
            batchMode: true,
            autoReconnect: false
        )
        let multiplexer = SSHMultiplexer()
        let executor = SystemProcessExecutor()
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        let forwarder = LiveSSHProxyForwarder(
            profile: profile,
            multiplexer: multiplexer,
            identity: identity
        )
        let socksCredentials = ProxyCredentials(password: "live-socks-secret")
        let httpCredentials = ProxyCredentials(password: "live-http-secret")
        let socksProxy = SOCKS5Proxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: socksCredentials,
            forwarder: forwarder,
            profileID: profile.id,
            connectionLeaseID: forwarder.leaseID
        )
        let httpProxy = HTTPConnectProxy(
            listenPort: try Self.availableLoopbackPort(),
            credentials: httpCredentials,
            forwarder: forwarder,
            profileID: profile.id,
            connectionLeaseID: forwarder.leaseID
        )
        var disconnected = false
        defer {
            socksProxy.stop()
            httpProxy.stop()
            if !disconnected {
                try? multiplexer.disconnect(profile: profile, executor: executor)
            }
        }
        try await socksProxy.start()
        try await httpProxy.start()
        socksProxy.activate()
        httpProxy.activate()

        let rejectedSOCKS = try await connectLiveProxyClient(to: socksProxy.port)
        try await sendLiveProxyData(Data([0x05, 0x01, 0x02]), on: rejectedSOCKS)
        #expect(try await receiveLiveProxyData(count: 2, on: rejectedSOCKS) == Data([0x05, 0x02]))
        let username = Data(ProxyCredentials.username.utf8)
        let wrongPassword = Data("wrong".utf8)
        var rejectedAuthentication = Data([0x01, UInt8(username.count)])
        rejectedAuthentication.append(username)
        rejectedAuthentication.append(UInt8(wrongPassword.count))
        rejectedAuthentication.append(wrongPassword)
        rejectedAuthentication.append(Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0, 0]))
        try await sendLiveProxyData(rejectedAuthentication, on: rejectedSOCKS)
        #expect(try await receiveLiveProxyData(count: 2, on: rejectedSOCKS) == Data([0x01, 0x01]))
        rejectedSOCKS.cancel()
        #expect(forwarder.openedTargets.isEmpty)

        let socksClient = try await connectLiveProxyClient(to: socksProxy.port)
        try await sendLiveProxyData(Data([0x05, 0x01, 0x02]), on: socksClient)
        #expect(try await receiveLiveProxyData(count: 2, on: socksClient) == Data([0x05, 0x02]))
        let password = Data(socksCredentials.password.utf8)
        var authentication = Data([0x01, UInt8(username.count)])
        authentication.append(username)
        authentication.append(UInt8(password.count))
        authentication.append(password)
        try await sendLiveProxyData(authentication, on: socksClient)
        #expect(try await receiveLiveProxyData(count: 2, on: socksClient) == Data([0x01, 0x00]))
        let targetPort = UInt16(targetHTTPPort)
        try await sendLiveProxyData(
            Data([
                0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1,
                UInt8(targetPort >> 8), UInt8(targetPort & 0xff),
            ]),
            on: socksClient
        )
        #expect(try await receiveLiveProxyData(count: 10, on: socksClient)[1] == 0x00)
        try await sendLiveProxyData(
            Data("GET / HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n".utf8),
            on: socksClient
        )
        let socksResponse = try await receiveLiveProxyResponse(
            containing: Data("forward-ok".utf8),
            on: socksClient
        )
        #expect(String(decoding: socksResponse, as: UTF8.self).contains("forward-ok"))
        socksClient.cancel()

        let rejectedHTTP = try await connectLiveProxyClient(to: httpProxy.port)
        try await sendLiveProxyData(
            Data(
                (
                    "CONNECT invalid-target HTTP/1.1\r\n" +
                    "Proxy-Authorization: Basic " +
                    "\(socksCredentials.basicAuthorizationValue)\r\n\r\n"
                ).utf8
            ),
            on: rejectedHTTP
        )
        let rejectedHTTPResponse = try await receiveLiveProxyResponse(
            containing: Data("\r\n\r\n".utf8),
            on: rejectedHTTP
        )
        #expect(String(decoding: rejectedHTTPResponse, as: UTF8.self).hasPrefix("HTTP/1.1 407"))
        rejectedHTTP.cancel()
        #expect(forwarder.openedTargets.count == 1)

        let httpClient = try await connectLiveProxyClient(to: httpProxy.port)
        let connectRequest = "CONNECT 127.0.0.1:\(targetHTTPPort) HTTP/1.1\r\n" +
            "Proxy-Authorization: Basic \(httpCredentials.basicAuthorizationValue)\r\n\r\n"
        try await sendLiveProxyData(Data(connectRequest.utf8), on: httpClient)
        let connectResponse = try await receiveLiveProxyResponse(
            containing: Data("\r\n\r\n".utf8),
            on: httpClient
        )
        #expect(String(decoding: connectResponse, as: UTF8.self).hasPrefix("HTTP/1.1 200"))
        try await finishLiveProxyWrites(
            Data("GET / HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n".utf8),
            on: httpClient
        )
        let httpResponse = try await receiveLiveProxyResponse(
            containing: Data("forward-ok".utf8),
            on: httpClient
        )
        #expect(String(decoding: httpResponse, as: UTF8.self).contains("forward-ok"))
        httpClient.cancel()

        let target = try ProxyTarget(host: "127.0.0.1", port: targetHTTPPort)
        #expect(forwarder.openedTargets == [target, target])
        try multiplexer.disconnect(profile: profile, executor: executor)
        disconnected = true
    }
}
