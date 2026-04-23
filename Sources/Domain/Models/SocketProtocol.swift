// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketProtocol.swift - Wire protocol types for CLI-to-app communication.

import Foundation

// MARK: - Socket Request

/// A command request received from the CLI companion over the Unix Domain Socket.
///
/// Wire format: 4 bytes big-endian payload length + JSON payload.
///
/// Example JSON:
/// ```json
/// {
///   "id": "550e8400-e29b-41d4-a716-446655440000",
///   "command": "notify",
///   "params": { "message": "Task completed" }
/// }
/// ```
///
/// - SeeAlso: `SocketResponse` for the reply format.
/// - SeeAlso: ADR-006 (CLI communication).
struct SocketRequest: Codable, Sendable, Equatable {
    /// Unique identifier for this request. Used to match responses.
    let id: String

    /// The command to execute.
    let command: String

    /// Command-specific parameters. Nil when the command takes no arguments.
    let params: [String: String]?
}

// MARK: - Socket Response

/// A response sent back to the CLI companion after processing a `SocketRequest`.
///
/// Wire format: 4 bytes big-endian payload length + JSON payload.
///
/// Example JSON (success):
/// ```json
/// {
///   "id": "550e8400-e29b-41d4-a716-446655440000",
///   "success": true,
///   "data": { "tabCount": "3" }
/// }
/// ```
///
/// Example JSON (error):
/// ```json
/// {
///   "id": "550e8400-e29b-41d4-a716-446655440000",
///   "success": false,
///   "error": "Unknown command: foo"
/// }
/// ```
struct SocketResponse: Codable, Sendable, Equatable {
    /// Matches the `id` of the originating `SocketRequest`.
    let id: String

    /// Whether the command was executed successfully.
    let success: Bool

    /// Command-specific response data. Nil on error.
    let data: [String: String]?

    /// Error message when `success` is `false`. Nil on success.
    let error: String?

    /// Convenience factory for a successful response with data.
    static func ok(id: String, data: [String: String]? = nil) -> SocketResponse {
        SocketResponse(id: id, success: true, data: data, error: nil)
    }

    /// Convenience factory for a failed response.
    static func failure(id: String, error: String) -> SocketResponse {
        SocketResponse(id: id, success: false, data: nil, error: error)
    }
}

// MARK: - Message Framing

/// Utilities for the length-prefixed message framing protocol.
///
/// Wire format:
/// ```
/// [4 bytes: payload length, big-endian UInt32][N bytes: JSON payload]
/// ```
///
/// The maximum payload size is 64 KB (65,536 bytes) to prevent
/// denial-of-service via oversized messages.
enum SocketMessageFraming {

    /// The number of bytes used for the length prefix.
    static let headerSize: Int = 4

    /// Maximum allowed payload size in bytes (64 KB).
    static let maxPayloadSize: UInt32 = 65_536

    /// Encodes a payload length as a 4-byte big-endian prefix.
    ///
    /// - Parameter length: The payload length to encode.
    /// - Returns: A 4-byte Data value containing the big-endian length.
    static func encodeLength(_ length: UInt32) -> Data {
        var bigEndianLength = length.bigEndian
        return Data(bytes: &bigEndianLength, count: 4)
    }

    /// Decodes a 4-byte big-endian length prefix.
    ///
    /// - Parameter data: Exactly 4 bytes of big-endian length data.
    /// - Returns: The decoded payload length, or nil if data is not 4 bytes.
    static func decodeLength(_ data: Data) -> UInt32? {
        guard data.count == 4 else { return nil }
        let value = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        return UInt32(bigEndian: value)
    }

    /// Frames a JSON-encodable value into a length-prefixed message.
    ///
    /// - Parameter value: The value to encode as JSON.
    /// - Returns: The framed message (4-byte header + JSON payload).
    /// - Throws: `CLISocketError.malformedMessage` if the payload exceeds max size.
    static func frame<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(value)

        guard payload.count <= maxPayloadSize else {
            throw CLISocketError.malformedMessage(
                reason: "Payload size \(payload.count) exceeds maximum \(maxPayloadSize)"
            )
        }

        let header = encodeLength(UInt32(payload.count))
        return header + payload
    }
}

// MARK: - Socket Server Constants

/// Configuration constants for the Unix Domain Socket server.
///
/// Centralizes security-sensitive values to make auditing easier.
enum SocketServerConstants {
    /// Path to the socket file. Uses XDG-style config directory.
    static let socketDirectory: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/cocxy"
    }()

    /// Full path to the socket file.
    static let socketPath: String = {
        return "\(socketDirectory)/cocxy.sock"
    }()

    /// POSIX permissions for the socket file (owner-only read/write).
    static let socketPermissions: mode_t = 0o600

    /// Maximum number of concurrent client connections.
    static let maxConcurrentConnections: Int = 10

    /// Connection inactivity timeout in seconds.
    static let connectionTimeoutSeconds: TimeInterval = 30

    /// Maximum pending connections in the listen backlog.
    ///
    /// Set to 128 (equivalent to `SOMAXCONN` on macOS) to absorb bursts of
    /// concurrent connects — notably multiple Claude Code hook events
    /// emitted in parallel plus concurrent CLI invocations. A backlog of 5
    /// was observed to drop ~80% of connections under 10 simultaneous
    /// connects, surfacing as `EPIPE` on the client side because the kernel
    /// acknowledges the SYN/connect but then purges the queued peer before
    /// our accept loop picks it up.
    static let listenBacklog: Int32 = 128
}
