// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayAuditLog.swift - JSON lines audit log for relay channel events.

import Foundation

// MARK: - Audit Events

/// Events tracked by the relay audit log.
enum RelayAuditEvent: Sendable {
    case channelOpened(channelID: UUID, name: String)
    case connectionAccepted(channelID: UUID, remoteHost: String)
    case connectionRejected(channelID: UUID, remoteHost: String, reason: String)
    case tokenRotated(channelID: UUID)
    case channelClosed(channelID: UUID)
    case mobileAction(
        channelID: UUID,
        remoteHost: String,
        action: String,
        targetDigest: String,
        outcome: String
    )
    case mobileRequestRejected(
        channelID: UUID,
        remoteHost: String,
        reason: String
    )

    /// Machine-readable event type name.
    var typeName: String {
        switch self {
        case .channelOpened: return "channelOpened"
        case .connectionAccepted: return "connectionAccepted"
        case .connectionRejected: return "connectionRejected"
        case .tokenRotated: return "tokenRotated"
        case .channelClosed: return "channelClosed"
        case .mobileAction: return "mobileAction"
        case .mobileRequestRejected: return "mobileRequestRejected"
        }
    }

    /// Channel ID associated with this event.
    var channelID: UUID {
        switch self {
        case .channelOpened(let id, _),
             .connectionAccepted(let id, _),
             .connectionRejected(let id, _, _),
             .tokenRotated(let id),
             .channelClosed(let id),
             .mobileAction(let id, _, _, _, _),
             .mobileRequestRejected(let id, _, _):
            return id
        }
    }

    /// Serializes the event to a JSON dictionary.
    func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "event": typeName,
            "channelID": channelID.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        switch self {
        case .channelOpened(_, let name):
            dict["name"] = name
        case .connectionAccepted(_, let host):
            dict["remoteHost"] = host
        case .connectionRejected(_, let host, let reason):
            dict["remoteHost"] = host
            dict["reason"] = reason
        case .mobileAction(_, let host, let action, let targetDigest, let outcome):
            dict["remoteHost"] = host
            dict["action"] = action
            dict["targetDigest"] = targetDigest
            dict["outcome"] = outcome
        case .mobileRequestRejected(_, let host, let reason):
            dict["remoteHost"] = host
            dict["reason"] = reason
        case .tokenRotated, .channelClosed:
            break
        }
        return dict
    }
}

enum RelayAuditLogError: Error, Equatable, LocalizedError, Sendable {
    case serializationFailed(String)
    case appendFailed(String)
    case rotationFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .serializationFailed(let reason):
            return "Audit event serialization failed: \(reason)"
        case .appendFailed(let reason):
            return "Audit event persistence failed: \(reason)"
        case .rotationFailed(let reason):
            return "Audit log rotation failed: \(reason)"
        case .readFailed(let reason):
            return "Audit log read failed: \(reason)"
        }
    }
}

// MARK: - Audit Log Writing Protocol

/// Abstraction for audit log file I/O. Enables testing without filesystem.
protocol AuditLogWriting: AnyObject, Sendable {
    func appendLine(_ line: String) throws
    func rotate() throws
    func readAllLines() throws -> [String]
    /// Returns the current size of the log in bytes.
    var currentSize: Int { get }
}

// MARK: - Relay Audit Log

/// Append-only JSON lines audit log for relay channel events.
///
/// Each event is written as a single JSON object on one line.
/// Auto-rotation occurs when the log exceeds `maxSizeBytes` (default 10 MB).
///
/// ## Log Format
///
/// ```json
/// {"event":"channelOpened","channelID":"...","timestamp":"...","name":"api"}
/// {"event":"connectionAccepted","channelID":"...","timestamp":"...","remoteHost":"127.0.0.1"}
/// ```
@MainActor
final class RelayAuditLog {

    /// Maximum log size before rotation (default 10 MB).
    let maxSizeBytes: Int

    private let writer: any AuditLogWriting
    private(set) var lastFailure: RelayAuditLogError?

    init(writer: any AuditLogWriting, maxSizeBytes: Int = 10 * 1024 * 1024) {
        self.writer = writer
        self.maxSizeBytes = maxSizeBytes
    }

    /// Logs an audit event.
    ///
    /// Serializes the event to a JSON line and appends it to the log.
    /// Triggers rotation when the log exceeds `maxSizeBytes`.
    func log(_ event: RelayAuditEvent) throws {
        let json = event.toJSON()
        let line: String
        do {
            let data = try JSONSerialization.data(withJSONObject: json)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw RelayAuditLogError.serializationFailed("invalid UTF-8")
            }
            line = encoded
        } catch let error as RelayAuditLogError {
            lastFailure = error
            throw error
        } catch {
            let failure = RelayAuditLogError.serializationFailed(error.localizedDescription)
            lastFailure = failure
            throw failure
        }

        do {
            try writer.appendLine(line)
        } catch {
            let failure = RelayAuditLogError.appendFailed(error.localizedDescription)
            lastFailure = failure
            throw failure
        }

        if writer.currentSize >= maxSizeBytes {
            do {
                try writer.rotate()
            } catch {
                let failure = RelayAuditLogError.rotationFailed(error.localizedDescription)
                lastFailure = failure
                throw failure
            }
        }
        lastFailure = nil
    }

    /// Reads all log entries.
    func readAll() throws -> [String] {
        do {
            return try writer.readAllLines()
        } catch {
            let failure = RelayAuditLogError.readFailed(error.localizedDescription)
            lastFailure = failure
            throw failure
        }
    }
}

// MARK: - Disk Audit Log Writer

/// Production implementation that writes to `~/.config/cocxy/relay/audit.log`.
final class DiskAuditLogWriter: AuditLogWriting, @unchecked Sendable {

    static let defaultPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/.config/cocxy/relay/audit.log"
    }()

    private let filePath: String
    private let maxRotatedFiles: Int

    init(filePath: String = DiskAuditLogWriter.defaultPath, maxRotatedFiles: Int = 3) {
        self.filePath = filePath
        self.maxRotatedFiles = maxRotatedFiles
    }

    func appendLine(_ line: String) throws {
        let url = URL(fileURLWithPath: filePath)
        let directory = url.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: filePath) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            handle.closeFile()
        } else {
            try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func rotate() throws {
        let fm = FileManager.default

        // Shift existing rotated files: .2 → .3, .1 → .2, etc.
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let from = "\(filePath).\(i)"
            let to = "\(filePath).\(i + 1)"
            if fm.fileExists(atPath: from) {
                try? fm.removeItem(atPath: to)
                try fm.moveItem(atPath: from, toPath: to)
            }
        }

        // Current → .1
        if fm.fileExists(atPath: filePath) {
            try? fm.removeItem(atPath: "\(filePath).1")
            try fm.moveItem(atPath: filePath, toPath: "\(filePath).1")
        }
    }

    var currentSize: Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
              let size = attrs[.size] as? Int
        else { return 0 }
        return size
    }

    func readAllLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: filePath) else { return [] }
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        return content.split(separator: "\n").map(String.init)
    }
}
