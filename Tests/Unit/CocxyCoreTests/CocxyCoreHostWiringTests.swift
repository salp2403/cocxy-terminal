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

    @Test("host view factory produces distinct daemon host views for each concurrent surface")
    func hostViewFactoryProducesDistinctDaemonHostViewsForConcurrentSurfaces() throws {
        let daemonClient = PTYDaemonClient(connection: FactoryMockPTYDaemonConnection())
        let viewModelA = TerminalViewModel(engine: daemonClient)
        let viewModelB = TerminalViewModel(engine: daemonClient)
        let viewModelC = TerminalViewModel(engine: daemonClient)

        let viewA = TerminalHostViewFactory.make(viewModel: viewModelA, engine: daemonClient)
        let viewB = TerminalHostViewFactory.make(viewModel: viewModelB, engine: daemonClient)
        let viewC = TerminalHostViewFactory.make(viewModel: viewModelC, engine: daemonClient)

        #expect(viewA is PTYDaemonHostView)
        #expect(viewB is PTYDaemonHostView)
        #expect(viewC is PTYDaemonHostView)
        #expect(viewA !== viewB)
        #expect(viewB !== viewC)
        #expect(viewA !== viewC)
    }

    @Test("terminal surface creation is centralized through TerminalHostViewFactory")
    func terminalSurfaceCreationCentralizedInFactory() throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourcesDir = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourcesDir.path) else {
            // Source tree is not available (e.g. running from a binary
            // distribution); the invariant is enforced at compile time
            // anyway, so skip rather than fail.
            return
        }

        let factoryFile = "TerminalHostViewFactory.swift"
        var directInstantiations: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let candidate = enumerator?.nextObject() as? URL {
            guard candidate.pathExtension == "swift" else { continue }
            guard candidate.lastPathComponent != factoryFile else { continue }
            let content = (try? String(contentsOf: candidate, encoding: .utf8)) ?? ""
            if content.contains("CocxyCoreView(viewModel:") {
                directInstantiations.append(candidate.lastPathComponent)
            }
        }

        #expect(
            directInstantiations.isEmpty,
            "Surface creation must go through TerminalHostViewFactory; direct CocxyCoreView use found in: \(directInstantiations)"
        )
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
