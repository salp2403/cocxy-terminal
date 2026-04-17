// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabTransferTests.swift - Tests for cross-window tab drag-and-drop.

import Testing
import Foundation
import AppKit
@testable import CocxyTerminal

@MainActor
private final class MockTerminalHostView: NSView, TerminalHostingView {
    var terminalViewModel: TerminalViewModel?
    var onFileDrop: (([URL]) -> Bool)?
    var onUserInputSubmitted: (() -> Void)?

    func syncSizeWithTerminal() {}
    func showNotificationRing(color: NSColor) {}
    func hideNotificationRing() {}
    func handleShellPrompt(row: Int, column: Int) {}
    func updateInteractionMetrics() {}
    func configureSurfaceIfNeeded(
        bridge: any TerminalEngine,
        surfaceID: SurfaceID
    ) {}
    func requestImmediateRedraw() {}
    func refreshDisplayLinkAnchor() {}
}

// MARK: - Session Drag Data Tests

@Suite("Session Drag Data")
struct SessionDragDataTests {

    @Test("Encode and decode round-trip preserves all fields")
    func encodeDecodeRoundTrip() throws {
        let sessionID = SessionID()
        let tabID = TabID()
        let windowID = WindowID()
        let original = SessionDragData(
            sessionID: sessionID,
            tabID: tabID,
            sourceWindowID: windowID
        )

        let data = try #require(original.pasteboardData())
        let decoded = try JSONDecoder().decode(SessionDragData.self, from: data)

        #expect(decoded.sessionID == sessionID)
        #expect(decoded.tabID == tabID)
        #expect(decoded.sourceWindowID == windowID)
    }
}

// MARK: - Tab Manager Transfer Tests

@Suite("TabManager Transfer Operations")
@MainActor
struct TabManagerTransferTests {

    // MARK: - insertExternalTab

    @Test("insertExternalTab adds tab and activates it")
    func insertExternalTabActivates() {
        let manager = TabManager()
        let initialTabID = manager.tabs.first!.id

        var externalTab = Tab(
            id: TabID(),
            title: "Transferred",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        externalTab.isActive = false

        manager.insertExternalTab(externalTab)

        #expect(manager.tabs.count == 2)
        #expect(manager.activeTabID == externalTab.id)
        // Previous tab should be deactivated.
        #expect(manager.tab(for: initialTabID)?.isActive == false)
    }

    @Test("insertExternalTab rejects duplicate tab ID")
    func insertExternalTabRejectsDuplicate() {
        let manager = TabManager()
        let existingID = manager.tabs.first!.id

        let duplicate = Tab(
            id: existingID,
            title: "Duplicate"
        )

        manager.insertExternalTab(duplicate)

        // Should still have only one tab.
        #expect(manager.tabs.count == 1)
    }

    @Test("insertExternalTab preserves tab properties")
    func insertExternalTabPreservesProperties() {
        let manager = TabManager()
        let dir = URL(fileURLWithPath: "/Users/dev/project")
        let tab = Tab(
            title: "My Tab",
            workingDirectory: dir,
            gitBranch: "main",
            hasUnreadNotification: true,
            customTitle: "Custom"
        )

        manager.insertExternalTab(tab)

        let inserted = manager.tab(for: tab.id)
        #expect(inserted?.title == "My Tab")
        #expect(inserted?.workingDirectory == dir)
        #expect(inserted?.gitBranch == "main")
        #expect(inserted?.hasUnreadNotification == true)
        #expect(inserted?.customTitle == "Custom")
        #expect(inserted?.isActive == true)
    }

    // MARK: - detachTab

    @Test("detachTab removes tab from list")
    func detachTabRemovesFromList() {
        let manager = TabManager()
        let secondTab = manager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp"))

        let detached = manager.detachTab(id: secondTab.id)

        #expect(detached != nil)
        #expect(detached?.id == secondTab.id)
        #expect(detached?.isActive == false)
        #expect(manager.tabs.count == 1)
    }

    @Test("detachTab activates next tab when detaching active tab")
    func detachTabActivatesNext() {
        let manager = TabManager()
        let firstTabID = manager.tabs.first!.id
        let secondTab = manager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp"))
        // secondTab is now active.

        let detached = manager.detachTab(id: secondTab.id)

        #expect(detached != nil)
        #expect(manager.activeTabID == firstTabID)
    }

    @Test("detachTab returns nil for pinned tab")
    func detachTabRejectsPinned() {
        let manager = TabManager()
        let tab = manager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp"))
        manager.togglePin(id: tab.id)

        let detached = manager.detachTab(id: tab.id)

        #expect(detached == nil)
        #expect(manager.tabs.count == 2)
    }

    @Test("detachTab returns nil for non-existent tab")
    func detachTabReturnsNilForUnknown() {
        let manager = TabManager()

        let detached = manager.detachTab(id: TabID())

        #expect(detached == nil)
    }

    @Test("detachTab allows detaching the last tab")
    func detachTabAllowsLastTab() {
        let manager = TabManager()
        let onlyTabID = manager.tabs.first!.id

        let detached = manager.detachTab(id: onlyTabID)

        #expect(detached != nil)
        #expect(manager.tabs.isEmpty)
        #expect(manager.activeTabID == nil)
    }

    // MARK: - Full Transfer Cycle

    @Test("Full transfer cycle: detach from source, insert into destination")
    func fullTransferCycle() {
        let source = TabManager()
        let destination = TabManager()

        let tab = source.addTab(workingDirectory: URL(fileURLWithPath: "/Users/dev"))
        let tabID = tab.id

        // Detach from source.
        guard let detached = source.detachTab(id: tabID) else {
            Issue.record("detachTab returned nil")
            return
        }

        // Insert into destination.
        destination.insertExternalTab(detached)

        // Source no longer has the tab.
        #expect(source.tab(for: tabID) == nil)
        // Destination has it and it's active.
        #expect(destination.tab(for: tabID) != nil)
        #expect(destination.activeTabID == tabID)
    }
}

// MARK: - Session Registry Transfer Integration Tests

@Suite("Registry Transfer Integration")
@MainActor
struct RegistryTransferIntegrationTests {

