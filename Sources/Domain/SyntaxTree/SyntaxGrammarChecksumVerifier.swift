// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxGrammarChecksumVerifier.swift - Verifies pinned bundled grammar parser checksums before loading.

import CryptoKit
import Foundation

enum SyntaxGrammarChecksumVerifierError: Error, Equatable {
    case unsupportedChecksum(String)
    case unreadableResource(String)
    case checksumMismatch(expected: String, actual: String)
}

struct SyntaxGrammarChecksumVerifier {
    typealias ReadData = (URL) throws -> Data

    private let readData: ReadData

    init(readData: @escaping ReadData = { try Data(contentsOf: $0) }) {
        self.readData = readData
    }

    func verify(language: SyntaxLanguage, plan: SyntaxGrammarLoadPlan) throws {
        let checksum = language.checksum?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !checksum.isEmpty else { return }

        let expectedDigest = try expectedSHA256Digest(from: checksum)
        let data: Data
        do {
            data = try readData(plan.parserURL)
        } catch {
            throw SyntaxGrammarChecksumVerifierError.unreadableResource(plan.parserURL.path)
        }

        let actualDigest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualDigest == expectedDigest else {
            throw SyntaxGrammarChecksumVerifierError.checksumMismatch(
                expected: "sha256:\(expectedDigest)",
                actual: "sha256:\(actualDigest)"
            )
        }
    }

    private func expectedSHA256Digest(from checksum: String) throws -> String {
        let parts = checksum.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              parts[0].lowercased() == "sha256" else {
            throw SyntaxGrammarChecksumVerifierError.unsupportedChecksum(checksum)
        }

        let digest = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard digest.count == 64,
              digest.unicodeScalars.allSatisfy({ hexCharacters.contains($0) }) else {
            throw SyntaxGrammarChecksumVerifierError.unsupportedChecksum(checksum)
        }
        return digest
    }
}
