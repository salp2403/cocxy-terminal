// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyExclusionListTests.swift - Tests for proxy bypass wildcard matching and PAC generation.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ProxyExclusionList")
struct ProxyExclusionListTests {

    // MARK: - Default Exclusions

    @Test("Default exclusions include localhost variants")
    func defaultsIncludeLocalhost() {
        let list = ProxyExclusionList()
        #expect(list.shouldBypass("localhost"))
        #expect(list.shouldBypass("127.0.0.1"))
        #expect(list.shouldBypass("::1"))
    }

    @Test("Default exclusions include .local domains")
    func defaultsIncludeLocal() {
        let list = ProxyExclusionList()
        #expect(list.shouldBypass("myhost.local"))
        #expect(list.shouldBypass("printer.local"))
    }

    @Test("Default exclusions include link-local addresses")
    func defaultsIncludeLinkLocal() {
        let list = ProxyExclusionList()
        #expect(list.shouldBypass("169.254.1.1"))
        #expect(list.shouldBypass("169.254.255.255"))
    }

    // MARK: - External Hosts Not Bypassed

    @Test("External hosts are not bypassed by default")
    func externalNotBypassed() {
        let list = ProxyExclusionList()
        #expect(!list.shouldBypass("google.com"))
        #expect(!list.shouldBypass("192.168.1.1"))
        #expect(!list.shouldBypass("10.0.0.1"))
        #expect(!list.shouldBypass("api.example.com"))
    }

    // MARK: - Custom Exclusions

    @Test("Custom wildcard subdomain exclusions work")
    func customSubdomainWildcard() {
        let list = ProxyExclusionList(custom: ["*.internal.company.com"])
        #expect(list.shouldBypass("api.internal.company.com"))
        #expect(list.shouldBypass("db.internal.company.com"))
        #expect(!list.shouldBypass("internal.company.com"))
        #expect(!list.shouldBypass("external.com"))
    }

    @Test("Custom wildcard IP prefix exclusions work")
    func customIPPrefixWildcard() {
        let list = ProxyExclusionList(custom: ["10.0.0.*"])
        #expect(list.shouldBypass("10.0.0.55"))
        #expect(list.shouldBypass("10.0.0.1"))
        #expect(!list.shouldBypass("10.0.1.1"))
        #expect(!list.shouldBypass("10.0.0"))
    }

    @Test("Custom exact host exclusions work")
    func customExactHost() {
        let list = ProxyExclusionList(custom: ["myserver.example.com"])
        #expect(list.shouldBypass("myserver.example.com"))
        #expect(!list.shouldBypass("other.example.com"))
    }

    @Test("Custom exclusions combine with defaults")
    func customPlusDefaults() {
        let list = ProxyExclusionList(custom: ["myhost.example.com"])
        #expect(list.shouldBypass("localhost"))
        #expect(list.shouldBypass("myhost.example.com"))
        #expect(!list.shouldBypass("otherhost.example.com"))
    }

    // MARK: - Case Insensitivity

    @Test("Matching is case insensitive")
    func caseInsensitive() {
        let list = ProxyExclusionList(custom: ["*.Example.COM"])
        #expect(list.shouldBypass("api.example.com"))
        #expect(list.shouldBypass("API.EXAMPLE.COM"))
        #expect(list.shouldBypass("Foo.Example.Com"))
    }

    // MARK: - Empty Custom

    @Test("Empty custom list uses only defaults")
    func emptyCustom() {
        let list = ProxyExclusionList(custom: [])
        #expect(list.shouldBypass("localhost"))
        #expect(!list.shouldBypass("google.com"))
    }

    // MARK: - PAC File Generation

    @Test("PAC file contains FindProxyForURL function")
    func pacHasFunction() {
        let list = ProxyExclusionList()
        let pac = list.generatePACContent(socksPort: 1080)
        #expect(pac.contains("FindProxyForURL"))
    }

    @Test("PAC file contains SOCKS5 directive with correct port")
    func pacHasSOCKSDirective() {
        let list = ProxyExclusionList()
        let pac = list.generatePACContent(socksPort: 9090)
        #expect(pac.contains("SOCKS5 127.0.0.1:9090"))
    }

    @Test("PAC file contains DIRECT for bypass entries")
    func pacHasDirectBypass() {
        let list = ProxyExclusionList()
        let pac = list.generatePACContent(socksPort: 1080)
        #expect(pac.contains("DIRECT"))
    }

    @Test("PAC file includes custom exclusions")
    func pacIncludesCustom() {
        let list = ProxyExclusionList(custom: ["*.corp.local"])
        let pac = list.generatePACContent(socksPort: 1080)
        #expect(pac.contains("corp.local"))
    }

    // MARK: - Codable

    @Test("ProxyExclusionList encodes and decodes correctly")
    func codableRoundTrip() throws {
        let original = ProxyExclusionList(custom: ["*.test.com", "10.0.0.*"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyExclusionList.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - All Patterns Accessor

    @Test("allPatterns returns defaults plus custom")
    func allPatternsCount() {
        let list = ProxyExclusionList(custom: ["extra.host"])
        #expect(list.patterns.count == ProxyExclusionList.defaultExclusions.count + 1)
    }
}
