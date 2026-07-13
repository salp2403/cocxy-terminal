// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HTTPConnectProxy.swift - HTTP CONNECT proxy using Network.framework.

import Foundation
import Network

// MARK: - HTTP CONNECT Parser

/// Parses HTTP CONNECT request lines and generates response strings.
///
/// Handles the text protocol layer of the HTTP CONNECT tunnel.
/// Separated from networking for pure-function testability.
enum HTTPConnectParser {

    // MARK: - Parse Result

    /// The target host and port extracted from a CONNECT request.
    struct ConnectTarget: Equatable, Sendable {
        let host: String
        let port: Int
    }

    // MARK: - Parse Errors

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

    // MARK: - Parsing

    /// Parses an HTTP CONNECT request line into host and port.
    ///
    /// Supports formats:
    /// - `CONNECT host:port HTTP/1.x`
    /// - `CONNECT [ipv6]:port HTTP/1.x`
    ///
    /// - Parameter requestLine: The first line of the HTTP request.
    /// - Returns: The parsed host and port.
    static func parse(requestLine: String) throws -> ConnectTarget {
        let parts = requestLine.split(separator: " ", maxSplits: 3)
        guard parts.count >= 2 else { throw ParseError.malformedRequestLine }
        guard parts[0].uppercased() == "CONNECT" else { throw ParseError.notConnectMethod }

        let target = String(parts[1])
        return try parseHostPort(target)
    }

    /// Parses a `host:port` or `[ipv6]:port` string.
    private static func parseHostPort(_ target: String) throws -> ConnectTarget {
        // IPv6 format: [::1]:port
        if target.hasPrefix("[") {
            guard let closeBracket = target.firstIndex(of: "]") else {
                throw ParseError.malformedRequestLine
            }
            let host = String(target[target.index(after: target.startIndex)..<closeBracket])
            let afterBracket = target[target.index(after: closeBracket)...]
            guard afterBracket.hasPrefix(":") else { throw ParseError.missingPort }
            let portStr = String(afterBracket.dropFirst())
            guard let port = Int(portStr), (1...65535).contains(port) else {
                throw ParseError.invalidPort
            }
            return ConnectTarget(host: host, port: port)
        }

        // Standard format: host:port
        guard let colonIndex = target.lastIndex(of: ":") else {
            throw ParseError.missingPort
        }
        let host = String(target[..<colonIndex])
        let portStr = String(target[target.index(after: colonIndex)...])
        guard let port = Int(portStr), (1...65535).contains(port) else {
            throw ParseError.invalidPort
        }
        return ConnectTarget(host: host, port: port)
    }

    // MARK: - Response Generation

    /// HTTP 200 response sent after successful tunnel establishment.
    static let connectionEstablishedResponse =
        "HTTP/1.1 200 Connection established\r\n\r\n"

    /// HTTP 502 response sent when the upstream connection fails.
    static func badGatewayResponse(reason: String) -> String {
        "HTTP/1.1 502 Bad Gateway\r\nContent-Length: \(reason.utf8.count)\r\n\r\n\(reason)"
    }

    /// HTTP 400 response sent for malformed requests.
    static let badRequestResponse =
        "HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\n\r\nBad Request"
}

enum HTTPConnectProxyError: Error, LocalizedError {
    case connectionLeaseChanged

    var errorDescription: String? {
        switch self {
        case .connectionLeaseChanged:
            return "SSH connection changed before HTTP proxy cleanup completed"
        }
    }
}

// MARK: - Relay Close Flag

/// Thread-safe flag ensuring a relay connection count is decremented exactly once.
/// Both relay directions share a single instance; whichever closes first "wins".
@MainActor
final class RelayCloseFlag {
    private var isClosed = false

    /// Returns `true` the first time called, `false` thereafter.
    func close() -> Bool {
        guard !isClosed else { return false }
        isClosed = true
        return true
    }
}

// MARK: - Forward Cache

/// Caches active SSH local forwards to avoid creating duplicate tunnels
/// for repeated CONNECT requests to the same host:port.
struct ForwardCache: Sendable {

