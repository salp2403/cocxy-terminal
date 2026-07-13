// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HTTPConnectProxy.swift - Authenticated HTTP CONNECT proxy.

import Foundation
import Network

// MARK: - HTTP CONNECT Parser

enum HTTPConnectParser {
    struct ConnectTarget: Equatable, Sendable {
        let host: String
        let port: Int
    }

    enum ParseError: Error, LocalizedError {
        case notConnectMethod
        case malformedRequestLine
        case missingPort
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .notConnectMethod: return "Request is not a CONNECT method"
            case .malformedRequestLine: return "Malformed HTTP request line"
            case .missingPort: return "CONNECT target missing port number"
            case .invalidPort: return "Invalid port number in CONNECT target"
            }
        }
    }

    static func parse(requestLine: String) throws -> ConnectTarget {
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[2] == "HTTP/1.0" || parts[2] == "HTTP/1.1" else {
            throw ParseError.malformedRequestLine
        }
        guard parts[0] == "CONNECT" else { throw ParseError.notConnectMethod }
        return try parseHostPort(String(parts[1]))
    }

    private static func parseHostPort(_ target: String) throws -> ConnectTarget {
        let rawHost: String
        let portString: String
        if target.hasPrefix("[") {
            guard let closingBracket = target.firstIndex(of: "]"),
                  closingBracket > target.startIndex else {
                throw ParseError.malformedRequestLine
            }
            let suffix = target[target.index(after: closingBracket)...]
            guard suffix.hasPrefix(":"), suffix.count > 1 else {
                throw ParseError.missingPort
            }
            rawHost = String(target[target.index(after: target.startIndex)..<closingBracket])
            portString = String(suffix.dropFirst())
        } else {
            guard let separator = target.lastIndex(of: ":") else {
                throw ParseError.missingPort
            }
            rawHost = String(target[..<separator])
            portString = String(target[target.index(after: separator)...])
        }

        guard let port = Int(portString), (1...65_535).contains(port) else {
            throw ParseError.invalidPort
        }
        do {
            let validated = try ProxyTarget(host: rawHost, port: port)
            return ConnectTarget(host: validated.host, port: validated.port)
        } catch let error as ProxyTargetError {
            switch error {
            case .invalidHost:
                throw ParseError.malformedRequestLine
            case .invalidPort:
                throw ParseError.invalidPort
            }
        }
    }

    static let connectionEstablishedResponse =
        "HTTP/1.1 200 Connection Established\r\n\r\n"

    static let authenticationRequiredResponse =
        "HTTP/1.1 407 Proxy Authentication Required\r\n" +
        "Proxy-Authenticate: Basic realm=\"Cocxy\"\r\n" +
        "Content-Length: 0\r\n" +
        "Connection: close\r\n\r\n"

    static func badGatewayResponse(reason: String) -> String {
        let sanitized = reason
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "HTTP/1.1 502 Bad Gateway\r\n" +
            "Content-Length: \(sanitized.utf8.count)\r\n" +
            "Connection: close\r\n\r\n\(sanitized)"
    }

    static let badRequestResponse =
        "HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request"

    static let serviceUnavailableResponse =
        "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
}

enum HTTPConnectAuthenticationResult: Equatable {
    case authorized(requestLine: String)
    case authenticationRequired
    case malformed
}

/// Authenticates complete HTTP headers without interpreting the CONNECT target.
enum HTTPConnectAuthenticator {
    static func authenticate(
        headerData: Data,
        credentials: ProxyCredentials
    ) -> HTTPConnectAuthenticationResult {
        guard let request = String(data: headerData, encoding: .utf8),
              !request.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && $0 != "\r" && $0 != "\n" && $0 != "\t"
              }) else {
            return .malformed
        }
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .malformed
        }

        var authorizationValues: [String] = []
        for line in lines.dropFirst() where !line.isEmpty {
            guard line.first != " " && line.first != "\t",
                  let separator = line.firstIndex(of: ":") else {
                return .malformed
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .malformed }
            if name.caseInsensitiveCompare("Proxy-Authorization") == .orderedSame {
                authorizationValues.append(
                    line[line.index(after: separator)...]
                        .trimmingCharacters(in: .whitespaces)
                )
            }
        }

        guard authorizationValues.count == 1 else {
            return .authenticationRequired
        }
        let fields = authorizationValues[0].split(
            whereSeparator: { $0 == " " || $0 == "\t" }
        )
        guard fields.count == 2,
              fields[0].caseInsensitiveCompare("Basic") == .orderedSame,
              credentials.matchesBasicAuthorization(String(fields[1])) else {
            return .authenticationRequired
        }
        return .authorized(requestLine: requestLine)
    }
}

