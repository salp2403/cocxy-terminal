// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Port forwarding operations")
struct PortForwardingOperationsTests {
    private enum TestFailure: Error {
        case rejected
    }

    @Test("Failed SSH activation is never published as an active tunnel")
    @MainActor func failedAddRollsBackUIState() {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8_080,
            remotePort: 80
        )

        #expect(throws: TestFailure.self) {
            try PortForwardingOperations.add(
                forward,
                profileID: profileID,
                to: manager
            ) {
                throw TestFailure.rejected
            }
        }
        #expect(manager.listTunnels(for: profileID).isEmpty)
    }

    @Test("Failed SSH cancellation keeps the tunnel visible for retry")
    @MainActor func failedRemoveRetainsUIState() throws {
        let manager = SSHTunnelManager()
        let profileID = UUID()
        let tunnel = manager.addTunnel(
            forward: .remote(remotePort: 9_000, localPort: 3_000),
            for: profileID
        )

        #expect(throws: TestFailure.self) {
            try PortForwardingOperations.remove(tunnel, from: manager) {
                throw TestFailure.rejected
            }
        }
        #expect(manager.listTunnels(for: profileID).map(\.id) == [tunnel.id])

        try PortForwardingOperations.remove(tunnel, from: manager) {}
        #expect(manager.listTunnels(for: profileID).isEmpty)
    }
}
