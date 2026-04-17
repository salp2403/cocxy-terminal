// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Tests for the per-surface `.launched` watchdog.
///
/// The watchdog is a thin wrapper around `DispatchWorkItem` that fires on
/// the main actor after a caller-specified timeout. Coverage focuses on
/// the three observable behaviours that the rest of the agent-recovery
/// system depends on: the handler eventually runs, an explicit cancel
/// stops it, and rescheduling replaces the previous work item without
/// leaking a call.
///
/// Serialized via `.serialized` because every test awaits a real
/// `DispatchQueue.main.asyncAfter` deadline. When the full test suite runs
/// in parallel and many other `@MainActor` tests share the main queue, the
/// work item can miss a tight deadline while other main-actor tests hold
/// the queue. Serializing keeps the deadlines deterministic. Timeouts are
/// generous (`0.20s` trigger, `1.50s` sleep) to absorb residual jitter
/// from simulator-level scheduling without resorting to retry wrappers —
/// see `feedback_no_retry_for_timeouts` for the rationale.
@MainActor
@Suite("AgentLaunchedWatchdog", .serialized)
struct AgentLaunchedWatchdogSwiftTestingTests {

    // MARK: - Scheduling fires

    @Test("handler runs after the timeout elapses")
    func handlerRunsAfterTimeout() async throws {
        let watchdog = AgentLaunchedWatchdog()
        let surfaceID = SurfaceID()

        var fireCount = 0
        watchdog.schedule(surfaceID: surfaceID, timeout: 0.20) {
            fireCount += 1
        }

        // Poll for up to 5 seconds waiting for the work item to fire.
        // The full suite saturates the main queue with other @MainActor
        // tests, so a fixed-length sleep (even a generous one) can race
        // against queue contention. Polling with short yields lets the
        // scheduler breathe and keeps the assertion deterministic
        // without a retry wrapper. See `feedback_no_retry_for_timeouts`
        // for why we prefer polling a real outcome over retrying.
        let deadline = Date().addingTimeInterval(5.0)
        while fireCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms per tick
        }

        #expect(fireCount == 1)
        // After firing, the watchdog clears its own entry so subsequent
        // introspection does not leak the stale work item.
        #expect(watchdog.isScheduled(surfaceID: surfaceID) == false)
        #expect(watchdog.scheduledCount == 0)
    }

    // MARK: - Cancel stops the firing

    @Test("cancel prevents the handler from firing")
    func cancelStopsHandlerFromFiring() async throws {
        let watchdog = AgentLaunchedWatchdog()
        let surfaceID = SurfaceID()

        var handlerCount = 0
        watchdog.schedule(surfaceID: surfaceID, timeout: 0.20) {
            handlerCount += 1
        }
        watchdog.cancel(surfaceID: surfaceID)

        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.50s

        #expect(handlerCount == 0)
        #expect(watchdog.isScheduled(surfaceID: surfaceID) == false)
    }

    @Test("cancel on a surface without a pending work item is a no-op")
    func cancelWithoutScheduleIsSafe() {
        let watchdog = AgentLaunchedWatchdog()
        watchdog.cancel(surfaceID: SurfaceID())
        #expect(watchdog.scheduledCount == 0)
    }

    // MARK: - Rescheduling replaces

    @Test("rescheduling replaces the previous work item")
    func rescheduleReplacesPrevious() async throws {
        let watchdog = AgentLaunchedWatchdog()
        let surfaceID = SurfaceID()

        var firstCount = 0
        var secondCount = 0

        watchdog.schedule(surfaceID: surfaceID, timeout: 0.20) {
            firstCount += 1
        }
        // Replace before first can fire.
        watchdog.schedule(surfaceID: surfaceID, timeout: 0.20) {
            secondCount += 1
        }

        // Poll for the replacement handler to fire. The first schedule
        // must never fire (work item cancelled), but the second must
        // fire exactly once. Polling protects against main-queue
        // contention from other suites without masking real bugs.
        let deadline = Date().addingTimeInterval(5.0)
        while secondCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }

    // MARK: - Isolation between surfaces

    @Test("each surface keeps its own work item")
    func surfacesAreIsolated() async throws {
        let watchdog = AgentLaunchedWatchdog()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        var firedA = false
        var firedB = false

        watchdog.schedule(surfaceID: surfaceA, timeout: 0.20) { firedA = true }
        watchdog.schedule(surfaceID: surfaceB, timeout: 0.20) { firedB = true }

        #expect(watchdog.scheduledCount == 2)
        #expect(watchdog.isScheduled(surfaceID: surfaceA))
        #expect(watchdog.isScheduled(surfaceID: surfaceB))

        watchdog.cancel(surfaceID: surfaceA)

        // Poll for surfaceB's work item to fire while surfaceA remains
        // cancelled. Waiting for firedB rather than a fixed sleep keeps
        // the test robust under main-queue contention from parallel
        // suites.
        let deadline = Date().addingTimeInterval(5.0)
        while firedB == false, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(firedA == false)
        #expect(firedB == true)
        #expect(watchdog.scheduledCount == 0)
    }

    // MARK: - Full sweep

    @Test("cancelAll stops every pending work item")
    func cancelAllStopsEverything() async throws {
        let watchdog = AgentLaunchedWatchdog()
        var fired = 0

        for _ in 0..<5 {
            watchdog.schedule(surfaceID: SurfaceID(), timeout: 0.20) {
                fired += 1
            }
        }
        #expect(watchdog.scheduledCount == 5)

        watchdog.cancelAll()
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(fired == 0)
        #expect(watchdog.scheduledCount == 0)
    }

    // MARK: - Introspection contract

    @Test("isScheduled reflects the current state")
    func isScheduledTracksLifecycle() {
        let watchdog = AgentLaunchedWatchdog()
        let surfaceID = SurfaceID()
        #expect(watchdog.isScheduled(surfaceID: surfaceID) == false)

        watchdog.schedule(surfaceID: surfaceID, timeout: 60.0) { }
        #expect(watchdog.isScheduled(surfaceID: surfaceID) == true)
        #expect(watchdog.scheduledCount == 1)

        watchdog.cancel(surfaceID: surfaceID)
        #expect(watchdog.isScheduled(surfaceID: surfaceID) == false)
        #expect(watchdog.scheduledCount == 0)
    }
}
