// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("CocxyCore host wiring", .serialized)
@MainActor
struct CocxyCoreHostWiringTests {

    @Test("TerminalHostViewFactory returns CocxyCoreView for CocxyCoreBridge")
    func factoryReturnsCocxyCoreView() throws {
        let bridge = try makeBridge()
        let viewModel = TerminalViewModel(engine: bridge)

        let view = TerminalHostViewFactory.makeView(engine: bridge, viewModel: viewModel)

        #expect(view is CocxyCoreView)
    }

    @Test("TerminalHostViewFactory returns TerminalSurfaceView for GhosttyBridge")
    func factoryReturnsGhosttyView() {
        let bridge = GhosttyBridge()
        let viewModel = TerminalViewModel(engine: bridge)

        let view = TerminalHostViewFactory.makeView(engine: bridge, viewModel: viewModel)

        #expect(view is TerminalSurfaceView)
    }

    @Test("wireSurfaceHandlers installs an outputBufferProvider on CocxyCoreView")
    func wireSurfaceHandlersInstallsOutputBufferProvider() throws {
        let bridge = try makeBridge()
        let controller = MainWindowController(bridge: bridge)
        let tabID = try #require(controller.tabManager.tabs.first?.id)
        let viewModel = TerminalViewModel(engine: bridge)
        let view = CocxyCoreView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        _ = view.layer

        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            command: "/bin/cat"
        )
        defer { bridge.destroySurface(surfaceID) }

        controller.wireSurfaceHandlers(
            for: surfaceID,
            tabID: tabID,
            in: view,
            initialWorkingDirectory: nil
        )

        #expect(view.outputBufferProvider != nil)
    }

    @Test("wireSurfaceHandlers routes output into the CocxyCore output buffer provider")
    func wireSurfaceHandlersRoutesOutputToProvider() async throws {
        let bridge = try makeBridge()
        let controller = MainWindowController(bridge: bridge)
        let tabID = try #require(controller.tabManager.tabs.first?.id)
        let viewModel = TerminalViewModel(engine: bridge)
        let view = CocxyCoreView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        _ = view.layer

        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            command: "/bin/cat"
        )
        defer { bridge.destroySurface(surfaceID) }

        controller.wireSurfaceHandlers(
            for: surfaceID,
            tabID: tabID,
            in: view,
            initialWorkingDirectory: nil
        )

        let outputHandler = try #require(bridge.surfaceState(for: surfaceID)?.outputHandler)
        outputHandler(Data("alpha\nbeta\n".utf8))

        try await waitUntil {
            view.outputBufferProvider?().contains("alpha") == true
        }

        let lines = view.outputBufferProvider?() ?? []
        #expect(lines.contains("alpha"))
        #expect(lines.contains("beta"))
    }
}
