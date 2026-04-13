// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TabTransfer.swift - Cross-window tab transfer logic.

import AppKit

// MARK: - Tab Transfer

/// Extension that handles detaching and accepting tabs for cross-window
/// drag-and-drop. Extracted to keep the main file focused on window setup.
///
/// ## Transfer Flow
///
/// 1. Source window calls `detachTabForTransfer` → extracts all state.
/// 2. Destination window calls `acceptTransferredTab` → installs state.
/// 3. Registry is updated throughout to maintain consistency.
///
/// The terminal surface (CocxyCoreView) is moved between windows without
/// destroying the underlying PTY. Output continues accumulating in the
/// CocxyCore buffer during the brief transfer window.
extension MainWindowController {

    /// All state associated with a tab that must be transferred between windows.
    ///
    /// This struct owns the view and view model references during the brief
    /// period between detach and accept. Once accepted, ownership transfers
    /// to the destination `MainWindowController`.
    struct TransferredTabState {
        let tab: Tab
        let sessionID: SessionID
        let surfaceID: SurfaceID?
        let surfaceView: TerminalHostView?
        let viewModel: TerminalViewModel?
        let splitView: NSSplitView?
        let splitSurfaceViews: [SurfaceID: TerminalHostView]
        let splitViewModels: [SurfaceID: TerminalViewModel]
        let panelContentViews: [UUID: NSView]
        let outputBuffer: TerminalOutputBuffer?
        let commandTracker: CommandDurationTracker?
    }

    // MARK: - Detach

    /// Detaches a tab from this window for transfer to another window.
    ///
    /// Removes the tab from the TabManager, extracts all associated state
    /// (surface views, view models, split state, buffers), and cleans up
    /// local tracking dictionaries. The PTY is NOT destroyed.
    ///
    /// - Parameter tabID: The tab to detach.
    /// - Returns: The complete transferred state, or `nil` if the tab
    ///   cannot be detached (not found, pinned, or is the last tab with
    ///   no additional windows).
    func detachTabForTransfer(_ tabID: TabID) -> TransferredTabState? {
        // FIX #1: Validate detachability BEFORE touching any state.
        // detachTab checks for pinned tabs and returns nil if blocked.
        // We must call it first to avoid irreversibly gutting state on failure.
        guard let detachedTab = tabManager.detachTab(id: tabID) else {
            return nil
        }

        let isActive = (tabID == displayedTabID)

        // Collect all associated state.
        let sessionID = sessionIDForTab(tabID)
        let surfaceID = tabSurfaceMap[tabID]
        let surfaceView = tabSurfaceViews[tabID]
        let viewModel = tabViewModels[tabID]
        let outputBuffer = tabOutputBuffers[tabID]
        let commandTracker = tabCommandTrackers[tabID]

        // Collect split state — may be in live or saved dictionaries.
        let tabSplitNSView: NSSplitView?
        let tabSplitSurfaces: [SurfaceID: TerminalHostView]
        let tabSplitVMs: [SurfaceID: TerminalViewModel]
        let tabPanels: [UUID: NSView]

        if isActive {
            tabSplitNSView = activeSplitView
            tabSplitSurfaces = splitSurfaceViews
            tabSplitVMs = splitViewModels
            tabPanels = panelContentViews

            // Remove live split state without destroying surfaces.
            activeSplitView?.removeFromSuperview()
            activeSplitView = nil
            splitSurfaceViews.removeAll()
            splitViewModels.removeAll()
            panelContentViews.removeAll()
        } else {
            tabSplitNSView = savedTabSplitViews[tabID]
            tabSplitSurfaces = savedTabSplitSurfaceViews[tabID] ?? [:]
            tabSplitVMs = savedTabSplitViewModels[tabID] ?? [:]
            tabPanels = savedTabPanelContentViews[tabID] ?? [:]

            savedTabSplitViews.removeValue(forKey: tabID)
            savedTabSplitSurfaceViews.removeValue(forKey: tabID)
            savedTabSplitViewModels.removeValue(forKey: tabID)
            savedTabPanelContentViews.removeValue(forKey: tabID)
        }

        // Remove from view hierarchy without destroying.
        surfaceView?.removeFromSuperview()

        // Clean up local tracking (DO NOT destroy the surface).
        tabSurfaceViews.removeValue(forKey: tabID)
        tabViewModels.removeValue(forKey: tabID)
        tabSurfaceMap.removeValue(forKey: tabID)
        tabOutputBuffers.removeValue(forKey: tabID)
        tabCommandTrackers.removeValue(forKey: tabID)
        tabSplitCoordinator.removeSplitManager(for: tabID)
        tabSessionMap.removeValue(forKey: tabID)
        processMonitor?.unregisterTab(tabID)

        // FIX #3: Clean up per-surface tracking for the primary surface.
        if let sid = surfaceID {
            surfaceWorkingDirectories.removeValue(forKey: sid)
            surfaceImageDetectors.removeValue(forKey: sid)
        }
        // Clean up per-surface tracking for split surfaces.
        for sid in tabSplitSurfaces.keys {
            surfaceWorkingDirectories.removeValue(forKey: sid)
            surfaceImageDetectors.removeValue(forKey: sid)
        }

        // Clear active reference if this was the displayed tab.
        if isActive && terminalSurfaceView === surfaceView {
            terminalSurfaceView = nil
        }

        // Switch to the newly active tab if one exists.
        if isActive, let newActiveID = tabManager.activeTabID {
            handleTabSwitch(to: newActiveID)
        }

        return TransferredTabState(
            tab: detachedTab,
            sessionID: sessionID,
            surfaceID: surfaceID,
            surfaceView: surfaceView,
            viewModel: viewModel,
            splitView: tabSplitNSView,
            splitSurfaceViews: tabSplitSurfaces,
            splitViewModels: tabSplitVMs,
            panelContentViews: tabPanels,
            outputBuffer: outputBuffer,
            commandTracker: commandTracker
        )
    }

