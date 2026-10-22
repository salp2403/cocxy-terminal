// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayHandshake.swift - Authenticated relay wire protocol.

import Foundation

/// Implements the binary wire protocol for relay authentication.
///
/// Wire format: a 40-byte payload containing channel UUID, timestamp, and
/// random nonce, prefixed by its length and followed by a 32-byte HMAC.
enum RelayHandshake {
    static let nonceSize = 16
    static let payloadSize = 40
    static let totalSize = 76
    static let timestampTolerance: UInt64 = 60

    enum ValidationResult: Equatable, Sendable {
        case accepted
        case rejected(RejectionReason)
    }

    enum RejectionReason: Equatable, Sendable {
        case malformed
        case channelMismatch
        case timestampExpired
        case invalidSignature
        case replayDetected
    }

    static func build(channelID: UUID, timestamp: UInt64, token: RelayToken) -> Data {
        var data = Data()
        var payloadLength = UInt32(payloadSize).bigEndian
        data.append(Data(bytes: &payloadLength, count: 4))
        data.append(withUnsafeBytes(of: channelID.uuid) { Data($0) })
        var bigEndianTimestamp = timestamp.bigEndian
        data.append(Data(bytes: &bigEndianTimestamp, count: 8))

        var generator = SystemRandomNumberGenerator()
        data.append(Data((0..<nonceSize).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }))
        data.append(token.sign(data[4..<44]))
        return data
    }

    static func validate(
        data: Data,
        expectedChannelID: UUID,
        token: RelayToken,
        replayTracker: UnsafeMutablePointer<ReplayTracker>?
    ) -> ValidationResult {
        guard data.count >= totalSize else { return .rejected(.malformed) }
        let payloadLength = Data(data[0..<4]).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).bigEndian
        }
        guard payloadLength == UInt32(payloadSize) else { return .rejected(.malformed) }

        let receivedUUID = Data(data[4..<20]).withUnsafeBytes { buffer -> UUID in
            UUID(uuid: buffer.loadUnaligned(as: uuid_t.self))
        }
        guard receivedUUID == expectedChannelID else { return .rejected(.channelMismatch) }

        let timestamp = Data(data[20..<28]).withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self).bigEndian
        }
        let now = UInt64(Date().timeIntervalSince1970)
        let difference = timestamp > now ? timestamp - now : now - timestamp
        guard difference <= timestampTolerance else { return .rejected(.timestampExpired) }

        let payload = Data(data[4..<44])
        let nonce = Data(data[28..<44])
        let signature = Data(data[44..<76])
        guard token.validate(payload: payload, signature: signature) else {
            return .rejected(.invalidSignature)
        }
        if let replayTracker,
           !replayTracker.pointee.isAllowed(timestamp: timestamp, nonce: nonce) {
            return .rejected(.replayDetected)
        }
        return .accepted
    }
}