    private var entries: [String: Int] = [:]

    /// Returns the local port for a cached forward, or nil if not cached.
    func lookup(host: String, port: Int) -> Int? {
        entries[cacheKey(host: host, port: port)]
    }

    /// Stores a forward mapping from remote host:port to local port.
    mutating func store(host: String, port: Int, localPort: Int) {
        entries[cacheKey(host: host, port: port)] = localPort
    }

    /// Removes a cached forward entry.
    mutating func remove(host: String, port: Int) {
        entries.removeValue(forKey: cacheKey(host: host, port: port))
    }

    /// Removes all cached entries.
    mutating func clear() {
        entries.removeAll()
    }

    private func cacheKey(host: String, port: Int) -> String {
        "\(host):\(port)"
    }
}

// MARK: - HTTP Connect Proxy

@MainActor
protocol HTTPConnectProxyLifecycle: AnyObject {
    var port: Int { get }
    var activeConnectionCount: Int { get }
    func start() async throws
    func activate()
    func stop() throws
    func releaseAfterSessionTermination()
}

/// HTTP CONNECT proxy server using Network.framework.
///
/// Listens on a local port and handles CONNECT requests by creating
/// SSH local forwards on demand, then relaying bytes bidirectionally.
///
/// ## Data Flow
///
/// ```
/// Client → HTTP CONNECT → parse host:port → SSH -L forward → relay bytes
/// ```
///
/// Forward caching avoids duplicate SSH forwards for the same destination.
@MainActor
final class HTTPConnectProxy: HTTPConnectProxyLifecycle {

