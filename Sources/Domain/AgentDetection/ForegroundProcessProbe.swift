// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ForegroundProcessProbe.swift - Main-thread-safe wrapper around
// `ForegroundProcessDetector.detect` for the shell-prompt recovery path.

import Foundation
import Darwin

/// Asynchronous, timeout-bounded probe that runs
/// `ForegroundProcessDetector.detect(...)` off the main thread.
///
/// The shell-prompt recovery path (`MainWindowController+AgentLifecycleRecovery`)
/// needs the PTY foreground process name to decide whether a surface's
/// agent state should be reset. `ForegroundProcessDetector.detect` relies
/// on `sysctl(KERN_PROC_ALL)`, which can stall the main thread under lock
/// contention or when the process table is large. A stall here blocks
/// keydown delivery for the focused surface, which is the exact failure
/// mode that Fase B smoke-tested: typing "dies" on a split immediately
/// after a zsh autocorrect prompt redraws.
///
/// This probe moves the `sysctl` call onto a user-initiated dispatch
/// queue and enforces a hard deadline (`defaultTimeout = 50 ms`). When
/// the deadline elapses first, the caller receives `nil` and the
/// recovery is silently skipped for that shell-prompt event — the
/// `.launched` watchdog and the next shell prompt remain as safety
/// nets, so the worst case is a single deferred reset, not a regression.
///
/// ## Threading model
///
/// The probe is isolated to the main actor because it owns the pending
/// work items keyed by `SurfaceID` and because the completion handler
/// needs to touch `AgentStatePerSurfaceStore` / UI state without hops.
/// The actual `sysctl` runs on `probeQueue`
/// (`DispatchQueue.global(qos: .userInitiated)` by default).
///
/// ## Race-free completion
///
/// Two things can finish the probe: the background work item (fast
/// path) or the deadline timer (slow path). The internal `ProbeBox`
/// serialises access with an `NSLock` so exactly one of those two
/// callers delivers the completion; the other observes an already
/// claimed box and is a no-op. That keeps the shape of the API simple
/// — completion is called at most once per `probe(...)` invocation.
///
/// ## Idempotency and cancellation
///
/// `probe(surfaceID:...)` cancels any probe still pending for the same
/// surface before arming a new one, matching the semantics of
/// `AgentLaunchedWatchdog.schedule(...)`. `cancel(surfaceID:)` drops
/// the pending entry and cancels its work item (cancellation is
/// advisory — the work item may have already started running, but the
/// box will not deliver anything because its `claim` window closed).
///
/// - SeeAlso: `ForegroundProcessDetector.detect(shellPID:ptyMasterFD:)`
/// - SeeAlso: `MainWindowController.recoverAgentStateOnShellPromptIfNeeded(surfaceID:tabID:)`
@MainActor
final class ForegroundProcessProbe {

    /// Default upper bound on the background `sysctl` wall time. Chosen
    /// conservatively so the main thread never stalls across a typing
    /// burst. 50 ms is longer than a typical `KERN_PROC_ALL` call on a
    /// healthy machine (microseconds) but well under the 16.6 ms frame
    /// budget we care about for smooth input.
    static let defaultTimeout: TimeInterval = 0.05

    private struct Pending {
        let workItem: DispatchWorkItem
        let box: ProbeBox
    }

    private var pending: [SurfaceID: Pending] = [:]

    private let probeQueue: DispatchQueue
    private let detect: @Sendable (pid_t, Int32?) -> ForegroundProcessInfo?

    /// - Parameters:
    ///   - probeQueue: Background queue on which the `sysctl` call runs.
    ///     Defaults to a global user-initiated queue so contention with
    ///     other background work is bounded.
    ///   - detect: Injection point used by tests to drive the probe
    ///     without touching real `sysctl` state. Defaults to the
    ///     production detector.
    init(
        probeQueue: DispatchQueue = DispatchQueue.global(qos: .userInitiated),
        detect: @Sendable @escaping (pid_t, Int32?) -> ForegroundProcessInfo? = {
            ForegroundProcessDetector.detect(shellPID: $0, ptyMasterFD: $1)
        }
    ) {
        self.probeQueue = probeQueue
        self.detect = detect
    }

    // MARK: - Probe

