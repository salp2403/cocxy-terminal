// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `RateLimitProbeService`, the `@MainActor`
/// coordinator the status-bar pill subscribes to.
///
/// Behaviour the suite pins:
///
///   * `setActiveAgent(nil)` clears the snapshot synchronously so the
///     pill can hide immediately when the visible tab loses an agent.
///   * `refresh()` honours the current agent and produces a typed
///     snapshot from the matching provider.
///   * Switching agents replaces the snapshot — sibling agents must
///     not see one another's usage data.
///   * An agent without a registered provider collapses to a `nil`
///     snapshot so the pill hides instead of crashing.
///
/// The polling timer is intentionally *not* exercised here. `Timer.publish`
/// is gated by the `XCTestConfigurationFilePath` environment variable
/// (`feedback_xctest_timer_publish_runloop`) so it never fires under
/// the test runner. Tests drive the probe deterministically through
/// `refresh()`.
@MainActor
@Suite("RateLimitProbeService")
struct RateLimitProbeServiceSwiftTestingTests {

    // MARK: - Test fixtures

    private static let frozenInstant = Date(timeIntervalSince1970: 1_750_000_000)

    private struct StubProvider: RateLimitProviding {
        let agent: RateLimitSnapshot.AgentKind
        let result: RateLimitSnapshot?

        func snapshot() async -> RateLimitSnapshot? { result }
    }

    private func makeProvider(
        for agent: RateLimitSnapshot.AgentKind,
        usagePercent: Double
    ) -> StubProvider {
        StubProvider(
            agent: agent,
            result: RateLimitSnapshot(
                agent: agent,
                usagePercent: usagePercent,
                usedAmount: Int(usagePercent * 1_000_000),
                limitAmount: 1_000_000,
                unit: .tokens,
                updatedAt: Self.frozenInstant
            )
        )
    }

    // MARK: - Initial state

    @Test("a fresh probe has no snapshot until an agent is set")
    func initialSnapshotIsNil() {
        let probe = RateLimitProbeService(providers: [:])

        #expect(probe.snapshot == nil)
    }

    // MARK: - Setting and clearing the active agent

    @Test("setActiveAgent(nil) clears the snapshot synchronously so the pill hides without delay")
    func nilAgentClearsSnapshot() async {
        let provider = makeProvider(for: .claude, usagePercent: 0.42)
        let probe = RateLimitProbeService(providers: [.claude: provider])

        probe.setActiveAgent(.claude)
        await probe.refresh()
        #expect(probe.snapshot != nil)

        probe.setActiveAgent(nil)

        #expect(probe.snapshot == nil)
    }

    // MARK: - refresh

    @Test("refresh produces the typed snapshot from the registered provider")
    func refreshProducesTypedSnapshot() async {
        let provider = makeProvider(for: .claude, usagePercent: 0.42)
        let probe = RateLimitProbeService(providers: [.claude: provider])

        probe.setActiveAgent(.claude)
        await probe.refresh()

        #expect(probe.snapshot?.agent == .claude)
        #expect(probe.snapshot?.usagePercent == 0.42)
    }

    @Test("refresh with no registered provider for the current agent collapses to a nil snapshot")
    func refreshWithMissingProviderClearsSnapshot() async {
        let probe = RateLimitProbeService(providers: [:])

        probe.setActiveAgent(.gemini)
        await probe.refresh()

        #expect(probe.snapshot == nil)
    }

    @Test("switching agents replaces the snapshot — siblings never observe each other's usage")
    func switchingAgentsReplacesSnapshot() async {
        let claude = makeProvider(for: .claude, usagePercent: 0.30)
        let codex = makeProvider(for: .codex, usagePercent: 0.85)
        let probe = RateLimitProbeService(providers: [
            .claude: claude,
            .codex: codex,
        ])

        probe.setActiveAgent(.claude)
        await probe.refresh()
        #expect(probe.snapshot?.agent == .claude)
        #expect(probe.snapshot?.heatLevel == .green)

        probe.setActiveAgent(.codex)
        await probe.refresh()

        #expect(probe.snapshot?.agent == .codex)
        #expect(probe.snapshot?.heatLevel == .red)
    }

    @Test("refresh while no agent is active leaves the snapshot at nil")
    func refreshWithNoActiveAgentStaysNil() async {
        let provider = makeProvider(for: .claude, usagePercent: 0.5)
        let probe = RateLimitProbeService(providers: [.claude: provider])

        await probe.refresh()

        #expect(probe.snapshot == nil)
    }

    // MARK: - Timer gate (no spinning under XCTest)

    @Test("setActiveAgent never schedules the polling timer when running under XCTest")
    func timerIsGatedUnderXCTest() {
        let provider = makeProvider(for: .claude, usagePercent: 0.1)
        let probe = RateLimitProbeService(providers: [.claude: provider])

        probe.setActiveAgent(.claude)

        // The probe exposes its current poll cancellable as `internal`
        // for tests; a non-nil value would mean a `Timer.publish` is
        // running on the runloop, which under XCTest is exactly the
        // pattern feedback_xctest_timer_publish_runloop forbids.
        #expect(probe.activePollCancellableForTesting == nil)
    }
}
