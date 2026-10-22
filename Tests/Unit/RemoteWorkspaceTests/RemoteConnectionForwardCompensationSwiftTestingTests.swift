// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionForwardCompensationSwiftTestingTests.swift - Exact-lease compensation coverage.

import Foundation
import Testing
@testable import CocxyTerminal

extension RemoteConnectionManagerTests {
    @Test @MainActor func exactLeaseForwardCompensatesAnAppliedStaleOutcome() async throws {
        let multiplexer = MockSSHMultiplexerDelegate()
        let manager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: MockRemoteProfileStore(),
            tunnelManager: SSHTunnelManager(),
            executor: MockProcessExecutor()
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: 9_090,
            localPort: 3_000
        )
        await manager.connect(profile: profile)
        let leaseID = try #require(manager.connectionLeaseID(for: profile.id))
        multiplexer.forwardAsyncError = SSHMultiplexerError.notConnected

        await #expect(throws: SSHMultiplexerError.notConnected) {
            try await manager.forwardPort(
                forward,
                for: profile.id,
                expectedConnectionLeaseID: leaseID
            )
        }

        #expect(multiplexer.forwardedPorts == [forward])
        #expect(multiplexer.lifecycleEvents.suffix(2) == ["forward", "cancel"])
        #expect(multiplexer.exactForwardIdentities == multiplexer.exactCancelIdentities)
    }
}
