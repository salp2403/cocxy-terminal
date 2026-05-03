// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ComputerUseAuditLog.swift - Local audit trail for computer actions.

import Foundation

struct ComputerUseAuditLog: Sendable {
    let fileURL: URL
    private let clock: @Sendable () -> Date

    init(
        fileURL: URL = ComputerUseAuditLog.defaultFileURL(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.clock = clock
    }

    func record(
        action: String,
        outcome: ComputerUseAuditOutcome,
        metadata: [String: ComputerUseAuditValue] = [:]
    ) throws {
        let event = ComputerUseAuditEvent(
            timestamp: ISO8601DateFormatter().string(from: clock()),
            action: action,
            outcome: outcome,
            metadata: metadata
        )
        var data = try JSONEncoder.sorted.encode(event)
        data.append(0x0A)

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }

    static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agent", isDirectory: true)
            .appendingPathComponent("computer-use.log")
    }
}

enum ComputerUseAuditOutcome: String, Codable, Sendable, Equatable {
    case success
    case denied
    case failure
}

enum ComputerUseAuditValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

private struct ComputerUseAuditEvent: Codable {
    let timestamp: String
    let action: String
    let outcome: ComputerUseAuditOutcome
    let metadata: [String: ComputerUseAuditValue]
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