    private let windowA = WindowID()
    private let windowB = WindowID()

    private func makeRegistry() -> SessionRegistryImpl {
        let registry = SessionRegistryImpl()
        registry.registerWindow(windowA)
        registry.registerWindow(windowB)
        return registry
    }

    @Test("Transfer lifecycle: prepare, complete updates owner in-place")
    func transferLifecycleUpdatesOwner() {
        let registry = makeRegistry()
        let sessionID = SessionID()
        let tabID = TabID()
        let newTabID = TabID()

        registry.registerSession(SessionEntry(
            sessionID: sessionID,
            ownerWindowID: windowA,
            tabID: tabID
        ))

        let prepared = registry.prepareTransfer(sessionID, from: windowA, to: windowB)
        #expect(prepared == true)

        registry.completeTransfer(sessionID, newTabID: newTabID)

        let entry = registry.session(for: sessionID)
        #expect(entry?.ownerWindowID == windowB)
        #expect(entry?.tabID == newTabID)
        #expect(entry?.sessionID == sessionID)
        #expect(entry?.transferState == .stable)
    }

    @Test("Transfer rejected for pinned session still in stable state")
    func sameWindowTransferRejected() {
        let registry = makeRegistry()
        let sessionID = SessionID()

        registry.registerSession(SessionEntry(
            sessionID: sessionID,
            ownerWindowID: windowA,
            tabID: TabID()
        ))

        // Same source and destination.
        let result = registry.prepareTransfer(sessionID, from: windowA, to: windowA)
        #expect(result == false)
    }

    @Test("Cancel transfer preserves original owner")
    func cancelPreservesOwner() {
        let registry = makeRegistry()
        let sessionID = SessionID()

        registry.registerSession(SessionEntry(
            sessionID: sessionID,
            ownerWindowID: windowA,
            tabID: TabID()
        ))

        registry.prepareTransfer(sessionID, from: windowA, to: windowB)
        registry.cancelTransfer(sessionID)

        let entry = registry.session(for: sessionID)
        #expect(entry?.ownerWindowID == windowA)
        #expect(entry?.transferState == .stable)
    }
}

// MARK: - Main Window Transfer Integration

@Suite("MainWindowController transfer integration")
@MainActor
struct MainWindowControllerTransferTests {

