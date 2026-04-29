// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PictureInPictureSwiftTestingTests.swift - PIP panel lifecycle coverage.

import AppKit
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Picture-in-Picture terminal panel")
struct PictureInPictureSwiftTestingTests {

    @Test("PIPWindowController restores the detached view exactly once")
    func panelRestoresDetachedViewOnce() {
        let tabID = TabID()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        var restoreCount = 0
        let controller = PIPWindowController(tabID: tabID, title: "PIP", detachedView: view) { restoredID, restoredView in
            #expect(restoredID == tabID)
            #expect(restoredView === view)
            restoreCount += 1
        }

        controller.restore()
        controller.restore()

        #expect(restoreCount == 1)
        #expect(controller.didRestore == true)
    }

    @Test("PIPWindowController configures a floating resizable panel for agent work")
    func panelUsesFloatingResizableWindowConfiguration() {
        let controller = PIPWindowController(
            tabID: TabID(),
            title: "PIP",
            detachedView: NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80)),
            onRestore: { _, _ in }
        )

        #expect(controller.window?.level == .floating)
        #expect(controller.window?.styleMask.contains(.resizable) == true)
        #expect(controller.window?.styleMask.contains(.closable) == true)
        #expect(controller.window?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        #expect(controller.window?.collectionBehavior.contains(.fullScreenAuxiliary) == true)
    }

    @Test("detach is feature-gated off by default")
    func detachIsFeatureGatedOffByDefault() {
        let controller = MainWindowController(bridge: MockTerminalEngine())

        #expect(controller.detachActiveTerminalToPIP() == false)
        #expect(controller.pipControllers.isEmpty)
    }

    @Test("detach is blocked while a split view is active so view ownership stays unambiguous")
    func detachIsBlockedWhenSplitViewIsActive() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: makeConfigService(pipEnabled: true)
        )
        controller.activeSplitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        #expect(controller.detachActiveTerminalToPIP() == false)
        #expect(controller.pipControllers.isEmpty)
    }

    @Test("detach creates a PIP controller when the experimental flag is enabled")
    func detachCreatesControllerWhenEnabled() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: makeConfigService(pipEnabled: true)
        )
        guard let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID else {
            Issue.record("Expected initial tab")
            return
        }

        let didDetach = controller.detachActiveTerminalToPIP()

        #expect(didDetach == true)
        #expect(controller.pipControllers[tabID] != nil)
    }

    @Test("detach re-arms rendering after moving the terminal into the PIP panel")
    func detachRearmsRenderingForReparentedSurface() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: makeConfigService(pipEnabled: true)
        )
        guard let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let surfaceView = controller.tabSurfaceViews[tabID] as? CocxyCoreView else {
            Issue.record("Expected initial CocxyCore surface")
            return
        }
        surfaceView.needsRender = false

        let didDetach = controller.detachActiveTerminalToPIP()

        #expect(didDetach == true)
        #expect(surfaceView.needsRender == true)
        #expect(surfaceView.window?.firstResponder === surfaceView)
    }

    @Test("windowWillClose tears down active PIP panels so they do not outlive the controller")
    func windowWillCloseTearsDownActivePIPPanels() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: makeConfigService(pipEnabled: true)
        )
        guard let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID else {
            Issue.record("Expected initial tab")
            return
        }

        #expect(controller.detachActiveTerminalToPIP() == true)
        #expect(controller.pipControllers[tabID] != nil)

        let notification = Notification(name: NSWindow.willCloseNotification, object: nil)
        controller.windowWillClose(notification)

        #expect(controller.pipControllers.isEmpty)
    }

    @Test("PIP remains owned by its panel if the source tab disappears before restore")
    func pipSurvivesSourceTabRemovalUntilPanelRestores() async {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: makeConfigService(pipEnabled: true)
        )
        guard let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID else {
            Issue.record("Expected initial tab")
            return
        }

        #expect(controller.detachActiveTerminalToPIP() == true)
        let secondTab = controller.tabManager.addTab()
        controller.tabManager.removeTab(id: tabID)

        #expect(controller.tabManager.tab(for: tabID) == nil)
        #expect(controller.tabManager.activeTabID == secondTab.id)
        #expect(controller.pipControllers[tabID] != nil)

        controller.pipControllers[tabID]?.restore()
        await Task.yield()

        #expect(controller.pipControllers[tabID] == nil)
        #expect(controller.tabManager.tab(for: tabID) == nil)
        #expect(controller.tabManager.activeTabID == secondTab.id)
    }

    private func makeConfigService(pipEnabled: Bool) -> ConfigService {
        let provider = InMemoryPIPConfigProvider(content: """
        [experimental]
        pip-enabled = \(pipEnabled)
        pty-daemon = false
        """)
        let service = ConfigService(fileProvider: provider)
        try? service.reload()
        return service
    }
}

private final class InMemoryPIPConfigProvider: ConfigFileProviding, @unchecked Sendable {
    private var content: String?

    init(content: String?) {
        self.content = content
    }

    func readConfigFile() -> String? { content }

    func writeConfigFile(_ content: String) throws {
        self.content = content
    }
}
