// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Foundation

public enum SignatureAlgorithm: String, Codable, Sendable, Equatable {
    case ed25519
}

public enum SignatureKeyError: Error, Equatable, Sendable {
    case keyIDMismatch(expected: String, actual: String)
    case unsupportedAlgorithm(SignatureAlgorithm)
    case invalidPublicKey
    case invalidPrivateKey
}

public struct SignaturePublicKey: Codable, Equatable, Sendable {
    public let algorithm: SignatureAlgorithm
    public let keyID: String
    public let author: String
    public let rawRepresentation: Data

    public var publicKeyBase64: String {
        rawRepresentation.base64EncodedString()
    }

    public var fingerprint: String {
        SignatureDigest.sha256Hex(rawRepresentation)
    }

    public init(
        algorithm: SignatureAlgorithm,
        keyID: String,
        author: String,
        rawRepresentation: Data
    ) throws {
        let actualKeyID = SignatureDigest.keyID(for: rawRepresentation)
        guard keyID == actualKeyID else {
            throw SignatureKeyError.keyIDMismatch(expected: keyID, actual: actualKeyID)
        }
        self.algorithm = algorithm
        self.keyID = keyID
        self.author = author
        self.rawRepresentation = rawRepresentation
    }
}

public struct SignatureKeyPair: Codable, Equatable, Sendable {
    public let algorithm: SignatureAlgorithm
    public let keyID: String
    public let author: String
    public let publicKeyRawRepresentation: Data
    public let privateKeyRawRepresentation: Data?

    public var hasPrivateKey: Bool {
        privateKeyRawRepresentation != nil
    }

    public var publicKeyBase64: String {
        publicKeyRawRepresentation.base64EncodedString()
    }

    public var fingerprint: String {
        SignatureDigest.sha256Hex(publicKeyRawRepresentation)
    }

    public var publicKey: SignaturePublicKey {
        try! SignaturePublicKey(
            algorithm: algorithm,
            keyID: keyID,
            author: author,
            rawRepresentation: publicKeyRawRepresentation
        )
    }

    public static func generate(author: String) throws -> SignatureKeyPair {
        let privateKey = Curve25519.Signing.PrivateKey()
        return try SignatureKeyPair(
            algorithm: .ed25519,
            author: author,
            publicKeyRawRepresentation: privateKey.publicKey.rawRepresentation,
            privateKeyRawRepresentation: privateKey.rawRepresentation
        )
    }

    public init(
        algorithm: SignatureAlgorithm,
        author: String,
        publicKeyRawRepresentation: Data,
        privateKeyRawRepresentation: Data?
    ) throws {
        let keyID = SignatureDigest.keyID(for: publicKeyRawRepresentation)
        self.algorithm = algorithm
        self.keyID = keyID
        self.author = author
        self.publicKeyRawRepresentation = publicKeyRawRepresentation
        self.privateKeyRawRepresentation = privateKeyRawRepresentation
    }

    public func publicOnly() -> SignatureKeyPair {
        try! SignatureKeyPair(
            algorithm: algorithm,
            author: author,
            publicKeyRawRepresentation: publicKeyRawRepresentation,
            privateKeyRawRepresentation: nil
        )
    }

    func privateSigningKey() throws -> Curve25519.Signing.PrivateKey {
        guard algorithm == .ed25519 else {
            throw SignatureKeyError.unsupportedAlgorithm(algorithm)
        }
        guard let privateKeyRawRepresentation else {
            throw SignatureSigningError.missingPrivateKey(keyID)
        }
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRawRepresentation)
        } catch {
            throw SignatureKeyError.invalidPrivateKey
        }
    }
}
