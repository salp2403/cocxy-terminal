// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskOrchestrationSession.swift - Scoped leases for directed TaskRun terminal input.

import CryptoKit
import Foundation

enum TaskOrchestrationSessionError: Error, Equatable, Sendable {
    case emptyRunID
    case emptyTabSet
    case invalidSecretLength(Int)
}

struct TaskOrchestrationSessionCredential: Equatable, Sendable {
    let sessionID: UUID
    let runID: String
    let token: String
    let expiresAt: Date
}

struct TaskOrchestrationAuthorization: Equatable, Sendable {
    let sessionID: UUID
    let runID: String
    let tabID: UUID
    let expiresAt: Date
}

struct TaskOrchestrationAuditEvent: Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let runID: String
    let tabID: UUID
    let command: String
    let payloadBytes: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        runID: String,
        tabID: UUID,
        command: String,
        payloadBytes: Int,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.runID = runID
        self.tabID = tabID
        self.command = command
        self.payloadBytes = max(0, payloadBytes)
        self.createdAt = createdAt
    }
}

protocol TaskOrchestrationAuditLogging: Sendable {
    func append(_ event: TaskOrchestrationAuditEvent) throws
}

final class TaskOrchestrationFileAuditLog: TaskOrchestrationAuditLogging, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        fileURL: URL = TaskOrchestrationFileAuditLog.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func append(_ event: TaskOrchestrationAuditEvent) throws {
        try lock.withLock {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(event)
            data.append(0x0A)

            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: [.atomic])
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        }
    }

    static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agent", isDirectory: true)
            .appendingPathComponent("task-orchestration.log")
    }
}

final class TaskOrchestrationSessionManager: @unchecked Sendable {
    static let defaultTTL: TimeInterval = 60 * 60
    static let defaultMaximumWrites = 4_096

    private struct Session: Equatable, Sendable {
        let id: UUID
        let runID: String
        let tabIDs: Set<UUID>
        let issuedAt: Date
        let expiresAt: Date
        let maximumWrites: Int
        var writeCount: Int
    }

    private let secret: Data
    private let ttl: TimeInterval
    private let maximumWrites: Int
    private let clock: @Sendable () -> Date
    private let auditLog: any TaskOrchestrationAuditLogging
    private let lock = NSLock()
    private var sessionsByID: [UUID: Session] = [:]
    private var sessionIDByRunID: [String: UUID] = [:]

    init(
        secret: Data = TaskOrchestrationSessionManager.randomSecret(),
        ttl: TimeInterval = TaskOrchestrationSessionManager.defaultTTL,
        maximumWrites: Int = TaskOrchestrationSessionManager.defaultMaximumWrites,
        clock: @escaping @Sendable () -> Date = { Date() },
        auditLog: any TaskOrchestrationAuditLogging = TaskOrchestrationFileAuditLog()
    ) {
        self.secret = secret
        self.ttl = max(1, ttl)
        self.maximumWrites = max(1, maximumWrites)
        self.clock = clock
        self.auditLog = auditLog
    }

    func issue(runID rawRunID: String, tabIDs: Set<UUID>) throws -> TaskOrchestrationSessionCredential {
        let runID = rawRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runID.isEmpty else { throw TaskOrchestrationSessionError.emptyRunID }
        guard !tabIDs.isEmpty else { throw TaskOrchestrationSessionError.emptyTabSet }
        guard secret.count == 32 else {
            throw TaskOrchestrationSessionError.invalidSecretLength(secret.count)
        }

        let issuedAt = clock()
        let session = Session(
            id: UUID(),
            runID: runID,
            tabIDs: tabIDs,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(ttl),
            maximumWrites: maximumWrites,
            writeCount: 0
        )
        lock.withLock {
            if let previousID = sessionIDByRunID[runID] {
                sessionsByID.removeValue(forKey: previousID)
            }
            sessionsByID[session.id] = session
            sessionIDByRunID[runID] = session.id
        }
        return credential(for: session)
    }

    func credential(forRunID runID: String) -> TaskOrchestrationSessionCredential? {
        lock.withLock {
            purgeExpiredSessions(at: clock())
            guard let id = sessionIDByRunID[runID],
                  let session = sessionsByID[id] else {
                return nil
            }
            return credential(for: session)
        }
    }

