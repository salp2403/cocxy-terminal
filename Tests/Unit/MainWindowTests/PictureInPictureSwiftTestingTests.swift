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

    @Test("detach is feature-gated off by default")
    func detachIsFeatureGatedOffByDefault() {
        let controller = MainWindowController(bridge: MockTerminalEngine())

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
