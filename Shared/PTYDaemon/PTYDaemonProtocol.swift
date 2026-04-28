// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonProtocol.swift - Shared JSONL contract for the local PTY daemon.

import Foundation

public enum PTYDaemonProtocol {
    public static let helperName = "cocxyd"
    public static let protocolVersion = 1
    public static let jsonLinesCapability = "ipc-jsonl-v1"
    public static let terminalSurfaceCapability = "terminal-surface-v1"
}

public struct PTYDaemonHello: Codable, Equatable, Sendable {
    public let version: String
    public let protocolVersion: Int
    public let pid: Int32?
    public let capabilities: [String]

    public init(
        version: String,
        protocolVersion: Int = PTYDaemonProtocol.protocolVersion,
        pid: Int32? = nil,
        capabilities: [String] = [PTYDaemonProtocol.jsonLinesCapability]
    ) {
        self.version = version
        self.protocolVersion = protocolVersion
        self.pid = pid
        self.capabilities = capabilities
    }

    public var supportsTerminalSurfaces: Bool {
        capabilities.contains(PTYDaemonProtocol.terminalSurfaceCapability)
    }
}

public struct PTYDaemonRequest: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable {
        case hello
        case shutdown
    }

    public let id: String
    public let command: Command

    public init(id: String, command: Command) {
        self.id = id
        self.command = command
    }
}

public struct PTYDaemonResponse: Codable, Equatable, Sendable {
    public let id: String
    public let ok: Bool
    public let hello: PTYDaemonHello?
    public let error: String?

    public init(id: String, ok: Bool, hello: PTYDaemonHello? = nil, error: String? = nil) {
        self.id = id
        self.ok = ok
        self.hello = hello
        self.error = error
    }
}

public enum PTYDaemonLineCodec {
    public enum CodecError: Error, Equatable {
        case missingNewline
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, fromLine data: Data) throws -> T {
        guard data.last == 0x0A else { throw CodecError.missingNewline }
        return try JSONDecoder().decode(type, from: data.dropLast())
    }
}