enum HTTPConnectProxyError: Error, LocalizedError {
    case connectionLeaseChanged

    var errorDescription: String? {
        "SSH connection changed before the HTTP proxy operation completed"
    }
}

// MARK: - Lifecycle

@MainActor
protocol HTTPConnectProxyLifecycle: AnyObject {
    var port: Int { get }
    var activeConnectionCount: Int { get }
    var isReady: Bool { get }
    var failureHandler: (@MainActor @Sendable (String) -> Void)? { get set }
    func start() async throws
    func activate()
    func stop()
    func releaseAfterSessionTermination()
}

/// Loopback-only HTTP CONNECT broker with per-activation Basic authentication.
@MainActor
final class HTTPConnectProxy: HTTPConnectProxyLifecycle {
    private final class ClientSession: @unchecked Sendable {
        let id = UUID()
        let connection: NWConnection
        let acceptanceSequence: UInt64
        var isAuthenticated = false
        var headerBuffer = Data()
        var timeoutTask: Task<Void, Never>?
        var readinessTask: Task<Void, Never>?
        var transport: (any ProxyUpstreamTransport)?
        var relay: ProxyConnectionRelay?

        init(connection: NWConnection, acceptanceSequence: UInt64) {
            self.connection = connection
            self.acceptanceSequence = acceptanceSequence
        }
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let maximumHeaderBytes = 16_384
    static let maximumPendingAuthenticationConnections = 16
    private static let maximumAuthenticatedConnections = 128

    let port: Int
    private(set) var activeConnectionCount = 0
    var isReady: Bool { listeners.isReady }
    var failureHandler: (@MainActor @Sendable (String) -> Void)?

    private let credentials: ProxyCredentials
    private weak var forwarder: (any PortForwarding)?
    private let profileID: UUID
    private let connectionLeaseID: UUID
    private let listeners: LoopbackTCPListenerGroup
    private let authenticationTimeoutNanoseconds: UInt64
    private let upstreamSetupTimeoutNanoseconds: UInt64

    private var acceptsConnections = false
    private var sessions: [UUID: ClientSession] = [:]
    private var nextAcceptanceSequence: UInt64 = 0

    init(
        listenPort: Int = 8_888,
        credentials: ProxyCredentials = .generate(),
        forwarder: any PortForwarding,
        profileID: UUID,
        connectionLeaseID: UUID,
        authenticationTimeoutNanoseconds: UInt64 = 3_000_000_000,
        upstreamSetupTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        port = listenPort
        self.credentials = credentials
        self.forwarder = forwarder
        self.profileID = profileID
        self.connectionLeaseID = connectionLeaseID
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
        stopLocalTraffic()
    }

    func releaseAfterSessionTermination() {
        stopLocalTraffic()
    }

    private func handleListenerFailure(_ reason: String) {
        let shouldReport = acceptsConnections
        stopLocalTraffic()
        if shouldReport {
            failureHandler?(reason)
        }
    }

    private func stopLocalTraffic() {
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
        receiveHeaders(for: session)
    }

