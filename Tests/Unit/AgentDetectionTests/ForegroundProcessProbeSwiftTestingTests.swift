// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

/// Coverage for the asynchronous foreground-process probe used by the
/// shell-prompt recovery path.
///
/// The probe has three observable outcomes the rest of the agent-recovery
/// subsystem depends on: the completion eventually receives the detector
/// result when the background finishes first, the completion receives
/// `nil` when the hard deadline wins, and explicit cancellation
/// suppresses the callback entirely. Isolation between surfaces and the
/// rescheduling contract are pinned here too so regressions surface in
/// isolation from the surrounding `MainWindowController` wiring.
///
/// Serialized because every test awaits a real `DispatchQueue` deadline
/// (either the 50 ms probe timeout or a scripted `Thread.sleep` on the
/// background queue). Under the full test suite's parallel main-actor
/// contention, those deadlines can slip enough to flake assertions.
/// Serializing keeps each test deterministic without a retry wrapper —
/// see `feedback_no_retry_for_timeouts` for the rationale.
@MainActor
@Suite("ForegroundProcessProbe", .serialized)
struct ForegroundProcessProbeSwiftTestingTests {

    // MARK: - Helpers

    /// Creates a `ForegroundProcessInfo` stub. Uses the same constructor
    /// shape as the production detector so any future field addition
    /// lands in one place.
    private func makeInfo(name: String, pid: pid_t = 42) -> ForegroundProcessInfo {
        ForegroundProcessInfo(name: name, command: nil, pid: pid)
    }

    // MARK: - Fast-path completion

