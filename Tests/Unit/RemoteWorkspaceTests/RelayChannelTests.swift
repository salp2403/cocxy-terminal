// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayChannelTests.swift - Tests for relay channel model and ACL evaluation.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - RelayACL Tests

@Suite("RelayACL")
struct RelayACLTests {

    @Test("Default ACL allows localhost only")
    func defaults() {
        let acl = RelayACL()
        #expect(acl.evaluate(processName: "node", remoteHost: "127.0.0.1"))
        #expect(!acl.evaluate(processName: "node", remoteHost: "10.0.0.5"))
    }

    @Test("Empty allowedProcesses permits all processes")
    func emptyProcessAllowlist() {
        let acl = RelayACL()
        #expect(acl.evaluate(processName: "node", remoteHost: "127.0.0.1"))
        #expect(acl.evaluate(processName: "python3", remoteHost: "127.0.0.1"))
        #expect(acl.evaluate(processName: "any-process", remoteHost: "127.0.0.1"))
    }

    @Test("Process allowlist filters correctly")
    func processFilter() {
        let acl = RelayACL(allowedProcesses: ["node", "python3"])
        #expect(acl.evaluate(processName: "node", remoteHost: "127.0.0.1"))
        #expect(acl.evaluate(processName: "python3", remoteHost: "127.0.0.1"))
        #expect(!acl.evaluate(processName: "ruby", remoteHost: "127.0.0.1"))
    }

    @Test("Custom allowed remote hosts work")
    func customRemoteHosts() {
        let acl = RelayACL(allowedRemoteHosts: ["127.0.0.1", "10.0.0.5"])
        #expect(acl.evaluate(processName: "node", remoteHost: "127.0.0.1"))
        #expect(acl.evaluate(processName: "node", remoteHost: "10.0.0.5"))
        #expect(!acl.evaluate(processName: "node", remoteHost: "192.168.1.1"))
    }

    @Test("Max connections enforced")
    func maxConnections() {
        let acl = RelayACL(maxConnections: 2)
        #expect(acl.canAcceptConnection(currentCount: 0))
        #expect(acl.canAcceptConnection(currentCount: 1))
        #expect(!acl.canAcceptConnection(currentCount: 2))
        #expect(!acl.canAcceptConnection(currentCount: 100))
    }

    @Test("Default max connections is 10")
    func defaultMaxConnections() {
        let acl = RelayACL()
        #expect(acl.canAcceptConnection(currentCount: 9))
        #expect(!acl.canAcceptConnection(currentCount: 10))
    }

    @Test("Both process and host must pass")
    func combinedFiltering() {
        let acl = RelayACL(
            allowedProcesses: ["node"],
            allowedRemoteHosts: ["127.0.0.1"]
        )
        #expect(acl.evaluate(processName: "node", remoteHost: "127.0.0.1"))
        #expect(!acl.evaluate(processName: "ruby", remoteHost: "127.0.0.1"))
        #expect(!acl.evaluate(processName: "node", remoteHost: "10.0.0.1"))
        #expect(!acl.evaluate(processName: "ruby", remoteHost: "10.0.0.1"))
    }

    @Test("RelayACL is Codable")
    func codableRoundTrip() throws {
        let original = RelayACL(
            allowedProcesses: ["node", "python3"],
            maxConnections: 5,
            allowedRemoteHosts: ["127.0.0.1", "10.0.0.1"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RelayACL.self, from: data)
        #expect(decoded.allowedProcesses == original.allowedProcesses)
        #expect(decoded.maxConnections == original.maxConnections)
        #expect(decoded.allowedRemoteHosts == original.allowedRemoteHosts)
    }
}

// MARK: - RelayChannel Tests

@Suite("RelayChannel")
struct RelayChannelTests {

    @Test("Channel creation with all fields")
    func creation() {
        let profileID = UUID()
        let channel = RelayChannel(
            profileID: profileID,
            name: "api-service",
            localHost: "localhost",
            localPort: 3000,
            remotePort: 9000,
            acl: RelayACL()
        )
        #expect(channel.name == "api-service")
        #expect(channel.localHost == "localhost")
        #expect(channel.localPort == 3000)
        #expect(channel.remotePort == 9000)
        #expect(channel.profileID == profileID)
        #expect(channel.connectionCount == 0)
        #expect(channel.expiresAt == nil)
    }

    @Test("Channel with expiration")
    func withExpiration() {
        let expiry = Date().addingTimeInterval(3600)
        let channel = RelayChannel(
            profileID: UUID(),
            name: "temp",
            localHost: "localhost",
            localPort: 8080,
            remotePort: 9090,
            acl: RelayACL(),
            expiresAt: expiry
        )
        #expect(channel.expiresAt == expiry)
        #expect(!channel.isExpired)
    }

    @Test("Expired channel reports isExpired")
    func expiredChannel() {
        let pastDate = Date().addingTimeInterval(-60)
        let channel = RelayChannel(
            profileID: UUID(),
            name: "expired",
            localHost: "localhost",
            localPort: 8080,
            remotePort: 9090,
            acl: RelayACL(),
            expiresAt: pastDate
        )
        #expect(channel.isExpired)
    }

    @Test("Channel without expiration is never expired")
    func noExpirationNeverExpires() {
        let channel = RelayChannel(
            profileID: UUID(),
            name: "permanent",
            localHost: "localhost",
            localPort: 8080,
            remotePort: 9090,
            acl: RelayACL()
        )
        #expect(!channel.isExpired)
    }

    @Test("RelayChannelConfig is Codable")
    func configCodable() throws {
        let original = RelayChannelConfig(
            name: "api",
            localHost: "localhost",
            localPort: 3000,
            remotePort: 9000
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RelayChannelConfig.self, from: data)
        #expect(decoded.name == original.name)
        #expect(decoded.localPort == original.localPort)
        #expect(decoded.remotePort == original.remotePort)
    }
}
