// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowControllerEnhancedTests.swift - Tests for enhanced MainWindowController (T-012).

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - Window Style Mask Tests

/// Tests that the window has the correct NSWindow.StyleMask for a native macOS terminal.
@MainActor
final class MainWindowStyleMaskTests: XCTestCase {

    func testWindowHasTitledStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.titled),
            "Window must have .titled style"
        )
    }

    func testWindowHasClosableStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.closable),
            "Window must have .closable style"
        )
    }

    func testWindowHasMiniaturizableStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.miniaturizable),
            "Window must have .miniaturizable style"
        )
    }

    func testWindowHasResizableStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.resizable),
            "Window must have .resizable style"
        )
    }

    func testWindowHasFullSizeContentViewStyle() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let styleMask = controller.window?.styleMask ?? []
        XCTAssertTrue(
            styleMask.contains(.fullSizeContentView),
            "Window must have .fullSizeContentView style"
        )
    }
}

// MARK: - Window Titlebar Tests

/// Tests that the titlebar is configured for a transparent, modern macOS look.
@MainActor
final class MainWindowTitlebarTests: XCTestCase {

    func testTitlebarAppearsTransparent() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertTrue(
            controller.window?.titlebarAppearsTransparent ?? false,
            "Titlebar must appear transparent"
        )
    }

    func testDefaultTitleIsCocxyTerminal() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertEqual(
            controller.window?.title,
            "Cocxy Terminal",
            "Default window title must be 'Cocxy Terminal'"
        )
    }
}

// MARK: - Window Size and Position Tests

/// Tests for window sizing, minimum size, and position persistence.
@MainActor
final class MainWindowSizeTests: XCTestCase {

    func testWindowHasMinimumWidth() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let minSize = controller.window?.minSize ?? .zero
        XCTAssertGreaterThanOrEqual(
            minSize.width,
            320,
            "Window minimum width must be at least 320"
        )
    }

    func testWindowHasMinimumHeight() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let minSize = controller.window?.minSize ?? .zero
        XCTAssertGreaterThanOrEqual(
            minSize.height,
            240,
            "Window minimum height must be at least 240"
        )
    }

    func testWindowHasFrameAutosaveName() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let autosaveName = controller.window?.frameAutosaveName ?? ""
        XCTAssertFalse(
            autosaveName.isEmpty,
            "Window must have a non-empty frame autosave name"
        )
    }

    func testWindowIsNotReleasedWhenClosed() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertFalse(
            controller.window?.isReleasedWhenClosed ?? true,
            "Window must not be released when closed"
        )
    }
}

// MARK: - Window Delegate Tests

/// Tests that the NSWindowDelegate methods are properly implemented.
@MainActor
final class MainWindowDelegateTests: XCTestCase {

    func testWindowDelegateIsSetToController() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertTrue(
            controller.window?.delegate === controller,
            "Window delegate must be the controller itself"
        )
    }

    func testWindowWillCloseCallsDestroyTerminalSurface() {
        // This test verifies that closing the window triggers cleanup.
        // We verify by checking the viewModel state after close notification.
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)

        // Mark the viewModel as running so we can verify it stops.
        let fakeSurfaceID = SurfaceID()
        controller.terminalViewModel.markRunning(surfaceID: fakeSurfaceID)
        XCTAssertTrue(controller.terminalViewModel.isRunning)

        // Simulate the windowWillClose notification.
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        // After close, the viewModel should be stopped.
        XCTAssertFalse(
            controller.terminalViewModel.isRunning,
            "Closing the window must stop the terminal viewModel"
        )
    }
}

// MARK: - Window Background Color Tests

/// Tests that the window background color is set correctly.
@MainActor
final class MainWindowBackgroundTests: XCTestCase {

    func testWindowHasNonNilBackgroundColor() {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        XCTAssertNotNil(
            controller.window?.backgroundColor,
            "Window must have a background color set"
        )
    }
}