    private func receiveHeaders(for session: ClientSession) {
        guard sessions[session.id] === session else { return }
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.sessions[session.id] === session else { return }
                if error != nil || isComplete {
                    self.closeSession(id: session.id)
                    return
                }
                guard let data, !data.isEmpty else {
                    self.receiveHeaders(for: session)
                    return
                }
                guard session.headerBuffer.count + data.count <= Self.maximumHeaderBytes else {
                    self.sendAndClose(HTTPConnectParser.badRequestResponse, session: session)
                    return
                }
                session.headerBuffer.append(data)
                guard let headerRange = session.headerBuffer.range(of: Self.headerTerminator) else {
                    self.receiveHeaders(for: session)
                    return
                }
                let headerData = Data(session.headerBuffer[..<headerRange.upperBound])
                let initialData = Data(session.headerBuffer[headerRange.upperBound...])
                session.headerBuffer.removeAll(keepingCapacity: false)
                self.authorizeAndOpen(
                    headerData: headerData,
                    initialData: initialData,
                    session: session
                )
            }
        }
    }

    private func authorizeAndOpen(
        headerData: Data,
        initialData: Data,
        session: ClientSession
    ) {
        let requestLine: String
        switch HTTPConnectAuthenticator.authenticate(
            headerData: headerData,
            credentials: credentials
        ) {
        case .authorized(let authorizedRequestLine):
            requestLine = authorizedRequestLine
        case .authenticationRequired:
            sendAndClose(HTTPConnectParser.authenticationRequiredResponse, session: session)
            return
        case .malformed:
            sendAndClose(HTTPConnectParser.badRequestResponse, session: session)
            return
        }
        guard promoteToAuthenticated(session) else {
            sendAndClose(HTTPConnectParser.serviceUnavailableResponse, session: session)
            return
        }

        let target: ProxyTarget
        do {
            let parsed = try HTTPConnectParser.parse(requestLine: requestLine)
            target = try ProxyTarget(host: parsed.host, port: parsed.port)
        } catch {
            sendAndClose(HTTPConnectParser.badRequestResponse, session: session)
            return
        }

        do {
            try requireCurrentConnectionLease()
            guard let forwarder else {
                throw HTTPConnectProxyError.connectionLeaseChanged
            }
            let transport = try forwarder.openProxyTransport(
                to: target,
                for: profileID,
                expectedConnectionLeaseID: connectionLeaseID
            )
            session.transport = transport
            do {
                try requireCurrentConnectionLease()
            } catch {
                transport.cancel()
                session.transport = nil
                throw error
            }
            waitForTransportReadiness(
                transport,
                initialData: initialData,
                session: session
            )
        } catch {
            sendAndClose(
                HTTPConnectParser.badGatewayResponse(reason: "Upstream connection failed"),
                session: session
            )
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
                guard transport.isRunning else {
                    throw ProxyUpstreamTransportError.closed
                }
                try self.requireCurrentConnectionLease()
                currentSession.readinessTask = nil
                currentSession.timeoutTask?.cancel()
                currentSession.timeoutTask = nil
                self.sendConnectionEstablished(
                    initialData: initialData,
                    session: currentSession
                )
            } catch {
                guard let self,
                      let currentSession = self.sessions[sessionID],
                      currentSession.transport === transport else {
                    transport.cancel()
                    return
                }
                currentSession.readinessTask = nil
                self.sendAndClose(
                    HTTPConnectParser.badGatewayResponse(reason: "Upstream connection failed"),
                    session: currentSession
                )
            }
        }
    }

    private func sendConnectionEstablished(initialData: Data, session: ClientSession) {
        session.connection.send(
            content: Data(HTTPConnectParser.connectionEstablishedResponse.utf8),
            completion: .contentProcessed { [weak self, weak session] error in
                Task { @MainActor in
                    guard let self, let session,
                          self.sessions[session.id] === session,
                          let transport = session.transport else { return }
                    guard error == nil else {
                        self.closeSession(id: session.id)
                        return
                    }
                    let sessionID = session.id
                    let relay = ProxyConnectionRelay(
                        client: session.connection,
                        upstream: transport,
                        onClose: { [weak self] in
                            self?.finishSession(id: sessionID)
                        }
                    )
                    session.transport = nil
                    session.relay = relay
                    relay.start(initialClientData: initialData)
                }
            }
        )
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

    private func sendAndClose(_ response: String, session: ClientSession) {
        session.connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { [weak self, weak session] _ in
                Task { @MainActor in
                    guard let session else { return }
                    self?.closeSession(id: session.id)
                }
            }
        )
    }

    private func requireCurrentConnectionLease() throws {
        guard let forwarder,
              forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
            throw HTTPConnectProxyError.connectionLeaseChanged
        }
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
