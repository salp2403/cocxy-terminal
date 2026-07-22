// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SOCKS5Proxy.swift - Authenticated app-owned SOCKS5 broker.

import Darwin
import Foundation
import Network

@MainActor
protocol SOCKS5ProxyLifecycle: AnyObject {
    var port: Int { get }
    var activeConnectionCount: Int { get }
    var isReady: Bool { get }
    var failureHandler: (@MainActor @Sendable (String) -> Void)? { get set }
    func start() async throws
    func activate()
    func stop()
    func releaseAfterSessionTermination()
}

/// SOCKS5 CONNECT broker that requires RFC 1929 authentication before reading
/// a destination and opens no secondary TCP listener.
@MainActor
final class SOCKS5Proxy: SOCKS5ProxyLifecycle {
    private enum Phase {
        case greeting
        case sendingMethodSelection
        case authentication
        case sendingAuthenticationResult
        case request
        case openingTransport
        case relaying
    }

    private final class ClientSession: @unchecked Sendable {
        let id = UUID()
        let connection: NWConnection
        let acceptanceSequence: UInt64
        var phase: Phase = .greeting
        var isAuthenticated = false
        var buffer = Data()
        var timeoutTask: Task<Void, Never>?
        var readinessTask: Task<Void, Never>?
        var transport: (any ProxyUpstreamTransport)?
        var relay: ProxyConnectionRelay?

        init(connection: NWConnection, acceptanceSequence: UInt64) {
            self.connection = connection
            self.acceptanceSequence = acceptanceSequence
        }
    }

    private static let maximumHandshakeBytes = 8_192
    static let maximumPendingAuthenticationConnections = 16
    private static let maximumAuthenticatedConnections = 128

    let port: Int
    private(set) var activeConnectionCount = 0
    private(set) var acceptedConnectionCount = 0
    private(set) var authenticationAttemptCount = 0
    private(set) var authenticationFailureCount = 0
    private(set) var targetRejectionCount = 0
    var isReady: Bool { listeners.isReady }
    var failureHandler: (@MainActor @Sendable (String) -> Void)?

    private let credentials: ProxyCredentials
    private weak var forwarder: (any PortForwarding)?
    private let profileID: UUID
    private let connectionLeaseID: UUID
    private let allowedTargets: Set<ProxyTarget>?
    private let targetMappings: [ProxyTarget: ProxyTarget]?
    private let listeners: LoopbackTCPListenerGroup
    private let authenticationTimeoutNanoseconds: UInt64
    private let upstreamSetupTimeoutNanoseconds: UInt64

    private var acceptsConnections = false
    private var sessions: [UUID: ClientSession] = [:]
    private var nextAcceptanceSequence: UInt64 = 0

    init(
        listenPort: Int,
        credentials: ProxyCredentials,
        forwarder: any PortForwarding,
        profileID: UUID,
        connectionLeaseID: UUID,
        allowedTargets: Set<ProxyTarget>? = nil,
        targetMappings: [ProxyTarget: ProxyTarget]? = nil,
        authenticationTimeoutNanoseconds: UInt64 = 3_000_000_000,
        upstreamSetupTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        port = listenPort
        self.credentials = credentials
        self.forwarder = forwarder
        self.profileID = profileID
        self.connectionLeaseID = connectionLeaseID
        self.allowedTargets = allowedTargets
        self.targetMappings = targetMappings
        self.authenticationTimeoutNanoseconds = authenticationTimeoutNanoseconds
        self.upstreamSetupTimeoutNanoseconds = upstreamSetupTimeoutNanoseconds
        listeners = LoopbackTCPListenerGroup(port: listenPort)
        listeners.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listeners.failureHandler = { [weak self] error in
            self?.handleListenerFailure(error.localizedDescription)
        }
    }

    func start() async throws {
        try await listeners.start()
    }

    func activate() {
        acceptsConnections = true
    }

    func stop() {
        acceptsConnections = false
        listeners.stop()
        let currentSessions = Array(sessions.values)
        sessions.removeAll()
        activeConnectionCount = 0
        for session in currentSessions {
            session.timeoutTask?.cancel()
            session.timeoutTask = nil
            session.readinessTask?.cancel()
            session.readinessTask = nil
            if let relay = session.relay {
                relay.close()
            } else {
                session.transport?.cancel()
                session.transport = nil
                session.connection.stateUpdateHandler = nil
                session.connection.cancel()
            }
        }
    }