// MARK: - Config Integration Tests

/// Tests that MainWindowController integrates with ConfigService.
@MainActor
final class MainWindowConfigIntegrationTests: XCTestCase {

    func testWindowControllerAcceptsConfigService() {
        let bridge = MockTerminalEngine()
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let configService = ConfigService(fileProvider: fileProvider)
        let controller = MainWindowController(bridge: bridge, configService: configService)
        XCTAssertNotNil(
            controller,
            "MainWindowController must accept a ConfigService parameter"
        )
    }

    func testWindowSizeReflectsConfigDimensions() throws {
        let toml = """
        [appearance]
        font-size = 14.0
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)

        // The window should have a reasonable size (not zero).
        let frame = controller.window?.frame ?? .zero
        XCTAssertGreaterThan(
            frame.width,
            0,
            "Window width must be greater than 0 when config is provided"
        )
        XCTAssertGreaterThan(
            frame.height,
            0,
            "Window height must be greater than 0 when config is provided"
        )
    }

    func testEditorLSPWiringOpensDocumentWhenEnabled() throws {
        let fileURL = try makeSwiftFile(contents: "func greet() {}\n")
        let configService = try makeConfigService(toml: """
        [lsp]
        enabled = true
        enabled-languages = ["swift"]
        """)
        let factory = MainWindowCapturingLSPProcessFactory()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        controller.lspServerDiscoveryFactory = {
            LSPServerDiscovery(
                executableResolver: { executable in
                    executable == "sourcekit-lsp" ? "/usr/bin/sourcekit-lsp" : nil
                },
                homebrewDetector: { true }
            )
        }
        controller.lspProcessFactory = factory.makeProcess(configuration:)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        controller.tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = fileURL.deletingLastPathComponent()
        }
        let editorView = EditorView(fileURL: fileURL)

        controller.wireEditorLSPIfNeeded(editorView: editorView, fileURL: fileURL, tabID: tabID)

        XCTAssertEqual(controller.lspWorkspaceCoordinators[tabID]?.activeLanguageIDs, ["swift"])
        let process = try XCTUnwrap(factory.lastProcess)
        let methods = try process.decodedMessages().compactMap(\.methodForTest)
        XCTAssertEqual(methods, ["initialize", "textDocument/didOpen"])
    }

    func testEditorLSPWiringRoutesEditorRequestsWhenEnabled() throws {
        let fileURL = try makeSwiftFile(contents: "let value = 1\nprint(value)\n")
        let configService = try makeConfigService(toml: """
        [lsp]
        enabled = true
        enabled-languages = ["swift"]
        """)
        let factory = MainWindowCapturingLSPProcessFactory()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        controller.lspServerDiscoveryFactory = {
            LSPServerDiscovery(
                executableResolver: { executable in
                    executable == "sourcekit-lsp" ? "/usr/bin/sourcekit-lsp" : nil
                },
                homebrewDetector: { true }
            )
        }
        controller.lspProcessFactory = factory.makeProcess(configuration:)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        controller.tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = fileURL.deletingLastPathComponent()
        }
        let editorView = EditorView(fileURL: fileURL)
        editorView.setSelection(EditorSelection(ranges: [EditorTextRange(location: 20, length: 0)]))

        controller.wireEditorLSPIfNeeded(editorView: editorView, fileURL: fileURL, tabID: tabID)

        XCTAssertTrue(editorView.isLSPControlsEnabled)
        XCTAssertTrue(editorView.requestLSPHoverAtSelection())
        XCTAssertTrue(editorView.requestLSPCompletionAtSelection())
        XCTAssertTrue(editorView.requestLSPDefinitionAtSelection())
        XCTAssertTrue(editorView.requestLSPReferencesAtSelection())

        let process = try XCTUnwrap(factory.lastProcess)
        let methods = try process.decodedMessages().compactMap(\.methodForTest)
        XCTAssertEqual(methods, [
            "initialize",
            "textDocument/didOpen",
            "textDocument/hover",
            "textDocument/completion",
            "textDocument/definition",
            "textDocument/references",
        ])
    }

    func testAgentModeLSPDiagnosticsUseOpenEditorDiagnostics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-main-window-agent-lsp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Sample.swift")
        try "let value = missing\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let configService = try makeConfigService(toml: """
        [lsp]
        enabled = true
        enabled-languages = ["swift"]
        """)
        let factory = MainWindowCapturingLSPProcessFactory()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        controller.lspServerDiscoveryFactory = {
            LSPServerDiscovery(
                executableResolver: { executable in
                    executable == "sourcekit-lsp" ? "/usr/bin/sourcekit-lsp" : nil
                },
                homebrewDetector: { true }
            )
        }
        controller.lspProcessFactory = factory.makeProcess(configuration:)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        controller.tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = directory
        }
        let editorView = EditorView(fileURL: fileURL)
        let diagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 2, character: 4),
                end: LSPPosition(line: 2, character: 11)
            ),
            severity: .warning,
            message: "Cannot find 'missing'.",
            source: "sourcekit"
        )

        controller.wireEditorLSPIfNeeded(editorView: editorView, fileURL: fileURL, tabID: tabID)
        let process = try XCTUnwrap(factory.lastProcess)
        process.emit(try LSPFraming.encode(.notification(
            method: "textDocument/publishDiagnostics",
            params: .object([
                "uri": .string(fileURL.absoluteString),
                "diagnostics": .array([diagnostic.jsonValue]),
            ])
        )))

        XCTAssertEqual(controller.currentAgentModeLSPDiagnostics(limit: 5), [
            AgentLSPDiagnostic(
                path: "Sample.swift",
                line: 3,
                column: 5,
                severity: "warning",
                message: "Cannot find 'missing'.",
                source: "sourcekit"
            ),
        ])
    }

    func testEditorLSPWiringClosesPreviousDocumentWhenNextFileIsUnsupported() throws {
        let swiftURL = try makeSwiftFile(contents: "let value = 1\n")
        let textURL = try makeFile(name: "Notes.txt", contents: "plain notes\n")
        let configService = try makeConfigService(toml: """
        [lsp]
        enabled = true
        enabled-languages = ["swift"]
        """)
        let factory = MainWindowCapturingLSPProcessFactory()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        controller.lspServerDiscoveryFactory = {
            LSPServerDiscovery(
                executableResolver: { executable in
                    executable == "sourcekit-lsp" ? "/usr/bin/sourcekit-lsp" : nil
                },
                homebrewDetector: { true }
            )
        }
        controller.lspProcessFactory = factory.makeProcess(configuration:)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        controller.tabManager.updateTab(id: tabID) { tab in
            tab.workingDirectory = swiftURL.deletingLastPathComponent()
        }
        let editorView = EditorView(fileURL: swiftURL)

        controller.wireEditorLSPIfNeeded(editorView: editorView, fileURL: swiftURL, tabID: tabID)
        let process = try XCTUnwrap(factory.lastProcess)
        XCTAssertTrue(editorView.isLSPControlsEnabled)
        XCTAssertEqual(controller.lspWorkspaceCoordinators[tabID]?.activeLanguageIDs, ["swift"])

        editorView.loadFile(textURL)
        controller.wireEditorLSPIfNeeded(editorView: editorView, fileURL: textURL, tabID: tabID)

        XCTAssertFalse(editorView.isLSPControlsEnabled)
        XCTAssertFalse(editorView.requestLSPCompletionAtSelection())
        XCTAssertNil(controller.lspWorkspaceCoordinators[tabID])
        XCTAssertTrue(controller.lspEditorViewsByDocumentURI.isEmpty)
        XCTAssertTrue(controller.lspDocumentTabIDs.isEmpty)
        XCTAssertEqual(process.stopCount, 1)
    }

    func testEditorLSPWiringDoesNothingWhenDisabled() throws {
        let fileURL = try makeSwiftFile(contents: "func greet() {}\n")
        let configService = try makeConfigService(toml: """
        [lsp]
        enabled = false
        enabled-languages = ["swift"]
        """)
        let factory = MainWindowCapturingLSPProcessFactory()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        controller.lspProcessFactory = factory.makeProcess(configuration:)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        let editorView = EditorView(fileURL: fileURL)

        controller.wireEditorLSPIfNeeded(editorView: editorView, fileURL: fileURL, tabID: tabID)

        XCTAssertNil(controller.lspWorkspaceCoordinators[tabID])
        XCTAssertNil(factory.lastProcess)
    }

    func testEditorVimWiringUsesEffectiveConfig() throws {
        let configService = try makeConfigService(toml: """
        [vim]
        enabled = true
        """)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        let editorView = EditorView(text: "abc")

        controller.wireEditorVimMode(editorView: editorView, tabID: tabID)

        XCTAssertTrue(editorView.isVimModeEnabled)
    }

    func testEditorVimWiringDefaultsOff() throws {
        let configService = try makeConfigService(toml: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        let editorView = EditorView(text: "abc")

        controller.wireEditorVimMode(editorView: editorView, tabID: tabID)

        XCTAssertFalse(editorView.isVimModeEnabled)
    }

    func testEditorCompletionWiringUsesEffectiveConfig() throws {
        let fileURL = try makeSwiftFile(contents: "let value = ")
        let configService = try makeConfigService(toml: """
        [completions]
        inline-ai = true
        provider = "foundation-models-on-device"
        enabled-languages = ["swift"]
        """)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        let editorView = EditorView(fileURL: fileURL)

        controller.wireEditorCompletionIfNeeded(editorView: editorView, fileURL: fileURL, tabID: tabID)

        XCTAssertTrue(editorView.isInlineCompletionEnabled)
    }

    func testEditorCompletionWiringDefaultsOff() throws {
        let fileURL = try makeSwiftFile(contents: "let value = ")
        let configService = try makeConfigService(toml: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            deferContentSetup: true
        )
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        let editorView = EditorView(fileURL: fileURL)

        controller.wireEditorCompletionIfNeeded(editorView: editorView, fileURL: fileURL, tabID: tabID)

        XCTAssertFalse(editorView.isInlineCompletionEnabled)
    }

    func testTopTabPositionUsesTopLevelStripOnlyWhenAuroraDisabled() throws {
        let toml = """
        [appearance]
        tab-position = "top"
        aurora-enabled = false
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)