    @Test("completion receives the detector result when the background finishes first")
    func completionReceivesDetectorResult() async throws {
        let expected = makeInfo(name: "zsh")
        let probe = ForegroundProcessProbe(detect: { _, _ in expected })

        var received: ForegroundProcessInfo?
        var completed = false
        probe.probe(
            surfaceID: SurfaceID(),
            shellPID: 42,
            ptyMasterFD: nil,
            timeout: 1.0
        ) { info in
            received = info
            completed = true
        }

        // Poll the outcome instead of a fixed sleep so parallel main-queue
        // contention cannot flake the assertion. See `feedback_no_retry_for_timeouts`.
        let deadline = Date().addingTimeInterval(5.0)
        while !completed, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000) // 20 ms
        }

        #expect(completed == true)
        #expect(received?.name == "zsh")
        #expect(probe.pendingCount == 0)
    }

    @Test("completion receives nil when the detector itself returns nil")
    func completionPropagatesDetectorNil() async throws {
        let probe = ForegroundProcessProbe(detect: { _, _ in nil })

        var received: ForegroundProcessInfo?
        var completed = false
        probe.probe(
            surfaceID: SurfaceID(),
            shellPID: 42,
            ptyMasterFD: nil,
            timeout: 1.0
        ) { info in
            received = info
            completed = true
        }

        let deadline = Date().addingTimeInterval(5.0)
        while !completed, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(completed == true)
        #expect(received == nil)
        #expect(probe.pendingCount == 0)
    }

    // MARK: - Deadline path

    @Test("completion receives nil when the hard deadline elapses before the detector")
    func completionReceivesNilOnTimeout() async throws {
        // The detector sleeps well past the deadline so the timeout is
        // guaranteed to win. `Thread.sleep` runs on the probe's
        // background queue and does not block the main actor.
        let probe = ForegroundProcessProbe(detect: { _, _ in
            Thread.sleep(forTimeInterval: 0.50)
            return ForegroundProcessInfo(name: "zsh", command: nil, pid: 42)
        })

        var received: ForegroundProcessInfo?
        var completed = false
        probe.probe(
            surfaceID: SurfaceID(),
            shellPID: 42,
            ptyMasterFD: nil,
            timeout: 0.05
        ) { info in
            received = info
            completed = true
        }

        // Wait enough to observe the deadline fire. The deadline is
        // 50 ms; we poll for up to 2 s to absorb scheduling jitter.
        let deadline = Date().addingTimeInterval(2.0)
        while !completed, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(completed == true)
        #expect(received == nil, "Timeout should have won; detector was still sleeping")
        #expect(probe.pendingCount == 0)
    }

    // MARK: - Cancellation

    @Test("cancel before the detector completes suppresses the callback")
    func cancelSuppressesCallback() async throws {
        let probe = ForegroundProcessProbe(detect: { _, _ in
            Thread.sleep(forTimeInterval: 0.20)
            return ForegroundProcessInfo(name: "zsh", command: nil, pid: 42)
        })

        var fireCount = 0
        let sid = SurfaceID()
        probe.probe(
            surfaceID: sid,
            shellPID: 42,
            ptyMasterFD: nil,
            timeout: 1.0
        ) { _ in
            fireCount += 1
        }
        probe.cancel(surfaceID: sid)

        // Wait for the detector's sleep to finish so the `notify` path
        // would have had a chance to deliver if cancel had failed.
        try await Task.sleep(nanoseconds: 400_000_000) // 400 ms

        #expect(fireCount == 0)
        #expect(probe.pendingCount == 0)
    }

    @Test("cancel on a surface without a pending probe is a no-op")
    func cancelWithoutProbeIsSafe() {
        let probe = ForegroundProcessProbe(detect: { _, _ in nil })
        probe.cancel(surfaceID: SurfaceID())
        #expect(probe.pendingCount == 0)
    }

    @Test("cancelAll stops every pending probe")
    func cancelAllStopsAllProbes() async throws {
        let probe = ForegroundProcessProbe(detect: { _, _ in
            Thread.sleep(forTimeInterval: 0.30)
            return ForegroundProcessInfo(name: "zsh", command: nil, pid: 42)
        })

        var fireCount = 0
        for _ in 0..<5 {
            probe.probe(
                surfaceID: SurfaceID(),
                shellPID: 42,
                ptyMasterFD: nil,
                timeout: 1.0
            ) { _ in
                fireCount += 1
            }
        }
        #expect(probe.pendingCount == 5)

        probe.cancelAll()
        try await Task.sleep(nanoseconds: 500_000_000) // 500 ms

        #expect(fireCount == 0)
        #expect(probe.pendingCount == 0)
    }

    // MARK: - Rescheduling

    @Test("probing the same surface twice cancels the first completion")
    func rescheduleCancelsPrevious() async throws {
        // Detector behaviour is keyed by `shellPID` so each probe has a
        // deterministic outcome. The global `userInitiated` queue is
        // concurrent — two work items can run in parallel on different
        // threads — so a shared call counter would deliver the
        // "stalled" work to whichever probe the scheduler happens to
        // pick first. Keying on the PID removes that race entirely.
        let probe = ForegroundProcessProbe(detect: { shellPID, _ in
            if shellPID == 42 {
                // First probe: simulate a slow sysctl so the callback
                // would clearly arrive after the replacement if the
                // cancel did not take effect.
                Thread.sleep(forTimeInterval: 0.25)
                return ForegroundProcessInfo(name: "first", command: nil, pid: shellPID)
            }
            return ForegroundProcessInfo(name: "second", command: nil, pid: shellPID)
        })

        var firstCompletions = 0
        var lastReceived: ForegroundProcessInfo?
        var secondCompleted = false
        let sid = SurfaceID()

        probe.probe(
            surfaceID: sid,
            shellPID: 42,
            ptyMasterFD: nil,
            timeout: 2.0
        ) { info in
            firstCompletions += 1
            lastReceived = info
        }

        // Re-schedule for the same surface — should cancel the first.
        probe.probe(
            surfaceID: sid,
            shellPID: 99,
            ptyMasterFD: nil,
            timeout: 2.0
        ) { info in
            lastReceived = info
            secondCompleted = true
        }

        let deadline = Date().addingTimeInterval(5.0)
        while !secondCompleted, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        // Give the first detector's sleep time to wrap up — if the
        // cancel failed, the `notify` path would have delivered by now.
        try await Task.sleep(nanoseconds: 350_000_000) // 350 ms

        #expect(firstCompletions == 0, "First probe must not have delivered")
        #expect(lastReceived?.name == "second")
        #expect(probe.pendingCount == 0)
    }

    // MARK: - Isolation between surfaces

    @Test("each surface keeps its own probe entry")
    func surfacesAreIsolated() async throws {
        let probe = ForegroundProcessProbe(detect: { shellPID, _ in
            // Tag the returned info with the shellPID so the test can
            // distinguish which completion fired for which surface.
            ForegroundProcessInfo(name: "shell\(shellPID)", command: nil, pid: shellPID)
        })

        let sidA = SurfaceID()
        let sidB = SurfaceID()
        var nameA: String?
        var nameB: String?

        probe.probe(
            surfaceID: sidA,
            shellPID: 111,
            ptyMasterFD: nil,
            timeout: 1.0
        ) { info in
            nameA = info?.name
        }
        probe.probe(
            surfaceID: sidB,
            shellPID: 222,
            ptyMasterFD: nil,
            timeout: 1.0
        ) { info in
            nameB = info?.name
        }

        let deadline = Date().addingTimeInterval(5.0)
        while (nameA == nil || nameB == nil), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(nameA == "shell111")
        #expect(nameB == "shell222")
        #expect(probe.pendingCount == 0)
    }

    // MARK: - Introspection

    @Test("isPending reflects the current state")
    func isPendingTracksLifecycle() {
        let probe = ForegroundProcessProbe(detect: { _, _ in
            // Block long enough for the synchronous introspection checks
            // below to run before the callback resolves the probe entry.
            Thread.sleep(forTimeInterval: 1.0)
            return ForegroundProcessInfo(name: "zsh", command: nil, pid: 42)
        })
        let sid = SurfaceID()
        #expect(probe.isPending(surfaceID: sid) == false)

        probe.probe(
            surfaceID: sid,
            shellPID: 42,
            ptyMasterFD: nil,
            timeout: 5.0
        ) { _ in /* no-op */ }

        #expect(probe.isPending(surfaceID: sid) == true)
        #expect(probe.pendingCount == 1)

        probe.cancel(surfaceID: sid)
        #expect(probe.isPending(surfaceID: sid) == false)
        #expect(probe.pendingCount == 0)
    }
}

