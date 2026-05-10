// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCommandSignatures

@Suite("Signed artifact model")
struct SignedArtifactSwiftTestingTests {
    @Test("signed artifacts round-trip through sorted JSON")
    func signedArtifactsRoundTripThroughSortedJSON() throws {
        let artifact = SignedArtifact(
            algorithm: .ed25519,
            keyID: "0123456789abcdef",
            author: "Cocxy",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            payloadSHA256: "digest",
            signature: "signature"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(artifact)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SignedArtifact.self, from: data)

        #expect(decoded == artifact)
    }

    @Test("frontmatter block preserves signature metadata")
    func frontmatterBlockPreservesSignatureMetadata() throws {
        let artifact = SignedArtifact(
            algorithm: .ed25519,
            keyID: "0123456789abcdef",
            author: "Cocxy",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            payloadSHA256: "digest",
            signature: "signature"
        )

        let encoded = try SignedArtifactFrontmatter.encode(artifact)
        let decoded = try SignedArtifactFrontmatter.decode(encoded)

        #expect(encoded.contains("signature:"))
        #expect(decoded == artifact)
    }
}
