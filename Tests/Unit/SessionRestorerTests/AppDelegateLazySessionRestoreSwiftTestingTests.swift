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

    @Test("restore defers inactive tab project config until activation")
    func restoreDefersInactiveTabProjectConfigUntilActivation() throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let root = try makeTemporaryDirectory(named: "cocxy-deferred-project-config")
        let activeDirectory = root.appendingPathComponent("active", isDirectory: true)
        let deferredDirectory = root.appendingPathComponent("deferred", isDirectory: true)
        try FileManager.default.createDirectory(
            at: activeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: deferredDirectory,
            withIntermediateDirectories: true
        )
        try "font-size = 19\n".write(
            to: deferredDirectory.appendingPathComponent(".cocxy.toml"),
            atomically: true,
            encoding: .utf8
        )

        let activeTabID = TabID()
        let deferredTabID = TabID()
        let session = makeSession(
            tabIDs: [activeTabID, deferredTabID],
            activeTabIndex: 0,
            workingDirectories: [activeDirectory, deferredDirectory]
        )

        #expect(delegate.restoreSession(session, into: controller))
        #expect(controller.tabManager.tab(for: deferredTabID)?.projectConfig == nil)

        controller.tabManager.setActive(id: deferredTabID)
        controller.handleTabSwitch(to: deferredTabID)

        #expect(controller.tabManager.tab(for: deferredTabID)?.projectConfig?.fontSize == 19)
    }

    @Test("background metadata hydration does not materialize deferred tab shells")
    func backgroundMetadataHydrationDoesNotMaterializeDeferredTabShells() async throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let root = try makeTemporaryDirectory(named: "cocxy-background-project-config")
        let activeDirectory = root.appendingPathComponent("active", isDirectory: true)
        let deferredDirectory = root.appendingPathComponent("deferred", isDirectory: true)
        try FileManager.default.createDirectory(
            at: activeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: deferredDirectory,
            withIntermediateDirectories: true
        )
        try "font-size = 21\n".write(
            to: deferredDirectory.appendingPathComponent(".cocxy.toml"),
            atomically: true,
            encoding: .utf8
        )

        let activeTabID = TabID()
        let deferredTabID = TabID()
        let session = makeSession(
            tabIDs: [activeTabID, deferredTabID],
            activeTabIndex: 0,
            workingDirectories: [activeDirectory, deferredDirectory]
        )

        #expect(delegate.restoreSession(session, into: controller))
        let surfaceCountAfterRestore = bridge.createSurfaceRequests.count
        #expect(controller.tabSurfaceMap[deferredTabID] == nil)

        controller.scheduleDeferredRestoredTabMetadataHydration(after: 0)
        await settleMainQueue()

        #expect(controller.tabManager.tab(for: deferredTabID)?.projectConfig?.fontSize == 21)
        #expect(controller.tabSurfaceMap[deferredTabID] == nil)
        #expect(bridge.createSurfaceRequests.count == surfaceCountAfterRestore)
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

    @Test("restore covers visible terminal area until first repaint")
    func restoreCoversVisibleTerminalAreaUntilFirstRepaint() async throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)

        let transparentBackground = CocxyColors.base.withAlphaComponent(0.35)
        controller.window?.backgroundColor = transparentBackground
        controller.terminalContainerView?.layer?.backgroundColor = transparentBackground.cgColor

        let session = makeSession(tabIDs: [TabID(), TabID()], activeTabIndex: 0)

        #expect(delegate.restoreSession(session, into: controller))
        let shield = try #require(controller.sessionRestoreShieldView)
        #expect(shield.superview === controller.terminalContainerView)
        #expect(shield.layer?.isOpaque == true)
        #expect(shield.layer?.backgroundColor?.alpha == 1.0)

        try await waitForShieldRemoval(on: controller)

        #expect(controller.sessionRestoreShieldView == nil)
        #expect(shield.superview == nil)
        #expect(controller.terminalContainerView?.layer?.backgroundColor?.alpha == 1.0)
    }

    @Test("restore shield stays visible through the first repaint window")
    func restoreShieldStaysVisibleThroughFirstRepaintWindow() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())

        controller.installSessionRestoreShield()
        let shield = try #require(controller.sessionRestoreShieldView)
        controller.scheduleSessionRestoreShieldRemoval()

        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(controller.sessionRestoreShieldView === shield)
        #expect(shield.superview === controller.terminalContainerView)

        try await waitForShieldRemoval(on: controller)
    }

    @Test("restore shield covers slower terminal repaints before removal")
    func restoreShieldCoversSlowerTerminalRepaintsBeforeRemoval() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())

        controller.installSessionRestoreShield()
        let shield = try #require(controller.sessionRestoreShieldView)
        controller.scheduleSessionRestoreShieldRemoval()

        try await Task.sleep(nanoseconds: 450_000_000)
        #expect(controller.sessionRestoreShieldView === shield)
        #expect(shield.superview === controller.terminalContainerView)

        try await waitForShieldRemoval(on: controller)
    }

    @Test("restore shield removes after the active terminal presents a frame")
    func restoreShieldRemovesAfterActiveTerminalFrame() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let hostView = FrameReportingTerminalHostView(frame: controller.terminalContainerView?.bounds ?? .zero)
        let tabID = try #require(controller.tabManager.activeTabID)
        controller.tabSurfaceViews[tabID] = hostView
        controller.terminalSurfaceView = hostView
        controller.terminalContainerView?.addSubview(hostView)

        controller.installSessionRestoreShield()
        let shield = try #require(controller.sessionRestoreShieldView)
        controller.scheduleSessionRestoreShieldRemoval()

        #expect(hostView.onFramePresented != nil)
        hostView.onFramePresented?()

        try await Task.sleep(nanoseconds: 220_000_000)

        #expect(controller.sessionRestoreShieldView == nil)
        #expect(shield.superview == nil)
    }

    @Test("restore shield remains through compositor settling after first frame")
    func restoreShieldRemainsThroughCompositorSettlingAfterFirstFrame() async throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let hostView = FrameReportingTerminalHostView(frame: controller.terminalContainerView?.bounds ?? .zero)
        let tabID = try #require(controller.tabManager.activeTabID)
        controller.tabSurfaceViews[tabID] = hostView
        controller.terminalSurfaceView = hostView
        controller.terminalContainerView?.addSubview(hostView)

        controller.installSessionRestoreShield()
        let shield = try #require(controller.sessionRestoreShieldView)
        controller.scheduleSessionRestoreShieldRemoval()

        hostView.onFramePresented?()

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(controller.sessionRestoreShieldView === shield)
        #expect(shield.superview === controller.terminalContainerView)

        try await waitForShieldRemoval(on: controller)
    }

    @Test("restore shield timeout covers slower first paints")
    func restoreShieldTimeoutCoversSlowerFirstPaints() {
        #expect(MainWindowController.sessionRestoreShieldRemovalTimeout >= 1.0)
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

    @Test("restore does not force synchronous window display")
    func restoreDoesNotForceSynchronousWindowDisplay() throws {
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
        controller.window = trackingWindow

        let session = makeSession(tabIDs: [TabID(), TabID()], activeTabIndex: 0)

        #expect(delegate.restoreSession(session, into: controller))
        #expect(trackingWindow.displayIfNeededCount == 0)
    }

    @Test("manual restore batches visible rebuild until the next window flush")
    func manualRestoreBatchesVisibleRebuildUntilNextWindowFlush() throws {
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
        #expect(trackingWindow.disableScreenUpdatesCount == 1)
        #expect(trackingWindow.displayIfNeededCount == 0)
        #expect(trackingWindow.setFrameDisplayFlags == [false])
    }

    @Test("crash recovery restore batches visible rebuild until the next window flush")
    func crashRecoveryRestoreBatchesVisibleRebuildUntilNextWindowFlush() throws {
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

        #expect(delegate.restoreCrashRecoverySession(session, into: controller))
        #expect(trackingWindow.disableScreenUpdatesCount == 1)
        #expect(trackingWindow.displayIfNeededCount == 0)
    }

    private func makeSession(
        tabIDs: [TabID],
        activeTabIndex: Int,
        splitTabID: TabID? = nil,
        workingDirectories: [URL] = []
    ) -> Session {
        let root = FileManager.default.temporaryDirectory
        let tabs = tabIDs.enumerated().map { index, tabID in
            let workingDirectory: URL
            if index < workingDirectories.count {
                workingDirectory = workingDirectories[index]
            } else {
                workingDirectory = root.appendingPathComponent("cocxy-lazy-restore-\(index)", isDirectory: true)
                try? FileManager.default.createDirectory(
                    at: workingDirectory,
                    withIntermediateDirectories: true
                )
            }
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

    private func waitForShieldRemoval(
        on controller: MainWindowController,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while controller.sessionRestoreShieldView != nil {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                Issue.record("Timed out waiting for session restore shield removal")
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
            await Task.yield()
        }
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private final class TrackingRestoreWindow: NSWindow {
    private(set) var setFrameDisplayFlags: [Bool] = []
    private(set) var displayIfNeededCount = 0
    private(set) var disableScreenUpdatesCount = 0

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        setFrameDisplayFlags.append(flag)
        super.setFrame(frameRect, display: flag)
    }

    override func disableScreenUpdatesUntilFlush() {
        disableScreenUpdatesCount += 1
        super.disableScreenUpdatesUntilFlush()
    }

    override func displayIfNeeded() {
        displayIfNeededCount += 1
        super.displayIfNeeded()
    }
}

@MainActor
private final class FrameReportingTerminalHostView: NSView, TerminalHostingView {
    var terminalViewModel: TerminalViewModel?
    var onFileDrop: (([URL]) -> Bool)?
    var onUserInputSubmitted: (() -> Void)?
    var onFramePresented: (() -> Void)?

    func syncSizeWithTerminal() {}
    func showNotificationRing(color: NSColor) {}
    func hideNotificationRing() {}
    func handleShellPrompt(row: Int, column: Int) {}
    func updateInteractionMetrics() {}
    func configureSurfaceIfNeeded(bridge: any TerminalEngine, surfaceID: SurfaceID) {}
    func requestImmediateRedraw() {}
    func refreshDisplayLinkAnchor() {}
}