    func releaseAfterSessionTermination() {
        stop()
    }

    private func handleListenerFailure(_ reason: String) {
        let shouldReport = acceptsConnections
        stop()
        if shouldReport {
            failureHandler?(reason)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        guard acceptsConnections else {
            connection.cancel()
            return
        }

        evictOldestPendingAuthenticationIfNeeded()
        guard authenticatedConnectionCount < Self.maximumAuthenticatedConnections,
              pendingAuthenticationCount < Self.maximumPendingAuthenticationConnections else {
            connection.cancel()
            return
        }

        nextAcceptanceSequence &+= 1
        let session = ClientSession(
            connection: connection,
            acceptanceSequence: nextAcceptanceSequence
        )
        acceptedConnectionCount += 1
        sessions[session.id] = session
        updateConnectionCount()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.closeSession(id: session.id) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        scheduleTimeout(
            for: session,
            nanoseconds: authenticationTimeoutNanoseconds
        )
        receiveHandshakeData(for: session)
    }

    private func receiveHandshakeData(for session: ClientSession) {
        guard sessions[session.id] === session,
              session.phase != .relaying else { return }
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.sessions[session.id] === session else { return }
                if error != nil || isComplete {
                    self.closeSession(id: session.id)
                    return
                }
                guard let data, !data.isEmpty else {
                    self.receiveHandshakeData(for: session)
                    return
                }
                guard session.buffer.count + data.count <= Self.maximumHandshakeBytes else {
                    self.closeSession(id: session.id)
                    return
                }
                session.buffer.append(data)
                self.advanceHandshake(for: session)
            }
        }
    }

    private func advanceHandshake(for session: ClientSession) {
        guard sessions[session.id] === session else { return }
        switch session.phase {
        case .greeting:
            parseGreeting(for: session)
        case .authentication:
            parseAuthentication(for: session)
        case .request:
            parseRequest(for: session)
        case .sendingMethodSelection, .sendingAuthenticationResult, .openingTransport, .relaying:
            break
        }
    }

    private func parseGreeting(for session: ClientSession) {
        guard session.buffer.count >= 2 else {
            receiveHandshakeData(for: session)
            return
        }
        let version = session.buffer[session.buffer.startIndex]
        let methodCount = Int(session.buffer[session.buffer.startIndex + 1])
        guard version == 0x05, methodCount > 0 else {
            send(Data([0x05, 0xff]), to: session, closeAfterSending: true)
            return
        }
        let frameLength = 2 + methodCount
        guard session.buffer.count >= frameLength else {
            receiveHandshakeData(for: session)
            return
        }
        let methods = session.buffer[2..<frameLength]
        session.buffer = Data(session.buffer.dropFirst(frameLength))
        guard methods.contains(0x02) else {
            send(Data([0x05, 0xff]), to: session, closeAfterSending: true)
            return
        }

        session.phase = .sendingMethodSelection
        send(Data([0x05, 0x02]), to: session) { [weak self] in
            guard let self, self.sessions[session.id] === session else { return }
            session.phase = .authentication
            self.advanceOrReceive(for: session)
        }
    }

    private func parseAuthentication(for session: ClientSession) {
        guard session.buffer.count >= 2 else {
            receiveHandshakeData(for: session)
            return
        }
        let version = session.buffer[session.buffer.startIndex]
        let usernameLength = Int(session.buffer[session.buffer.startIndex + 1])
        guard version == 0x01, usernameLength > 0 else {
            send(Data([0x01, 0x01]), to: session, closeAfterSending: true)
            return
        }
        let passwordLengthIndex = 2 + usernameLength
        guard session.buffer.count > passwordLengthIndex else {
            receiveHandshakeData(for: session)
            return
        }
        let passwordLength = Int(session.buffer[session.buffer.startIndex + passwordLengthIndex])
        guard passwordLength > 0 else {
            send(Data([0x01, 0x01]), to: session, closeAfterSending: true)
            return
        }
        let frameLength = passwordLengthIndex + 1 + passwordLength
        guard session.buffer.count >= frameLength else {
            receiveHandshakeData(for: session)
            return
        }

        let username = Data(session.buffer[2..<passwordLengthIndex])
        let passwordStart = passwordLengthIndex + 1
        let password = Data(session.buffer[passwordStart..<frameLength])
        session.buffer = Data(session.buffer.dropFirst(frameLength))
        authenticationAttemptCount += 1
        guard credentials.matches(username: username, password: password) else {
            authenticationFailureCount += 1
            send(Data([0x01, 0x01]), to: session, closeAfterSending: true)
            return
        }
        guard promoteToAuthenticated(session) else {
            send(Data([0x01, 0x01]), to: session, closeAfterSending: true)
            return
        }

        session.phase = .sendingAuthenticationResult
        send(Data([0x01, 0x00]), to: session) { [weak self] in
            guard let self, self.sessions[session.id] === session else { return }
            session.phase = .request
            self.advanceOrReceive(for: session)
        }
    }

    private func parseRequest(for session: ClientSession) {
        guard session.buffer.count >= 4 else {
            receiveHandshakeData(for: session)
            return
        }
        guard session.buffer[0] == 0x05, session.buffer[2] == 0x00 else {
            sendRequestReply(0x01, to: session, closeAfterSending: true)
            return
        }
        guard session.buffer[1] == 0x01 else {
            sendRequestReply(0x07, to: session, closeAfterSending: true)
            return
        }

        let parsed: (host: String, port: Int, frameLength: Int)?
        switch session.buffer[3] {
        case 0x01:
            parsed = parseIPv4Request(session.buffer)
        case 0x03:
            parsed = parseDomainRequest(session.buffer)
        case 0x04:
            parsed = parseIPv6Request(session.buffer)
        default:
            sendRequestReply(0x08, to: session, closeAfterSending: true)
            return
        }
        guard let parsed else {
            receiveHandshakeData(for: session)
            return
        }

        let target: ProxyTarget
        do {
            target = try ProxyTarget(host: parsed.host, port: parsed.port)
        } catch {
            sendRequestReply(0x04, to: session, closeAfterSending: true)
            return
        }
        guard allowedTargets?.contains(target) != false else {
            targetRejectionCount += 1
            sendRequestReply(0x02, to: session, closeAfterSending: true)
            return
        }
        let upstreamTarget: ProxyTarget
        if let targetMappings {
            guard let mappedTarget = targetMappings[target] else {
                targetRejectionCount += 1
                sendRequestReply(0x02, to: session, closeAfterSending: true)
                return
            }
            upstreamTarget = mappedTarget
        } else {
            upstreamTarget = target
        }
        session.buffer = Data(session.buffer.dropFirst(parsed.frameLength))
        let initialData = session.buffer
        session.buffer.removeAll(keepingCapacity: false)
        session.phase = .openingTransport

        do {
            guard let forwarder,
                  forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
                throw SSHMultiplexerError.notConnected
            }
            let transport = try forwarder.openProxyTransport(
                to: upstreamTarget,
                for: profileID,
                expectedConnectionLeaseID: connectionLeaseID
            )
            session.transport = transport
            guard forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
                transport.cancel()
                session.transport = nil
                throw SSHMultiplexerError.notConnected
            }
            waitForTransportReadiness(
                transport,
                initialData: initialData,
                session: session
            )
        } catch {
            sendRequestReply(0x01, to: session, closeAfterSending: true)
        }
    }

    private func waitForTransportReadiness(
        _ transport: any ProxyUpstreamTransport,
        initialData: Data,
        session: ClientSession
    ) {
        let sessionID = session.id
        session.readinessTask = Task { @MainActor [weak self] in
            do {
                try await transport.waitUntilReady()
                guard !Task.isCancelled,
                      let self,
                      let currentSession = self.sessions[sessionID],
                      currentSession.transport === transport else {
                    transport.cancel()
                    return
                }
                guard transport.isRunning,
                      let forwarder = self.forwarder,
                      forwarder.connectionLeaseID(for: self.profileID)
                        == self.connectionLeaseID else {
                    throw SSHMultiplexerError.notConnected
                }
                currentSession.readinessTask = nil
                currentSession.timeoutTask?.cancel()
                currentSession.timeoutTask = nil
                self.sendRequestReply(0x00, to: currentSession) { [weak self] in
                    guard let self,
                          let session = self.sessions[sessionID],
                          let transport = session.transport else { return }
                    let relay = ProxyConnectionRelay(
                        client: session.connection,
                        upstream: transport,
                        onClose: { [weak self] in
                            self?.finishSession(id: sessionID)
                        }
                    )
                    session.phase = .relaying
                    session.transport = nil
                    session.relay = relay
                    relay.start(initialClientData: initialData)
                }
            } catch {
                guard let self,
                      let currentSession = self.sessions[sessionID],
                      currentSession.transport === transport else {
                    transport.cancel()
                    return
                }
                currentSession.readinessTask = nil
                self.sendRequestReply(0x01, to: currentSession, closeAfterSending: true)
            }
        }
    }

    private func parseIPv4Request(_ data: Data) -> (String, Int, Int)? {
        let frameLength = 10
        guard data.count >= frameLength else { return nil }
        var address = in_addr()
        withUnsafeMutableBytes(of: &address) { bytes in
            bytes.copyBytes(from: data[4..<8])
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
            return nil
        }
        return (String(cString: buffer), parsePort(data, offset: 8), frameLength)
    }

    private func parseDomainRequest(_ data: Data) -> (String, Int, Int)? {
        guard data.count >= 5 else { return nil }
        let length = Int(data[4])
        guard length > 0 else { return ("", 0, 5) }
        let frameLength = 5 + length + 2
        guard data.count >= frameLength,
              let host = String(data: data[5..<(5 + length)], encoding: .utf8) else {
            return nil
        }
        return (host, parsePort(data, offset: 5 + length), frameLength)
    }

    private func parseIPv6Request(_ data: Data) -> (String, Int, Int)? {
        let frameLength = 22
        guard data.count >= frameLength else { return nil }
        var address = in6_addr()
        withUnsafeMutableBytes(of: &address) { bytes in
            bytes.copyBytes(from: data[4..<20])
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else {
            return nil
        }
        return (String(cString: buffer), parsePort(data, offset: 20), frameLength)
    }

    private func parsePort(_ data: Data, offset: Int) -> Int {
        (Int(data[offset]) << 8) | Int(data[offset + 1])
    }

    private func advanceOrReceive(for session: ClientSession) {
        if session.buffer.isEmpty {
            receiveHandshakeData(for: session)
        } else {
            advanceHandshake(for: session)
        }
    }

    private var pendingAuthenticationCount: Int {
        sessions.values.lazy.filter { !$0.isAuthenticated }.count
    }

    private var authenticatedConnectionCount: Int {
        sessions.values.lazy.filter(\.isAuthenticated).count
    }

    private func evictOldestPendingAuthenticationIfNeeded() {
        guard pendingAuthenticationCount >= Self.maximumPendingAuthenticationConnections,
              let oldest = sessions.values
                .filter({ !$0.isAuthenticated })
                .min(by: { $0.acceptanceSequence < $1.acceptanceSequence }) else {
            return
        }
        closeSession(id: oldest.id)
    }

    private func promoteToAuthenticated(_ session: ClientSession) -> Bool {
        guard sessions[session.id] === session,
              !session.isAuthenticated,
              authenticatedConnectionCount < Self.maximumAuthenticatedConnections else {
            return false
        }
        session.isAuthenticated = true
        scheduleTimeout(
            for: session,
            nanoseconds: upstreamSetupTimeoutNanoseconds
        )
        return true
    }

    private func scheduleTimeout(for session: ClientSession, nanoseconds: UInt64) {
        session.timeoutTask?.cancel()
        session.timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.closeSession(id: session.id)
        }
    }

    private func sendRequestReply(
        _ reply: UInt8,
        to session: ClientSession,
        closeAfterSending: Bool = false,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        send(
            Data([0x05, reply, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            to: session,
            closeAfterSending: closeAfterSending,
            completion: completion
        )
    }

    private func send(
        _ data: Data,
        to session: ClientSession,
        closeAfterSending: Bool = false,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        session.connection.send(content: data, completion: .contentProcessed { [weak self, weak session] error in
            Task { @MainActor in
                guard let self, let session,
                      self.sessions[session.id] === session else { return }
                if error != nil || closeAfterSending {
                    self.closeSession(id: session.id)
                } else {
                    completion?()
                }
            }
        })
    }

    private func closeSession(id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.timeoutTask?.cancel()
        session.timeoutTask = nil
        session.readinessTask?.cancel()
        session.readinessTask = nil
        updateConnectionCount()
        if let relay = session.relay {
            session.relay = nil
            relay.close()
        } else {
            session.transport?.cancel()
            session.transport = nil
            session.connection.stateUpdateHandler = nil
            session.connection.cancel()
        }
    }

    private func finishSession(id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.timeoutTask?.cancel()
        session.timeoutTask = nil
        session.readinessTask?.cancel()
        session.readinessTask = nil
        session.transport = nil
        session.relay = nil
        updateConnectionCount()
    }

    private func updateConnectionCount() {
        activeConnectionCount = sessions.count
    }
}
