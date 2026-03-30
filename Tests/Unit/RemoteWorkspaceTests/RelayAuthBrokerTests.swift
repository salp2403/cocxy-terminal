// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayAuthBrokerTests.swift - Tests for relay wire protocol handshake.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("RelayAuthBroker")
struct RelayAuthBrokerTests {

    // MARK: - Handshake Building

    @Test("Build valid handshake produces correct format")
    func buildHandshake() {
        let channelID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        // 4 bytes length + 16 UUID + 8 timestamp + 32 HMAC = 60 bytes total
        #expect(data.count == 60)
    }

    // MARK: - Handshake Validation

    @Test("Valid handshake is accepted")
    func validHandshake() throws {
        let channelID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: nil
        )
        #expect(result == .accepted)
    }

    @Test("Wrong channel ID is rejected")
    func wrongChannelID() throws {
        let channelID = UUID()
        let wrongID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: wrongID,
            token: token,
            replayTracker: nil
        )
        #expect(result == .rejected(.channelMismatch))
    }

    @Test("Invalid HMAC is rejected")
    func invalidHMAC() throws {
        let channelID = UUID()
        let token = RelayToken.generate()
        let wrongToken = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: wrongToken,
            replayTracker: nil
        )
        #expect(result == .rejected(.invalidSignature))
    }

    @Test("Expired timestamp is rejected")
    func expiredTimestamp() throws {
        let channelID = UUID()
        let token = RelayToken.generate()
        let oldTimestamp = UInt64(Date().timeIntervalSince1970) - 120

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: oldTimestamp,
            token: token
        )

        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: nil
        )
        #expect(result == .rejected(.timestampExpired))
    }

    @Test("Truncated data is rejected")
    func truncatedData() throws {
        let data = Data(repeating: 0, count: 10)
        let result = RelayHandshake.validate(
            data: data,
            expectedChannelID: UUID(),
            token: RelayToken.generate(),
            replayTracker: nil
        )
        #expect(result == .rejected(.malformed))
    }

    @Test("Replay is rejected via tracker")
    func replayRejected() {
        let channelID = UUID()
        let token = RelayToken.generate()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        let data = RelayHandshake.build(
            channelID: channelID,
            timestamp: timestamp,
            token: token
        )

        var tracker = ReplayTracker(windowSeconds: 60)

        let first = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: &tracker
        )
        #expect(first == .accepted)

        let second = RelayHandshake.validate(
            data: data,
            expectedChannelID: channelID,
            token: token,
            replayTracker: &tracker
        )
        #expect(second == .rejected(.replayDetected))
    }

    // MARK: - Validation Result

    @Test("ValidationResult equality")
    func resultEquality() {
        #expect(RelayHandshake.ValidationResult.accepted == .accepted)
        #expect(RelayHandshake.ValidationResult.rejected(.invalidSignature)
                == .rejected(.invalidSignature))
        #expect(RelayHandshake.ValidationResult.rejected(.invalidSignature)
                != .rejected(.timestampExpired))
    }
}