    private func makeRegistry() -> SessionRegistryImpl {
        SessionRegistryImpl()
    }

    private func makeRegisteredSession(
        for controller: MainWindowController,
        tabID: TabID,
        in registry: SessionRegistryImpl
    ) -> SessionID {
        registry.registerWindow(controller.windowID)
        let sessionID = controller.sessionIDForTab(tabID)
        let tab = controller.tabManager.tab(for: tabID)!
        // Agent state is resolved from the per-surface store; fresh
        // registry entries start idle since the test doesn't seed one.
        registry.registerSession(SessionEntry(
            sessionID: sessionID,
            ownerWindowID: controller.windowID,
            tabID: tabID,
            title: tab.displayTitle,
            workingDirectory: tab.workingDirectory,
            agentState: .idle,
            detectedAgentName: nil,
            hasUnreadNotification: tab.hasUnreadNotification
        ))
        return sessionID
    }

    @Test("Transfer preserves saved split tree state for the moved tab")
    func transferPreservesSavedSplitTreeState() {
        let source = MainWindowController(bridge: MockTerminalEngine())
        let destination = MainWindowController(bridge: MockTerminalEngine())
        let registry = makeRegistry()
        source.sessionRegistry = registry
        destination.sessionRegistry = registry

        guard let originalTabID = source.tabManager.tabs.first?.id else {
            Issue.record("Expected an initial tab")
            return
        }

        source.newTabAction(nil) // Make the original tab non-active so saved split state is used.

        let splitView = NSSplitView()
        let splitSurfaceID = SurfaceID(rawValue: UUID())
        let splitSurfaceView = MockTerminalHostView()
        let splitViewModel = TerminalViewModel()
        source.savedTabSplitViews[originalTabID] = splitView
        source.savedTabSplitSurfaceViews[originalTabID] = [splitSurfaceID: splitSurfaceView]
        source.savedTabSplitViewModels[originalTabID] = [splitSurfaceID: splitViewModel]

        _ = makeRegisteredSession(for: source, tabID: originalTabID, in: registry)

        #expect(source.transferTab(originalTabID, to: destination))

        #expect(destination.activeSplitView === splitView)
        #expect(destination.splitSurfaceViews[splitSurfaceID] === splitSurfaceView)
        #expect(destination.splitViewModels[splitSurfaceID] === splitViewModel)
        #expect(destination.savedTabSplitViews[originalTabID] == nil)
        #expect(destination.savedTabSplitSurfaceViews[originalTabID] == nil)
        #expect(destination.savedTabSplitViewModels[originalTabID] == nil)
        #expect(source.savedTabSplitViews[originalTabID] == nil)
    }

    @Test("Transfer preserves the live output buffer so data continuity survives the move")
    func transferPreservesOutputBufferContinuity() {
        let source = MainWindowController(bridge: MockTerminalEngine())
        let destination = MainWindowController(bridge: MockTerminalEngine())
        let registry = makeRegistry()
        source.sessionRegistry = registry
        destination.sessionRegistry = registry

        guard let tabID = source.tabManager.tabs.first?.id else {
            Issue.record("Expected an initial tab")
            return
        }

        let buffer = TerminalOutputBuffer()
        buffer.append(Data("before-transfer\n".utf8))
        source.tabOutputBuffers[tabID] = buffer

        _ = makeRegisteredSession(for: source, tabID: tabID, in: registry)

        #expect(source.transferTab(tabID, to: destination))

        let transferredBuffer = destination.tabOutputBuffers[tabID]
        #expect(transferredBuffer === buffer)
        #expect(transferredBuffer?.lines == ["before-transfer"])

        transferredBuffer?.append(Data("after-transfer\n".utf8))
        #expect(destination.tabOutputBuffers[tabID]?.lines == ["before-transfer", "after-transfer"])
        #expect(source.tabOutputBuffers[tabID] == nil)
    }
}
