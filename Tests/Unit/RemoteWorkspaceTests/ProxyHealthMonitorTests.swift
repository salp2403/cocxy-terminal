// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyHealthMonitorTests.swift - Tests for proxy health monitoring and failover.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Health Probe

/// Controllable health probe that returns predetermined results.
@MainActor
final class MockHealthProbe: HealthProbing {

    var results: [Bool] = [true]
    private var callIndex = 0

    func probe() async -> Bool {
        let result = callIndex < results.count ? results[callIndex] : results.last ?? false
        callIndex += 1
        return result
    }

    func reset() {
        callIndex = 0
    }
}

// MARK: - Mock Proxy State Delegate

/// Records state change notifications from the health monitor.
@MainActor
final class MockProxyStateDelegate: ProxyHealthDelegate {

    var stateChanges: [ProxyHealthState] = []

    func proxyHealthDidChange(to state: ProxyHealthState) {
        stateChanges.append(state)
    }
}

// MARK: - ProxyHealthMonitor Tests

@Suite("ProxyHealthMonitor")
struct ProxyHealthMonitorTests {

    @Test("Initial state is unknown")
    @MainActor func initialState() {
        let monitor = ProxyHealthMonitor(
            probe: MockHealthProbe(),
            consecutiveFailuresThreshold: 3
        )
        #expect(monitor.state == .unknown)
    }

    @Test("Successful probe transitions to healthy")
    @MainActor func successfulProbe() async {
        let probe = MockHealthProbe()
        probe.results = [true]
        let delegate = MockProxyStateDelegate()
        let monitor = ProxyHealthMonitor(
            probe: probe,
            consecutiveFailuresThreshold: 3
        )
        monitor.delegate = delegate

        await monitor.checkOnce()

        #expect(monitor.state == .healthy)
        #expect(delegate.stateChanges.contains(.healthy))
    }

    @Test("Single failure does not trigger failing state")
    @MainActor func singleFailure() async {
        let probe = MockHealthProbe()
        probe.results = [false]
        let monitor = ProxyHealthMonitor(
            probe: probe,
            consecutiveFailuresThreshold: 3
        )

        await monitor.checkOnce()

        #expect(monitor.state == .degraded(consecutiveFailures: 1))
    }

    @Test("Three consecutive failures trigger failing state")
    @MainActor func threeFailures() async {
        let probe = MockHealthProbe()
        probe.results = [false, false, false]
        let delegate = MockProxyStateDelegate()
        let monitor = ProxyHealthMonitor(
            probe: probe,
            consecutiveFailuresThreshold: 3
        )
        monitor.delegate = delegate

        await monitor.checkOnce()
        await monitor.checkOnce()
        await monitor.checkOnce()

        #expect(monitor.state == .failing)
        #expect(delegate.stateChanges.contains(.failing))
    }

    @Test("Recovery after failures resets to healthy")
    @MainActor func recoveryAfterFailures() async {
        let probe = MockHealthProbe()
        probe.results = [false, false, true]
        let monitor = ProxyHealthMonitor(
            probe: probe,
            consecutiveFailuresThreshold: 3
        )

        await monitor.checkOnce() // fail 1
        await monitor.checkOnce() // fail 2
        await monitor.checkOnce() // success

        #expect(monitor.state == .healthy)
    }

    @Test("Consecutive failure counter resets on success")
    @MainActor func counterResets() async {
        let probe = MockHealthProbe()
        probe.results = [false, false, true, false]
        let monitor = ProxyHealthMonitor(
            probe: probe,
            consecutiveFailuresThreshold: 3
        )

        await monitor.checkOnce() // fail 1
        await monitor.checkOnce() // fail 2
        await monitor.checkOnce() // success, reset
        await monitor.checkOnce() // fail 1 (not fail 3)

        #expect(monitor.state == .degraded(consecutiveFailures: 1))
    }

    @Test("Delegate receives state changes in order")
    @MainActor func delegateOrder() async {
        let probe = MockHealthProbe()
        probe.results = [true, false, false, false]
        let delegate = MockProxyStateDelegate()
        let monitor = ProxyHealthMonitor(
            probe: probe,
            consecutiveFailuresThreshold: 3
        )
        monitor.delegate = delegate

        await monitor.checkOnce() // healthy
        await monitor.checkOnce() // degraded 1
        await monitor.checkOnce() // degraded 2
        await monitor.checkOnce() // failing

        #expect(delegate.stateChanges.count == 4)
        #expect(delegate.stateChanges[0] == .healthy)
        #expect(delegate.stateChanges[3] == .failing)
    }

    @Test("ProxyHealthState equality")
    func stateEquality() {
        #expect(ProxyHealthState.unknown == ProxyHealthState.unknown)
        #expect(ProxyHealthState.healthy == ProxyHealthState.healthy)
        #expect(ProxyHealthState.failing == ProxyHealthState.failing)
        #expect(ProxyHealthState.degraded(consecutiveFailures: 1) == ProxyHealthState.degraded(consecutiveFailures: 1))
        #expect(ProxyHealthState.degraded(consecutiveFailures: 1) != ProxyHealthState.degraded(consecutiveFailures: 2))
    }
}
