// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLIMessageFraming.swift - Length-prefixed framing for CLI socket protocol.

import Foundation

// MARK: - CLI Message Framing

/// Utilities for the length-prefixed message framing protocol.
///
/// Wire format:
/// ```
/// [4 bytes: payload length, big-endian UInt32][N bytes: JSON payload]
/// ```
///
/// Maximum payload size is 64 KB to match the server's limit.
///
/// This is a standalone copy of the app's `SocketMessageFraming`.
/// The CLI must not import the main app module.
public enum CLIMessageFraming {

    /// The number of bytes used for the length prefix.
    public static let headerSize: Int = 4

    /// Maximum allowed payload size in bytes (64 KB).
    public static let maxPayloadSize: UInt32 = 65_536

    /// Encodes a payload length as a 4-byte big-endian prefix.
    ///
    /// - Parameter length: The payload length to encode.
    /// - Returns: A 4-byte Data value containing the big-endian length.
    public static func encodeLength(_ length: UInt32) -> Data {
        var bigEndianLength = length.bigEndian
        return Data(bytes: &bigEndianLength, count: 4)
    }

    /// Decodes a 4-byte big-endian length prefix.
    ///
    /// - Parameter data: Exactly 4 bytes of big-endian length data.
    /// - Returns: The decoded payload length, or nil if data is not 4 bytes.
    public static func decodeLength(_ data: Data) -> UInt32? {
        guard data.count == 4 else { return nil }
        let value = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        return UInt32(bigEndian: value)
    }

    /// Frames a JSON-encodable value into a length-prefixed message.
    ///
    /// - Parameter value: The value to encode as JSON.
    /// - Returns: The framed message (4-byte header + JSON payload).
    /// - Throws: `CLIError.payloadTooLarge` if the payload exceeds max size.
    public static func frame<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(value)

        guard payload.count <= maxPayloadSize else {
            throw CLIError.payloadTooLarge(
                size: payload.count,
                maximum: Int(maxPayloadSize)
            )
        }

        let header = encodeLength(UInt32(payload.count))
        return header + payload
    }

    /// Extracts the payload from a framed message.
    ///
    /// - Parameters:
    ///   - type: The expected type to decode.
    ///   - framedData: The complete framed message (header + payload).
    /// - Returns: The decoded value.
    /// - Throws: `CLIError.malformedResponse` on failure.
    public static func unframe<T: Decodable>(_ type: T.Type, from framedData: Data) throws -> T {
        guard framedData.count >= headerSize else {
            throw CLIError.malformedResponse(reason: "Data too short for header")
        }

        let headerData = framedData.prefix(headerSize)
        guard let payloadLength = decodeLength(headerData) else {
            throw CLIError.malformedResponse(reason: "Invalid length header")
        }

        let expectedTotal = headerSize + Int(payloadLength)
        guard framedData.count >= expectedTotal else {
            throw CLIError.malformedResponse(
                reason: "Expected \(expectedTotal) bytes, got \(framedData.count)"
            )
        }

        let payload = framedData[headerSize..<expectedTotal]
        return try JSONDecoder().decode(type, from: payload)
    }
}