    // MARK: - Accept

    /// Accepts a tab transferred from another window.
    ///
    /// Installs the transferred state (surface view, view model, split state)
    /// into this window's tracking dictionaries and TabManager. The tab is
    /// activated immediately.
    ///
    /// - Parameter state: The complete transferred state from `detachTabForTransfer`.
    @discardableResult
    func acceptTransferredTab(_ state: TransferredTabState) -> Bool {
        let tabID = state.tab.id

        guard tabManager.tab(for: tabID) == nil else {
            return false
        }

        // Insert the tab into this window's TabManager.
        tabManager.insertExternalTab(state.tab)

        // Install state into tracking dictionaries.
        if let surfaceView = state.surfaceView {
            tabSurfaceViews[tabID] = surfaceView
        }
        if let viewModel = state.viewModel {
            tabViewModels[tabID] = viewModel
        }
        if let surfaceID = state.surfaceID {
            tabSurfaceMap[tabID] = surfaceID
        }
        if let outputBuffer = state.outputBuffer {
            tabOutputBuffers[tabID] = outputBuffer
        }
        if let commandTracker = state.commandTracker {
            tabCommandTrackers[tabID] = commandTracker
        }

        // Store session ID mapping.
        tabSessionMap[tabID] = state.sessionID

        // Install split state into saved dictionaries (handleTabSwitch
        // will restore them when this tab is displayed).
        if let splitView = state.splitView {
            savedTabSplitViews[tabID] = splitView
        }
        if !state.splitSurfaceViews.isEmpty {
            savedTabSplitSurfaceViews[tabID] = state.splitSurfaceViews
        }
        if !state.splitViewModels.isEmpty {
            savedTabSplitViewModels[tabID] = state.splitViewModels
        }
        if !state.panelContentViews.isEmpty {
            savedTabPanelContentViews[tabID] = state.panelContentViews
        }

        if let existingEntry = sessionRegistry?.session(for: state.sessionID) {
            if case .inTransfer = existingEntry.transferState {
                sessionRegistry?.completeTransfer(state.sessionID, newTabID: tabID)
            } else if existingEntry.ownerWindowID != windowID {
                sessionRegistry?.prepareTransfer(
                    state.sessionID,
                    from: existingEntry.ownerWindowID,
                    to: windowID
                )
                sessionRegistry?.completeTransfer(state.sessionID, newTabID: tabID)
            }
        } else {
            sessionRegistry?.registerSession(SessionEntry(
                sessionID: state.sessionID,
                ownerWindowID: windowID,
                tabID: tabID,
                title: state.tab.displayTitle,
                workingDirectory: state.tab.workingDirectory,
                agentState: state.tab.agentState,
                detectedAgentName: state.tab.detectedAgent?.displayName,
                hasUnreadNotification: state.tab.hasUnreadNotification
            ))
        }

        // Wire handlers for the transferred surface so OSC events,
        // agent detection, and command tracking work in the new window.
        if let surfaceID = state.surfaceID, let surfaceView = state.surfaceView {
            wireSurfaceHandlers(
                for: surfaceID,
                tabID: tabID,
                in: surfaceView,
                initialWorkingDirectory: state.tab.workingDirectory
            )
        }

        // Switch to the transferred tab.
        handleTabSwitch(to: tabID)

        // Trigger a resize so CocxyCore knows the new dimensions.
        if let surfaceView = state.surfaceView {
            surfaceView.syncSizeWithTerminal()
        }

        return true
    }

