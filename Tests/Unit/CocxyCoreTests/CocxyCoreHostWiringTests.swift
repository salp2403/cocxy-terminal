// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal
import CocxyShared

@Suite("CocxyCore host wiring", .serialized)
@MainActor
struct CocxyCoreHostWiringTests {

    @Test("CocxyCore host view is CocxyCoreView")
    func hostViewIsCocxyCoreView() throws {
        let bridge = try makeBridge()
        let viewModel = TerminalViewModel(engine: bridge)
        let view: TerminalHostView = CocxyCoreView(viewModel: viewModel)

        #expect(view is CocxyCoreView)
    }

    @Test("host view factory keeps CocxyCore on Metal and uses daemon host for PTYDaemonClient")
    func hostViewFactorySelectsRendererForEngine() throws {
        let cocxyBridge = try makeBridge()
        let cocxyModel = TerminalViewModel(engine: cocxyBridge)
        let cocxyView = TerminalHostViewFactory.make(viewModel: cocxyModel, engine: cocxyBridge)

        let daemonClient = PTYDaemonClient(connection: FactoryMockPTYDaemonConnection())
        let daemonModel = TerminalViewModel(engine: daemonClient)
        let daemonView = TerminalHostViewFactory.make(viewModel: daemonModel, engine: daemonClient)

        #expect(cocxyView is CocxyCoreView)
        #expect(daemonView is PTYDaemonHostView)
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

@MainActor
private final class FactoryMockPTYDaemonConnection: PTYDaemonClientConnection {
    func send(_ request: PTYDaemonRequest) throws -> PTYDaemonResponse {
        PTYDaemonResponse(id: request.id, ok: false, error: "not used")
    }

    func receiveEvent(timeout: TimeInterval) throws -> PTYDaemonEvent? {
        nil
    }

    func reconnect() throws {}
}
