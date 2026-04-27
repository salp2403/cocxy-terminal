// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitProbeService.swift - Periodic probe that publishes the
// active agent's `RateLimitSnapshot` for the status-bar pill.

import Combine
import Foundation

/// Coordinator the status-bar pill subscribes to. Tracks the active
/// agent of the visible tab and periodically polls its registered
/// `RateLimitProviding` implementation so the pill stays current
/// without the view ever owning a Timer of its own.
///
/// ## Threading
///
/// `@MainActor`-isolated because the published `snapshot` drives
/// SwiftUI rendering and Combine subscribers in the status-bar
/// hierarchy. Provider I/O happens off the main actor inside
/// `provider.snapshot()` (`async`), so the probe never blocks the
/// runloop.
///
/// ## Polling
///
/// Production paths poll every `pollInterval` seconds via a
/// `Timer.publish(...).autoconnect()` Combine pipeline. The pipeline
/// is gated by `XCTestConfigurationFilePath` so the timer never
/// arms when running under the test runner — a decision documented
/// in `feedback_xctest_timer_publish_runloop` after a previous suite
/// hung waiting on a runloop tick that never came.
///
/// ## Determinism in tests
///
/// `refresh()` is `internal` so unit tests drive the probe by hand
/// instead of waiting for the polling timer. The `activePollCancellableForTesting`
/// accessor lets tests assert that the gate held: a non-nil value
/// under XCTest would mean the timer leaked through.
@MainActor
final class RateLimitProbeService: ObservableObject {

    /// Latest snapshot produced by the active agent's provider, or
    /// `nil` when no provider applies (no agent active, no provider
    /// registered for the active agent, the provider returned `nil`).
    /// SwiftUI subscribers hide the pill on a `nil` value.
    @Published private(set) var snapshot: RateLimitSnapshot?

    /// Per-agent providers the probe consults when refreshing. Only
    /// the agent currently set through `setActiveAgent(_:)` is queried
    /// — sibling providers stay idle.
    private let providers: [RateLimitSnapshot.AgentKind: any RateLimitProviding]

    /// Polling cadence in seconds for the production timer pipeline.
    private let pollInterval: TimeInterval

    /// Combine cancellable owning the polling timer in production.
    /// Stays `nil` under XCTest because the timer pipeline is gated
    /// off, and stays `nil` after `setActiveAgent(nil)` so the pill
    /// stops consuming wakeups while no agent is active.
    private var pollCancellable: AnyCancellable?

    /// Agent the probe currently tracks. Updated by `setActiveAgent(_:)`
    /// and consulted by `refresh()` so concurrent refresh calls always
    /// see the most recent agent rather than racing against the
    /// previous selection.
    private var currentAgent: RateLimitSnapshot.AgentKind?

    /// Test-only accessor used by the suite that pins the XCTest gate.
    /// Never read from production code.
    var activePollCancellableForTesting: AnyCancellable? {
        pollCancellable
    }

    init(
        providers: [RateLimitSnapshot.AgentKind: any RateLimitProviding],
        pollInterval: TimeInterval = 5 * 60
    ) {
        self.providers = providers
        self.pollInterval = pollInterval
    }

    // MARK: - Public API

    /// Sets the agent the probe tracks. Triggers an immediate refresh
    /// (asynchronously) and, in production, restarts the polling
    /// timer. `nil` clears the snapshot synchronously and stops the
    /// timer so the pill hides without waiting for an `await`.
    func setActiveAgent(_ agent: RateLimitSnapshot.AgentKind?) {
        currentAgent = agent
        pollCancellable?.cancel()
        pollCancellable = nil

        if agent == nil {
            // Clear synchronously so the SwiftUI pill hides on the
            // next render without depending on a Task hop.
            snapshot = nil
            return
        }

        // First sample fires off-actor; the result is published when
        // the await resumes back on the main actor.
        Task { [weak self] in
            await self?.refresh()
        }

        guard !Self.isRunningUnderXCTest else { return }

        pollCancellable = Timer.publish(
            every: pollInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    /// Refreshes the published snapshot for the current agent. Exposed
    /// as `internal` so unit tests can drive the probe deterministically
    /// without depending on the polling timer (which is gated off
    /// under XCTest).
    func refresh() async {
        guard let agent = currentAgent,
              let provider = providers[agent] else {
            snapshot = nil
            return
        }
        snapshot = await provider.snapshot()
    }

    // MARK: - XCTest gate

    /// Mirrors the canonical pattern shared with `AuroraChromeController`:
    /// when running under either XCTest or Swift Testing, skip the
    /// runloop-owning Timer pipeline so a unit suite cannot hang
    /// waiting on a tick that the test runner does not pump.
    ///
    /// Four checks layered defensively:
    ///   1. `XCTestConfigurationFilePath` env var (`xcodebuild test`).
    ///   2. The main bundle path ends in `.xctest` (a hosted test
    ///      target running inside an `.xctest` bundle).
    ///   3. The process name or `argv[0]` includes `xctest`,
    ///      `swift-testing`, or `swiftpm-testing` (a `swift test` run
    ///      where the env-var path is not set).
    ///   4. `NSClassFromString("XCTestCase")` resolves — the testing
    ///      harness is loaded into the process. This is the only
    ///      check that catches a `swift test` invocation reliably,
    ///      because `swift test` loads both XCTest and the
    ///      Swift-Testing harness regardless of which suite the
    ///      target uses.
    private static var isRunningUnderXCTest: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if Bundle.main.bundlePath.hasSuffix(".xctest") {
            return true
        }
        let names = [
            ProcessInfo.processInfo.processName,
            URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent,
        ].map { $0.lowercased() }
        if names.contains(where: { name in
            name.contains("xctest")
                || name.contains("swift-testing")
                || name.contains("swiftpm-testing")
        }) {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }
}
