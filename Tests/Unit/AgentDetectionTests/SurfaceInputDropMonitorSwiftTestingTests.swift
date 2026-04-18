// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for the per-surface input-drop monitor used by the
/// `CocxyCoreBridge` input observers.
///
/// The monitor's contract has four observable behaviours the input-path
/// wiring depends on:
///   1. Consecutive drops below the threshold do not notify.
///   2. Reaching the threshold fires the handler exactly once per
///      stuck episode.
///   3. A successful delivery ends the episode — a subsequent run of
///      drops can still fire the handler again.
///   4. `clear(surfaceID:)` and `clearAll()` flush the tracker so a
///      recycled surface ID starts from zero.
///
/// Serialized so the assertions on shared-state counters stay
/// deterministic when the full suite runs under parallel main-actor
/// contention. The monitor is main-actor isolated so the tests run in
/// a known scheduling domain.
@MainActor
@Suite("SurfaceInputDropMonitor", .serialized)
struct SurfaceInputDropMonitorSwiftTestingTests {

    // MARK: - Sub-threshold

    @Test("drops under the threshold do not invoke the handler")
    func dropsUnderThresholdDoNotNotify() {
        var fireCount = 0
        let monitor = SurfaceInputDropMonitor(
            threshold: 3,
            onStuckPane: { _, _ in fireCount += 1 }
        )
        let sid = SurfaceID()

        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)

        #expect(fireCount == 0)
        #expect(monitor.consecutiveDrops(for: sid) == 2)
        #expect(monitor.hasNotified(for: sid) == false)
    }

    // MARK: - Threshold reached

    @Test("hitting the threshold fires the handler once with the last reason")
    func thresholdFiresHandlerOnce() {
        var fireCount = 0
        var seenReason: InputDropReason?
        var seenSurface: SurfaceID?
        let monitor = SurfaceInputDropMonitor(
            threshold: 3,
            onStuckPane: { sid, reason in
                fireCount += 1
                seenReason = reason
                seenSurface = sid
            }
        )
        let sid = SurfaceID()

        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .surfaceMissing)

        #expect(fireCount == 1)
        #expect(seenReason == .surfaceMissing)
        #expect(seenSurface == sid)
        #expect(monitor.hasNotified(for: sid) == true)
        #expect(monitor.consecutiveDrops(for: sid) == 3)
    }

    @Test("additional drops after notification do not re-fire the handler")
    func repeatedDropsDoNotReFire() {
        var fireCount = 0
        let monitor = SurfaceInputDropMonitor(
            threshold: 2,
            onStuckPane: { _, _ in fireCount += 1 }
        )
        let sid = SurfaceID()

        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)

        #expect(fireCount == 1)
        #expect(monitor.consecutiveDrops(for: sid) == 4)
    }

    // MARK: - Delivery resets

    @Test("a successful delivery resets the counter and the notified flag")
    func deliveryResetsCounter() {
        var fireCount = 0
        let monitor = SurfaceInputDropMonitor(
            threshold: 2,
            onStuckPane: { _, _ in fireCount += 1 }
        )
        let sid = SurfaceID()

        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        #expect(fireCount == 1)

        monitor.recordDelivery(surfaceID: sid)
        #expect(monitor.consecutiveDrops(for: sid) == 0)
        #expect(monitor.hasNotified(for: sid) == false)

        // A fresh stuck episode can now fire the handler again.
        monitor.recordDrop(surfaceID: sid, reason: .surfaceMissing)
        monitor.recordDrop(surfaceID: sid, reason: .surfaceMissing)
        #expect(fireCount == 2)
    }

    @Test("recordDelivery on an untracked surface is a cheap no-op")
    func deliveryOnUntrackedSurfaceIsSafe() {
        let monitor = SurfaceInputDropMonitor(threshold: 3)
        monitor.recordDelivery(surfaceID: SurfaceID())
        #expect(monitor.trackedCount == 0)
    }

    // MARK: - Isolation between surfaces

    @Test("each surface keeps its own consecutive-drop counter")
    func surfacesAreIsolated() {
        var fireCount = 0
        let monitor = SurfaceInputDropMonitor(
            threshold: 3,
            onStuckPane: { _, _ in fireCount += 1 }
        )
        let sidA = SurfaceID()
        let sidB = SurfaceID()

        monitor.recordDrop(surfaceID: sidA, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sidA, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sidB, reason: .surfaceMissing)

        #expect(fireCount == 0)
        #expect(monitor.consecutiveDrops(for: sidA) == 2)
        #expect(monitor.consecutiveDrops(for: sidB) == 1)

        // Delivering on B does not affect A's counter.
        monitor.recordDelivery(surfaceID: sidB)
        #expect(monitor.consecutiveDrops(for: sidA) == 2)

        // Third drop on A crosses the threshold; B stays quiet.
        monitor.recordDrop(surfaceID: sidA, reason: .ptyWriteFailed)
        #expect(fireCount == 1)
    }

    // MARK: - Cleanup

    @Test("clear removes the tracker entry for a surface")
    func clearRemovesEntry() {
        var fireCount = 0
        let monitor = SurfaceInputDropMonitor(
            threshold: 3,
            onStuckPane: { _, _ in fireCount += 1 }
        )
        let sid = SurfaceID()

        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        #expect(monitor.trackedCount == 1)

        monitor.clear(surfaceID: sid)
        #expect(monitor.trackedCount == 0)
        #expect(monitor.consecutiveDrops(for: sid) == 0)

        // After clear, the counter starts at zero again.
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        #expect(fireCount == 0, "Still below the threshold for a fresh episode")
    }

    @Test("clearAll flushes every tracker entry")
    func clearAllFlushesEverything() {
        let monitor = SurfaceInputDropMonitor(threshold: 3)
        for _ in 0..<5 {
            let sid = SurfaceID()
            monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        }
        #expect(monitor.trackedCount == 5)

        monitor.clearAll()
        #expect(monitor.trackedCount == 0)
    }

    // MARK: - Threshold tunability

    @Test("threshold of 1 fires on the first drop")
    func thresholdOfOneFiresImmediately() {
        var fireCount = 0
        let monitor = SurfaceInputDropMonitor(
            threshold: 1,
            onStuckPane: { _, _ in fireCount += 1 }
        )
        let sid = SurfaceID()

        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)

        #expect(fireCount == 1)
        #expect(monitor.hasNotified(for: sid) == true)
    }

    // MARK: - Handler re-assignment

    @Test("handler assignment after construction takes effect on next threshold hit")
    func handlerSwapAfterConstruction() {
        let monitor = SurfaceInputDropMonitor(threshold: 2)
        var fireCount = 0
        monitor.onStuckPane = { _, _ in fireCount += 1 }

        let sid = SurfaceID()
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)
        monitor.recordDrop(surfaceID: sid, reason: .ptyWriteFailed)

        #expect(fireCount == 1)
    }
}