    func authorization(token: String, tabID: UUID) -> TaskOrchestrationAuthorization? {
        guard let (sessionID, signature) = Self.parseToken(token) else { return nil }
        return lock.withLock {
            let now = clock()
            purgeExpiredSessions(at: now)
            guard let session = sessionsByID[sessionID],
                  session.tabIDs.contains(tabID),
                  session.writeCount < session.maximumWrites,
                  constantTimeEqual(signature, sign(session)) else {
                return nil
            }
            return TaskOrchestrationAuthorization(
                sessionID: session.id,
                runID: session.runID,
                tabID: tabID,
                expiresAt: session.expiresAt
            )
        }
    }

    func recordWrite(
        authorization: TaskOrchestrationAuthorization,
        command: String,
        payloadBytes: Int
    ) -> Bool {
        recordWrite(
            sessionID: authorization.sessionID,
            runID: authorization.runID,
            tabID: authorization.tabID,
            expectedExpiresAt: authorization.expiresAt,
            command: command,
            payloadBytes: payloadBytes
        )
    }

    func recordWrite(
        sessionID: UUID,
        runID: String,
        tabID: UUID,
        command: String,
        payloadBytes: Int
    ) -> Bool {
        recordWrite(
            sessionID: sessionID,
            runID: runID,
            tabID: tabID,
            expectedExpiresAt: nil,
            command: command,
            payloadBytes: payloadBytes
        )
    }

    private func recordWrite(
        sessionID: UUID,
        runID: String,
        tabID: UUID,
        expectedExpiresAt: Date?,
        command: String,
        payloadBytes: Int
    ) -> Bool {
        lock.withLock {
            let now = clock()
            purgeExpiredSessions(at: now)
            guard var session = sessionsByID[sessionID],
                  session.runID == runID,
                  session.tabIDs.contains(tabID),
                  expectedExpiresAt == nil || session.expiresAt == expectedExpiresAt,
                  session.writeCount < session.maximumWrites,
                  command == "send" || command == "send-key" else {
                return false
            }
            do {
                try auditLog.append(TaskOrchestrationAuditEvent(
                    sessionID: session.id,
                    runID: session.runID,
                    tabID: tabID,
                    command: command,
                    payloadBytes: payloadBytes,
                    createdAt: now
                ))
            } catch {
                return false
            }
            session.writeCount += 1
            sessionsByID[session.id] = session
            return true
        }
    }

    func revoke(runID: String) {
        lock.withLock {
            guard let sessionID = sessionIDByRunID.removeValue(forKey: runID) else { return }
            sessionsByID.removeValue(forKey: sessionID)
        }
    }

    private func credential(for session: Session) -> TaskOrchestrationSessionCredential {
        TaskOrchestrationSessionCredential(
            sessionID: session.id,
            runID: session.runID,
            token: "\(session.id.uuidString).\(Self.base64URL(sign(session)))",
            expiresAt: session.expiresAt
        )
    }

    private func sign(_ session: Session) -> Data {
        let payload = [
            session.id.uuidString,
            session.runID,
            session.tabIDs.map(\.uuidString).sorted().joined(separator: ","),
            String(format: "%.6f", session.issuedAt.timeIntervalSince1970),
            String(format: "%.6f", session.expiresAt.timeIntervalSince1970),
            String(session.maximumWrites),
        ].joined(separator: "|")
        let key = SymmetricKey(data: secret)
        return Data(HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key))
    }

    private func purgeExpiredSessions(at now: Date) {
        let expiredIDs = sessionsByID.values
            .filter { now >= $0.expiresAt }
            .map(\.id)
        for id in expiredIDs {
            guard let session = sessionsByID.removeValue(forKey: id) else { continue }
            if sessionIDByRunID[session.runID] == id {
                sessionIDByRunID.removeValue(forKey: session.runID)
            }
        }
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    private static func parseToken(_ token: String) -> (UUID, Data)? {
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2,
              let sessionID = UUID(uuidString: String(components[0])),
              let signature = decodeBase64URL(String(components[1])) else {
            return nil
        }
        return (sessionID, signature)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: base64)
    }

    private static func randomSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
