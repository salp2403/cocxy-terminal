// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task orchestration sessions")
struct TaskOrchestrationSessionSwiftTestingTests {
    @Test("session is HMAC-bound to one run and its exact tabs")
    func sessionIsBoundToRunAndTabs() throws {
        let clock = MutableOrchestrationClock(now: Date(timeIntervalSince1970: 1_000))
        let audit = RecordingTaskOrchestrationAuditLog()
        let manager = TaskOrchestrationSessionManager(
            secret: Data(repeating: 7, count: 32),
            ttl: 60,
            maximumWrites: 2,
            clock: { clock.now },
            auditLog: audit
        )
        let allowedTab = UUID()
        let credential = try manager.issue(runID: "task-1", tabIDs: [allowedTab])

        let authorization = try #require(
            manager.authorization(token: credential.token, tabID: allowedTab)
        )
        #expect(authorization.runID == "task-1")
        #expect(manager.authorization(token: credential.token, tabID: UUID()) == nil)
        #expect(manager.authorization(token: credential.token + "x", tabID: allowedTab) == nil)

        #expect(manager.recordWrite(
            authorization: authorization,
            command: "send",
            payloadBytes: 17
        ))
        #expect(manager.recordWrite(
            authorization: authorization,
            command: "send-key",
            payloadBytes: 1
        ))
        #expect(!manager.recordWrite(
            authorization: authorization,
            command: "send",
            payloadBytes: 1
        ))
        #expect(audit.recordedEvents.map(\.command) == ["send", "send-key"])
        #expect(audit.recordedEvents.map(\.payloadBytes) == [17, 1])
    }

    @Test("expired and revoked sessions fail closed")
    func expirationAndRevocationFailClosed() throws {
        let clock = MutableOrchestrationClock(now: Date(timeIntervalSince1970: 2_000))
        let manager = TaskOrchestrationSessionManager(
            secret: Data(repeating: 9, count: 32),
            ttl: 10,
            clock: { clock.now },
            auditLog: RecordingTaskOrchestrationAuditLog()
        )
        let tabID = UUID()
        let credential = try manager.issue(runID: "task-expiring", tabIDs: [tabID])
        #expect(manager.authorization(token: credential.token, tabID: tabID) != nil)

        manager.revoke(runID: credential.runID)
        #expect(manager.authorization(token: credential.token, tabID: tabID) == nil)

        let expiring = try manager.issue(runID: "task-expiring", tabIDs: [tabID])
        clock.now = clock.now.addingTimeInterval(10)
        #expect(manager.authorization(token: expiring.token, tabID: tabID) == nil)
        #expect(manager.credential(forRunID: expiring.runID) == nil)
    }

    @Test("audit failure prevents a preauthorized write")
    func auditFailureFailsClosed() throws {
        let manager = TaskOrchestrationSessionManager(
            secret: Data(repeating: 3, count: 32),
            auditLog: FailingTaskOrchestrationAuditLog()
        )
        let tabID = UUID()
        let credential = try manager.issue(runID: "task-audit", tabIDs: [tabID])
        let authorization = try #require(
            manager.authorization(token: credential.token, tabID: tabID)
        )

        #expect(!manager.recordWrite(
            authorization: authorization,
            command: "send",
            payloadBytes: 4
        ))
        #expect(manager.authorization(token: credential.token, tabID: tabID) != nil)
    }

    @Test("file audit is owner-only and contains metadata without terminal text")
    func fileAuditIsOwnerOnlyAndMetadataOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-orchestration-audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("audit.jsonl")
        let log = TaskOrchestrationFileAuditLog(fileURL: fileURL)
        let event = TaskOrchestrationAuditEvent(
            sessionID: UUID(),
            runID: "task-audit",
            tabID: UUID(),
            command: "send",
            payloadBytes: 19,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )

        try log.append(event)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("task-audit"))
        #expect(content.contains("\"payloadBytes\":19"))
        #expect(!content.contains("terminal text"))
    }
}

private final class MutableOrchestrationClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class RecordingTaskOrchestrationAuditLog: TaskOrchestrationAuditLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TaskOrchestrationAuditEvent] = []

    var recordedEvents: [TaskOrchestrationAuditEvent] {
        lock.withLock { events }
    }

    func append(_ event: TaskOrchestrationAuditEvent) {
        lock.withLock {
            events.append(event)
        }
    }
}

private struct FailingTaskOrchestrationAuditLog: TaskOrchestrationAuditLogging {
    struct AuditFailure: Error {}

    func append(_ event: TaskOrchestrationAuditEvent) throws {
        throw AuditFailure()
    }
}
