// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorEncryptedActionEnvelope.swift - Authenticated mobile action payloads.

import CryptoKit
import Foundation

enum MobileMirrorEncryptedActionEnvelopeError: Error, Equatable {
    case invalidEnvelope
}

struct MobileMirrorOpenedActionEnvelope: Equatable, Sendable {
    let sequence: UInt64
    let plaintext: Data
}

enum MobileMirrorEncryptedActionEnvelope {
    static let headerLength = 26
    static let tagLength = 16
    static let maximumSequence: UInt64 = 9_007_199_254_740_991

    private struct Container: Decodable {
        let envelope: String
    }

    static func open(
        requestBody: Data,
        encryptionKey: Data
    ) throws -> MobileMirrorOpenedActionEnvelope {
        do {
            guard encryptionKey.count == 32 else { throw InvalidEnvelope() }
            let container = try JSONDecoder().decode(Container.self, from: requestBody)
            let envelope = try decodeBase64URL(container.envelope)
            guard envelope.count >= headerLength + tagLength,
                  envelope.prefix(4) == Data("CXYE".utf8),
                  envelope[4] == 2,
                  envelope[5] == 1 else {
                throw InvalidEnvelope()
            }

            let header = Data(envelope.prefix(headerLength))
            let sequence = readSequence(from: header)
            guard sequence <= maximumSequence else { throw InvalidEnvelope() }

            let nonce = try AES.GCM.Nonce(data: header[14..<headerLength])
            let ciphertextEnd = envelope.count - tagLength
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: Data(envelope[headerLength..<ciphertextEnd]),
                tag: Data(envelope.suffix(tagLength))
            )
            let plaintext = try AES.GCM.open(
                sealedBox,
                using: SymmetricKey(data: encryptionKey),
                authenticating: header
            )
            return MobileMirrorOpenedActionEnvelope(
                sequence: sequence,
                plaintext: plaintext
            )
        } catch {
            throw MobileMirrorEncryptedActionEnvelopeError.invalidEnvelope
        }
    }

    private static func readSequence(from header: Data) -> UInt64 {
        header[6..<14].reduce(into: UInt64.zero) { value, byte in
            value = (value << 8) | UInt64(byte)
        }
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        guard !value.isEmpty,
              value.utf8.count <= MobileMirrorHTTPRequest.maximumBodyBytes,
              value.utf8.allSatisfy({ byte in
                  byte >= 48 && byte <= 57
                      || byte >= 65 && byte <= 90
                      || byte >= 97 && byte <= 122
                      || byte == 45 || byte == 95
              }),
              value.utf8.count % 4 != 1 else {
            throw InvalidEnvelope()
        }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let decoded = Data(base64Encoded: base64) else { throw InvalidEnvelope() }
        return decoded
    }

    private struct InvalidEnvelope: Error {}
}
