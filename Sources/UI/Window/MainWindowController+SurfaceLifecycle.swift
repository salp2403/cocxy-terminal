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

            // Wire OSC handler for title changes.
            bridge.setOSCHandler(for: surfaceID) { [weak self] notification in
                Task { @MainActor in
                    self?.handleOSCNotification(notification)
                }
            }

            // Wire output handler for scrollback search and agent detection.
            if let firstTabID = tabManager.tabs.first?.id {
                let buffer = TerminalOutputBuffer()
                tabOutputBuffers[firstTabID] = buffer
                terminalOutputBuffer = buffer
                let engine = injectedAgentDetectionEngine

                // Track command durations via OSC 133 ;B (start) and ;D (finish).
                let commandTracker = CommandDurationTracker { [weak self] notification in
                    Task { @MainActor in
                        self?.handleOSCNotification(notification)
                    }
                }
                tabCommandTrackers[firstTabID] = commandTracker

                let imageDetector = InlineImageOSCDetector { [weak self] payload in
                    Task { @MainActor in
                        self?.handleOSCNotification(.inlineImage(payload))
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
        bridge.setOSCHandler(for: surfaceID) { [weak self] notification in
            Task { @MainActor in
                self?.handleOSCNotification(notification)
            }
        }

        let buffer = TerminalOutputBuffer()
        tabOutputBuffers[tabID] = buffer
        let engine = injectedAgentDetectionEngine

        let commandTracker = CommandDurationTracker { [weak self] notification in
            Task { @MainActor in
                self?.handleOSCNotification(notification)
            }
        }
        tabCommandTrackers[tabID] = commandTracker

        let imageDetector = InlineImageOSCDetector { [weak self] payload in
            Task { @MainActor in
                self?.handleOSCNotification(.inlineImage(payload))
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

    func handleOSCNotification(_ notification: OSCNotification) {
        switch notification {
        case .titleChange(let title):
            terminalViewModel.updateTitle(title)
            window?.title = title
            if let activeID = tabManager.activeTabID {
                tabManager.updateTab(id: activeID) { tab in
                    tab.title = title

                    // Detect SSH sessions from terminal title changes.
                    // Many shells set the title to "ssh user@host" or "user@host"
                    // when an SSH session is active.
                    if title.lowercased().hasPrefix("ssh ") {
                        tab.sshSession = SSHSessionDetector.detect(from: title)
                        tab.processName = "ssh"
                    } else if SSHSessionDetector.isSSHProcess(tab.processName ?? "") &&
                              !title.lowercased().contains("ssh") {
                        // SSH ended — title changed back to something else.
                        tab.sshSession = nil
                        tab.processName = nil
                    }
                }
                tabBarViewModel?.syncWithManager()
                refreshTabStrip()
            }

        case .notification(title: let title, body: let body):
            // Forward OSC notification to the notification pipeline.
            guard let activeID = tabManager.activeTabID else { break }
            let notification = CocxyNotification(
                type: .custom("osc-notification"),
                tabId: activeID,
                title: title,
                body: body
            )
            injectedNotificationManager?.notify(notification)

        case .shellPrompt:
            // Shell prompt indicates the command finished. If an agent was
            // working, mark it as finished so the tab badge updates.
            guard let activeID = tabManager.activeTabID else { break }
            tabManager.updateTab(id: activeID) { tab in
                if tab.agentState == .working {
                    tab.agentState = .finished
                }
            }
            tabBarViewModel?.syncWithManager()

            // Notify IDE cursor controller that a new prompt is ready.
            // This enables click-to-position within the command line.
            if let surfaceView = terminalSurfaceView {
                let cursorCtrl = surfaceView.ideCursorController
                // Estimate prompt row from terminal dimensions.
                // The prompt is at the bottom of the visible area.
                let viewHeight = surfaceView.bounds.height
                let cellHeight = cursorCtrl.cellHeight
                let promptRow = cellHeight > 0 ? max(0, Int(viewHeight / cellHeight) - 1) : 0
                // Standard prompt ends at column 2 (e.g., "$ ").
                cursorCtrl.shellPromptDetected(row: promptRow, column: 2)
            }

        case .currentDirectory(let directoryURL):
            // Update the active tab's working directory and git branch.
            guard let activeID = tabManager.activeTabID else { break }
            let gitProvider = GitInfoProviderImpl()
            let branch = gitProvider.currentBranch(at: directoryURL)
            tabManager.updateTab(id: activeID) { tab in
                tab.workingDirectory = directoryURL
                tab.gitBranch = branch
            }
            tabBarViewModel?.syncWithManager()
            refreshStatusBar()
            refreshTabStrip()

        case .commandStarted:
            guard let activeID = tabManager.activeTabID else { break }
            tabManager.updateTab(id: activeID) { tab in
                tab.lastCommandStartedAt = Date()
                tab.lastCommandDuration = nil
                tab.lastCommandExitCode = nil
            }
            refreshStatusBar()

        case .commandFinished(let exitCode):
            guard let activeID = tabManager.activeTabID else { break }
            tabManager.updateTab(id: activeID) { tab in
                if let startTime = tab.lastCommandStartedAt {
                    tab.lastCommandDuration = Date().timeIntervalSince(startTime)
                }
                tab.lastCommandExitCode = exitCode
                tab.lastCommandStartedAt = nil
            }
            refreshStatusBar()

        case .inlineImage(let payload):
            // Parse the OSC 1337 payload and render the image on the active surface.
            guard let surfaceView = terminalSurfaceView,
                  let imageData = OSC1337Parser.parse(payload) else { break }
            let renderer = inlineImageRenderer(for: surfaceView)
            let position = surfaceView.bounds.height - 20
            renderer.renderImage(imageData, at: position)
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
