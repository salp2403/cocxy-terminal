// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+AgentLifecycleRecovery.swift - Safety net that clears stuck
// per-surface agent state when the backing shell prompt returns without the agent
// emitting a `SessionEnd` hook.

import AppKit

extension MainWindowController {

    // MARK: - Reasons

    /// Explains what triggered a call to `performAgentStateReset`.
    ///
    /// The reason is currently used only for logging and regression tests,
    /// but keeping it as part of the API makes future diagnostic tooling
    /// (for example, a developer log channel or a telemetry-free debug
    /// overlay) straightforward to wire without reshaping the control flow.
    enum AgentStateResetReason: Equatable, Sendable {
        /// A shell prompt appeared on a surface whose PTY foreground
        /// process is now a login shell. Used by the primary recovery
        /// path in `MainWindowController+SurfaceLifecycle`.
        case shellPromptWithShellForeground

        /// The `.launched` watchdog expired without observing any
        /// further transitions on the surface. Used by the secondary
        /// safety net for agents that crash before producing output.
        case launchedWatchdog
    }

    // MARK: - Shell Prompt Recovery

    /// Recovers the per-surface agent state when a shell prompt returns
    /// on a surface whose agent already terminated but never emitted a
    /// `SessionEnd` hook.
    ///
    /// The routine is a **no-op** in every safe scenario:
    /// - Agent detection disabled (`injectedPerSurfaceStore == nil`).
    /// - Store entry already `.idle`.
    /// - Bridge cannot resolve the surface's process metadata.
    /// - Foreground process detection fails.
    /// - Foreground process is not a known shell (the user is in an
    ///   editor, `git`, a sub-command invoked by the agent, or the
    ///   agent itself is still foregrounded).
    ///
    /// When all safety guards pass, the routine delegates to
    /// `performAgentStateReset(surfaceID:tabID:reason:)` so the rest of
    /// the UI (sidebar, status bar, progress overlay, notification ring,
    /// session registry) observes the same state-reset sequence used by
    /// explicit teardown paths.
    ///
    /// Designed to be safe to call on every OSC 133;A (shell prompt)
    /// event: misses are silent and each hit performs O(1) work.
    ///
    /// - Parameters:
    ///   - surfaceID: The surface that emitted the prompt.
    ///   - tabID: The tab that owns the surface; used to refresh
    ///     tab-scoped UI (status bar, notification ring).
    func recoverAgentStateOnShellPromptIfNeeded(
        surfaceID: SurfaceID,
        tabID: TabID
    ) {
        guard let store = injectedPerSurfaceStore else { return }

        let currentState = store.state(for: surfaceID).agentState
        let foregroundName = resolveForegroundProcessName(for: surfaceID)

        guard AgentLifecycleRecovery.shouldResetOnShellPrompt(
            currentState: currentState,
            foregroundProcessName: foregroundName
        ) else { return }

        performAgentStateReset(
            surfaceID: surfaceID,
            tabID: tabID,
            reason: .shellPromptWithShellForeground
        )
    }

    // MARK: - Watchdog Schedule / Cancel

    /// Arms the `.launched` watchdog for a surface when the store
    /// transitions the surface into `.launched`.
    ///
    /// Called from the agent-detection wiring (`wireAgentDetectionToTabs`)
    /// after the store has been updated. If the watchdog is already armed
    /// for the same surface, the existing work item is cancelled and a
    /// fresh one is scheduled — callers do not need to track whether the
    /// surface was already being watched.
    ///
    /// - Parameters:
    ///   - surfaceID: The surface that just entered `.launched`.
    ///   - tabID: The owning tab used to refresh tab-scoped UI when the
    ///     watchdog fires.
    ///   - timeout: Seconds until the watchdog fires. Tests pass small
    ///     values; production uses `AgentLaunchedWatchdog.defaultTimeout`.
    func scheduleLaunchedWatchdog(
        surfaceID: SurfaceID,
        tabID: TabID,
        timeout: TimeInterval = AgentLaunchedWatchdog.defaultTimeout
    ) {
        agentLaunchedWatchdog.schedule(
            surfaceID: surfaceID,
            timeout: timeout
        ) { [weak self] in
            guard let self else { return }
            // Re-read the current state inside the handler: if the
            // surface has moved out of `.launched` between scheduling
            // and firing, the wiring should have cancelled the watchdog,
            // but re-checking keeps the recovery idempotent under any
            // out-of-order delivery.
            let currentState = self.injectedPerSurfaceStore?
                .state(for: surfaceID)
                .agentState
                ?? .idle
            guard currentState == .launched else { return }
            self.performAgentStateReset(
                surfaceID: surfaceID,
                tabID: tabID,
                reason: .launchedWatchdog
            )
        }
    }

