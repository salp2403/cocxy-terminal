// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AppDelegate lazy session restore")
struct AppDelegateLazySessionRestoreSwiftTestingTests {

    @Test("restore materializes only the active tab surface")
    func restoreMaterializesOnlyActiveTabSurface() async throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let tabIDs = [TabID(), TabID(), TabID()]
        let session = makeSession(tabIDs: tabIDs, activeTabIndex: 1)
        let baselineSurfaceCount = bridge.createSurfaceRequests.count

        #expect(delegate.restoreSession(session, into: controller))

        #expect(bridge.createSurfaceRequests.count == baselineSurfaceCount + 1)
        #expect(controller.tabSurfaceMap[tabIDs[1]] != nil)
        #expect(controller.tabSurfaceMap[tabIDs[0]] == nil)
        #expect(controller.tabSurfaceMap[tabIDs[2]] == nil)

        await settleMainQueue()

        #expect(bridge.createSurfaceRequests.count == baselineSurfaceCount + 1)
        #expect(controller.tabSurfaceMap[tabIDs[0]] == nil)
        #expect(controller.tabSurfaceMap[tabIDs[2]] == nil)
    }

    @Test("switching to a deferred restored tab materializes it once")
    func switchingToDeferredRestoredTabMaterializesItOnce() throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let tabIDs = [TabID(), TabID(), TabID()]
        let session = makeSession(tabIDs: tabIDs, activeTabIndex: 0)

        #expect(delegate.restoreSession(session, into: controller))
        let afterRestoreSurfaceCount = bridge.createSurfaceRequests.count
        let deferredTabID = tabIDs[2]

        controller.tabManager.setActive(id: deferredTabID)
        controller.handleTabSwitch(to: deferredTabID)

        #expect(bridge.createSurfaceRequests.count == afterRestoreSurfaceCount + 1)
        #expect(controller.tabSurfaceMap[deferredTabID] != nil)

        controller.handleTabSwitch(to: deferredTabID)
        #expect(bridge.createSurfaceRequests.count == afterRestoreSurfaceCount + 1)
    }

    @Test("closing a deferred restored tab does not create a shell")
    func closingDeferredRestoredTabDoesNotCreateShell() throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let tabIDs = [TabID(), TabID()]
        let session = makeSession(tabIDs: tabIDs, activeTabIndex: 0)

        #expect(delegate.restoreSession(session, into: controller))
        let afterRestoreSurfaceCount = bridge.createSurfaceRequests.count
        let deferredTabID = tabIDs[1]

        #expect(controller.tabSurfaceMap[deferredTabID] == nil)
        controller.performCloseTab(deferredTabID)

        #expect(bridge.createSurfaceRequests.count == afterRestoreSurfaceCount)
        #expect(controller.tabManager.tab(for: deferredTabID) == nil)
    }

    @Test("deferred split tabs keep their layout metadata before materialization")
    func deferredSplitTabsKeepLayoutMetadataBeforeMaterialization() throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let activeTabID = TabID()
        let splitTabID = TabID()
        let session = makeSession(
            tabIDs: [activeTabID, splitTabID],
            activeTabIndex: 0,
            splitTabID: splitTabID
        )
        let baselineSurfaceCount = bridge.createSurfaceRequests.count

        #expect(delegate.restoreSession(session, into: controller))

        let splitManager = controller.tabSplitCoordinator.splitManager(for: splitTabID)
        #expect(bridge.createSurfaceRequests.count == baselineSurfaceCount + 1)
        #expect(splitManager.rootNode.allLeafIDs().count == 2)
        #expect(controller.tabSurfaceMap[splitTabID] == nil)

        controller.tabManager.setActive(id: splitTabID)
        controller.handleTabSwitch(to: splitTabID)

        #expect(bridge.createSurfaceRequests.count == baselineSurfaceCount + 3)
        #expect(controller.tabSurfaceMap[splitTabID] != nil)
    }

    @Test("restore keeps terminal container opaque while rebuilding surfaces")
    func restoreKeepsTerminalContainerOpaqueWhileRebuildingSurfaces() throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let transparentBackground = CocxyColors.base.withAlphaComponent(0.35)
        controller.window?.backgroundColor = transparentBackground
        controller.terminalContainerView?.layer?.backgroundColor = transparentBackground.cgColor

        let session = makeSession(tabIDs: [TabID(), TabID()], activeTabIndex: 0)

        #expect(delegate.restoreSession(session, into: controller))
        #expect(controller.terminalContainerView?.layer?.backgroundColor?.alpha == 1.0)
    }

    @Test("restore does not force an intermediate window display before surfaces exist")
    func restoreDoesNotForceIntermediateWindowDisplayBeforeSurfacesExist() throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let trackingWindow = TrackingRestoreWindow(
            contentRect: controller.window?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: controller.window?.styleMask ?? [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        trackingWindow.contentView = controller.window?.contentView
        trackingWindow.backgroundColor = CocxyColors.base.withAlphaComponent(0.35)
        controller.window = trackingWindow

        let session = makeSession(tabIDs: [TabID(), TabID()], activeTabIndex: 0)

        #expect(delegate.restoreSession(session, into: controller))
        #expect(trackingWindow.setFrameDisplayFlags == [false])
    }

    private func makeSession(
        tabIDs: [TabID],
        activeTabIndex: Int,
        splitTabID: TabID? = nil
    ) -> Session {
        let root = FileManager.default.temporaryDirectory
        let tabs = tabIDs.enumerated().map { index, tabID in
            let workingDirectory = root.appendingPathComponent("cocxy-lazy-restore-\(index)", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: workingDirectory,
                withIntermediateDirectories: true
            )
            let splitTree: SplitNodeState
            if tabID == splitTabID {
                splitTree = .split(
                    direction: .horizontal,
                    first: .leaf(workingDirectory: workingDirectory, command: nil),
                    second: .leaf(workingDirectory: workingDirectory, command: nil),
                    ratio: 0.5
                )
            } else {
                splitTree = .leaf(workingDirectory: workingDirectory, command: nil)
            }

            return TabState(
                id: tabID,
                title: "Tab \(index + 1)",
                workingDirectory: workingDirectory,
                splitTree: splitTree
            )
        }

        return Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 100, y: 100, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: tabs,
                    activeTabIndex: activeTabIndex
                ),
            ]
        )
    }

    private func settleMainQueue() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await Task.yield()
    }
}

private final class TrackingRestoreWindow: NSWindow {
    private(set) var setFrameDisplayFlags: [Bool] = []

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        setFrameDisplayFlags.append(flag)
        super.setFrame(frameRect, display: flag)
    }
}