        XCTAssertTrue(
            controller.usesTopLevelTabsInHorizontalStrip,
            "Classic top mode must render top-level tabs, not split panes"
        )
    }

    func testTopTabPositionKeepsAuroraSidebarWhenAuroraDefaultsOn() throws {
        let toml = """
        [appearance]
        tab-position = "top"
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)

        XCTAssertFalse(
            controller.usesTopLevelTabsInHorizontalStrip,
            "Aurora is enabled by default and owns its own sidebar instead of reusing classic top tabs"
        )
    }

    func testTopTabStripCloseFocusedPaneCollapsesSplitWithoutClosingWorkspaceTab() throws {
        let toml = """
        [general]
        confirm-close-process = false

        [appearance]
        tab-position = "top"
        aurora-enabled = false
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }
        controller.newTabAction(nil)

        guard let strip = controller.horizontalTabStripView as? HorizontalTabStripView,
              let activeTabID = controller.tabManager.activeTabID else {
            XCTFail("Expected a visible top strip and active tab")
            return
        }
        let tabCountBefore = controller.tabManager.tabs.count

        strip.onSplitSideBySide?()

        XCTAssertTrue(
            controller.usesTopLevelTabsInHorizontalStrip,
            "The regression only applies to classic top-level tab mode"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            2,
            "The split toolbar action should create a second pane in the active workspace tab"
        )
        XCTAssertEqual(
            strip.tabs.count,
            tabCountBefore,
            "In top mode the strip must keep showing workspace tabs, not split leaves"
        )

        strip.onClosePanel?()

        XCTAssertNil(
            controller.activeSplitView,
            "The right-side close action in top mode must collapse the visual split hierarchy"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            1,
            "Closing the focused pane must also collapse the split model back to one leaf"
        )
        XCTAssertEqual(
            controller.tabManager.tabs.count,
            tabCountBefore,
            "Closing the focused pane must not close the workspace tab shown in the top strip"
        )
        XCTAssertEqual(
            controller.tabManager.activeTabID,
            activeTabID,
            "The active workspace tab should remain selected after closing its focused split"
        )
    }

    func testTopTabStripCloseFocusedPaneWaitsForConfirmation() throws {
        let toml = """
        [general]
        confirm-close-process = true

        [appearance]
        tab-position = "top"
        aurora-enabled = false
        """
        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let configService = ConfigService(fileProvider: fileProvider)
        try configService.reload()

        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge, configService: configService)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }
        controller.newTabAction(nil)

        guard let strip = controller.horizontalTabStripView as? HorizontalTabStripView,
              let activeTabID = controller.tabManager.activeTabID else {
            XCTFail("Expected a visible top strip and active tab")
            return
        }
        let tabCountBefore = controller.tabManager.tabs.count

        strip.onSplitSideBySide?()

        var capturedTitle: String?
        var capturedMessage: String?
        var pendingDecision: ((Bool) -> Void)?
        controller.focusedPaneCloseConfirmationPresenter = { title, message, completion in
            capturedTitle = title
            capturedMessage = message
            pendingDecision = completion
        }

        strip.onClosePanel?()

        XCTAssertEqual(capturedTitle, "Close Focused Pane?")
        XCTAssertTrue(
            capturedMessage?.contains("workspace tab stays open") ?? false,
            "The confirmation should make it clear that this closes only the focused pane"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            2,
            "Clicking the top-strip close icon must not close the split before confirmation"
        )
        XCTAssertEqual(
            controller.tabManager.tabs.count,
            tabCountBefore,
            "Prompting to close a focused pane must not close the workspace tab"
        )

        pendingDecision?(true)

        XCTAssertNil(
            controller.activeSplitView,
            "Confirming should collapse the split hierarchy"
        )
        XCTAssertEqual(
            controller.activeSplitManager?.rootNode.allLeafIDs().count,
            1,
            "Confirming should close the focused pane after the prompt"
        )
        XCTAssertEqual(controller.tabManager.tabs.count, tabCountBefore)
        XCTAssertEqual(controller.tabManager.activeTabID, activeTabID)
    }

    private func makeConfigService(toml: String) throws -> ConfigService {
        let provider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service
    }

    private func makeSwiftFile(contents: String) throws -> URL {
        try makeFile(name: "Sample.swift", contents: contents)
    }

    private func makeFile(name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-main-window-lsp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

private final class MainWindowFakeLSPProcess: LSPProcessManaging {
    var onOutputData: ((Data) -> Void)?
    private(set) var sentFrames: [Data] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false

    func start() throws {
        startCount += 1
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func send(_ frame: Data) throws {
        sentFrames.append(frame)
    }

    func emit(_ data: Data) {
        onOutputData?(data)
    }

    func decodedMessages() throws -> [LSPMessage] {
        try sentFrames.flatMap { try LSPFraming.decodeMessages(from: $0) }
    }
}

private final class MainWindowCapturingLSPProcessFactory {
    private(set) var lastProcess: MainWindowFakeLSPProcess?

    func makeProcess(configuration: LSPProcessConfiguration) -> LSPProcessManaging {
        let process = MainWindowFakeLSPProcess()
        lastProcess = process
        return process
    }
}

private extension LSPMessage {
    var methodForTest: String? {
        switch self {
        case let .request(_, method, _), let .notification(method, _):
            return method
        case .response:
            return nil
        }
    }
}
