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
            // Snapshot child PIDs before surface creation to identify
            // the new shell process spawned for the first tab.
            let childrenBefore = snapshotChildPIDs()

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

                // Register tab with process monitor for SSH detection.
                let childrenAfter = snapshotChildPIDs()
                if let shellPID = findNewShellPID(current: childrenAfter, previous: childrenBefore) {
                    processMonitor?.registerTab(firstTabID, shellPID: shellPID)
                }
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
                    engine?.processTerminalOutput(data)
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
            engine?.notifyUserInput()
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

    /// Updates the notification ring on a surface view based on agent state.
    ///
    /// Shows a pulsing ring when the agent is waiting for input (similar to cmux).
    /// Hides the ring when the user focuses the tab or the state changes.
    func updateNotificationRing(for tabID: TabID, agentState: AgentState) {
        guard let surfaceView = tabSurfaceViews[tabID] else { return }

        switch agentState {
        case .waitingInput:
            // Only show ring on background tabs (not the active one).
            if tabID != (visibleTabID ?? tabManager.activeTabID) {
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
                if tab.agentState == .working {
                    tab.agentState = .finished
                }
            }
            tabBarViewModel?.syncWithManager()

            // Notify IDE cursor controller only for the active tab.
            if (sourceTabID == nil || sourceTabID == visibleTabID),
               let surfaceView = sourceSurfaceID.flatMap(surfaceView(for:))
                    ?? activeTerminalSurfaceView {
                let promptRow: Int
                if let surfaceView = surfaceView as? CocxyCoreView {
                    let cursorCtrl = surfaceView.ideCursorController
                    let viewHeight = surfaceView.bounds.height
                    let cellHeight = cursorCtrl.cellHeight
                    promptRow = cellHeight > 0 ? max(0, Int(viewHeight / cellHeight) - 1) : 0
                } else {
                    promptRow = 0
                }
                surfaceView.handleShellPrompt(row: promptRow, column: 2)
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
                payload: "file://localhost\(directoryURL.path)",
                fromTabID: targetTabID,
                surfaceID: sourceSurfaceID
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
            guard let imageData = OSC1337Parser.parse(payload),
                  let surfaceView = sourceSurfaceID.flatMap(surfaceView(for:))
                    ?? activeTerminalSurfaceView else { break }
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
            engine.processTerminalOutput(data)
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
