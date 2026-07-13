// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayTokenTests.swift - Tests for HMAC-SHA256 token generation and validation.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("RelayToken")
struct RelayTokenTests {

    @Test("Generated token has 32-byte secret")
    func secretSize() {
        let token = RelayToken.generate()
        #expect(token.secret.count == 32)
    }

    @Test("Two generated tokens are different")
    func uniqueness() {
        let a = RelayToken.generate()
        let b = RelayToken.generate()
        #expect(a.secret != b.secret)
    }

    @Test("Sign produces 32-byte HMAC")
    func signatureSize() {
        let token = RelayToken.generate()
        let signature = token.sign(Data("payload".utf8))
        #expect(signature.count == 32)
    }

    @Test("Generated token validates correctly")
    func generateAndValidate() {
        let token = RelayToken.generate()
        let payload = Data("test-payload".utf8)
        let signature = token.sign(payload)
        #expect(token.validate(payload: payload, signature: signature))
    }

    @Test("Wrong payload fails validation")
    func wrongPayload() {
        let token = RelayToken.generate()
        let payload = Data("correct".utf8)
        let signature = token.sign(payload)
        let wrong = Data("wrong".utf8)
        #expect(!token.validate(payload: wrong, signature: signature))
    }

    @Test("Wrong signature fails validation")
    func wrongSignature() {
        let token = RelayToken.generate()
        let payload = Data("test".utf8)
        let fakeSignature = Data(repeating: 0, count: 32)
        #expect(!token.validate(payload: payload, signature: fakeSignature))
    }

    @Test("Rotated token invalidates old signatures")
    func rotation() {
        let token = RelayToken.generate()
        let payload = Data("test".utf8)
        let oldSignature = token.sign(payload)
        let rotated = token.rotated()
        #expect(!rotated.validate(payload: payload, signature: oldSignature))
    }

    @Test("Rotated token validates its own signatures")
    func rotatedSelfValidation() {
        let token = RelayToken.generate()
        let rotated = token.rotated()
        let payload = Data("after-rotation".utf8)
        let signature = rotated.sign(payload)
        #expect(rotated.validate(payload: payload, signature: signature))
    }

    @Test("RelayToken is Codable")
    func codableRoundTrip() throws {
        let original = RelayToken.generate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RelayToken.self, from: data)
        let payload = Data("test".utf8)
        let signature = original.sign(payload)
        #expect(decoded.validate(payload: payload, signature: signature))
    }
}

@Suite("RelayKeychainStore", .serialized)
struct RelayKeychainStoreTests {
    @Test("keychain store saves replaces loads and deletes channel tokens")
    func keychainStoreSavesReplacesLoadsAndDeletesChannelTokens() throws {
        let store = RelayKeychainStore()
        let channelID = UUID()
        defer { try? store.delete(channelID: channelID) }

        try store.delete(channelID: channelID)
        #expect(try store.load(channelID: channelID) == nil)

        let firstToken = RelayToken(secret: Data(repeating: 7, count: 32))
        try store.save(token: firstToken, channelID: channelID)
        #expect(try store.load(channelID: channelID)?.secret == firstToken.secret)

        let replacementToken = RelayToken(secret: Data(repeating: 9, count: 32))
        try store.save(token: replacementToken, channelID: channelID)
        #expect(try store.load(channelID: channelID)?.secret == replacementToken.secret)

        try store.delete(channelID: channelID)
        #expect(try store.load(channelID: channelID) == nil)
    }
}

// MARK: - Replay Tracker Tests

@Suite("ReplayTracker")
struct ReplayTrackerTests {

    @Test("First timestamp is allowed")
    func firstAllowed() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let ts = UInt64(Date().timeIntervalSince1970)
        let result = tracker.isAllowed(
            timestamp: ts,
            nonce: Data(repeating: 1, count: RelayHandshake.nonceSize)
        )
        #expect(result)
    }

    @Test("Replayed nonce is rejected")
    func replayRejected() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let ts = UInt64(Date().timeIntervalSince1970)
        let nonce = Data(repeating: 2, count: RelayHandshake.nonceSize)
        _ = tracker.isAllowed(timestamp: ts, nonce: nonce)
        let result = tracker.isAllowed(timestamp: ts, nonce: nonce)
        #expect(!result)
    }

    @Test("Distinct nonces in the same second are allowed")
    func differentAllowed() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let timestamp = UInt64(Date().timeIntervalSince1970)
        let r1 = tracker.isAllowed(
            timestamp: timestamp,
            nonce: Data(repeating: 3, count: RelayHandshake.nonceSize)
        )
        let r2 = tracker.isAllowed(
            timestamp: timestamp,
            nonce: Data(repeating: 4, count: RelayHandshake.nonceSize)
        )
        #expect(r1)
        #expect(r2)
    }

    @Test("Timestamp outside window is rejected")
    func outsideWindow() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let old = UInt64(Date().timeIntervalSince1970) - 120
        let result = tracker.isAllowed(
            timestamp: old,
            nonce: Data(repeating: 5, count: RelayHandshake.nonceSize)
        )
        #expect(!result)
    }

    @Test("Future timestamp within tolerance is allowed")
    func futureWithinTolerance() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let future = UInt64(Date().timeIntervalSince1970) + 30
        let result = tracker.isAllowed(
            timestamp: future,
            nonce: Data(repeating: 6, count: RelayHandshake.nonceSize)
        )
        #expect(result)
    }

    @Test("Far future timestamp is rejected")
    func farFutureRejected() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let farFuture = UInt64(Date().timeIntervalSince1970) + 120
        let result = tracker.isAllowed(
            timestamp: farFuture,
            nonce: Data(repeating: 7, count: RelayHandshake.nonceSize)
        )
        #expect(!result)
    }

    @Test("Extreme timestamp is rejected without unsigned overflow")
    func extremeTimestampRejected() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let result = tracker.isAllowed(
            timestamp: .max,
            nonce: Data(repeating: 11, count: RelayHandshake.nonceSize)
        )
        #expect(!result)
    }

    @Test("Replay window fails closed when its bounded capacity is exhausted")
    func boundedCapacity() {
        var tracker = ReplayTracker(windowSeconds: 60, maxEntries: 2)
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let firstAccepted = tracker.isAllowed(
            timestamp: timestamp,
            nonce: Data(repeating: 8, count: RelayHandshake.nonceSize)
        )
        let secondAccepted = tracker.isAllowed(
            timestamp: timestamp,
            nonce: Data(repeating: 9, count: RelayHandshake.nonceSize)
        )
        let overCapacityAccepted = tracker.isAllowed(
            timestamp: timestamp,
            nonce: Data(repeating: 10, count: RelayHandshake.nonceSize)
        )

        #expect(firstAccepted)
        #expect(secondAccepted)
        #expect(!overCapacityAccepted)
    }
}
