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

    /// Machine-readable event type name.
    var typeName: String {
        switch self {
        case .channelOpened: return "channelOpened"
        case .connectionAccepted: return "connectionAccepted"
        case .connectionRejected: return "connectionRejected"
        case .tokenRotated: return "tokenRotated"
        case .channelClosed: return "channelClosed"
        }
    }

    /// Channel ID associated with this event.
    var channelID: UUID {
        switch self {
        case .channelOpened(let id, _),
             .connectionAccepted(let id, _),
             .connectionRejected(let id, _, _),
             .tokenRotated(let id),
             .channelClosed(let id):
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
        case .tokenRotated, .channelClosed:
            break
        }
        return dict
    }
}

// MARK: - Audit Log Writing Protocol

/// Abstraction for audit log file I/O. Enables testing without filesystem.
protocol AuditLogWriting: AnyObject, Sendable {
    func appendLine(_ line: String) throws
    func rotate() throws
    func readAllLines() throws -> [String]
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

    init(writer: any AuditLogWriting, maxSizeBytes: Int = 10 * 1024 * 1024) {
        self.writer = writer
        self.maxSizeBytes = maxSizeBytes
    }

    /// Logs an audit event.
    ///
    /// Serializes the event to a JSON line and appends it to the log.
    func log(_ event: RelayAuditEvent) {
        let json = event.toJSON()
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let line = String(data: data, encoding: .utf8)
        else { return }

        try? writer.appendLine(line)
    }

    /// Reads all log entries.
    func readAll() -> [String] {
        (try? writer.readAllLines()) ?? []
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

    func readAllLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: filePath) else { return [] }
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        return content.split(separator: "\n").map(String.init)
    }
}
