// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+SurfaceLifecycle.swift - Terminal surface creation, destruction, and wiring.

import AppKit
import CocxyCommandCorrections

private enum CocxyCoreSemanticState {
    static let commandRunning: UInt8 = 3
    static let agentActive: UInt8 = 4
}

private enum CocxyCoreSemanticBlockType {
    static let commandInput: UInt8 = 1
}

private enum AgentScrollFallback {
    static let launchConfigs = AgentConfigService
        .defaultAgentConfigs()
        .map(AgentConfigService.compile)

    static func commandInputLaunchesKnownAgent(_ command: String) -> Bool {
        AgentConfigService.agentIdentifier(
            matchingLaunchLine: command,
            compiledConfigs: launchConfigs
        ) != nil
    }
}

// MARK: - Surface Lifecycle

/// Extension that manages the lifecycle of terminal surfaces:
/// creation, destruction, handler wiring, and OSC notification processing.
///
/// Extracted from MainWindowController to isolate terminal engine
/// interactions from window layout and UI concerns.
extension MainWindowController {

    // MARK: - Surface Creation

    /// Creates a terminal surface in the view and spawns the shell.
    ///
    /// Called after the window is displayed and the view has a valid
    /// frame for Metal rendering.
    func createTerminalSurface() {
        guard let surfaceView = terminalSurfaceView else { return }
        let firstTabWorkingDirectory = tabManager.tabs.first.flatMap { tab in
            tabManager.tab(for: tab.id)?.workingDirectory
        }

        do {
            let surfaceID = try bridge.createSurface(
                in: surfaceView,
                workingDirectory: firstTabWorkingDirectory,
                command: nil
            )
            terminalViewModel.markRunning(surfaceID: surfaceID)
            surfaceView.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)
            surfaceView.syncSizeWithTerminal()

            // Register the first tab's surface in all tracking dictionaries.
            // This ensures destroyAllSurfaces can find it without special-casing.
            if let firstTabID = tabManager.tabs.first?.id {
                tabSurfaceMap[firstTabID] = surfaceID
                tabSurfaceViews[firstTabID] = surfaceView
                tabViewModels[firstTabID] = terminalViewModel
                displayedTabID = firstTabID
                registerTerminalEngine(bridge, tabID: firstTabID, surfaceID: surfaceID)

                registerSurfaceWithProcessMonitor(surfaceID, tabID: firstTabID)
                wireSurfaceHandlers(
                    for: surfaceID,
                    tabID: firstTabID,
                    in: surfaceView,
                    initialWorkingDirectory: firstTabWorkingDirectory
                )
                attachRestoredCommandBlocksIfAvailable(
                    tabID: firstTabID,
                    surfaceID: surfaceID,
                    in: surfaceView
                )
                startAutomaticSessionReplayIfNeeded(surfaceID: surfaceID, tabID: firstTabID)
            }
        } catch {
            NSLog("[MainWindowController] Failed to create terminal surface: %@",
                  String(describing: error))
        }
    }

    func registerSurfaceWithProcessMonitor(_ surfaceID: SurfaceID, tabID: TabID) {
        guard let registration = terminalEngine(for: surfaceID).processMonitorRegistration(for: surfaceID) else {
            return
        }
        processMonitor?.registerTab(
            tabID,
            shellPID: registration.shellPID,
            ptyMasterFD: registration.ptyMasterFD,
            shellIdentity: registration.shellIdentity
        )
    }

    // MARK: - Shared Handler Wiring

    /// Wires OSC/output callbacks and auxiliary helpers for any terminal surface.
    ///
    /// Tabs, restored tabs, and split panes all share the same per-tab
    /// pipelines for search, agent detection, command timing, and inline image
    /// parsing. Keeping this in one place prevents subtle drift between the
    /// different surface creation paths.
    func wireSurfaceHandlers(
        for surfaceID: SurfaceID,
        tabID: TabID,
        in surfaceView: TerminalHostView,
        initialWorkingDirectory: URL?
    ) {
        if let initialWorkingDirectory {
            surfaceWorkingDirectories[surfaceID] = initialWorkingDirectory
        }

        let capturedTabID = tabID
        let capturedSurfaceID = surfaceID

        let surfaceEngine = terminalEngine(for: surfaceID)

        surfaceEngine.setOSCHandler(for: surfaceID) { [weak self] notification in
            Task { @MainActor in
                self?.handleOSCNotification(
                    notification,
                    fromTabID: capturedTabID,
                    surfaceID: capturedSurfaceID
                )
            }
        }

        let buffer: TerminalOutputBuffer
        if let existingBuffer = tabOutputBuffers[tabID] {
            buffer = existingBuffer
        } else {
            let newBuffer = TerminalOutputBuffer()
            tabOutputBuffers[tabID] = newBuffer
            buffer = newBuffer
        }

        if tabID == visibleTabID {
            terminalOutputBuffer = buffer
        }

        let engine = injectedAgentDetectionEngine
        let commandTracker = commandTracker(for: tabID)
        let imageDetector = imageDetector(for: surfaceID, tabID: tabID)
        let outputDispatcher = outputDispatcher(
            for: surfaceID,
            commandTracker: commandTracker,
            imageDetector: imageDetector,
            engine: engine
        )

        surfaceEngine.setOutputHandler(
            for: surfaceID
        ) { [weak buffer, weak outputDispatcher] data in
            // Fan the chunk to the thread-safe detectors on the per-
            // surface background queue. The dispatcher runs the
            // command-duration tracker, the inline-image OSC detector,
            // and (when an engine is wired) the three agent-detection
            // layers — all `NSLock`-protected and ordered by the
            // dispatcher's serial queue. Signal resolution and the
            // state-machine bookkeeping hop back to the main actor
            // through `engine.processBackgroundSignals`, so the main
            // thread keeps rendering even under sustained agent output.
            outputDispatcher?.dispatch(data)

            // Buffer.append is `@MainActor`-bound for SwiftUI scrollback
            // search. Keep it on main exactly as before.
            Task { @MainActor in
                buffer?.append(data)
            }
        }

        if let surfaceView = surfaceView as? CocxyCoreView {
            surfaceView.outputBufferProvider = { [weak buffer] in
                buffer?.lines ?? []
            }
        }

        surfaceView.onUserInputSubmitted = { [weak engine] in
            // `capturedSurfaceID` is a value-type `SurfaceID` captured
            // implicitly by the closure; propagate it so the
            // waitingInput -> working transition is attributed to the
            // originating split rather than whatever surface happens
            // to be focused when Enter is pressed.
            engine?.notifyUserInput(surfaceID: capturedSurfaceID)
        }

        if let cocxyView = surfaceView as? CocxyCoreView {
            cocxyView.onFocusRequested = { [weak self] in
                guard let self else { return }
                self.applyFocusToSurface(surfaceID: capturedSurfaceID)
            }
            cocxyView.prefersLocalScrollInMouseTrackingMode = { [weak self] in
                self?.surfaceLooksLikeActiveAgent(capturedSurfaceID) ?? false
            }
            cocxyView.prefersPacedDeleteRepeat = { [weak self] in
                self?.surfaceLooksLikeActiveAgent(capturedSurfaceID) ?? false
            }
            cocxyView.prefersPacedPasteDelivery = { [weak self] in
                self?.surfaceLooksLikeActiveAgent(capturedSurfaceID) ?? false
            }
            cocxyView.onRichInputRequested = { [weak self, weak cocxyView] request in
                guard let self, let cocxyView else { return false }
                guard self.shouldAutoShowRichInput(for: request) else { return false }
                return self.presentRichInputComposer(
                    request,
                    for: cocxyView,
                    tabID: capturedTabID
                )
            }
            configureCommandBlockOverlayIntegration(
                for: capturedTabID,
                surfaceID: capturedSurfaceID,
                in: cocxyView
            )
        }
    }

    private func surfaceLooksLikeActiveAgent(_ surfaceID: SurfaceID) -> Bool {
        let surfaceState = injectedPerSurfaceStore?.state(for: surfaceID)
        let bridge = cocxyCoreBridge(forSurface: surfaceID)
        let semantic = bridge?.semanticDiagnostics(for: surfaceID)
        return surfaceState?.isActive == true
            || surfaceState?.hasAgent == true
            || semantic?.state == CocxyCoreSemanticState.agentActive
            || semanticCommandInputLooksLikeActiveAgent(
                bridge: bridge,
                surfaceID: surfaceID,
                semantic: semantic
            )
    }

    private func semanticCommandInputLooksLikeActiveAgent(
        bridge: CocxyCoreBridge?,
        surfaceID: SurfaceID,
        semantic: TerminalSemanticDiagnostics?
    ) -> Bool {
        guard semantic?.state == CocxyCoreSemanticState.commandRunning,
              let command = bridge?
                .semanticBlocks(for: surfaceID, limit: 8)
                .first(where: { $0.blockType == CocxyCoreSemanticBlockType.commandInput })?
                .detail else {
            return false
        }

        return AgentScrollFallback.commandInputLaunchesKnownAgent(command)
    }

    private func commandTracker(for tabID: TabID) -> CommandDurationTracker {
        if let existingTracker = tabCommandTrackers[tabID] {
            return existingTracker
        }

        let tracker = CommandDurationTracker { [weak self] notification in
            Task { @MainActor in
                self?.handleOSCNotification(notification, fromTabID: tabID)
            }
        }
        tabCommandTrackers[tabID] = tracker
        return tracker
    }

    private func imageDetector(for surfaceID: SurfaceID, tabID: TabID) -> InlineImageOSCDetector {
        if let existingDetector = surfaceImageDetectors[surfaceID] {
            return existingDetector
        }

        let detector = InlineImageOSCDetector { [weak self] payload in
            Task { @MainActor in
                self?.handleOSCNotification(
                    .inlineImage(payload),
                    fromTabID: tabID,
                    surfaceID: surfaceID
                )
            }
        }
        surfaceImageDetectors[surfaceID] = detector
        return detector
    }

    /// Returns the background dispatcher that hands PTY chunks to the
    /// per-surface detectors off the main thread. Created on first use
    /// for a surface so the surface-lifecycle path can wire it up at the
    /// same point it constructs the underlying detectors.
    ///
    /// The dispatcher is keyed by `surfaceID` (not `tabID`) because the
    /// inline image detector is per-surface and a split layout would
    /// otherwise share a single dispatcher across panes — defeating the
    /// independent ordering each parser relies on.
    ///
    /// When `engine` is non-nil, the dispatcher also runs the three
    /// agent-detection layers (OSC, pattern, timing) on its background
    /// queue and forwards the resulting signals to the engine through
    /// `processBackgroundSignals(_:_:surfaceID:)`. The engine takes care
    /// of hopping back to the main actor for resolution and state-machine
    /// work, so everything that does not need `@MainActor` ends up off
    /// the main thread.
    private func outputDispatcher(
        for surfaceID: SurfaceID,
        commandTracker: CommandDurationTracker,
        imageDetector: InlineImageOSCDetector,
        engine: AgentDetectionEngineImpl?
    ) -> SurfaceOutputBackgroundDispatcher {
        if let existing = surfaceOutputDispatchers[surfaceID] {
            return existing
        }

        // Capture the detectors weakly so the dispatcher does not extend
        // their lifetimes past `clearSurfaceTracking`. If a chunk reaches
        // the queue after the surface was torn down both closures collapse
        // to no-ops and the data is dropped, exactly as it would be if
        // the bridge had detached the output handler in the same moment.
        var processors: [SurfaceOutputBackgroundDispatcher.Processor] = [
            { [weak commandTracker] data in
                commandTracker?.processBytes(data)
            },
            { [weak imageDetector] data in
                imageDetector?.processBytes(data)
            },
        ]

        if let engine {
            // Capture the per-surface detection layers at registration
            // time so the dispatcher's serial queue keeps each parser's
            // partial-OSC state coherent across chunks. Held weakly so
            // a chunk that lands after `engine.clearSurface(_:)` runs
            // collapses to a no-op instead of resurrecting torn-down
            // detection state.
            let bundle = engine.detectorsForSurface(surfaceID)
            let osc = bundle.osc
            let pattern = bundle.pattern
            let timing = bundle.timing

            processors.append({
                [weak engine, weak osc, weak pattern, weak timing] data in
                guard let osc, let pattern, let timing else { return }
                let oscSignals = osc.processBytes(data)
                let patternSignals = pattern.processBytes(data)
                _ = timing.processBytes(data)
                engine?.processBackgroundSignals(
                    osc: oscSignals,
                    pattern: patternSignals,
                    surfaceID: surfaceID
                )
            })
        }

        let dispatcher = SurfaceOutputBackgroundDispatcher(
            label: "dev.cocxy.terminal.output-processing.\(surfaceID.rawValue.uuidString)",
            processors: processors
        )
        surfaceOutputDispatchers[surfaceID] = dispatcher
        return dispatcher
    }

    func clearSurfaceTracking(for surfaceID: SurfaceID) {
        if let surfaceView = surfaceView(for: surfaceID) {
            let key = ObjectIdentifier(surfaceView)
            inlineImageRenderers[key]?.clearAllImages()
            inlineImageRenderers.removeValue(forKey: key)
        }
        surfaceImageDetectors.removeValue(forKey: surfaceID)
        surfaceOutputDispatchers.removeValue(forKey: surfaceID)
        surfaceWorkingDirectories.removeValue(forKey: surfaceID)
    }

    // MARK: - Surface Destruction

    /// Destroys the terminal surface and cleans up resources.
    func destroyTerminalSurface() {
        guard let tabID = visibleTabID,
              let surfaceID = tabSurfaceMap[tabID] ?? tabViewModels[tabID]?.surfaceID else { return }
        stopSessionReplayIfActive(surfaceID: surfaceID)
        clearSurfaceTracking(for: surfaceID)
        // Cancel any pending `.launched` watchdog and in-flight
        // foreground-process probe first so their `DispatchWorkItem`s
        // cannot fire against a surface that is about to be destroyed.
        // Drop the input-drop tracker entry in the same block so a
        // recycled surface ID never inherits stale drop state.
        cancelLaunchedWatchdog(surfaceID: surfaceID)
        cancelForegroundProbe(surfaceID: surfaceID)
        cancelInputDropTracking(surfaceID: surfaceID)
        // Release any per-surface state the detection engine accumulated
        // (debounce bucket + hook-session record) before the underlying
        // terminal is torn down. Calling after destroySurface would leave
        // a brief window where late-arriving signals could re-seed the
        // bucket on a surface that no longer exists.
        injectedAgentDetectionEngine?.clearSurface(surfaceID)
        // Drop the surface's shadow entry from the per-surface store so
        // stale agent state does not leak across future surfaces that
        // could reuse the slot (unlikely with UUID-based SurfaceIDs, but
        // defensive in case session restore replays the same ID).
        injectedPerSurfaceStore?.reset(surfaceID: surfaceID)
        terminalEngine(for: surfaceID).destroySurface(surfaceID)
        clearTerminalEngineTracking(surfaceID: surfaceID)
        tabViewModels[tabID]?.markStopped()
    }

    /// Destroys all terminal surfaces across all tabs.
    /// Called during window close and app termination to ensure clean teardown.
    func destroyAllSurfaces() {
        activeSplitView?.removeFromSuperview()
        terminalSurfaceView?.removeFromSuperview()

        // Collect all unique surface IDs to destroy exactly once.
        var surfacesToDestroy = Set<SurfaceID>()

        // Gather active split surfaces (current tab).
        for (surfaceID, _) in splitSurfaceViews {
            surfacesToDestroy.insert(surfaceID)
            splitViewModels[surfaceID]?.markStopped()
        }
        splitSurfaceViews.removeAll()
        splitViewModels.removeAll()
        activeSplitView = nil

        // Gather saved per-tab split surfaces (background tabs).
        for (_, tabSplitSurfaces) in savedTabSplitSurfaceViews {
            for (surfaceID, _) in tabSplitSurfaces {
                surfacesToDestroy.insert(surfaceID)
            }
        }
        for (_, tabSplitVMs) in savedTabSplitViewModels {
            for (_, vm) in tabSplitVMs {
                vm.markStopped()
            }
        }
        savedTabSplitViews.removeAll()
        savedTabSplitSurfaceViews.removeAll()
        savedTabSplitViewModels.removeAll()
        savedTabPanelContentViews.removeAll()

        // Gather all tab surfaces (includes the primary surface since
        // createTerminalSurface registers it in tabSurfaceMap).
        for (tabID, surfaceID) in tabSurfaceMap {
            surfacesToDestroy.insert(surfaceID)
            tabViewModels[tabID]?.markStopped()
        }

        // Include the primary surface even if it was never added to tabSurfaceMap
        // (defensive guard against initialization edge cases).
        if let primaryID = terminalViewModel.surfaceID {
            surfacesToDestroy.insert(primaryID)
        }

        // Cancel every pending `.launched` watchdog in one pass so no
        // fire-and-forget `DispatchWorkItem` outlives the window. Done
        // outside the per-surface loop because the watchdog exposes a
        // single-call API for a full sweep. Same applies to the
        // foreground-process probe: a completion delivered after window
        // teardown would touch a dead controller. The input-drop
        // monitor also flushes here so no per-surface tracker leaks
        // into the next window.
        agentLaunchedWatchdog.cancelAll()
        foregroundProcessProbe.cancelAll()
        surfaceInputDropMonitor.clearAll()

        // Destroy each surface exactly once.
        for surfaceID in surfacesToDestroy {
            stopSessionReplayIfActive(surfaceID: surfaceID)
            clearSurfaceTracking(for: surfaceID)
            // Release any per-surface detection state before the
            // underlying terminal is torn down, so the engine does not
            // retain debounce buckets or hook-session records keyed to
            // surfaces that no longer exist. Drop the shadow store entry
            // in the same step so per-surface agent state is not carried
            // over a full window teardown.
            injectedAgentDetectionEngine?.clearSurface(surfaceID)
            injectedPerSurfaceStore?.reset(surfaceID: surfaceID)
            terminalEngine(for: surfaceID).destroySurface(surfaceID)
            clearTerminalEngineTracking(surfaceID: surfaceID)
        }

        tabSurfaceMap.removeAll()
        resetTerminalEngineRouting()
        tabSurfaceViews.removeAll()
        tabViewModels.removeAll()
        tabOutputBuffers.removeAll()
        tabCommandTrackers.removeAll()
        deferredRestoredTabs.removeAll()
        deferredRestoredTabLoader = nil
        surfaceImageDetectors.removeAll()
        surfaceOutputDispatchers.removeAll()
        panelContentViews.removeAll()

        // Clear all inline image overlays before releasing surface views.
        for (_, renderer) in inlineImageRenderers {
            renderer.clearAllImages()
        }
        inlineImageRenderers.removeAll()

        terminalViewModel.markStopped()
        terminalOutputBuffer = TerminalOutputBuffer()
    }

    // MARK: - Handler Wiring for Restored Tabs

    /// Wires OSC and output handlers for a restored tab's surface.
    ///
    /// Called by AppDelegate during session restoration. Restored tabs are
    /// created without handlers (only ViewModel + SurfaceView + surface ID).
    /// This method completes the wiring so the restored tab behaves
    /// identically to a tab created via Cmd+T.
    ///
    /// - Parameters:
    ///   - tabID: The tab to wire handlers for.
    ///   - surfaceID: The surface ID associated with the tab.
    func wireHandlersForRestoredTab(tabID: TabID, surfaceID: SurfaceID) {
        if let surfaceView = tabSurfaceViews[tabID] {
            wireSurfaceHandlers(
                for: surfaceID,
                tabID: tabID,
                in: surfaceView,
                initialWorkingDirectory: tabManager.tab(for: tabID)?.workingDirectory
            )
            startAutomaticSessionReplayIfNeeded(surfaceID: surfaceID, tabID: tabID)
        }
    }

    // MARK: - Notification Ring

    /// Updates the notification ring on every surface of the tab based on
    /// per-surface agent state.
    ///
    /// Pulses a ring around a surface whose agent is waiting for user
    /// input, as long as the user is not already looking at that exact
    /// surface. Background tabs, background splits of the active tab, and
    /// unfocused-but-visible splits all receive the ring so the waiting
    /// signal is never swallowed when multiple splits run different
    /// agents.
    ///
    /// Reads per-surface state from `injectedPerSurfaceStore`. The
    /// `agentState` parameter is kept for callers that pre-date the Fase 3
    /// migration: when the store is unavailable the method falls back to
    /// the legacy primary-only behavior driven by that parameter.
    ///
    /// - Parameters:
    ///   - tabID: Owning tab whose surfaces should be re-evaluated.
    ///   - agentState: Last agent state reported for the tab. Used only
    ///     on the legacy fallback path.
    func updateNotificationRing(for tabID: TabID, agentState: AgentState) {
        let isTabVisible = tabID == (visibleTabID ?? tabManager.activeTabID)

        guard let store = injectedPerSurfaceStore else {
            // Legacy fallback: no per-surface store injected yet.
            // The primary surface inherits the tab-level agent state;
            // splits are untouched because we have no per-surface signal
            // to drive them safely.
            guard let primaryView = tabSurfaceViews[tabID] else { return }
            let decision = NotificationRingDecision.decide(
                agentState: agentState,
                isTabVisible: isTabVisible,
                isSurfaceFocused: false
            )
            applyNotificationRingDecision(decision, to: primaryView)
            return
        }

        // Per-surface path: fan out to every surface of the tab so splits
        // running independent agents get their own ring.
        let focusedSurfaceID = isTabVisible
            ? focusedSplitSurfaceView?.terminalViewModel?.surfaceID
            : nil

        for surfaceID in surfaceIDs(for: tabID) {
            guard let view = surfaceView(for: surfaceID) else { continue }

            let state = store.state(for: surfaceID)
            let decision = NotificationRingDecision.decide(
                agentState: state.agentState,
                isTabVisible: isTabVisible,
                isSurfaceFocused: surfaceID == focusedSurfaceID
            )
            applyNotificationRingDecision(decision, to: view)
        }
    }

    private func applyNotificationRingDecision(
        _ decision: NotificationRingDecision,
        to view: TerminalHostView
    ) {
        switch decision {
        case .show:
            view.showNotificationRing(color: CocxyColors.blue)
        case .hide:
            view.hideNotificationRing()
        }
    }

    // MARK: - OSC Notification Handling

    /// Processes an OSC notification from a terminal surface.
    ///
    /// - Parameters:
    ///   - notification: The parsed OSC notification.
    ///   - sourceTabID: The tab that owns the surface. When provided, the update
    ///     targets this specific tab instead of falling back to the active tab.
    ///     This ensures background tabs receive correct title/directory updates.
    func handleOSCNotification(
        _ notification: OSCNotification,
        fromTabID sourceTabID: TabID? = nil,
        surfaceID sourceSurfaceID: SurfaceID? = nil
    ) {
        // Use the source tab when known, fall back to active tab.
        let targetTabID = sourceTabID ?? visibleTabID ?? tabManager.activeTabID

        switch notification {
        case .titleChange(let title):
            // Update the window title only when the source is the active tab
            // (or unknown, for backward compatibility).
            if let tabID = targetTabID {
                viewModelForTab(tabID)?.updateTitle(title)
            }

            if sourceTabID == nil || sourceTabID == visibleTabID {
                window?.title = title
            }

            if let tabID = targetTabID {
                let previousSSH = tabManager.tab(for: tabID)?.sshSession
                tabManager.updateTab(id: tabID) { tab in
                    tab.title = title
                    tab.lastActivityAt = Date()

                    // Detect SSH sessions from terminal title changes.
                    if title.lowercased().hasPrefix("ssh ") {
                        tab.sshSession = SSHSessionDetector.detect(from: title)
                        tab.processName = "ssh"
                    } else if SSHSessionDetector.isSSHProcess(tab.processName ?? "") &&
                              !title.lowercased().contains("ssh") {
                        tab.sshSession = nil
                        tab.processName = nil
                    }
                }

                // Wire/unwire SSH file drop handler based on session state.
                let currentSSH = tabManager.tab(for: tabID)?.sshSession
                if let surfaceView = tabSurfaceViews[tabID] {
                    if let session = currentSSH, previousSSH == nil {
                        surfaceView.onFileDrop = makeSSHFileDropHandler(session: session, tabID: tabID)
                    } else if currentSSH == nil, previousSSH != nil {
                        surfaceView.onFileDrop = nil
                    }
                }

                tabBarViewModel?.syncWithManager()
                refreshTabStrip()

                let registryTitle = tabManager.tab(for: tabID)?.displayTitle ?? title
                sessionRegistry?.updateTitle(sessionIDForTab(tabID), title: registryTitle)
            }

            // Feed the title to the agent detection engine.
            feedDetectionEngine(
                oscCode: 0,
                payload: title,
                fromTabID: targetTabID,
                surfaceID: sourceSurfaceID
            )

        case .notification(title: let title, body: let body):
            guard let tabID = targetTabID else { break }
            let cocxyNotification = CocxyNotification(
                type: .custom("osc-notification"),
                tabId: tabID,
                title: title,
                body: body
            )
            injectedNotificationManager?.notify(cocxyNotification)

            feedDetectionEngine(
                oscCode: 9,
                payload: body,
                fromTabID: targetTabID,
                surfaceID: sourceSurfaceID
            )

        case .shellPrompt:
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                tab.lastActivityAt = Date()
            }
            // A shell prompt on a concrete surface means that surface is
            // back at the shell. Clear any stale agent state immediately
            // instead of waiting for the async foreground-process probe:
            // the probe is still useful as a fallback for unusual
            // prompt-like events, but OSC 133;A is already the strong
            // signal we need. This prevents Aurora/status/dashboard from
            // keeping a dead Codex/Claude entry lit after the shell
            // visibly returned to `$`.
            if let sid = sourceSurfaceID {
                let didReset = resetAgentStateOnShellPromptIfNeeded(
                    surfaceID: sid,
                    tabID: tabID
                )
                if !didReset {
                    recoverAgentStateOnShellPromptIfNeeded(
                        surfaceID: sid,
                        tabID: tabID
                    )
                }
            }
            tabBarViewModel?.syncWithManager()
            refreshStatusBar()
            updateAgentProgressOverlay()
            auroraChromeController?.refreshSources()

            // Notify the IDE cursor controller of the real prompt row/col
            // from the backing CocxyCore terminal. Only the active tab's
            // surface is notified because pattern detection on background
            // tabs would otherwise race with the user's focused surface.
            //
            // The previous implementation used `viewHeight / cellHeight - 1`
            // (i.e. the last visible row) as the prompt row, which is
            // always wrong and produced the v0.1.52 "stray blinking line
            // near the status bar" bug. The real cursor row is the only
            // reliable source.
            if (sourceTabID == nil || sourceTabID == visibleTabID),
               let surfaceView = sourceSurfaceID.flatMap(surfaceView(for:))
                    ?? activeTerminalSurfaceView {
                if let cocxyView = surfaceView as? CocxyCoreView {
                    cocxyView.handleShellPromptAtCurrentCursor()
                }
            }

            feedDetectionEngine(
                oscCode: 133,
                payload: "A",
                fromTabID: targetTabID,
                surfaceID: sourceSurfaceID
            )

        case .currentDirectory(let directoryURL):
            guard let tabID = targetTabID else { break }
            let previousDirectory = tabManager.tab(for: tabID)?.workingDirectory.standardizedFileURL
            let standardizedDirectory = directoryURL.standardizedFileURL
            if let sourceSurfaceID {
                surfaceWorkingDirectories[sourceSurfaceID] = directoryURL
            }
            let gitProvider = GitInfoProviderImpl()
            let branch = gitProvider.currentBranch(at: directoryURL)
            tabManager.updateTab(id: tabID) { tab in
                tab.workingDirectory = directoryURL
                tab.gitBranch = branch
                tab.lastActivityAt = Date()
            }
            tabBarViewModel?.syncWithManager()
            refreshStatusBar()
            refreshTabStrip()
            sessionRegistry?.updateWorkingDirectory(
                sessionIDForTab(tabID),
                directory: directoryURL
            )
            if previousDirectory != standardizedDirectory {
                var metadata = ["source": "osc7"]
                if let sourceSurfaceID {
                    metadata["surface_id"] = sourceSurfaceID.rawValue.uuidString
                }
                recordLocalActivity(
                    kind: .projectSwitched,
                    summary: projectSwitchActivitySummary(standardizedDirectory),
                    workingDirectory: directoryURL,
                    sessionID: sessionIDForTab(tabID).rawValue.uuidString,
                    metadata: metadata
                )
            }

            // Reload project config for the new working directory.
            //
            // When the tab belongs to a cocxy-managed worktree and the
            // user has `inherit-project-config = true` (default), allow
            // the service to fall back to the origin repo's
            // `.cocxy.toml` if the walk from the current CWD yields
            // nothing. Tabs without a worktree hit the legacy single
            // walk because `worktreeOriginRepo` is nil.
            let projectService = ProjectConfigService()
            let tabSnapshot = tabManager.tab(for: tabID)
            let inheritProjectConfig = configService?.current.worktree.inheritProjectConfig ?? true
            let originRepo = inheritProjectConfig ? tabSnapshot?.worktreeOriginRepo : nil
            let newProjectConfig = projectService.loadConfig(
                for: directoryURL,
                originRepo: originRepo
            )
            tabManager.updateTab(id: tabID) { tab in
                tab.projectConfig = newProjectConfig
            }
            applyProjectConfig(for: tabID)

            feedDetectionEngine(
                oscCode: 7,
                payload: directoryURL.standardizedFileURL.absoluteString,
                fromTabID: targetTabID,
                surfaceID: sourceSurfaceID
            )

        case .commandStarted:
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                tab.markCommandStarted()
                tab.lastActivityAt = Date()
            }
            refreshStatusBar()

        case .commandFinished(let exitCode):
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                if let startTime = tab.lastCommandStartedAt {
                    tab.markCommandFinished(
                        duration: Date().timeIntervalSince(startTime),
                        exitCode: exitCode
                    )
                }
                tab.lastCommandStartedAt = nil
                tab.lastActivityAt = Date()
            }
            persistLatestCommandBlockIfAvailable(tabID: tabID, surfaceID: sourceSurfaceID)
            refreshStatusBar()

        case .inlineImage(let payload):
            guard let imageData = OSC1337Parser.parse(payload),
                  let surfaceView = sourceSurfaceID.flatMap(surfaceView(for:))
                    ?? activeTerminalSurfaceView else { break }
            let renderer = inlineImageRenderer(for: surfaceView)
            let position = surfaceView.bounds.height - 20
            renderer.renderImage(imageData, at: position)

        case .processExited:
            // Shell process exited. Run the same teardown we'd run on
            // surface destroy, but in-place because the surface object
            // can outlive its backing shell (e.g. user keeps the pane
            // around to read the final output):
            //
            //   1. `notifyProcessExited` emits an `agentExited`
            //      transition so any subscribers see the final idle
            //      state.
            //   2. `clearSurface` drops the engine's debounce and
            //      hook-session buckets — `notifyProcessExited` alone
            //      does *not* do this, so skipping it would leave
            //      stale per-surface routing state behind.
            //   3. The per-surface store entry is reset so the sidebar
            //      pill and other indicators relax.
            //   4. The tab's last-activity timestamp moves forward.
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                tab.lastActivityAt = Date()
            }
            injectedAgentDetectionEngine?.notifyProcessExited(
                surfaceID: sourceSurfaceID
            )
            if let sid = sourceSurfaceID {
                injectedAgentDetectionEngine?.clearSurface(sid)
                injectedPerSurfaceStore?.reset(surfaceID: sid)
                // Defensive: if a launched-watchdog or a foreground
                // probe was armed for this surface (rare — the shell
                // process normally exits after the agent, not while
                // `.launched` or a probe is in flight), cancel them so
                // the callbacks do not double-fire a reset on an
                // already-cleared store entry. The drop tracker is
                // cleared alongside so a process re-exec on the same
                // surface ID starts with a clean counter.
                cancelLaunchedWatchdog(surfaceID: sid)
                cancelForegroundProbe(surfaceID: sid)
                cancelInputDropTracking(surfaceID: sid)
            }
            tabBarViewModel?.syncWithManager()
            refreshStatusBar()
            updateAgentProgressOverlay()
            updateNotificationRing(for: tabID, agentState: .idle)
            auroraChromeController?.refreshSources()
        }
    }

    func attachRestoredCommandBlocksIfAvailable(
        tabID: TabID,
        surfaceID: SurfaceID,
        in surfaceView: TerminalHostView
    ) {
        let sessionID = sessionIDForTab(tabID).rawValue.uuidString
        let restored = (try? TerminalBlockStore().load(sessionID: sessionID)) ?? []
        let blocks = TerminalBlockRestoration.blocksForDisplay(
            live: [],
            restored: restored,
            limit: 32
        )
        guard !blocks.isEmpty else { return }

        restoredCommandBlocksBySurfaceID[surfaceID] = blocks
        (surfaceView as? CocxyCoreView)?.refreshCommandBlockOverlay()
    }

    func availableCommandBlocks(
        surfaceID: SurfaceID,
        liveBlocks: [TerminalCommandBlock],
        limit: UInt32
    ) -> [TerminalCommandBlock] {
        TerminalBlockRestoration.blocksForDisplay(
            live: liveBlocks,
            restored: restoredCommandBlocksBySurfaceID[surfaceID] ?? [],
            limit: Int(limit)
        )
    }

    func availableCommandBlock(
        surfaceID: SurfaceID,
        liveBlock: TerminalCommandBlock?,
        blockID: UInt64
    ) -> TerminalCommandBlock? {
        TerminalBlockRestoration.block(
            id: blockID,
            live: liveBlock,
            restored: restoredCommandBlocksBySurfaceID[surfaceID] ?? []
        )
    }

    private func persistLatestCommandBlockIfAvailable(tabID: TabID, surfaceID sourceSurfaceID: SurfaceID?) {
        let fallbackSurfaceID = activeTerminalSurfaceView?.terminalViewModel?.surfaceID
        guard let surfaceID = sourceSurfaceID ?? fallbackSurfaceID,
              let cocxyBridge = terminalEngine(for: surfaceID).cocxyCoreBridge else {
            return
        }

        let liveBlocks = cocxyBridge.commandBlocks(for: surfaceID, limit: 32)
        guard let block = liveBlocks.last else { return }

        preserveCommandBlockMetadata(for: surfaceID, liveBlocks: liveBlocks)
        (surfaceView(for: surfaceID) as? CocxyCoreView)?.refreshCommandBlockOverlay()
        updateCommandCorrectionSuggestion(for: block, tabID: tabID, surfaceID: surfaceID)

        let key = "\(surfaceID.rawValue.uuidString)#\(block.id)"
        guard persistedCommandBlockKeys.insert(key).inserted else { return }

        let sessionID = sessionIDForTab(tabID).rawValue.uuidString
        recordCommandBlockActivity(block, tabID: tabID, surfaceID: surfaceID)
        let spotlightConfig = configService?.current.spotlight ?? .defaults
        Task.detached(priority: .utility) {
            try? TerminalBlockStore().append(block, sessionID: sessionID)
            if spotlightConfig.enabled {
                _ = try? await SpotlightIncrementalIndexer.indexCommandBlock(
                    block,
                    sessionID: sessionID,
                    config: spotlightConfig
                )
            }
        }
    }

    private func updateCommandCorrectionSuggestion(
        for block: TerminalCommandBlock,
        tabID: TabID,
        surfaceID: SurfaceID
    ) {
        guard let coreView = surfaceView(for: surfaceID) as? CocxyCoreView else { return }

        let correctionConfig = configService?.current.commandCorrections ?? .defaults
        guard correctionConfig.enabled,
              correctionConfig.autoShowOnFailure,
              block.exitCode != nil,
              block.exitCode != 0,
              !block.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            coreView.dismissCommandCorrection()
            return
        }

        let workingDirectory = block.pwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? workingDirectory(for: surfaceID)
            ?? tabManager.tab(for: tabID)?.workingDirectory
        let engine = CommandCorrectionEngine.localDefault(
            editDistanceThreshold: correctionConfig.editDistanceThreshold,
            foundationModelsEnabled: correctionConfig.foundationModelsEnabled,
            agentFallback: correctionConfig.agentFallback,
            maxSuggestions: correctionConfig.maxSuggestionsShown
        )
        let execution = CommandExecutionSnapshot(
            command: block.command,
            exitCode: block.exitCode,
            stdout: block.output,
            stderr: block.output,
            workingDirectory: workingDirectory
        )

        if let correction = CommandCorrectionListener(engine: engine).suggestion(
            for: execution,
            enabled: true
        ) {
            coreView.presentCommandCorrection(
                correction,
                showConfidenceBadge: correctionConfig.showConfidenceBadge
            )
        } else {
            coreView.dismissCommandCorrection()
        }
    }

    private func preserveCommandBlockMetadata(
        for surfaceID: SurfaceID,
        liveBlocks: [TerminalCommandBlock]
    ) {
        guard let restored = restoredCommandBlocksBySurfaceID[surfaceID],
              !restored.isEmpty else { return }

        let liveIDs = Set(liveBlocks.map(\.id))
        let metadata = TerminalBlockRestoration.blocksForDisplay(
            live: [],
            restored: restored.filter { liveIDs.contains($0.id) },
            limit: 256
        )

        if metadata.isEmpty {
            restoredCommandBlocksBySurfaceID.removeValue(forKey: surfaceID)
        } else {
            restoredCommandBlocksBySurfaceID[surfaceID] = metadata
        }
    }

    private func configureCommandBlockOverlayIntegration(
        for tabID: TabID,
        surfaceID: SurfaceID,
        in coreView: CocxyCoreView
    ) {
        coreView.restoredCommandBlocksProvider = { [weak self] in
            self?.restoredCommandBlocksBySurfaceID[surfaceID] ?? []
        }
        coreView.onToggleCommandBlockBookmark = { [weak self] block in
            self?.toggleCommandBlockBookmark(block, tabID: tabID, surfaceID: surfaceID)
        }
    }

    private func toggleCommandBlockBookmark(
        _ block: TerminalCommandBlock,
        tabID: TabID,
        surfaceID: SurfaceID
    ) {
        let updated = block.withBookmark(!block.isBookmarked)
        var restored = restoredCommandBlocksBySurfaceID[surfaceID] ?? []
        restored.append(updated)
        restoredCommandBlocksBySurfaceID[surfaceID] = TerminalBlockRestoration.blocksForDisplay(
            live: [],
            restored: restored,
            limit: 256
        )

        (surfaceView(for: surfaceID) as? CocxyCoreView)?.refreshCommandBlockOverlay()

        let sessionID = sessionIDForTab(tabID).rawValue.uuidString
        let spotlightConfig = configService?.current.spotlight ?? .defaults
        Task.detached(priority: .utility) {
            try? TerminalBlockStore().append(updated, sessionID: sessionID)
            if spotlightConfig.enabled {
                _ = try? await SpotlightIncrementalIndexer.indexCommandBlock(
                    updated,
                    sessionID: sessionID,
                    config: spotlightConfig
                )
            }
        }
    }

    // MARK: - Detection Engine Feeding

    /// Synthesizes an OSC escape sequence and feeds it to the agent detection engine.
    ///
    /// The terminal host view surfaces parsed events to Swift callbacks, while
    /// the detection engine expects raw OSC bytes. This method bridges the gap
    /// by reconstructing the OSC sequence from the already-parsed action data.
    ///
    /// - Parameters:
    ///   - oscCode: The OSC code (0 = title, 7 = pwd, 9 = notification, 133 = prompt).
    ///   - payload: The OSC payload string.
    private func feedDetectionEngine(
        oscCode: Int,
        payload: String,
        fromTabID sourceTabID: TabID?,
        surfaceID sourceSurfaceID: SurfaceID?
    ) {
        guard let engine = injectedAgentDetectionEngine else { return }
        guard shouldRouteOutputToDetection(
            fromTabID: sourceTabID,
            surfaceID: sourceSurfaceID
        ) else { return }
        let oscSequence = "\u{1b}]\(oscCode);\(payload)\u{07}"
        if let data = oscSequence.data(using: .utf8) {
            engine.processTerminalOutput(data, surfaceID: sourceSurfaceID)
        }
    }

    /// Pattern/OSC-based detection can safely observe every identified
    /// terminal surface now that the engine owns detector/state buckets
    /// per `SurfaceID`. Keeping the old "focused pane only" filter meant
    /// a split running Claude would stop feeding detection as soon as the
    /// user focused a sibling Codex pane, so Aurora/status/dashboard could
    /// only ever show one live agent. Legacy calls that lack a surface ID
    /// still fall back to the visible-tab guard because there is no safe
    /// routing key to isolate them.
    private func shouldRouteOutputToDetection(
        fromTabID sourceTabID: TabID?,
        surfaceID sourceSurfaceID: SurfaceID?
    ) -> Bool {
        if sourceSurfaceID != nil {
            return true
        }

        guard let visibleTabID else { return false }
        let resolvedTabID = sourceTabID ?? visibleTabID
        guard resolvedTabID == visibleTabID else { return false }
        return true
    }

    // MARK: - Inline Image Renderer

    /// Returns or creates the inline image renderer for a surface view.
    ///
    /// Renderers are lazily created and cached per surface view instance.
    /// When a surface view is deallocated, the weak reference in the
    /// renderer's initializer ensures cleanup.
    private func inlineImageRenderer(for surfaceView: NSView) -> InlineImageRenderer {
        if let existing = inlineImageRenderers[ObjectIdentifier(surfaceView)] {
            return existing
        }
        let renderer = InlineImageRenderer(terminalView: surfaceView)
        inlineImageRenderers[ObjectIdentifier(surfaceView)] = renderer
        return renderer
    }

    // MARK: - SSH File Drop Handler

    /// Creates an `onFileDrop` closure that uploads files to the SSH host via `scp`.
    ///
    /// When an SSH session is detected, this handler replaces the default
    /// "paste file paths" behavior. Files are uploaded to the remote user's
    /// home directory in a background process.
    ///
    /// - Parameters:
    ///   - session: The detected SSH session info (user, host, port).
    ///   - tabID: The tab where the SSH session is running.
    /// - Returns: A closure that handles file drops and returns `true` on success.
    func makeSSHFileDropHandler(session: SSHSessionInfo, tabID: TabID) -> ([URL]) -> Bool {
        let notificationManager = injectedNotificationManager
        let host = session.host
        let user = session.user
        let port = session.port
        let capturedTabID = tabID
        let localizer = appLocalizer()
        let uploadCompleteTitle = Self.localizedSSHUploadCompleteTitle(localizer: localizer)
        let uploadFailedTitle = Self.localizedSSHUploadFailedTitle(localizer: localizer)
        let unknownUploadError = Self.localizedSSHUploadUnknownError(localizer: localizer)

        return { urls in
            let localPaths = urls.map(\.path)
            guard !localPaths.isEmpty else { return false }

            Task.detached(priority: .userInitiated) {
                let destination: String
                if let user {
                    destination = "\(user)@\(host):~/"
                } else {
                    destination = "\(host):~/"
                }

                var args = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]
                if let port {
                    args += ["-P", String(port)]
                }
                args += localPaths
                args.append(destination)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
                process.arguments = args
                let stderrPipe = Pipe()
                process.standardError = stderrPipe
                process.standardOutput = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let fileNames = urls.map(\.lastPathComponent).joined(separator: ", ")
                    let succeeded = process.terminationStatus == 0

                    await MainActor.run {
                        if succeeded {
                            let notification = CocxyNotification(
                                type: .custom("ssh-upload"),
                                tabId: capturedTabID,
                                title: uploadCompleteTitle,
                                body: "\(fileNames) → \(host)"
                            )
                            notificationManager?.notify(notification)
                        } else {
                            let stderr = String(
                                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8
                            ) ?? unknownUploadError
                            let notification = CocxyNotification(
                                type: .custom("ssh-upload-error"),
                                tabId: capturedTabID,
                                title: uploadFailedTitle,
                                body: String(stderr.prefix(200))
                            )
                            notificationManager?.notify(notification)
                        }
                    }
                } catch {
                    await MainActor.run {
                        let notification = CocxyNotification(
                            type: .custom("ssh-upload-error"),
                            tabId: capturedTabID,
                            title: uploadFailedTitle,
                            body: error.localizedDescription
                        )
                        notificationManager?.notify(notification)
                    }
                }
            }

            return true
        }
    }
}
