// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentLaunchedWatchdog.swift - Per-surface watchdog for the `.launched` agent state.

import Foundation

/// Per-surface watchdog that fires a recovery callback when a surface has
/// remained in the `.launched` state for longer than a configurable timeout
/// without any further activity.
///
/// The detection pipeline marks a surface as `.launched` as soon as the
/// pattern detector recognises the agent command being typed into the shell
/// (for example `claude --dangerously-skip-permissions`). From there, the
/// pipeline expects one of three outcomes: the agent emits output and the
/// state transitions to `.working`, the agent fails and the state transitions
/// to `.error`, or the agent process terminates and `notifyProcessExited`
/// brings the state back to `.idle`. When none of those happens — typically
/// because the agent crashed before printing anything or the user aborted
/// the launch before the first output — the state is frozen at `.launched`
/// indefinitely and the UI shows `"… starting…"` forever.
///
/// This watchdog plugs that gap by scheduling a one-shot `DispatchWorkItem`
/// on the main queue whenever a surface enters `.launched`. If any other
/// transition arrives before the timeout, the caller cancels the work item
/// and no callback runs. If the timeout elapses, the callback runs on the
/// main actor and the caller performs the same reset routine used by the
/// shell-prompt recovery path.
///
/// ## Threading
///
/// The watchdog is isolated to the main actor because the detection engine
/// and the per-surface store both run on the main actor. Keeping the
/// scheduler on the same isolation domain avoids cross-actor hops when the
/// timer fires and lets the callback mutate per-surface state directly.
///
/// ## Idempotency
///
/// `schedule(surfaceID:timeout:handler:)` cancels any previously queued
/// work item for the same surface before arming a new one. This makes the
/// method safe to call from state-change sinks that may observe several
/// consecutive `.launched` events (for example, when a hook session starts
/// after a pattern-based launch has already been recorded).
///
/// ## Handler contract
///
/// The handler is invoked exactly once per successful schedule, at the
/// scheduled deadline, on the main actor. If the work item is cancelled
/// before the deadline, the handler is not invoked. Callers should keep
/// the handler short and defer heavy work to the window controller's
/// existing refresh helpers.
///
/// - SeeAlso: `AgentLifecycleRecovery.shouldResetOnShellPrompt(currentState:foregroundProcessName:)`
/// - SeeAlso: `AgentDetectionEngineImpl.clearSurface(_:)`
/// - SeeAlso: `AgentStatePerSurfaceStore.reset(surfaceID:)`
@MainActor
final class AgentLaunchedWatchdog {

    /// Default timeout in seconds. Chosen to be generous enough to cover
    /// slow agents (Aider, Gemini CLI) whose bootstrap produces output
    /// within single-digit seconds, while still recovering from stuck
    /// `.launched` states within the same minute. Callers can override
    /// per-call via `schedule(surfaceID:timeout:handler:)`.
    static let defaultTimeout: TimeInterval = 30.0

    /// Work items keyed by the surface they monitor. Cancelling a work
    /// item removes it from the dictionary so `isScheduled(surfaceID:)`
    /// returns the expected truth value right after the cancellation.
    private var workItems: [SurfaceID: DispatchWorkItem] = [:]

    // MARK: - Scheduling

    /// Arms a watchdog for the given surface.
    ///
    /// Any pending work item for the same surface is cancelled before the
    /// new one is queued. The handler runs on the main actor after the
    /// timeout unless `cancel(surfaceID:)` (or a subsequent `schedule`)
    /// replaces it first.
    ///
    /// - Parameters:
    ///   - surfaceID: The surface to monitor.
    ///   - timeout: Seconds until the handler fires. Defaults to
    ///     `defaultTimeout`. Tests may pass small values (e.g. `0.05`).
    ///   - handler: Closure invoked on the main actor when the timeout
    ///     elapses without a prior cancellation.
    func schedule(
        surfaceID: SurfaceID,
        timeout: TimeInterval = AgentLaunchedWatchdog.defaultTimeout,
        handler: @escaping @MainActor () -> Void
    ) {
        cancel(surfaceID: surfaceID)

        let workItem = DispatchWorkItem { [weak self] in
            // `DispatchWorkItem` hands control back on whatever queue it
            // was scheduled on (main, in our case). Hop onto the main
            // actor explicitly so callers observe the handler on the
            // expected isolation domain and can touch store / engine /
            // UI state without additional indirection.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.workItems.removeValue(forKey: surfaceID)
                handler()
            }
        }

        workItems[surfaceID] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + timeout,
            execute: workItem
        )
    }

    /// Cancels any pending watchdog for the given surface.
    ///
    /// Idempotent: calling on a surface without a scheduled work item
    /// does nothing.
    func cancel(surfaceID: SurfaceID) {
        guard let pending = workItems.removeValue(forKey: surfaceID) else {
            return
        }
        pending.cancel()
    }

    /// Cancels every pending watchdog. Called during full window teardown
    /// so fire-and-forget work items do not touch dead state.
    func cancelAll() {
        for (_, item) in workItems {
            item.cancel()
        }
        workItems.removeAll()
    }

    // MARK: - Introspection

    /// Returns `true` when a watchdog is currently scheduled for the
    /// given surface. Intended for tests and defensive assertions.
    func isScheduled(surfaceID: SurfaceID) -> Bool {
        workItems[surfaceID] != nil
    }

    /// Returns the number of pending watchdogs. Intended for tests.
    var scheduledCount: Int {
        workItems.count
    }
}
