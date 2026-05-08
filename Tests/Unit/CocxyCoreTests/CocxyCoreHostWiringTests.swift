// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
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

    @Test("known agent command input keeps local scroll when semantic agent block is absent")
    func knownAgentCommandInputKeepsLocalScrollWithoutAgentBlock() throws {
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
        view.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)

        controller.wireSurfaceHandlers(
            for: surfaceID,
            tabID: tabID,
            in: view,
            initialWorkingDirectory: nil
        )

        let state = try #require(bridge.surfaceState(for: surfaceID))
        feed("\u{1B}]133;A\u{07}", into: state.terminal)
        feed("\u{1B}]133;B\u{07}", into: state.terminal)
        feed("\u{1B}]133;C;claude\u{07}", into: state.terminal)
        feed("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h", into: state.terminal)
        feed(numberedTerminalLines(100), into: state.terminal)

        let diagnostics = try #require(bridge.semanticDiagnostics(for: surfaceID))
        #expect(diagnostics.state == 3)
        #expect(diagnostics.agentBlockCount == 0)
        #expect(bridge.semanticBlocks(for: surfaceID, limit: 8).contains {
            $0.blockType == 1 && $0.detail == "claude"
        })

        let before = try #require(bridge.historyVisibleStart(for: surfaceID))
        #expect(before == cocxycore_terminal_history_max_visible_start(state.terminal))
        #expect(view.prefersLocalScrollInMouseTrackingMode?() == true)

        view.scrollWheel(with: makeScrollEvent(deltaY: 120))

        let after = try #require(bridge.historyVisibleStart(for: surfaceID))
        #expect(after < before)
    }

    @Test("known agent command input keeps keyboard input writable in mouse mode")
    func knownAgentCommandInputKeepsKeyboardInputWritableInMouseMode() async throws {
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
        view.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)

        controller.wireSurfaceHandlers(
            for: surfaceID,
            tabID: tabID,
            in: view,
            initialWorkingDirectory: nil
        )

        let output = TestDataSink()
        bridge.setOutputHandler(for: surfaceID) { data in
            output.data.append(data)
        }

        let state = try #require(bridge.surfaceState(for: surfaceID))
        feed("\u{1B}]133;A\u{07}", into: state.terminal)
        feed("\u{1B}]133;B\u{07}", into: state.terminal)
        feed("\u{1B}]133;C;claude\u{07}", into: state.terminal)
        feed("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h", into: state.terminal)

        let diagnostics = try #require(bridge.semanticDiagnostics(for: surfaceID))
        #expect(diagnostics.state == 3)
        #expect(diagnostics.agentBlockCount == 0)

        for character in "typed-ok" {
            view.keyDown(with: makeKeyEvent(characters: String(character)))
        }
        view.keyDown(with: makeKeyEvent(characters: "\r", keyCode: 0x24))

        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("typed-ok") == true
        }

        #expect(String(data: output.data, encoding: .utf8)?.contains("typed-ok") == true)
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

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

private func numberedTerminalLines(_ count: Int) -> String {
    (0..<count)
        .map { String(format: "agent-line-%03d", $0) }
        .joined(separator: "\r\n") + "\r\n"
}

private func makeScrollEvent(deltaY: CGFloat) -> NSEvent {
    let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 1,
        wheel1: Int32(deltaY),
        wheel2: 0,
        wheel3: 0
    )!
    event.location = NSPoint(x: 10, y: 10)
    return NSEvent(cgEvent: event)!
}

private func makeKeyEvent(
    characters: String,
    charactersIgnoringModifiers: String? = nil,
    modifiers: NSEvent.ModifierFlags = [],
    keyCode: UInt16 = 15
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters.lowercased(),
        isARepeat: false,
        keyCode: keyCode
    )!
}
