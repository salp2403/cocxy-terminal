// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentConversationEncryption.swift - Optional local encryption for conversation records.

import CryptoKit
import CommonCrypto
import Foundation
import Security

enum AgentConversationEncryptionError: Error, Sendable, Equatable {
    case emptyPassphrase
    case randomSaltFailed
    case invalidSaltLength
    case invalidLinePrefix
    case invalidEnvelope
    case invalidCiphertext
    case invalidPlaintext
    case invalidIterationCount
    case keyDerivationFailed
}

struct AgentConversationLineCodec: Sendable {
    static let plaintext = AgentConversationLineCodec(storage: .plaintext)

    private enum Storage: Sendable {
        case plaintext
        case encrypted(AgentConversationEncryptionCodec)
    }

    private let storage: Storage

    static func encrypted(
        passphrase: String,
        saltGenerator: @escaping @Sendable () throws -> Data = { try AgentConversationEncryptionCodec.randomSalt() }
    ) throws -> AgentConversationLineCodec {
        AgentConversationLineCodec(
            storage: .encrypted(
                try AgentConversationEncryptionCodec(
                    passphrase: passphrase,
                    saltGenerator: saltGenerator
                )
            )
        )
    }

    func encodeLine(_ message: AgentMessage) throws -> Data {
        let plaintextLine = try AgentMessageSerializer.encodeLine(message)

        switch storage {
        case .plaintext:
            return Data(plaintextLine.utf8)
        case .encrypted(let codec):
            let encryptedLine = try codec.encrypt(Data(plaintextLine.utf8))
            return Data((encryptedLine + "\n").utf8)
        }
    }

    func decodeLine(_ line: String) throws -> AgentMessage {
        switch storage {
        case .plaintext:
            return try AgentMessageSerializer.decodeLine(line)
        case .encrypted(let codec):
            let plaintext = try codec.decrypt(line)
            guard let decodedLine = String(data: plaintext, encoding: .utf8) else {
                throw AgentConversationEncryptionError.invalidPlaintext
            }
            return try AgentMessageSerializer.decodeLine(decodedLine)
        }
    }

    private init(storage: Storage) {
        self.storage = storage
    }
}

struct AgentConversationEncryptionCodec: Sendable {
    static let linePrefix = "cocxy-agent-v1:"
    static let saltByteCount = 16

    private static let envelopeHeaderByteCount = 4
    private static let keyByteCount = 32
    private static let keyDerivationIterations: UInt32 = 210_000
    private static let maxKeyDerivationIterations: UInt32 = 1_000_000

    private let passphraseData: Data
    private let saltGenerator: @Sendable () throws -> Data

    init(
        passphrase: String,
        saltGenerator: @escaping @Sendable () throws -> Data = { try AgentConversationEncryptionCodec.randomSalt() }
    ) throws {
        guard !passphrase.isEmpty else {
            throw AgentConversationEncryptionError.emptyPassphrase
        }
        self.passphraseData = Data(passphrase.utf8)
        self.saltGenerator = saltGenerator
    }

    static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: saltByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AgentConversationEncryptionError.randomSaltFailed
        }
        return Data(bytes)
    }

    func encrypt(_ plaintext: Data) throws -> String {
        let salt = try saltGenerator()
        guard salt.count == Self.saltByteCount else {
            throw AgentConversationEncryptionError.invalidSaltLength
        }

        let key = try Self.deriveKey(
            passphraseData: passphraseData,
            salt: salt,
            iterations: Self.keyDerivationIterations
        )
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let ciphertext = sealedBox.combined else {
            throw AgentConversationEncryptionError.invalidCiphertext
        }

        var envelope = Data()
        envelope.append(Self.encodedIterations(Self.keyDerivationIterations))
        envelope.append(salt)
        envelope.append(ciphertext)
        return Self.linePrefix + envelope.base64EncodedString()
    }

    func decrypt(_ line: String) throws -> Data {
        guard line.hasPrefix(Self.linePrefix) else {
            throw AgentConversationEncryptionError.invalidLinePrefix
        }

        let encodedEnvelope = String(line.dropFirst(Self.linePrefix.count))
        guard let envelope = Data(base64Encoded: encodedEnvelope) else {
            throw AgentConversationEncryptionError.invalidEnvelope
        }
        guard envelope.count > Self.envelopeHeaderByteCount + Self.saltByteCount else {
            throw AgentConversationEncryptionError.invalidEnvelope
        }

        let iterations = try Self.decodedIterations(from: envelope.prefix(Self.envelopeHeaderByteCount))
        let saltStart = Self.envelopeHeaderByteCount
        let saltEnd = saltStart + Self.saltByteCount
        let salt = envelope.subdata(in: saltStart..<saltEnd)
        let ciphertext = envelope.subdata(in: saltEnd..<envelope.count)
        let key = try Self.deriveKey(
            passphraseData: passphraseData,
            salt: salt,
            iterations: iterations
        )
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func deriveKey(passphraseData: Data, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard iterations > 0 && iterations <= maxKeyDerivationIterations else {
            throw AgentConversationEncryptionError.invalidIterationCount
        }

        var derivedKey = Data(repeating: 0, count: keyByteCount)
        let status = derivedKey.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                passphraseData.withUnsafeBytes { passphraseBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passphraseBytes.bindMemory(to: Int8.self).baseAddress,
                        passphraseData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw AgentConversationEncryptionError.keyDerivationFailed
        }
        return SymmetricKey(data: derivedKey)
    }

    private static func encodedIterations(_ iterations: UInt32) -> Data {
        var bigEndianIterations = iterations.bigEndian
        return withUnsafeBytes(of: &bigEndianIterations) { Data($0) }
    }

    private static func decodedIterations(from data: Data.SubSequence) throws -> UInt32 {
        guard data.count == envelopeHeaderByteCount else {
            throw AgentConversationEncryptionError.invalidEnvelope
        }

        let iterations = data.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        guard iterations > 0 && iterations <= maxKeyDerivationIterations else {
            throw AgentConversationEncryptionError.invalidIterationCount
        }
        return iterations
    }
}