    /// Cancels the `.launched` watchdog for a surface. Called from any
    /// state transition that leaves `.launched` (output received, error,
    /// agent exit, explicit teardown). Idempotent and cheap.
    func cancelLaunchedWatchdog(surfaceID: SurfaceID) {
        agentLaunchedWatchdog.cancel(surfaceID: surfaceID)
    }

    // MARK: - Reset Routine

    /// Flushes the per-surface agent state back to `.idle` and refreshes
    /// every dependent UI surface. This is the one place that owns the
    /// "agent went away" cleanup so the shell-prompt recovery path and
    /// the `.launched` watchdog behave identically.
    ///
    /// The sequence matches what `wireAgentDetectionToTabs` does when it
    /// observes an `.agentExited` transition, but without going through
    /// the detection engine's state machine. Rationale: the state machine
    /// is currently global (one instance per engine) while the store is
    /// genuinely per-surface. Emitting a global `.agentExited` event to
    /// clear a single surface could desynchronize the global state from
    /// other surfaces that are still running an agent.
    ///
    /// Steps, in order:
    /// 1. **Cancel watchdog** — avoid double-firing if reset was invoked
    ///    by the shell-prompt path while the watchdog was still armed.
    /// 2. **Engine bucket cleanup** — `clearSurface(_:)` drops the
    ///    engine's debounce bucket and hook-session record so stale
    ///    entries cannot suppress future transitions on the surface.
    /// 3. **Store reset** — removes the per-surface entry entirely.
    ///    Subsequent reads return `.idle` from
    ///    `AgentStatePerSurfaceStore.state(for:)`.
    /// 4. **Session registry sync** — propagates the reset to the
    ///    cross-window aggregator so other windows stop counting the
    ///    surface as active.
    /// 5. **UI refresh** — sidebar (`syncWithManager`), status bar
    ///    (`refreshStatusBar`), progress overlay
    ///    (`updateAgentProgressOverlay`), and the per-surface
    ///    notification ring (`updateNotificationRing`).
    ///
    /// - Parameters:
    ///   - surfaceID: The surface whose state should be cleared.
    ///   - tabID: The owning tab; used to refresh tab-scoped UI.
    ///   - reason: What triggered the reset (for logging / tests).
    func performAgentStateReset(
        surfaceID: SurfaceID,
        tabID: TabID,
        reason: AgentStateResetReason
    ) {
        _ = reason  // Reserved for future diagnostic logging.

        cancelLaunchedWatchdog(surfaceID: surfaceID)

        injectedAgentDetectionEngine?.clearSurface(surfaceID)
        injectedPerSurfaceStore?.reset(surfaceID: surfaceID)

        sessionRegistry?.updateAgentState(
            sessionIDForTab(tabID),
            state: .idle,
            agentName: nil
        )

        tabBarViewModel?.syncWithManager()
        refreshStatusBar()
        updateAgentProgressOverlay()
        updateNotificationRing(for: tabID, agentState: .idle)
    }

    // MARK: - Foreground Process Resolution

    /// Reads the PTY foreground process name for a surface through the
    /// terminal engine's process-monitor registration.
    ///
    /// Returns `nil` when the bridge cannot supply a registration (engine
    /// disabled, surface destroyed, shell PID unknown) or when the
    /// `sysctl`-based detector fails. The caller treats a `nil` result as
    /// "do not reset" which is the safe default.
    ///
    /// Uses the convenience overload of `ForegroundProcessDetector.detect`
    /// that internally takes a full process snapshot. The recovery path
    /// fires at most once per shell-prompt event — at human typing cadence
    /// — so the one-shot `sysctl(KERN_PROC_ALL)` cost (a few milliseconds
    /// at worst) is negligible compared to the monitoring poll that
    /// `ProcessMonitorService` already runs every 2 seconds.
    ///
    /// Kept `internal` so the agent-lifecycle recovery extension and the
    /// regression tests can reuse it; not part of the controller's public
    /// API surface.
    func resolveForegroundProcessName(for surfaceID: SurfaceID) -> String? {
        guard let registration = bridge.processMonitorRegistration(for: surfaceID) else {
            return nil
        }
        return ForegroundProcessDetector.detect(
            shellPID: registration.shellPID,
            ptyMasterFD: registration.ptyMasterFD
        )?.name
    }
}