    private final class ListenerStartupGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }

    /// The local port this proxy listens on.
    let port: Int

    /// The port forwarder (typically RemoteConnectionManager).
    private let forwarder: any PortForwarding

    /// The profile whose SSH session carries the forwards.
    private let profileID: UUID

    /// Exact SSH session that owns every local forward created by this proxy.
    private let connectionLeaseID: UUID

    /// Network listener for incoming connections.
    private var listener: NWListener?

    /// Cache of active SSH local forwards.
    private var forwardCache = ForwardCache()

    /// Exact forwards remain owned until cancellation succeeds or SSH death is proven.
    private var activeForwards: [String: RemoteConnectionProfile.PortForward] = [:]

    /// Accepted client and upstream sockets are retained so stop is revocable.
    private var trackedConnections: [ObjectIdentifier: NWConnection] = [:]
    private var clientConnectionIDs: Set<ObjectIdentifier> = []

    /// Number of currently active connections.
    private(set) var activeConnectionCount: Int = 0

    /// A ready listener rejects traffic until ProxyManager commits ownership.
    private var acceptsConnections = false

    /// Creates an HTTP CONNECT proxy.
    ///
    /// - Parameters:
    ///   - listenPort: Local port to listen on (default 8888).
    ///   - forwarder: SSH port forwarding abstraction.
    ///   - profileID: Remote profile for SSH tunnel creation.
    ///   - connectionLeaseID: Exact SSH session that owns generated forwards.
    init(
        listenPort: Int = 8888,
        forwarder: any PortForwarding,
        profileID: UUID,
        connectionLeaseID: UUID
    ) {
        self.port = listenPort
        self.forwarder = forwarder
        self.profileID = profileID
        self.connectionLeaseID = connectionLeaseID
    }

    func activate() {
        acceptsConnections = true
    }

    /// Starts the proxy listener and waits until the listener is either ready or failed.
    func start() async throws {
        let parameters = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let gate = ListenerStartupGate()

            listener.stateUpdateHandler = { [weak self] newState in
                switch newState {
                case .ready:
                    guard gate.claim() else { return }
                    continuation.resume()
                case .failed(let error):
                    NSLog("[HTTPConnectProxy] Listener failed: \(error)")
                    Task { @MainActor [weak self] in
                        self?.listener = nil
                    }
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

    /// Stops local traffic and cancels every exact SSH local forward.
    func stop() throws {
        stopLocalTraffic()

        var firstError: (any Error)?
        for (key, forward) in Array(activeForwards) {
            do {
                try requireCurrentConnectionLease()
                try forwarder.cancelForward(forward, for: profileID)
                activeForwards.removeValue(forKey: key)
                if case let .local(_, remotePort, remoteHost) = forward {
                    forwardCache.remove(host: remoteHost, port: remotePort)
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if activeForwards.isEmpty {
            forwardCache.clear()
        }
        if let firstError { throw firstError }
    }

    /// Clears forwarding ownership only after the ControlMaster process died.
    func releaseAfterSessionTermination() {
        stopLocalTraffic()
        activeForwards.removeAll()
        forwardCache.clear()
    }

    private func stopLocalTraffic() {
        acceptsConnections = false
        listener?.cancel()
        listener = nil
        let connections = Array(trackedConnections.values)
        trackedConnections.removeAll()
        clientConnectionIDs.removeAll()
        activeConnectionCount = 0
        for connection in connections {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }

    // MARK: - Connection Handling

    /// Handles an incoming TCP connection.
    ///
    /// Reads the first line, parses the CONNECT request, creates an SSH
    /// forward if needed, and sets up bidirectional relay.
    private func handleConnection(_ connection: NWConnection) {
        guard acceptsConnections else {
            connection.cancel()
            return
        }
        trackConnection(connection, isClient: true)
        connection.start(queue: .main)

        // Read the HTTP request line.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, _, error in

            Task { @MainActor in
                guard let self else { return }
                guard self.isTracked(connection), self.acceptsConnections else { return }

                if let error {
                    NSLog("[HTTPConnectProxy] Read error: \(error)")
                    self.closeConnection(connection)
                    return
                }

                guard let data,
                      let requestString = String(data: data, encoding: .utf8),
                      let firstLine = requestString.split(separator: "\r\n").first
                else {
                    self.sendResponse(HTTPConnectParser.badRequestResponse, on: connection)
                    self.closeConnection(connection)
                    return
                }

                do {
                    let target = try HTTPConnectParser.parse(requestLine: String(firstLine))
                    self.connectToTarget(target, clientConnection: connection)
                } catch {
                    self.sendResponse(HTTPConnectParser.badRequestResponse, on: connection)
                    self.closeConnection(connection)
                }
            }
        }
    }

    /// Creates or reuses an SSH forward, sends 200, then starts bidirectional relay.
    private func connectToTarget(
        _ target: HTTPConnectParser.ConnectTarget,
        clientConnection: NWConnection
    ) {
        guard acceptsConnections, isTracked(clientConnection) else {
            closeConnection(clientConnection)
            return
        }
        do {
            try requireCurrentConnectionLease()
        } catch {
            sendResponse(
                HTTPConnectParser.badGatewayResponse(reason: error.localizedDescription),
                on: clientConnection
            )
            closeConnection(clientConnection)
            return
        }

        // Determine the local forward port (cached or new).
        let localPort: Int
        if let cached = forwardCache.lookup(host: target.host, port: target.port) {
            localPort = cached
        } else {
            localPort = ephemeralPort()
            let forward = RemoteConnectionProfile.PortForward.local(
                localPort: localPort,
                remotePort: target.port,
                remoteHost: target.host
            )
            do {
                try forwarder.forwardPort(forward, for: profileID)
                forwardCache.store(host: target.host, port: target.port, localPort: localPort)
                activeForwards[forwardKey(host: target.host, port: target.port)] = forward
            } catch {
                let reason = "Failed to create SSH forward: \(error.localizedDescription)"
                sendResponse(HTTPConnectParser.badGatewayResponse(reason: reason), on: clientConnection)
                closeConnection(clientConnection)
                return
            }
        }

        // Connect to the local forward port.
        let upstreamPort = NWEndpoint.Port(rawValue: UInt16(localPort))!
        let upstream = NWConnection(
            host: .ipv4(.loopback),
            port: upstreamPort,
            using: .tcp
        )
        trackConnection(upstream, isClient: false)

        upstream.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    guard self.acceptsConnections,
                          self.isTracked(clientConnection),
                          self.isTracked(upstream)
                    else {
                        self.closeConnection(upstream)
                        self.closeConnection(clientConnection)
                        return
                    }
                    // Send 200 and start bidirectional relay.
                    self.sendResponse(
                        HTTPConnectParser.connectionEstablishedResponse,
                        on: clientConnection
                    )
                    self.startRelay(
                        client: clientConnection,
                        upstream: upstream
                    )
                case .failed, .cancelled:
                    if self.acceptsConnections, self.isTracked(clientConnection) {
                        let reason = "Upstream connection failed"
                        self.sendResponse(
                            HTTPConnectParser.badGatewayResponse(reason: reason),
                            on: clientConnection
                        )
                    }
                    self.closeConnection(upstream)
                    self.closeConnection(clientConnection)
                default:
                    break
                }
            }
        }

        upstream.start(queue: .main)
    }

    // MARK: - Bidirectional Relay

    /// Pipes bytes between two NWConnections until either side closes.
    private func startRelay(client: NWConnection, upstream: NWConnection) {
        // Shared flag to ensure we only decrement the connection count once,
        // regardless of which direction closes first.
        let closed = RelayCloseFlag()
        relayData(
            from: client,
            to: upstream,
            client: client,
            upstream: upstream,
            closeFlag: closed
        )
        relayData(
            from: upstream,
            to: client,
            client: client,
            upstream: upstream,
            closeFlag: closed
        )
    }

    /// Continuously reads from `source` and writes to `dest`.
    private func relayData(
        from source: NWConnection,
        to dest: NWConnection,
        client: NWConnection,
        upstream: NWConnection,
        closeFlag: RelayCloseFlag
    ) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            data, _, isComplete, error in
            if let data, !data.isEmpty {
                dest.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        Task { @MainActor [weak self] in
                            self?.finishRelay(
                                closeFlag,
                                client: client,
                                upstream: upstream
                            )
                        }
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.isTracked(source), self.isTracked(dest) else {
                            self.finishRelay(
                                closeFlag,
                                client: client,
                                upstream: upstream
                            )
                            return
                        }
                        self.relayData(
                            from: source,
                            to: dest,
                            client: client,
                            upstream: upstream,
                            closeFlag: closeFlag
                        )
                    }
                })
            } else if isComplete || error != nil {
                Task { @MainActor [weak self] in
                    self?.finishRelay(
                        closeFlag,
                        client: client,
                        upstream: upstream
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func sendResponse(_ response: String, on connection: NWConnection) {
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func closeConnection(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        trackedConnections.removeValue(forKey: identifier)
        if clientConnectionIDs.remove(identifier) != nil {
            activeConnectionCount = clientConnectionIDs.count
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func finishRelay(
        _ closeFlag: RelayCloseFlag,
        client: NWConnection,
        upstream: NWConnection
    ) {
        guard closeFlag.close() else { return }
        closeConnection(client)
        closeConnection(upstream)
    }

    private func trackConnection(_ connection: NWConnection, isClient: Bool) {
        let identifier = ObjectIdentifier(connection)
        trackedConnections[identifier] = connection
        if isClient {
            clientConnectionIDs.insert(identifier)
            activeConnectionCount = clientConnectionIDs.count
        }
    }

    private func isTracked(_ connection: NWConnection) -> Bool {
        trackedConnections[ObjectIdentifier(connection)] != nil
    }

    private func requireCurrentConnectionLease() throws {
        guard forwarder.connectionLeaseID(for: profileID) == connectionLeaseID else {
            throw HTTPConnectProxyError.connectionLeaseChanged
        }
    }

    private func forwardKey(host: String, port: Int) -> String {
        "\(host):\(port)"
    }

    /// Returns an ephemeral port in the dynamic range.
    private func ephemeralPort() -> Int {
        Int.random(in: 49152...65535)
    }
}
