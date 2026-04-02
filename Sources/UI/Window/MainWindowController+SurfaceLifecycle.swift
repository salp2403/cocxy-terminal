// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+SurfaceLifecycle.swift - Terminal surface creation, destruction, and wiring.

import AppKit

// MARK: - Surface Lifecycle

/// Extension that manages the lifecycle of ghostty terminal surfaces:
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
            // Snapshot child PIDs before surface creation to identify
            // the new shell process spawned by ghostty.
            let childrenBefore = snapshotChildPIDs()

            let surfaceID = try bridge.createSurface(
                in: surfaceView,
                workingDirectory: nil,
                command: nil
            )
            terminalViewModel.markRunning(surfaceID: surfaceID)
            surfaceView.syncSizeWithGhostty()

            // Register the first tab's surface in all tracking dictionaries.
            // This ensures destroyAllSurfaces can find it without special-casing.
            if let firstTabID = tabManager.tabs.first?.id {
                tabSurfaceMap[firstTabID] = surfaceID
                tabSurfaceViews[firstTabID] = surfaceView
                tabViewModels[firstTabID] = terminalViewModel
                displayedTabID = firstTabID

                // Register tab with process monitor for SSH detection.
                let childrenAfter = snapshotChildPIDs()
                if let shellPID = findNewShellPID(current: childrenAfter, previous: childrenBefore) {
                    processMonitor?.registerTab(firstTabID, shellPID: shellPID)
                }
            }

            // Wire OSC handler for title/directory/prompt changes.
            // Captures the tab ID so updates target the correct tab,
            // not just the active tab (critical for multi-tab).
            if let firstTabID = tabManager.tabs.first?.id {
                let capturedTabID = firstTabID
                bridge.setOSCHandler(for: surfaceID) { [weak self] notification in
                    Task { @MainActor in
                        self?.handleOSCNotification(notification, fromTabID: capturedTabID)
                    }
                }
            }

            // Wire output handler for scrollback search and agent detection.
            if let firstTabID = tabManager.tabs.first?.id {
                let buffer = TerminalOutputBuffer()
                tabOutputBuffers[firstTabID] = buffer
                terminalOutputBuffer = buffer
                let engine = injectedAgentDetectionEngine

                // Track command durations via OSC 133 ;B (start) and ;D (finish).
                let trackerTabID = firstTabID
                let commandTracker = CommandDurationTracker { [weak self] notification in
                    Task { @MainActor in
                        self?.handleOSCNotification(notification, fromTabID: trackerTabID)
                    }
                }
                tabCommandTrackers[firstTabID] = commandTracker

                let imageDetector = InlineImageOSCDetector { [weak self] payload in
                    Task { @MainActor in
                        self?.handleOSCNotification(.inlineImage(payload), fromTabID: trackerTabID)
                    }
                }
                tabImageDetectors[firstTabID] = imageDetector

                bridge.setOutputHandler(for: surfaceID) { [weak buffer, weak engine, weak commandTracker, weak imageDetector] data in
                    engine?.processTerminalOutput(data)
                    commandTracker?.processBytes(data)
                    imageDetector?.processBytes(data)
                    Task { @MainActor in
                        buffer?.append(data)
                    }
                }

                // Wire Smart Copy output provider for right-click context menu.
                surfaceView.outputBufferProvider = { [weak buffer] in
                    buffer?.lines ?? []
                }

                // Wire user input callback for agent detection.
                // Triggers waitingInput → working when the user presses Enter.
                surfaceView.onUserInputSubmitted = { [weak engine] in
                    engine?.notifyUserInput()
                }

                // Wire CWD provider for relative path resolution on Cmd+click.
                let tabID = firstTabID
                surfaceView.textSelectionManager.workingDirectoryProvider = { [weak self] in
                    self?.tabManager.tab(for: tabID)?.workingDirectory
                }
            }
        } catch {
            NSLog("[MainWindowController] Failed to create terminal surface: %@",
                  String(describing: error))
        }
    }

    // MARK: - Surface Destruction

    /// Destroys the terminal surface and cleans up resources.
    func destroyTerminalSurface() {
        guard let surfaceID = terminalViewModel.surfaceID else { return }
        bridge.destroySurface(surfaceID)
        terminalViewModel.markStopped()
    }

    /// Destroys all terminal surfaces across all tabs.
    /// Called during window close and app termination to ensure clean teardown.
    func destroyAllSurfaces() {
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
            bridge.destroySurface(surfaceID)
        }

        tabSurfaceMap.removeAll()
        tabSurfaceViews.removeAll()
        tabViewModels.removeAll()
        tabOutputBuffers.removeAll()
        tabCommandTrackers.removeAll()
        tabImageDetectors.removeAll()
        panelContentViews.removeAll()

        // Clear all inline image overlays before releasing surface views.
        for (_, renderer) in inlineImageRenderers {
            renderer.clearAllImages()
        }
        inlineImageRenderers.removeAll()

        terminalViewModel.markStopped()
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
    ///   - surfaceID: The ghostty surface ID associated with the tab.
    func wireHandlersForRestoredTab(tabID: TabID, surfaceID: SurfaceID) {
        let capturedTabID = tabID
        bridge.setOSCHandler(for: surfaceID) { [weak self] notification in
            Task { @MainActor in
                self?.handleOSCNotification(notification, fromTabID: capturedTabID)
            }
        }

        // Wire user input callback on the restored tab's surface view.
        let engine = injectedAgentDetectionEngine
        if let surfaceView = tabSurfaceViews[tabID] {
            surfaceView.onUserInputSubmitted = { [weak engine] in
                engine?.notifyUserInput()
            }
        }

        let buffer = TerminalOutputBuffer()
        tabOutputBuffers[tabID] = buffer

        let commandTracker = CommandDurationTracker { [weak self] notification in
            Task { @MainActor in
                self?.handleOSCNotification(notification, fromTabID: capturedTabID)
            }
        }
        tabCommandTrackers[tabID] = commandTracker

        let imageDetector = InlineImageOSCDetector { [weak self] payload in
            Task { @MainActor in
                self?.handleOSCNotification(.inlineImage(payload), fromTabID: capturedTabID)
            }
        }
        tabImageDetectors[tabID] = imageDetector

        bridge.setOutputHandler(for: surfaceID) { [weak buffer, weak engine, weak commandTracker, weak imageDetector] data in
            engine?.processTerminalOutput(data)
            commandTracker?.processBytes(data)
            imageDetector?.processBytes(data)
            Task { @MainActor in
                buffer?.append(data)
            }
        }
    }

    // MARK: - Notification Ring

    /// Updates the notification ring on a surface view based on agent state.
    ///
    /// Shows a pulsing ring when the agent is waiting for input (similar to cmux).
    /// Hides the ring when the user focuses the tab or the state changes.
    func updateNotificationRing(for tabID: TabID, agentState: AgentState) {
        guard let surfaceView = tabSurfaceViews[tabID] else { return }

        switch agentState {
        case .waitingInput:
            // Only show ring on background tabs (not the active one).
            if tabID != tabManager.activeTabID {
                surfaceView.showNotificationRing(color: CocxyColors.blue)
            }
        default:
            surfaceView.hideNotificationRing()
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
        fromTabID sourceTabID: TabID? = nil
    ) {
        // Use the source tab when known, fall back to active tab.
        let targetTabID = sourceTabID ?? tabManager.activeTabID

        switch notification {
        case .titleChange(let title):
            // Update the window title only when the source is the active tab
            // (or unknown, for backward compatibility).
            if sourceTabID == nil || sourceTabID == tabManager.activeTabID {
                terminalViewModel.updateTitle(title)
                window?.title = title
            }

            if let tabID = targetTabID {
                tabManager.updateTab(id: tabID) { tab in
                    tab.title = title

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
                tabBarViewModel?.syncWithManager()
                refreshTabStrip()
            }

            // Feed the title to the agent detection engine.
            feedDetectionEngine(oscCode: 0, payload: title)

        case .notification(title: let title, body: let body):
            guard let tabID = targetTabID else { break }
            let cocxyNotification = CocxyNotification(
                type: .custom("osc-notification"),
                tabId: tabID,
                title: title,
                body: body
            )
            injectedNotificationManager?.notify(cocxyNotification)

            feedDetectionEngine(oscCode: 9, payload: body)

        case .shellPrompt:
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                if tab.agentState == .working {
                    tab.agentState = .finished
                }
            }
            tabBarViewModel?.syncWithManager()

            // Notify IDE cursor controller only for the active tab.
            if (sourceTabID == nil || sourceTabID == tabManager.activeTabID),
               let surfaceView = terminalSurfaceView {
                let cursorCtrl = surfaceView.ideCursorController
                let viewHeight = surfaceView.bounds.height
                let cellHeight = cursorCtrl.cellHeight
                let promptRow = cellHeight > 0 ? max(0, Int(viewHeight / cellHeight) - 1) : 0
                cursorCtrl.shellPromptDetected(row: promptRow, column: 2)
            }

            feedDetectionEngine(oscCode: 133, payload: "A")

        case .currentDirectory(let directoryURL):
            guard let tabID = targetTabID else { break }
            let gitProvider = GitInfoProviderImpl()
            let branch = gitProvider.currentBranch(at: directoryURL)
            tabManager.updateTab(id: tabID) { tab in
                tab.workingDirectory = directoryURL
                tab.gitBranch = branch
            }
            tabBarViewModel?.syncWithManager()
            refreshStatusBar()
            refreshTabStrip()

            // Reload project config for the new working directory.
            let projectService = ProjectConfigService()
            let newProjectConfig = projectService.loadConfig(for: directoryURL)
            tabManager.updateTab(id: tabID) { tab in
                tab.projectConfig = newProjectConfig
            }
            applyProjectConfig(for: tabID)

            feedDetectionEngine(
                oscCode: 7,
                payload: "file://localhost\(directoryURL.path)"
            )

        case .commandStarted:
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                tab.lastCommandStartedAt = Date()
                tab.lastCommandDuration = nil
                tab.lastCommandExitCode = nil
            }
            refreshStatusBar()

        case .commandFinished(let exitCode):
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                if let startTime = tab.lastCommandStartedAt {
                    tab.lastCommandDuration = Date().timeIntervalSince(startTime)
                }
                tab.lastCommandExitCode = exitCode
                tab.lastCommandStartedAt = nil
            }
            refreshStatusBar()

        case .inlineImage(let payload):
            guard let surfaceView = terminalSurfaceView,
                  let imageData = OSC1337Parser.parse(payload) else { break }
            let renderer = inlineImageRenderer(for: surfaceView)
            let position = surfaceView.bounds.height - 20
            renderer.renderImage(imageData, at: position)

        case .processExited:
            // Shell process exited. Reset agent state to idle and clear
            // activity metadata so the sidebar reflects the terminated session.
            guard let tabID = targetTabID else { break }
            tabManager.updateTab(id: tabID) { tab in
                tab.agentState = .idle
                tab.agentActivity = nil
            }
            tabBarViewModel?.syncWithManager()
            injectedAgentDetectionEngine?.notifyProcessExited()
        }
    }

    // MARK: - Detection Engine Feeding

    /// Synthesizes an OSC escape sequence and feeds it to the agent detection engine.
    ///
    /// libghostty processes terminal output internally and only exposes parsed
    /// events via action callbacks. The detection engine expects raw bytes
    /// containing OSC sequences. This method bridges the gap by reconstructing
    /// the OSC bytes from the already-parsed action data.
    ///
    /// - Parameters:
    ///   - oscCode: The OSC code (0 = title, 7 = pwd, 9 = notification, 133 = prompt).
    ///   - payload: The OSC payload string.
    private func feedDetectionEngine(oscCode: Int, payload: String) {
        guard let engine = injectedAgentDetectionEngine else { return }
        let oscSequence = "\u{1b}]\(oscCode);\(payload)\u{07}"
        if let data = oscSequence.data(using: .utf8) {
            engine.processTerminalOutput(data)
        }
    }

    // MARK: - Inline Image Renderer

    /// Returns or creates the inline image renderer for a surface view.
    ///
    /// Renderers are lazily created and cached per surface view instance.
    /// When a surface view is deallocated, the weak reference in the
    /// renderer's initializer ensures cleanup.
    private func inlineImageRenderer(for surfaceView: TerminalSurfaceView) -> InlineImageRenderer {
        if let existing = inlineImageRenderers[ObjectIdentifier(surfaceView)] {
            return existing
        }
        let renderer = InlineImageRenderer(terminalView: surfaceView)
        inlineImageRenderers[ObjectIdentifier(surfaceView)] = renderer
        return renderer
    }
}
