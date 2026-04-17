// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+SurfaceLifecycle.swift - Terminal surface creation, destruction, and wiring.

import AppKit

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

        do {
            let surfaceID = try bridge.createSurface(
                in: surfaceView,
                workingDirectory: nil,
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

                registerSurfaceWithProcessMonitor(surfaceID, tabID: firstTabID)
                wireSurfaceHandlers(
                    for: surfaceID,
                    tabID: firstTabID,
                    in: surfaceView,
                    initialWorkingDirectory: tabManager.tab(for: firstTabID)?.workingDirectory
                )
            }
        } catch {
            NSLog("[MainWindowController] Failed to create terminal surface: %@",
                  String(describing: error))
        }
    }

    func registerSurfaceWithProcessMonitor(_ surfaceID: SurfaceID, tabID: TabID) {
        guard let registration = bridge.processMonitorRegistration(for: surfaceID) else {
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

        bridge.setOSCHandler(for: surfaceID) { [weak self] notification in
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

        bridge.setOutputHandler(
            for: surfaceID
        ) { [weak self, weak buffer, weak engine, weak commandTracker, weak imageDetector] data in
            commandTracker?.processBytes(data)
            imageDetector?.processBytes(data)
            Task { @MainActor in
                if self?.shouldRouteOutputToDetection(
                    fromTabID: capturedTabID,
                    surfaceID: capturedSurfaceID
                ) == true {
                    // Thread the surface ID into the detection engine so
                    // the emitted StateContext carries the split that
                    // produced the output. Subscribers can then target
                    // per-surface state without falling back to the
                    // focused tab (regresar a ese fallback contaminaría
                    // los splits hermanos del mismo tab).
                    engine?.processTerminalOutput(
                        data,
                        surfaceID: capturedSurfaceID
                    )
                }
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

    func clearSurfaceTracking(for surfaceID: SurfaceID) {
        if let surfaceView = surfaceView(for: surfaceID) {
            let key = ObjectIdentifier(surfaceView)
            inlineImageRenderers[key]?.clearAllImages()
            inlineImageRenderers.removeValue(forKey: key)
        }
        surfaceImageDetectors.removeValue(forKey: surfaceID)
        surfaceWorkingDirectories.removeValue(forKey: surfaceID)
    }

    // MARK: - Surface Destruction

    /// Destroys the terminal surface and cleans up resources.
    func destroyTerminalSurface() {
        guard let tabID = visibleTabID,
              let surfaceID = tabSurfaceMap[tabID] ?? tabViewModels[tabID]?.surfaceID else { return }
        clearSurfaceTracking(for: surfaceID)
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
        bridge.destroySurface(surfaceID)
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

        // Destroy each surface exactly once.
        for surfaceID in surfacesToDestroy {
            clearSurfaceTracking(for: surfaceID)
            // Release any per-surface detection state before the
            // underlying terminal is torn down, so the engine does not
            // retain debounce buckets or hook-session records keyed to
            // surfaces that no longer exist. Drop the shadow store entry
            // in the same step so per-surface agent state is not carried
            // over a full window teardown.
            injectedAgentDetectionEngine?.clearSurface(surfaceID)
            injectedPerSurfaceStore?.reset(surfaceID: surfaceID)
            bridge.destroySurface(surfaceID)
        }

        tabSurfaceMap.removeAll()
        tabSurfaceViews.removeAll()
        tabViewModels.removeAll()
        tabOutputBuffers.removeAll()
        tabCommandTrackers.removeAll()
        surfaceImageDetectors.removeAll()
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
            // When a shell prompt appears on a surface that was running
            // an agent, flip the per-surface store entry from `.working`
            // to `.finished` so the indicator relaxes. Other transitions
            // stay driven by the detection engine.
            if let sid = sourceSurfaceID,
               let store = injectedPerSurfaceStore {
                let current = store.state(for: sid)
                if current.agentState == .working {
                    store.update(surfaceID: sid) { state in
                        state.agentState = .finished
                    }
                }
            }
            tabBarViewModel?.syncWithManager()
            refreshStatusBar()

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

            // Reload project config for the new working directory.
            let projectService = ProjectConfigService()
            let newProjectConfig = projectService.loadConfig(for: directoryURL)
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
            }
            tabBarViewModel?.syncWithManager()
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

    /// Pattern/OSC-based detection must only observe the surface the user is
    /// actually looking at. Hook integration remains responsible for
    /// background-session updates across windows.
    private func shouldRouteOutputToDetection(
        fromTabID sourceTabID: TabID?,
        surfaceID sourceSurfaceID: SurfaceID?
    ) -> Bool {
        guard let visibleTabID else { return false }
        let resolvedTabID = sourceTabID ?? visibleTabID
        guard resolvedTabID == visibleTabID else { return false }

        let focusedSurfaceID = activeTerminalSurfaceView?.terminalViewModel?.surfaceID

        guard let focusedSurfaceID else { return true }
        guard let sourceSurfaceID else { return true }
        return focusedSurfaceID == sourceSurfaceID
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
                                title: "Upload Complete",
                                body: "\(fileNames) → \(host)"
                            )
                            notificationManager?.notify(notification)
                        } else {
                            let stderr = String(
                                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8
                            ) ?? "Unknown error"
                            let notification = CocxyNotification(
                                type: .custom("ssh-upload-error"),
                                tabId: capturedTabID,
                                title: "Upload Failed",
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
                            title: "Upload Failed",
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
