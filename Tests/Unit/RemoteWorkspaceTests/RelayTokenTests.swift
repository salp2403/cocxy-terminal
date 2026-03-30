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

// MARK: - Replay Tracker Tests

@Suite("ReplayTracker")
struct ReplayTrackerTests {

    @Test("First timestamp is allowed")
    func firstAllowed() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let ts = UInt64(Date().timeIntervalSince1970)
        let result = tracker.isAllowed(ts)
        #expect(result)
    }

    @Test("Replayed timestamp is rejected")
    func replayRejected() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let ts = UInt64(Date().timeIntervalSince1970)
        _ = tracker.isAllowed(ts)
        let result = tracker.isAllowed(ts)
        #expect(!result)
    }

    @Test("Different timestamps are allowed")
    func differentAllowed() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let ts1 = UInt64(Date().timeIntervalSince1970)
        let ts2 = ts1 + 1
        let r1 = tracker.isAllowed(ts1)
        let r2 = tracker.isAllowed(ts2)
        #expect(r1)
        #expect(r2)
    }

    @Test("Timestamp outside window is rejected")
    func outsideWindow() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let old = UInt64(Date().timeIntervalSince1970) - 120
        let result = tracker.isAllowed(old)
        #expect(!result)
    }

    @Test("Future timestamp within tolerance is allowed")
    func futureWithinTolerance() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let future = UInt64(Date().timeIntervalSince1970) + 30
        let result = tracker.isAllowed(future)
        #expect(result)
    }

    @Test("Far future timestamp is rejected")
    func farFutureRejected() {
        var tracker = ReplayTracker(windowSeconds: 60)
        let farFuture = UInt64(Date().timeIntervalSince1970) + 120
        let result = tracker.isAllowed(farFuture)
        #expect(!result)
    }
}
