// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror connection policy")
struct MobileMirrorConnectionPolicySwiftTestingTests {
    @Test("admission is bounded independently by origin and active count")
    func admissionIsBoundedByOrigin() {
        var policy = MobileMirrorConnectionPolicy(limits: MobileMirrorConnectionLimits(
            maximumTotal: 2,
            maximumPerAddress: 1,
            maximumStartsPerWindow: 4,
            maximumFailuresPerWindow: 2,
            rateWindow: 10
        ))

        #expect(policy.admit(address: "127.0.0.1", now: 100) == .accepted)
        #expect(policy.admit(address: "127.0.0.1", now: 101) == .tooManyConnections)
        #expect(policy.admit(address: "127.0.0.2", now: 101) == .accepted)
        #expect(policy.admit(address: "127.0.0.3", now: 101) == .tooManyConnections)

        policy.release(address: "127.0.0.1")
        #expect(policy.admit(address: "127.0.0.3", now: 102) == .accepted)
    }

    @Test("completed HTTP requests do not consume an authentication rate budget")
    func sequentialConnectionsRemainAvailable() {
        var policy = MobileMirrorConnectionPolicy(limits: MobileMirrorConnectionLimits(
            maximumTotal: 2,
            maximumPerAddress: 1,
            maximumStartsPerWindow: 1,
            maximumFailuresPerWindow: 1,
            rateWindow: 10
        ))

        for index in 0..<100 {
            #expect(policy.admit(address: "phone", now: TimeInterval(index)) == .accepted)
            policy.release(address: "phone")
        }
    }

    @Test("pre-authentication and failure windows are independent")
    func requestRateWindowsAreIndependent() {
        var policy = MobileMirrorRequestRatePolicy(limits: MobileMirrorConnectionLimits(
            maximumTotal: 4,
            maximumPerAddress: 4,
            maximumStartsPerWindow: 2,
            maximumFailuresPerWindow: 1,
            rateWindow: 10
        ))

        let firstPreAuthentication = policy.admitPreAuthentication(address: "phone", now: 20)
        let secondPreAuthentication = policy.admitPreAuthentication(address: "phone", now: 21)
        let limitedPreAuthentication = policy.admitPreAuthentication(
            address: "phone",
            now: 29.99
        )
        let firstFailure = policy.recordAuthenticationFailure(address: "phone", now: 29.99)
        let limitedFailure = policy.recordAuthenticationFailure(address: "phone", now: 29.99)
        let expiredPreAuthentication = policy.admitPreAuthentication(
            address: "phone",
            now: 30.01
        )

        #expect(firstPreAuthentication)
        #expect(secondPreAuthentication)
        #expect(!limitedPreAuthentication)
        #expect(firstFailure)
        #expect(!limitedFailure)
        #expect(expiredPreAuthentication)
    }

    @Test("absolute deadline never resets after partial progress")
    func requestDeadlineIsAbsolute() {
        let deadline = MobileMirrorRequestDeadline(startedAt: 40, timeout: 8)

        #expect(deadline.remainingPollMilliseconds(at: 40) == 8_000)
        #expect(deadline.remainingPollMilliseconds(at: 47.999) == 1)
        #expect(deadline.remainingPollMilliseconds(at: 48) == nil)
        #expect(deadline.remainingPollMilliseconds(at: 60) == nil)
    }
}

@Suite("Mobile mirror SSH tunnel", .serialized)
@MainActor
struct MobileMirrorSSHTunnelControllerSwiftTestingTests {
    @Test("remote forward binds phone loopback and closes the exact lease")
    func opensAndClosesExactRemoteForward() async throws {
        let profile = RemoteConnectionProfile(
            name: "Phone",
            host: "phone.local",
            user: "mobile"
        )
        let profileStore = MockRemoteProfileStore()
        profileStore.profiles = [profile]
        let multiplexer = MockSSHMultiplexerDelegate()
        let tunnelManager = SSHTunnelManager()
        let connectionManager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: profileStore,
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor()
        )
        await connectionManager.connect(profile: profile)
        let controller = MobileMirrorSSHTunnelController(
            connectionManager: connectionManager,
            profileStore: profileStore,
            tunnelManager: tunnelManager,
            portProvider: { 52_345 }
        )

        #expect(controller.targets == [MobileMirrorTunnelTarget(
            id: profile.id,
            name: "Phone",
            destination: "mobile@phone.local"
        )])
        let lease = try await controller.open(profileID: profile.id, localPort: 41_321)

        #expect(lease.remotePort == 52_345)
        #expect(multiplexer.forwardedPorts == [
            .remote(
                remotePort: 52_345,
                localPort: 41_321,
                localHost: "127.0.0.1",
                remoteBindHost: "127.0.0.1"
            ),
        ])
        #expect(tunnelManager.listTunnels(for: profile.id).count == 1)

        try await controller.close(lease)

        #expect(multiplexer.lifecycleEvents.suffix(2) == ["forward", "cancel"])
        #expect(tunnelManager.listTunnels(for: profile.id).isEmpty)
    }

    @Test("unconfirmed closure retains the lease and blocks reopening")
    func closureFailureQuarantinesLeaseUntilRevocation() async throws {
        let profile = RemoteConnectionProfile(
            name: "Phone",
            host: "phone.local",
            user: "mobile"
        )
        let profileStore = MockRemoteProfileStore()
        profileStore.profiles = [profile]
        let multiplexer = MockSSHMultiplexerDelegate()
        let tunnelManager = SSHTunnelManager()
        let connectionManager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: profileStore,
            tunnelManager: tunnelManager,
            executor: MockProcessExecutor(),
            delaySleep: { _ in }
        )
        await connectionManager.connect(profile: profile)
        let controller = MobileMirrorSSHTunnelController(
            connectionManager: connectionManager,
            profileStore: profileStore,
            tunnelManager: tunnelManager,
            portProvider: { 52_345 }
        )
        let lease = try await controller.open(profileID: profile.id, localPort: 41_321)
        multiplexer.shouldThrowOnCancelForward = true
        multiplexer.shouldThrowOnDisconnect = true
        multiplexer.controlMasterProcessAliveResult = true

        await #expect(throws: MobileMirrorTunnelError.closureUnconfirmed) {
            try await controller.close(lease)
        }
        #expect(controller.unresolvedLease == lease)
        #expect(tunnelManager.listTunnels(for: profile.id).count == 1)
        let forwardCount = multiplexer.forwardedPorts.count
        await #expect(throws: MobileMirrorTunnelError.closureUnconfirmed) {
            try await controller.open(profileID: profile.id, localPort: 41_322)
        }
        #expect(multiplexer.forwardedPorts.count == forwardCount)

        multiplexer.shouldThrowOnCancelForward = false
        multiplexer.shouldThrowOnDisconnect = false
        multiplexer.controlMasterProcessAliveResult = false
        try await controller.close(lease)

        #expect(controller.unresolvedLease == nil)
        #expect(tunnelManager.listTunnels(for: profile.id).isEmpty)
    }
}
