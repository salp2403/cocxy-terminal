// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HTTPConnectProxyTests.swift - Tests for HTTP CONNECT proxy request parsing and lifecycle.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("HTTPConnectProxy")
struct HTTPConnectProxyTests {

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
