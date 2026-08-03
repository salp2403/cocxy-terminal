// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayAuthBrokerAuditFailureSwiftTestingTests.swift - Fail-closed relay audit coverage.

import Foundation
import Testing
@testable import CocxyTerminal

extension RelayAuthBrokerTests {
    @Test("An accepted handshake is revoked before relay when audit persistence fails")
    @MainActor func auditFailureBlocksAcceptedHandshake() async throws {
        let writer = MockAuditLogWriter()
        writer.appendError = RelayAuthBrokerAuditTestError.injected
        let channelID = UUID()
        let token = RelayToken.generate()
        let broker = RelayAuthBroker(
            channelID: channelID,
            token: token,
            acl: RelayACL(),
            targetPort: 9,
            auditLog: RelayAuditLog(writer: writer)
        )
        var observedFailure: RelayAuditLogError?
        broker.setFailureHandler { error in
            observedFailure = error as? RelayAuditLogError
        }
        let port = try await broker.startOnEphemeralLoopbackPort()
        defer { broker.stop() }
        let handshake = RelayHandshake.build(
            channelID: channelID,
            timestamp: UInt64(Date().timeIntervalSince1970),
            token: token
        )

        try await sendRelayTestPayload(handshake, to: port)

        #expect(await waitForRelayEffect { observedFailure != nil })
        #expect(broker.activeConnections == 0)
        #expect(writer.entries.isEmpty)
    }
}

private enum RelayAuthBrokerAuditTestError: Error {
    case injected
}
