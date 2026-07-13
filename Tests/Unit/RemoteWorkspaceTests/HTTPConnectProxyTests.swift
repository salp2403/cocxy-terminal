// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HTTPConnectProxyTests.swift - Tests for HTTP CONNECT proxy request parsing and lifecycle.

import Darwin
import Foundation
import Network
import Testing
@testable import CocxyTerminal

private final class HTTPProxyTestContinuationGate: @unchecked Sendable {
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
private func connectHTTPProxyTestClient(to port: Int) async throws -> NWConnection {
    let connection = NWConnection(
        host: .ipv4(.loopback),
        port: NWEndpoint.Port(rawValue: UInt16(port))!,
        using: .tcp
    )

    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let gate = HTTPProxyTestContinuationGate()
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
private func sendHTTPProxyTestRequest(_ request: String, on connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        })
    }
}

@Suite("HTTPConnectProxy")
struct HTTPConnectProxyTests {

    private static func availableLoopbackPort() throws -> Int {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: 0,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }

    // MARK: - Request Parsing

    @Test("Parses valid CONNECT request")
    func parseValidConnect() throws {
        let line = "CONNECT example.com:443 HTTP/1.1"
        let result = try HTTPConnectParser.parse(requestLine: line)
        #expect(result.host == "example.com")
        #expect(result.port == 443)
    }

    @Test("Parses CONNECT with IP address")
    func parseConnectIP() throws {
        let line = "CONNECT 192.168.1.100:8080 HTTP/1.1"
        let result = try HTTPConnectParser.parse(requestLine: line)
        #expect(result.host == "192.168.1.100")
        #expect(result.port == 8080)
    }

    @Test("Parses CONNECT with IPv6 address")
    func parseConnectIPv6() throws {
        let line = "CONNECT [::1]:443 HTTP/1.1"
        let result = try HTTPConnectParser.parse(requestLine: line)
        #expect(result.host == "::1")
        #expect(result.port == 443)
    }

    @Test("Rejects non-CONNECT method")
    func rejectNonConnect() {
        let line = "GET / HTTP/1.1"
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: line)
        }
    }

    @Test("Rejects malformed request line")
    func rejectMalformed() {
        let line = "CONNECT"
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: line)
        }
    }

    @Test("Rejects missing port")
    func rejectMissingPort() {
        let line = "CONNECT example.com HTTP/1.1"
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: line)
        }
    }

    @Test("Rejects invalid port")
    func rejectInvalidPort() {
        let line = "CONNECT example.com:abc HTTP/1.1"
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: line)
        }
    }

    @Test("Rejects port out of range")
    func rejectPortOutOfRange() {
        let line = "CONNECT example.com:99999 HTTP/1.1"
        #expect(throws: HTTPConnectParser.ParseError.self) {
            _ = try HTTPConnectParser.parse(requestLine: line)
        }
    }

    // MARK: - Response Generation

    @Test("Generates 200 Connection Established response")
    func response200() {
        let response = HTTPConnectParser.connectionEstablishedResponse
        #expect(response.hasPrefix("HTTP/1.1 200"))
        #expect(response.hasSuffix("\r\n\r\n"))
    }

    @Test("Generates 502 Bad Gateway response")
    func response502() {
        let response = HTTPConnectParser.badGatewayResponse(reason: "Connection refused")
        #expect(response.contains("502"))
        #expect(response.contains("Connection refused"))
    }

    @Test("Generates 400 Bad Request response")
    func response400() {
        let response = HTTPConnectParser.badRequestResponse
        #expect(response.contains("400"))
    }

    // MARK: - Forward Cache

    @Test("Forward cache stores and retrieves entries")
    func cacheStoreAndRetrieve() {
        var cache = ForwardCache()
        cache.store(host: "example.com", port: 443, localPort: 50001)
        let result = cache.lookup(host: "example.com", port: 443)
        #expect(result == 50001)
    }

    @Test("Forward cache returns nil for unknown entries")
    func cacheMiss() {
        let cache = ForwardCache()
        let result = cache.lookup(host: "unknown.com", port: 443)
        #expect(result == nil)
    }

    @Test("Forward cache removes entries")
    func cacheRemove() {
        var cache = ForwardCache()
        cache.store(host: "example.com", port: 443, localPort: 50001)
        cache.remove(host: "example.com", port: 443)
        let result = cache.lookup(host: "example.com", port: 443)
        #expect(result == nil)
    }

    @Test("Forward cache clear removes all entries")
    func cacheClear() {
        var cache = ForwardCache()
        cache.store(host: "a.com", port: 80, localPort: 50001)
        cache.store(host: "b.com", port: 443, localPort: 50002)
        cache.clear()
        #expect(cache.lookup(host: "a.com", port: 80) == nil)
        #expect(cache.lookup(host: "b.com", port: 443) == nil)
    }

    // MARK: - Lifecycle

    @Test("stop revokes accepted client sockets")
    @MainActor func stopRevokesAcceptedClients() async throws {
        let forwarder = MockPortForwarder()
        let profileID = UUID()
        let connectionLeaseID = try #require(forwarder.currentConnectionLeaseID)
        let port = try Self.availableLoopbackPort()
        let proxy = HTTPConnectProxy(
            listenPort: port,
            forwarder: forwarder,
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        try await proxy.start()
        proxy.activate()
        let client = try await connectHTTPProxyTestClient(to: port)
        defer { client.cancel() }

        for _ in 0..<50 where proxy.activeConnectionCount != 1 {
            await Task.yield()
        }
        #expect(proxy.activeConnectionCount == 1)

        try proxy.stop()
        #expect(proxy.activeConnectionCount == 0)
    }

    @Test("stop retries exact SSH forward cancellation")
    @MainActor func stopRetriesExactForwardCancellation() async throws {
        let forwarder = MockPortForwarder()
        let profileID = UUID()
        let connectionLeaseID = try #require(forwarder.currentConnectionLeaseID)
        let port = try Self.availableLoopbackPort()
        let proxy = HTTPConnectProxy(
            listenPort: port,
            forwarder: forwarder,
            profileID: profileID,
            connectionLeaseID: connectionLeaseID
        )
        try await proxy.start()
        proxy.activate()
        let client = try await connectHTTPProxyTestClient(to: port)
        defer { client.cancel() }
        try await sendHTTPProxyTestRequest(
            "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com\r\n\r\n",
            on: client
        )

        for _ in 0..<100 where forwarder.forwardedPorts.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let forward = try #require(forwarder.forwardedPorts.first)
        guard case let .local(localPort, remotePort, remoteHost) = forward else {
            Issue.record("Expected an exact local SSH forward")
            return
        }
        #expect((49152...65535).contains(localPort))
        #expect(remotePort == 443)
        #expect(remoteHost == "example.com")

        forwarder.shouldThrowOnCancel = true
        #expect(throws: SSHMultiplexerError.self) {
            try proxy.stop()
        }
        #expect(forwarder.cancelledPorts.isEmpty)

        forwarder.shouldThrowOnCancel = false
        try proxy.stop()
        #expect(forwarder.cancelledPorts == [forward])
        #expect(forwarder.cancelledProfileIDs == [profileID])
    }

    // MARK: - ParseError Conformance

    @Test("ParseError has descriptive messages")
    func parseErrorDescriptions() {
        let errors: [HTTPConnectParser.ParseError] = [
            .notConnectMethod,
            .malformedRequestLine,
            .missingPort,
            .invalidPort
        ]
        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }
}
