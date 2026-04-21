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

    /// Clears stale per-surface agent state as soon as the shell prompt
    /// returns on that same surface.
    ///
    /// OSC 133;A is emitted by the shell prompt, not by Claude/Codex TUI
    /// input prompts. Once we receive it for a surface, any agent state
    /// still attached to that surface is stale. Waiting for the async
    /// foreground-process probe left a race where the probe could miss
    /// its 50 ms deadline and Aurora/status/dashboard would keep showing
    /// a dead Codex/Claude entry until another incidental refresh. This
    /// deterministic reset keeps the UI aligned with the terminal's own
    /// semantic state.
    ///
    /// - Returns: `true` when a non-idle / agent-bearing store entry was
    ///   reset, `false` when there was nothing to clear.
    @discardableResult
    func resetAgentStateOnShellPromptIfNeeded(
        surfaceID: SurfaceID,
        tabID: TabID
    ) -> Bool {
        guard let store = injectedPerSurfaceStore else { return false }
        let current = store.state(for: surfaceID)
        guard current.agentState != .idle || current.hasAgent else {
            return false
        }

        performAgentStateReset(
            surfaceID: surfaceID,
            tabID: tabID,
            reason: .shellPromptWithShellForeground
        )
        return true
    }

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
    /// ## Async probe
    ///
    /// The foreground-process lookup runs **off** the main thread via
    /// `ForegroundProcessProbe`. The synchronous path used to block the
    /// main thread on `sysctl(KERN_PROC_ALL)`, which could stall
    /// keystroke delivery for the focused surface under contention —
    /// the exact failure mode that Fase B smoke-tested as "split pane
    /// stops accepting input after a zsh autocorrect prompt". The probe
    /// enforces a hard 50 ms deadline; if detection does not resolve
    /// in time the recovery is skipped for this shell-prompt event.
    /// The next prompt and the `.launched` watchdog remain as safety
    /// nets, so a single missed probe never strands a stale state.
    ///
    /// The completion handler re-reads the store state before applying
    /// the reset because the per-surface store can advance between the
    /// moment we armed the probe and the moment the detector resolves
    /// (for example, a hook event may transition the surface back to
    /// `.idle` on its own).
    ///
    /// Designed to be safe to call on every OSC 133;A (shell prompt)
    /// event: misses are silent and each hit performs O(1) work on the
    /// main thread plus a bounded background probe.
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

        // Synchronous guards first — they match the original behaviour
        // and let the no-registration / already-idle tests stay green
        // without waiting on the async probe.
        let initialState = store.state(for: surfaceID).agentState
        guard initialState != .idle else { return }

        guard let registration = bridge.processMonitorRegistration(for: surfaceID) else {
            return
        }

        foregroundProcessProbe.probe(
            surfaceID: surfaceID,
            shellPID: registration.shellPID,
            ptyMasterFD: registration.ptyMasterFD
        ) { [weak self] info in
            guard let self else { return }
            // The probe delivered `nil` either because detection failed
            // or because the 50 ms deadline beat the background work.
            // Treat both the same way: skip the reset, the next prompt
            // or the `.launched` watchdog will retry.
            guard let info else { return }

            // Re-read the state — other detection layers may have moved
            // the surface on/off `.idle` while the probe was running.
            // This keeps the reset idempotent and race-free.
            guard let store = self.injectedPerSurfaceStore else { return }
            let currentState = store.state(for: surfaceID).agentState

            guard AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: currentState,
                foregroundProcessName: info.name
            ) else { return }

            self.performAgentStateReset(
                surfaceID: surfaceID,
                tabID: tabID,
                reason: .shellPromptWithShellForeground
            )
        }
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

    /// Cancels any pending foreground-process probe for a surface.
    ///
    /// Called from the same teardown paths that already cancel the
    /// `.launched` watchdog (`destroyTerminalSurface`,
    /// `destroyAllSurfaces`, `closeSplitAction`, `.processExited`).
    /// Dropping stale probes before the surface vanishes prevents the
    /// completion handler from touching a missing registration and
    /// keeps `pendingCount` accurate for diagnostics.
    func cancelForegroundProbe(surfaceID: SurfaceID) {
        foregroundProcessProbe.cancel(surfaceID: surfaceID)
    }

    /// Clears the surface-input-drop monitor entry for a surface.
    ///
    /// Teardown paths call this alongside the watchdog / probe cancels
    /// so a recycled `SurfaceID` (extremely rare with UUID identities
    /// but possible across session restore) never inherits a stale
    /// consecutive-drop counter or a stuck `notified` flag.
    func cancelInputDropTracking(surfaceID: SurfaceID) {
        surfaceInputDropMonitor.clear(surfaceID: surfaceID)
    }

    // MARK: - Input-drop observer wiring

    /// Connects the bridge's input-delivery observer to the per-surface
    /// drop monitor and wires the monitor's stuck-pane handler to the
    /// user-visible notification path.
    ///
    /// Idempotent: safe to call more than once. Production wiring
    /// happens during the controller's `init` so every window gets its
    /// own monitor from the first surface onwards. Tests that do not
    /// need bridge events can drive the monitor directly and ignore
    /// this plumbing.
    ///
    /// The wiring is conditional on the concrete `CocxyCoreBridge`
    /// type: only that bridge emits `InputDeliveryEvent`, and other
    /// `TerminalEngine` conformers used by tests (`MockTerminalEngine`)
    /// have no observer field. Those code paths simply skip the
    /// install — the monitor still works when driven directly.
    func installInputDropMonitorObserver() {
        surfaceInputDropMonitor.onStuckPane = { [weak self] surfaceID, reason in
            self?.presentStuckPaneNotification(
                surfaceID: surfaceID,
                reason: reason
            )
        }

        guard let cocxyBridge = bridge as? CocxyCoreBridge else { return }
        cocxyBridge.inputDeliveryObserver = { [weak self] surfaceID, event in
            guard let self else { return }
            switch event {
            case .delivered:
                self.surfaceInputDropMonitor.recordDelivery(surfaceID: surfaceID)
            case .dropped(let reason):
                self.surfaceInputDropMonitor.recordDrop(
                    surfaceID: surfaceID,
                    reason: reason
                )
            }
        }
    }

    /// Surfaces the "pane is not accepting input" notification to the
    /// user. Invoked by the drop monitor when a surface accumulates
    /// `SurfaceInputDropMonitor.threshold` consecutive drops since the
    /// last successful delivery.
    ///
    /// The handler does three things:
    /// 1. Emits a system beep — drops are silent by nature, the beep
    ///    is the first signal the user gets even if the notification
    ///    system is denied permissions.
    /// 2. Resolves the owning tab so the notification panel groups
    ///    correctly. Falls back to the active tab when the surface
    ///    mapping has already vanished (surface torn down between the
    ///    last drop and this handler).
    /// 3. Enqueues a `.custom("input-stuck-pane")` notification via
    ///    the injected manager. The body hints at the recovery action
    ///    (`Cmd+Shift+W` closes the split) so the user is never stuck
    ///    wondering how to escape the dead pane.
    private func presentStuckPaneNotification(
        surfaceID: SurfaceID,
        reason: InputDropReason
    ) {
        NSSound.beep()

        let targetTabID = tabID(for: surfaceID) ?? tabManager.activeTabID
        guard let tabID = targetTabID else { return }

        let body: String
        switch reason {
        case .surfaceMissing:
            body = "This pane lost its terminal and is no longer routing input. Close it with Cmd+Shift+W."
        case .ptyWriteFailed:
            body = "This pane's shell is not accepting keystrokes. Close it with Cmd+Shift+W and open a fresh split."
        }

        let notification = CocxyNotification(
            type: .custom("input-stuck-pane"),
            tabId: tabID,
            title: "Pane stopped accepting input",
            body: body
        )
        injectedNotificationManager?.notify(notification)
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
    /// 1. **Cancel watchdog + probe** — avoid double-firing if reset
    ///    was invoked by the shell-prompt path while the watchdog was
    ///    still armed, and drop any in-flight foreground probe that
    ///    would otherwise deliver a late completion onto a now-clean
    ///    surface.
    /// 2. **Engine bucket cleanup** — `clearSurface(_:)` drops the
    ///    engine's debounce bucket and hook-session record so stale
    ///    entries cannot suppress future transitions on the surface.
    ///    Critically, this call **does not** touch the bridge's
    ///    `surfaces[surfaceID]` entry: the only writer to that
    ///    dictionary is `CocxyCoreBridge.destroySurface(_:)`, which is
    ///    not called here. That invariant is what keeps `sendKeyEvent`
    ///    and `sendText` live after a shell-prompt recovery — regress
    ///    it at your peril. See `feedback_process_exit_clear_buckets`
    ///    for the paired `.processExited` path where both calls live.
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
        cancelForegroundProbe(surfaceID: surfaceID)

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
}
