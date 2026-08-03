// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayManagerAuditFailureSwiftTestingTests.swift - Channel audit compensation coverage.

import Foundation
import Testing
@testable import CocxyTerminal

extension RelayManagerTests {
    @Test("Close and rotate for unknown channels are safe no-ops")
    @MainActor func unknownChannelNoOps() async throws {
        let forwarder = MockPortForwarder()
        let manager = RelayManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )

        await manager.closeChannel(channelID: UUID())
        try manager.rotateToken(channelID: UUID())

        #expect(forwarder.cancelledPorts.isEmpty)
    }

    @Test("Open channel fails closed and tears down when its audit record cannot persist")
    @MainActor func openChannelAuditFailure() async throws {
        let writer = MockAuditLogWriter()
        writer.appendError = RelayManagerAuditTestError.injected
        let forwarder = MockPortForwarder()
        let brokerFactory = RelayBrokerFactoryRecorder()
        let manager = RelayManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder,
            auditLog: RelayAuditLog(writer: writer),
            brokerFactory: { channelID, token, acl, targetHost, targetPort, auditLog in
                brokerFactory.make(
                    channelID: channelID,
                    token: token,
                    acl: acl,
                    targetHost: targetHost,
                    targetPort: targetPort,
                    auditLog: auditLog
                )
            }
        )
        let profileID = UUID()

        await #expect(throws: RelayAuditLogError.self) {
            try await manager.openChannel(
                config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
                profileID: profileID
            )
        }

        let broker = try #require(brokerFactory.brokers.first)
        #expect(manager.listChannels(profileID: profileID).isEmpty)
        #expect(manager.clientToken(for: broker.channelID) == nil)
        #expect(forwarder.cancelledPorts == forwarder.forwardedPorts)
        #expect(broker.isStopped)
        #expect(manager.auditFailureDescription != nil)
    }
}

private enum RelayManagerAuditTestError: Error {
    case injected
}
