// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayAuditLogTests.swift - Tests for relay audit log writing and rotation.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Audit Log Writer

/// In-memory audit log writer for testing.
final class MockAuditLogWriter: AuditLogWriting, @unchecked Sendable {
    var entries: [String] = []
    var rotationCount = 0
    var currentSize: Int { entries.joined(separator: "\n").utf8.count }

    func appendLine(_ line: String) throws {
        entries.append(line)
    }

    func rotate() throws {
        rotationCount += 1
        entries.removeAll()
    }

    func readAllLines() throws -> [String] {
        entries
    }
}

// MARK: - RelayAuditLog Tests

@Suite("RelayAuditLog")
struct RelayAuditLogTests {

    @Test("Log event writes JSON line")
    @MainActor func logEvent() throws {
        let writer = MockAuditLogWriter()
        let log = RelayAuditLog(writer: writer)

        log.log(.channelOpened(channelID: UUID(), name: "test"))

        #expect(writer.entries.count == 1)
        #expect(writer.entries[0].contains("channelOpened"))
        #expect(writer.entries[0].contains("test"))
    }

    @Test("Log entries are valid JSON")
    @MainActor func validJSON() throws {
        let writer = MockAuditLogWriter()
        let log = RelayAuditLog(writer: writer)
        let channelID = UUID()

        log.log(.connectionAccepted(channelID: channelID, remoteHost: "127.0.0.1"))

        let line = writer.entries[0]
        let data = Data(line.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?["event"] as? String == "connectionAccepted")
        #expect(parsed?["timestamp"] != nil)
    }

    @Test("Multiple events written in order")
    @MainActor func ordering() {
        let writer = MockAuditLogWriter()
        let log = RelayAuditLog(writer: writer)
        let channelID = UUID()

        log.log(.channelOpened(channelID: channelID, name: "ch1"))
        log.log(.connectionAccepted(channelID: channelID, remoteHost: "127.0.0.1"))
        log.log(.connectionRejected(channelID: channelID, remoteHost: "10.0.0.1", reason: "ACL denied"))

        #expect(writer.entries.count == 3)
        #expect(writer.entries[0].contains("channelOpened"))
        #expect(writer.entries[1].contains("connectionAccepted"))
        #expect(writer.entries[2].contains("connectionRejected"))
    }

    @Test("All event types produce valid output")
    @MainActor func allEventTypes() {
        let writer = MockAuditLogWriter()
        let log = RelayAuditLog(writer: writer)
        let channelID = UUID()

        log.log(.channelOpened(channelID: channelID, name: "ch"))
        log.log(.connectionAccepted(channelID: channelID, remoteHost: "127.0.0.1"))
        log.log(.connectionRejected(channelID: channelID, remoteHost: "10.0.0.1", reason: "bad"))
        log.log(.tokenRotated(channelID: channelID))
        log.log(.channelClosed(channelID: channelID))

        #expect(writer.entries.count == 5)
    }

    @Test("Auto-rotation triggers when log exceeds maxSizeBytes")
    @MainActor func autoRotation() {
        let writer = MockAuditLogWriter()
        // Use a tiny max so rotation triggers quickly.
        let log = RelayAuditLog(writer: writer, maxSizeBytes: 50)
        let channelID = UUID()

        // Each JSON line is ~100+ bytes, so a single entry exceeds 50 bytes.
        log.log(.channelOpened(channelID: channelID, name: "test-channel"))

        #expect(writer.rotationCount >= 1, "Rotation should have been triggered")
    }

    @Test("No rotation when log is within size limit")
    @MainActor func noRotationUnderLimit() {
        let writer = MockAuditLogWriter()
        // 10 MB — a single entry won't trigger rotation.
        let log = RelayAuditLog(writer: writer, maxSizeBytes: 10 * 1024 * 1024)

        log.log(.channelClosed(channelID: UUID()))

        #expect(writer.rotationCount == 0)
    }

    @Test("AuditEvent type names are correct")
    func eventTypeNames() {
        let id = UUID()
        let events: [(RelayAuditEvent, String)] = [
            (.channelOpened(channelID: id, name: "x"), "channelOpened"),
            (.connectionAccepted(channelID: id, remoteHost: "h"), "connectionAccepted"),
            (.connectionRejected(channelID: id, remoteHost: "h", reason: "r"), "connectionRejected"),
            (.tokenRotated(channelID: id), "tokenRotated"),
            (.channelClosed(channelID: id), "channelClosed"),
        ]
        for (event, expected) in events {
            #expect(event.typeName == expected)
        }
    }
}