    // MARK: - Cross-Window Transfer Coordination

    /// Performs a complete tab transfer from this window to a destination window.
    ///
    /// Coordinates the detach, registry update, and accept in the correct
    /// order. If this was the last tab, closes this window after transfer.
    ///
    /// - Parameters:
    ///   - tabID: The tab to transfer.
    ///   - destination: The window controller to receive the tab.
    /// - Returns: `true` if the transfer succeeded.
    @discardableResult
    func transferTab(_ tabID: TabID, to destination: MainWindowController) -> Bool {
        // Do not transfer to ourselves — this is a reorder, not a transfer.
        guard destination !== self else { return false }

        let sessionID = sessionIDForTab(tabID)
        let isLastTab = tabManager.tabs.count == 1

        // FIX #4: Use the registry's prepare/complete state machine correctly.
        // Do NOT removeSession before completeTransfer — that breaks the
        // state machine. Instead: prepare → detach → accept (re-registers) →
        // complete updates ownership in-place.

        // Prepare the transfer in the registry.
        let prepared = sessionRegistry?.prepareTransfer(
            sessionID,
            from: windowID,
            to: destination.windowID
        ) ?? true // Allow transfer even without registry (graceful fallback).

        guard prepared else { return false }

        // Detach from source.
        guard let state = detachTabForTransfer(tabID) else {
            sessionRegistry?.cancelTransfer(sessionID)
            return false
        }

        guard destination.acceptTransferredTab(state) else {
            sessionRegistry?.cancelTransfer(sessionID)
            _ = acceptTransferredTab(state)
            return false
        }

        // If this was the last tab, close the source window.
        if isLastTab && tabManager.tabs.isEmpty {
            window?.close()
        }

        return true
    }

    /// Moves a tab into a freshly created window.
    ///
    /// This provides the command-driven counterpart to drag-and-drop transfer,
    /// matching the Phase 8G goal that a session can be moved to a new window
    /// without recreating the PTY manually.
    @discardableResult
    func moveTabToNewWindow(_ tabID: TabID) -> Bool {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let newController = appDelegate.makeWindowController(registerInitialSession: false) else {
            return false
        }

        appDelegate.additionalWindowControllers.append(newController)
        newController.showWindow(nil)
        newController.window?.center()

        // Remove the placeholder tab created by MainWindowController init.
        if let placeholderTabID = newController.tabManager.tabs.first?.id {
            _ = newController.tabManager.detachTab(id: placeholderTabID)
        }

        guard transferTab(tabID, to: newController) else {
            appDelegate.additionalWindowControllers.removeAll { $0 === newController }
            newController.close()
            return false
        }

        if let surfaceView = newController.terminalSurfaceView {
            newController.window?.makeFirstResponder(surfaceView)
        }

        return true
    }

    /// Moves the active tab into a new window. Wired from the File menu.
    @objc func moveActiveTabToNewWindowAction(_ sender: Any?) {
        guard let tabID = displayedTabID ?? tabManager.activeTabID else { return }
        _ = moveTabToNewWindow(tabID)
    }

    // MARK: - Drop Handling

    /// Handles a tab dropped onto this window's tab bar from another window.
    ///
    /// Finds the source window controller, verifies the session exists,
    /// and performs the transfer. Same-window drops are treated as no-ops
    /// (reordering is handled by the tab bar itself).
    ///
    /// - Parameter dragData: The decoded pasteboard payload.
    /// - Returns: `true` if the tab was successfully accepted.
    func handleTabDrop(_ dragData: SessionDragData) -> Bool {
        // Same-window drop = no-op (reordering handled separately).
        guard dragData.sourceWindowID != windowID else { return false }

        // Find the source window controller.
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return false }

        let sourceController: MainWindowController?
        if appDelegate.windowController?.windowID == dragData.sourceWindowID {
            sourceController = appDelegate.windowController
        } else {
            sourceController = appDelegate.additionalWindowControllers.first {
                $0.windowID == dragData.sourceWindowID
            }
        }

        guard let source = sourceController else { return false }

        // Perform the transfer.
        return source.transferTab(dragData.tabID, to: self)
    }
}
