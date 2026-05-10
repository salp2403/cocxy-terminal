// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct SignedArtifact: Codable, Equatable, Sendable {
    public let algorithm: SignatureAlgorithm
    public let keyID: String
    public let author: String
    public let timestamp: Date
    public let payloadSHA256: String
    public let signature: String

    public init(
        algorithm: SignatureAlgorithm,
        keyID: String,
        author: String,
        timestamp: Date,
        payloadSHA256: String,
        signature: String
    ) {
        self.algorithm = algorithm
        self.keyID = keyID
        self.author = author
        self.timestamp = timestamp
        self.payloadSHA256 = payloadSHA256
        self.signature = signature
    }
}

enum SignatureCanonicalPayload {
    static func data(
        algorithm: SignatureAlgorithm,
        keyID: String,
        author: String,
        timestamp: Date,
        payloadSHA256: String
    ) -> Data {
        let timestampString = ISO8601DateFormatter.cocxySignature.string(from: timestamp)
        return Data("""
        cocxy-signature-v1
        algorithm:\(algorithm.rawValue)
        key-id:\(keyID)
        author:\(author)
        timestamp:\(timestampString)
        payload-sha256:\(payloadSHA256)
        """.utf8)
    }
}

public enum SignedArtifactFrontmatterError: Error, Equatable, Sendable {
    case missingSignatureBlock
    case invalidTimestamp(String)
    case missingField(String)
    case unsupportedAlgorithm(String)
}

public enum SignedArtifactFrontmatter {
    public static func encode(_ artifact: SignedArtifact) throws -> String {
        let timestamp = ISO8601DateFormatter.cocxySignature.string(from: artifact.timestamp)
        return """
        signature:
          algorithm: \(artifact.algorithm.rawValue)
          key-id: \(artifact.keyID)
          author: \(artifact.author)
          timestamp: \(timestamp)
          payload-sha256: \(artifact.payloadSHA256)
          value: \(artifact.signature)
        """
    }

    public static func decode(_ text: String) throws -> SignedArtifact {
        guard text.components(separatedBy: .newlines)
            .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "signature:" })
        else {
            throw SignedArtifactFrontmatterError.missingSignatureBlock
        }

        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator])
            let value = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard key != "signature" else { continue }
            values[key] = value
        }

        guard let algorithmRaw = values["algorithm"] else {
            throw SignedArtifactFrontmatterError.missingField("algorithm")
        }
        guard let algorithm = SignatureAlgorithm(rawValue: algorithmRaw) else {
            throw SignedArtifactFrontmatterError.unsupportedAlgorithm(algorithmRaw)
        }
        guard let keyID = values["key-id"] else {
            throw SignedArtifactFrontmatterError.missingField("key-id")
        }
        guard let author = values["author"] else {
            throw SignedArtifactFrontmatterError.missingField("author")
        }
        guard let timestampRaw = values["timestamp"] else {
            throw SignedArtifactFrontmatterError.missingField("timestamp")
        }
        guard let timestamp = ISO8601DateFormatter.cocxySignature.date(from: timestampRaw) else {
            throw SignedArtifactFrontmatterError.invalidTimestamp(timestampRaw)
        }
        guard let payloadSHA256 = values["payload-sha256"] else {
            throw SignedArtifactFrontmatterError.missingField("payload-sha256")
        }
        guard let signature = values["value"] else {
            throw SignedArtifactFrontmatterError.missingField("value")
        }

        return SignedArtifact(
            algorithm: algorithm,
            keyID: keyID,
            author: author,
            timestamp: timestamp,
            payloadSHA256: payloadSHA256,
            signature: signature
        )
    }
}

public extension ISO8601DateFormatter {
    static let cocxySignature: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