    /// Arms a foreground-process probe for a surface.
    ///
    /// The completion handler is invoked exactly once on the main actor
    /// with either the detected info (background finished first) or
    /// `nil` (deadline elapsed first, or the probe was cancelled by a
    /// later `probe(...)` / `cancel(surfaceID:)` call).
    ///
    /// - Parameters:
    ///   - surfaceID: Surface whose PTY foreground to inspect.
    ///   - shellPID: Shell PID from the bridge's process-monitor
    ///     registration.
    ///   - ptyMasterFD: Master FD from the bridge's process-monitor
    ///     registration. Pass `nil` if the registration lacks it.
    ///   - timeout: Hard deadline. Defaults to `defaultTimeout`.
    ///   - completion: Closure invoked on the main actor. `nil`
    ///     indicates the probe did not resolve in time.
    func probe(
        surfaceID: SurfaceID,
        shellPID: pid_t,
        ptyMasterFD: Int32?,
        timeout: TimeInterval = ForegroundProcessProbe.defaultTimeout,
        completion: @MainActor @escaping (ForegroundProcessInfo?) -> Void
    ) {
        cancel(surfaceID: surfaceID)

        let box = ProbeBox()
        let detect = self.detect
        let workItem = DispatchWorkItem {
            let info = detect(shellPID, ptyMasterFD)
            box.store(info)
        }

        pending[surfaceID] = Pending(workItem: workItem, box: box)
        probeQueue.async(execute: workItem)

        // Deadline path. Wins when `sysctl` is slow enough that the
        // background work item has not yet populated the box.
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            Task { @MainActor [weak self] in
                self?.deliver(
                    surfaceID: surfaceID,
                    workItem: workItem,
                    box: box,
                    cancelWorkItemIfClaimed: true,
                    completion: completion
                )
            }
        }

        // Fast path. Wins when the background finishes before the
        // deadline. `notify` queues onto main regardless of whether the
        // work item was cancelled — the box claim guards against
        // double delivery.
        workItem.notify(queue: .main) { [weak self] in
            Task { @MainActor [weak self] in
                self?.deliver(
                    surfaceID: surfaceID,
                    workItem: workItem,
                    box: box,
                    cancelWorkItemIfClaimed: false,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Cancellation

    /// Cancels the pending probe for a surface if one exists. Safe to
    /// call from teardown paths (`destroySurface`, `closeSplitAction`,
    /// `destroyAllSurfaces`) so stale completions cannot touch dead
    /// state.
    func cancel(surfaceID: SurfaceID) {
        guard let entry = pending.removeValue(forKey: surfaceID) else { return }
        entry.workItem.cancel()
        // Claim the box so the late `notify` callback (if any) sees a
        // consumed outcome and skips delivery.
        _ = entry.box.claim()
    }

    /// Cancels every pending probe. Called during full window teardown.
    func cancelAll() {
        for (_, entry) in pending {
            entry.workItem.cancel()
            _ = entry.box.claim()
        }
        pending.removeAll()
    }

    // MARK: - Introspection

    /// Whether a probe is currently pending for the given surface.
    /// Intended for tests and defensive assertions.
    func isPending(surfaceID: SurfaceID) -> Bool {
        pending[surfaceID] != nil
    }

    /// Number of pending probes. Intended for tests.
    var pendingCount: Int { pending.count }

    // MARK: - Private

    private func deliver(
        surfaceID: SurfaceID,
        workItem: DispatchWorkItem,
        box: ProbeBox,
        cancelWorkItemIfClaimed: Bool,
        completion: @MainActor (ForegroundProcessInfo?) -> Void
    ) {
        // A later `probe(...)` or explicit `cancel(surfaceID:)` may have
        // replaced the entry we were called for. Compare by identity so
        // we only deliver when the state still matches what we armed.
        guard pending[surfaceID]?.workItem === workItem else { return }

        guard let outcome = box.claim() else {
            // The other branch (fast/slow) already claimed the outcome.
            // Drop the entry to keep introspection accurate and return.
            pending.removeValue(forKey: surfaceID)
            return
        }

        pending.removeValue(forKey: surfaceID)
        if cancelWorkItemIfClaimed {
            // Deadline path: the work item may still be running. Cancel
            // so the `sysctl` descheduled work does not waste cycles
            // after the caller has already received `nil`.
            workItem.cancel()
        }
        completion(outcome.info)
    }
}

// MARK: - ProbeBox

/// Race-safe single-shot container for the probe outcome.
///
/// Exactly one of `store(...)` (from the background queue) or the two
/// delivery callers (deadline / notify) will observe a non-nil value
/// via `claim()`. The lock guarantees the read/write pair is atomic
/// under contention.
///
/// Declared `@unchecked Sendable` because the stored struct is already
/// Sendable and the `NSLock` guards every mutable field.
private final class ProbeBox: @unchecked Sendable {

    struct Outcome {
        let info: ForegroundProcessInfo?
    }

    private let lock = NSLock()
    private var storedOutcome: Outcome?
    private var claimed = false

    /// Records the background detector result. No-op if already stored
    /// (which happens when `claim()` ran first due to a deadline win).
    func store(_ info: ForegroundProcessInfo?) {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed, storedOutcome == nil else { return }
        storedOutcome = Outcome(info: info)
    }

    /// Takes ownership of the outcome. Returns `nil` on every call after
    /// the first; the first call returns the stored outcome (which may
    /// wrap a `nil` `ForegroundProcessInfo` when detection failed, or
    /// even an empty outcome when the deadline beat the background).
    func claim() -> Outcome? {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return nil }
        claimed = true
        // When the deadline wins before `store` was called, return an
        // explicit empty outcome so the caller still completes with
        // `nil` instead of leaving the completion hanging.
        return storedOutcome ?? Outcome(info: nil)
    }
}
