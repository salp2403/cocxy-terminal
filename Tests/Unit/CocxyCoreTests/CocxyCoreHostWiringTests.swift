// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Darwin
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

    @Test("daemon host view forwards scroll wheel as viewport scroll")
    func daemonHostViewForwardsScrollWheelAsViewportScroll() {
        let engine = MockTerminalEngine()
        let viewModel = TerminalViewModel(engine: engine)
        let view = PTYDaemonHostView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        let surfaceID = SurfaceID()
        view.configureSurfaceIfNeeded(bridge: engine, surfaceID: surfaceID)

        view.scrollWheel(with: makeScrollEvent(deltaY: 120))

        #expect(engine.viewportScrollRequests.count == 1)
        #expect(engine.viewportScrollRequests.first?.surface == surfaceID)
        #expect(engine.viewportScrollRequests.first?.deltaRows == 18)
    }

    @Test("daemon host encodes exact X10 and SGR mouse wheel payloads")
    func daemonHostEncodesMouseWheelPayloads() {
        let x10 = PTYDaemonHostView.mouseWheelPayload(
            button: 64,
            mouseMode: 1,
            row: 2,
            column: 4,
            count: 1
        )
        let sgr = PTYDaemonHostView.mouseWheelPayload(
            button: 65,
            mouseMode: 6,
            row: 2,
            column: 4,
            count: 2
        )

        #expect(x10 == Data([0x1B, 0x5B, 0x4D, 0x60, 0x25, 0x23]))
        #expect(sgr == Data("\u{1B}[<65;5;3M\u{1B}[<65;5;3M".utf8))
    }

    @Test("daemon host routes an SGR wheel gesture through surface_write")
    func daemonHostRoutesSGRWheelGesture() throws {
        let rawSurfaceID = UUID()
        let frame = PTYDaemonSurfaceFrame(
            surfaceID: rawSurfaceID.uuidString,
            revision: 1,
            timestamp: 1,
            columns: 80,
            rows: 24,
            cells: [],
            cursor: PTYDaemonCursor(row: 0, column: 0),
            mouseTrackingMode: 6
        )
        let connection = RecordingPTYDaemonConnection(responses: [
            PTYDaemonResponse(
                id: "hello",
                ok: true,
                hello: PTYDaemonHello(
                    version: "dev",
                    capabilities: [
                        PTYDaemonProtocol.jsonLinesCapability,
                        PTYDaemonProtocol.terminalSurfaceCapability,
                        PTYDaemonProtocol.terminalEngineCapability,
                        PTYDaemonProtocol.terminalHostRendererCapability,
                    ]
                )
            ),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: rawSurfaceID.uuidString),
            PTYDaemonResponse(id: "subscribe", ok: true, frame: frame),
            PTYDaemonResponse(id: "resize", ok: true),
            PTYDaemonResponse(id: "write", ok: true),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: TerminalEngineConfig(
            fontFamily: "Menlo",
            fontSize: 13,
            themeName: "Catppuccin Mocha",
            shell: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        ))
        let viewModel = TerminalViewModel(engine: client)
        let view = PTYDaemonHostView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        let surfaceID = try client.createSurface(in: view, workingDirectory: nil, command: nil)
        view.configureSurfaceIfNeeded(bridge: client, surfaceID: surfaceID)

        view.scrollWheel(with: makeScrollEvent(deltaY: 24, location: .zero))

        let write = try #require(connection.requests.last { $0.command == .surfaceWrite })
        let encoded = try #require(write.payload?["bytesBase64"])
        #expect(Data(base64Encoded: encoded) == Data(
            "\u{1B}[<64;1;1M\u{1B}[<64;1;1M\u{1B}[<64;1;1M".utf8
        ))
    }

    @Test("in-process engine reaps a shell that exits without further PTY output")
    func inProcessEngineReapsSilentShellExit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-inprocess-pty-exit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("exit-now.sh")
        try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let bridge = try makeBridge()
        let viewModel = TerminalViewModel(engine: bridge)
        let view = CocxyCoreView(viewModel: viewModel)
        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: root,
            command: script.path
        )
        defer { bridge.destroySurface(surfaceID) }
        let shellPID = try #require(bridge.processMonitorRegistration(for: surfaceID)?.shellPID)

        let deadline = Date().addingTimeInterval(2)
        while processIsPresent(shellPID), Date() < deadline {
            bridge.tick()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        #expect(processIsPresent(shellPID) == false)
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
        viewModel.markRunning(surfaceID: surfaceID)
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
        #expect(view.prefersPacedDeleteRepeat?() == true)
        #expect(view.prefersPacedPasteDelivery?() == true)

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
        viewModel.markRunning(surfaceID: surfaceID)
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

    @Test("foreground agent process keeps local scroll when semantic state is unavailable")
    func foregroundAgentProcessKeepsLocalScrollWhenSemanticStateIsUnavailable() throws {
        let bridge = try makeBridge()
        let controller = MainWindowController(bridge: bridge)
        let tabID = try #require(controller.tabManager.tabs.first?.id)
        controller.tabManager.updateTab(id: tabID) { tab in
            tab.processName = "claude"
        }
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
        viewModel.markRunning(surfaceID: surfaceID)
        view.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)
        controller.tabSurfaceMap[tabID] = surfaceID

        controller.wireSurfaceHandlers(
            for: surfaceID,
            tabID: tabID,
            in: view,
            initialWorkingDirectory: nil
        )

        let state = try #require(bridge.surfaceState(for: surfaceID))
        feed("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h", into: state.terminal)
        feed(numberedTerminalLines(100), into: state.terminal)

        let before = try #require(bridge.historyVisibleStart(for: surfaceID))
        #expect(before == cocxycore_terminal_history_max_visible_start(state.terminal))
        #expect(view.prefersLocalScrollInMouseTrackingMode?() == true)

        view.scrollWheel(with: makeScrollEvent(deltaY: 120))

        let after = try #require(bridge.historyVisibleStart(for: surfaceID))
        #expect(after < before)
    }

    @Test("known agent command input enables immediate image file handoff")
    func knownAgentCommandInputEnablesImmediateImageFileHandoff() throws {
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
        viewModel.markRunning(surfaceID: surfaceID)
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

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-rich-input-host-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("paste.png")
        try Self.pngData.write(to: imageURL)

        let payload = try #require(controller.immediateRichInputPayload(
            for: TerminalRichInputRequest(text: "", fileURLs: [imageURL]),
            surfaceView: view
        ))

        #expect(payload.requiresRawControlSequences == false)
        #expect(payload.text.hasSuffix(".png"))
        #expect(payload.text.contains("RichInputAttachments"))
        #expect(FileManager.default.fileExists(atPath: payload.text))
        #expect(payload.text.contains("1337;File=") == false)
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
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

@MainActor
private final class RecordingPTYDaemonConnection: PTYDaemonClientConnection {
    private var responses: [PTYDaemonResponse]
    private(set) var requests: [PTYDaemonRequest] = []

    init(responses: [PTYDaemonResponse]) {
        self.responses = responses
    }

    func send(_ request: PTYDaemonRequest) throws -> PTYDaemonResponse {
        requests.append(request)
        guard responses.isEmpty == false else {
            return PTYDaemonResponse(id: request.id, ok: false, error: "missing response")
        }
        return responses.removeFirst()
    }

    func receiveEvent(timeout: TimeInterval) throws -> PTYDaemonEvent? { nil }
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

private func makeScrollEvent(
    deltaY: CGFloat,
    location: NSPoint = NSPoint(x: 10, y: 10)
) -> NSEvent {
    let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 1,
        wheel1: Int32(deltaY),
        wheel2: 0,
        wheel3: 0
    )!
    event.location = location
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

private func processIsPresent(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    errno = 0
    return kill(pid, 0) == 0 || errno == EPERM
}
