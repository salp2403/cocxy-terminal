// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CocxyCoreBridge", .serialized)
@MainActor
struct CocxyCoreBridgeTests {

    @Test("initialize marks the bridge as initialized")
    func initializeMarksBridgeAsInitialized() throws {
        let bridge = CocxyCoreBridge()
        #expect(bridge.isInitialized == false)

        try bridge.initialize(config: makeConfig())

        #expect(bridge.isInitialized == true)
    }

    @Test("createSurface registers a live surface")
    func createSurfaceRegistersSurface() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        #expect(bridge.activeSurfaceCount == 1)
        #expect(bridge.surfaceState(for: surfaceID) != nil)
    }

    @Test("destroySurface removes the surface state")
    func destroySurfaceRemovesState() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)

        bridge.destroySurface(surfaceID)

        #expect(bridge.activeSurfaceCount == 0)
        #expect(bridge.surfaceState(for: surfaceID) == nil)
    }

    @Test("process monitor registration exposes shell PID and PTY master fd")
    func processMonitorRegistrationExposesRuntimeMetadata() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let registration = try #require(bridge.processMonitorRegistration(for: surfaceID))
        #expect(registration.shellPID > 0)
        #expect(registration.ptyMasterFD >= 0)
        #expect(registration.shellIdentity?.pid == registration.shellPID)
    }

    @Test("surfaceState returns nil for unknown surfaces")
    func surfaceStateReturnsNilForUnknownSurface() throws {
        let bridge = try makeBridge()
        #expect(bridge.surfaceState(for: SurfaceID()) == nil)
        #expect(bridge.processMonitorRegistration(for: SurfaceID()) == nil)
    }

    @Test("historyLines returns the lines fed into the terminal")
    func historyLinesReturnsFedLines() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("alpha\r\nbeta\r\ngamma\r\n", to: state.terminal)

        let lines = bridge.historyLines(for: surfaceID).filter { !$0.isEmpty }
        #expect(Array(lines.prefix(3)) == ["alpha", "beta", "gamma"])
    }

    @Test("searchScrollback uses CocxyCore native search and preserves match coordinates")
    func searchScrollbackUsesNativeSearch() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("alpha\r\nbeta\r\ngamma\r\n", to: state.terminal)

        let results = try #require(bridge.searchScrollback(
            surfaceID: surfaceID,
            options: SearchOptions(query: "BETA", caseSensitive: false, useRegex: false)
        ))

        #expect(results.count == 1)
        #expect(results[0].lineNumber == 1)
        #expect(results[0].column == 0)
        #expect(results[0].matchText.lowercased() == "beta")
    }

    @Test("historyVisibleStart reports the live bottom before scrolling")
    func historyVisibleStartStartsAtBottom() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(numberedLines(40), to: state.terminal)
        let maxVisibleStart = cocxycore_terminal_history_max_visible_start(state.terminal)

        #expect(bridge.historyVisibleStart(for: surfaceID) == maxVisibleStart)
    }

    @Test("scrollToSearchResult centers the target line when possible")
    func scrollToSearchResultMovesViewportToTarget() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(numberedLines(40), to: state.terminal)
        bridge.scrollToSearchResult(surfaceID: surfaceID, lineNumber: 20)

        #expect(bridge.historyVisibleStart(for: surfaceID) == 8)
        #expect(bridge.visibleLineText(for: surfaceID, visibleRow: 12) == "line-20")
    }

    @Test("scrollToSearchResult clamps negative targets to the top")
    func scrollToSearchResultClampsToTop() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(numberedLines(40), to: state.terminal)
        bridge.scrollToSearchResult(surfaceID: surfaceID, lineNumber: -50)

        #expect(bridge.historyVisibleStart(for: surfaceID) == 0)
        #expect(bridge.visibleLineText(for: surfaceID, visibleRow: 0) == "line-00")
    }

    @Test("scrollViewport with a positive delta moves into older history")
    func scrollViewportMovesUpward() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(numberedLines(40), to: state.terminal)
        let before = bridge.historyVisibleStart(for: surfaceID)
        let maxVisibleStart = cocxycore_terminal_history_max_visible_start(state.terminal)

        bridge.scrollViewport(surfaceID: surfaceID, deltaRows: 5)

        #expect(before == maxVisibleStart)
        #expect(bridge.historyVisibleStart(for: surfaceID) == maxVisibleStart - 5)
    }

    @Test("scrollViewport with a negative delta clamps at the live bottom")
    func scrollViewportClampsAtBottom() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(numberedLines(40), to: state.terminal)
        let maxVisibleStart = cocxycore_terminal_history_max_visible_start(state.terminal)
        bridge.scrollViewport(surfaceID: surfaceID, deltaRows: -4)

        #expect(bridge.historyVisibleStart(for: surfaceID) == maxVisibleStart)
    }

    @Test("visibleLineText returns nil for an unknown surface")
    func visibleLineTextReturnsNilForUnknownSurface() throws {
        let bridge = try makeBridge()
        #expect(bridge.visibleLineText(for: SurfaceID(), visibleRow: 0) == nil)
    }

    @Test("TUI status glyphs stay narrow so incremental redraws do not smear text")
    func tuiStatusGlyphsStayNarrow() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        let glyphs = ["⏸", "⏹", "⏺", "✳", "✴"]
        for glyph in glyphs {
            cocxycore_terminal_resize(state.terminal, 24, 80)
            feed("\u{1B}[2J\u{1B}[H", to: state.terminal)
            feed(glyph, to: state.terminal)

            #expect(cocxycore_terminal_cursor_col(state.terminal) == 1)
            #expect(cocxycore_terminal_cell_width(state.terminal, 0, 0) == 0)
        }
    }

    @Test("TUI-style incremental redraw stays aligned after status glyphs")
    func tuiStyleIncrementalRedrawStaysAligned() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("\u{1B}[2J\u{1B}[H⏺abc\r\u{1B}[CX", to: state.terminal)

        #expect(bridge.visibleLineText(for: surfaceID, visibleRow: 0) == "⏺Xbc")
        #expect(cocxycore_terminal_cursor_col(state.terminal) == 2)
    }

    @Test("sendPreeditText activates preedit state")
    func sendPreeditTextActivatesPreedit() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        bridge.sendPreeditText("hola", to: surfaceID)

        #expect(cocxycore_terminal_preedit_active(state.terminal) == true)
        #expect(readPreedit(from: state.terminal) == "hola")
    }

    @Test("sendPreeditText with an empty string clears preedit state")
    func sendPreeditTextClearsPreedit() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        bridge.sendPreeditText("hola", to: surfaceID)
        bridge.sendPreeditText("", to: surfaceID)

        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
        #expect(readPreedit(from: state.terminal).isEmpty)
    }

    @Test("readSelection copies the selected text from history coordinates")
    func readSelectionReturnsSelectedText() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("alpha beta\r\n", to: state.terminal)
        cocxycore_terminal_selection_set(state.terminal, 0, 0, 0, 4)

        #expect(bridge.readSelection(for: surfaceID) == "alpha")
    }

    @Test("selection snapshot exposes active range and text")
    func selectionSnapshotExposesRangeAndText() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("alpha beta\r\n", to: state.terminal)
        cocxycore_terminal_selection_set(state.terminal, 0, 0, 0, 4)

        let snapshot = try #require(bridge.selectionSnapshot(for: surfaceID))
        #expect(snapshot.active == true)
        #expect(snapshot.startRow == 0)
        #expect(snapshot.startCol == 0)
        #expect(snapshot.endRow == 0)
        #expect(snapshot.endCol == 4)
        #expect(snapshot.text == "alpha")
    }

    @Test("sendKeyEvent returns true for supported arrow keys")
    func sendKeyEventHandlesArrowKeys() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let handled = bridge.sendKeyEvent(
            KeyEvent(characters: nil, keyCode: 123, modifiers: [], isKeyDown: true),
            to: surfaceID
        )

        #expect(handled == true)
    }

    @Test("sendText reaches the PTY-backed process")
    func sendTextReachesPty() async throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        let received = TestDataSink()
        bridge.setOutputHandler(for: surfaceID) { data in
            received.data.append(data)
        }

        bridge.sendText("ping\n", to: surfaceID)
        try await waitUntil {
            String(data: received.data, encoding: .utf8)?.contains("ping") == true
        }

        #expect(String(data: received.data, encoding: .utf8)?.contains("ping") == true)
    }

    @Test("updateDefaults stores shell and padding for future surfaces")
    func updateDefaultsStoresFutureSurfaceConfig() throws {
        let bridge = try makeBridge()

        bridge.updateDefaults(
            shell: "/bin/bash",
            windowPaddingX: 20,
            windowPaddingY: 10
        )

        #expect(bridge.configuredPaddingX == 20)
        #expect(bridge.configuredPaddingY == 10)
    }

    @Test("applyLigaturesEnabled updates diagnostics for existing surfaces")
    func applyLigaturesEnabledUpdatesDiagnostics() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        #expect(bridge.ligatureDiagnostics(for: surfaceID)?.enabled == true)
        bridge.applyLigaturesEnabled(false, to: surfaceID)
        #expect(bridge.ligatureDiagnostics(for: surfaceID)?.enabled == false)
    }

    @Test("applyImageSettings updates image diagnostics for existing surfaces")
    func applyImageSettingsUpdatesDiagnostics() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        bridge.applyImageSettings(
            memoryLimitBytes: 128 * 1024 * 1024,
            fileTransferEnabled: true,
            sixelEnabled: false,
            kittyEnabled: true,
            to: surfaceID
        )

        let diagnostics = try #require(bridge.imageDiagnostics(for: surfaceID))
        #expect(diagnostics.memoryLimitBytes == 128 * 1024 * 1024)
        #expect(diagnostics.fileTransferEnabled == true)
        #expect(diagnostics.sixelEnabled == false)
        #expect(diagnostics.kittyEnabled == true)
    }

    @Test("image snapshots enumerate live image metadata in a stable order")
    func imageSnapshotsEnumerateLiveImages() async throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("\u{1B}_Ga=T,f=32,s=1,v=1,i=7;/wAA/w==\u{1B}\\", to: state.terminal)
        feed("\u{1B}_Ga=T,f=32,s=1,v=1,i=11;AP8A/w==\u{1B}\\", to: state.terminal)

        try await waitUntil {
            bridge.imageSnapshots(for: surfaceID).count == 2
        }

        #expect(bridge.imageSnapshots(for: surfaceID).map(\.imageID) == [7, 11])
    }

    @Test("deleteImage removes a specific inline image")
    func deleteImageRemovesSpecificImage() async throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("\u{1B}_Ga=T,f=32,s=1,v=1,i=7;/wAA/w==\u{1B}\\", to: state.terminal)
        feed("\u{1B}_Ga=T,f=32,s=1,v=1,i=11;AP8A/w==\u{1B}\\", to: state.terminal)

        try await waitUntil {
            bridge.imageSnapshots(for: surfaceID).count == 2
        }

        #expect(bridge.deleteImage(7, for: surfaceID) == true)
        #expect(bridge.imageSnapshots(for: surfaceID).map(\.imageID) == [11])
    }

    @Test("protocol diagnostics track outbound capability requests")
    func protocolDiagnosticsTrackProtocolState() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        #expect(bridge.protocolDiagnostics(for: surfaceID)?.observed == false)
        #expect(bridge.requestProtocolV2Capabilities(for: surfaceID) == true)
        #expect(bridge.sendProtocolV2Viewport(for: surfaceID, requestID: "test-request") == true)

        let diagnostics = try #require(bridge.protocolDiagnostics(for: surfaceID))
        #expect(diagnostics.capabilitiesRequested == true)
    }

    @Test("mode diagnostics expose live terminal mode state")
    func modeDiagnosticsExposeTerminalState() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        let diagnostics = try #require(bridge.modeDiagnostics(for: surfaceID))
        #expect(diagnostics.cursorVisible == true)
        #expect(diagnostics.appCursorMode == false)
        #expect(diagnostics.bracketedPasteMode == false)
        #expect(diagnostics.mouseTrackingMode == 0)
        #expect(diagnostics.kittyKeyboardMode == 0)
        #expect(diagnostics.altScreen == false)
        #expect(diagnostics.preeditActive == false)
        #expect((0...5).contains(Int(diagnostics.cursorShape)))
        #expect(diagnostics.semanticBlockCount == 0)
    }

    @Test("process and font diagnostics expose live runtime state")
    func processAndFontDiagnosticsExposeRuntimeState() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let process = try #require(bridge.processDiagnostics(for: surfaceID))
        #expect(process.childPID > 0)
        #expect(process.isAlive == true)

        let font = try #require(bridge.fontMetricsSnapshot(for: surfaceID))
        #expect(font.cellWidth > 0)
        #expect(font.cellHeight > 0)
    }

    @Test("preedit snapshot exposes text, cursor, and anchor")
    func preeditSnapshotExposesTextCursorAndAnchor() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        bridge.sendPreeditText("hola", to: surfaceID)

        let snapshot = try #require(bridge.preeditSnapshot(for: surfaceID))
        #expect(snapshot.active == true)
        #expect(snapshot.text == "hola")
        #expect(snapshot.cursorBytes == 4)
    }

    @Test("semantic diagnostics expose state and recent blocks")
    func semanticDiagnosticsExposeStateAndRecentBlocks() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }

        let diagnostics = try #require(bridge.semanticDiagnostics(for: surfaceID))
        #expect(diagnostics.totalBlockCount == 0)
        #expect(bridge.semanticBlocks(for: surfaceID, limit: 5).isEmpty)
    }

    @Test("applyFont updates the live terminal font metrics")
    func applyFontUpdatesLiveMetrics() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        var before = cocxycore_font_metrics()
        #expect(cocxycore_terminal_get_font_metrics(state.terminal, &before) == true)

        bridge.applyFont(family: "Menlo", size: 24)

        var after = cocxycore_font_metrics()
        #expect(cocxycore_terminal_get_font_metrics(state.terminal, &after) == true)
        #expect(after.cell_height >= before.cell_height)
    }

    @Test("clipboard reads are allowed only when explicitly configured")
    func resolvedClipboardReadContentHonorsAllowPolicy() throws {
        let bridge = try makeBridge()
        let clipboard = RecordingClipboardService(content: "secret")
        bridge.clipboardService = clipboard
        bridge.updateDefaults(clipboardReadAccess: .allow)

        let content = bridge.resolvedClipboardReadContent(for: nil)

        #expect(content == "secret")
        #expect(clipboard.readCallCount == 1)
    }

    @Test("clipboard reads are denied without touching the pasteboard when policy is deny")
    func resolvedClipboardReadContentHonorsDenyPolicy() throws {
        let bridge = try makeBridge()
        let clipboard = RecordingClipboardService(content: "secret")
        bridge.clipboardService = clipboard
        bridge.updateDefaults(clipboardReadAccess: .deny)

        let content = bridge.resolvedClipboardReadContent(for: nil)

        #expect(content.isEmpty)
        #expect(clipboard.readCallCount == 0)
    }

    @Test("prompted clipboard reads do not read content when the user denies access")
    func resolvedClipboardReadContentSkipsClipboardWhenPromptDenied() throws {
        let bridge = try makeBridge()
        let clipboard = RecordingClipboardService(content: "secret")
        bridge.clipboardService = clipboard
        bridge.updateDefaults(clipboardReadAccess: .prompt)
        bridge.clipboardReadAuthorizationHandler = { _ in false }

        let content = bridge.resolvedClipboardReadContent(for: nil)

        #expect(content.isEmpty)
        #expect(clipboard.readCallCount == 0)
    }

    @Test("prompted clipboard reads return content only after approval")
    func resolvedClipboardReadContentReturnsClipboardAfterApproval() throws {
        let bridge = try makeBridge()
        let clipboard = RecordingClipboardService(content: "secret")
        bridge.clipboardService = clipboard
        bridge.updateDefaults(clipboardReadAccess: .prompt)
        bridge.clipboardReadAuthorizationHandler = { _ in true }

        let content = bridge.resolvedClipboardReadContent(for: nil)

        #expect(content == "secret")
        #expect(clipboard.readCallCount == 1)
    }

    @Test("parseWorkingDirectoryURL accepts file URLs and plain paths")
    func parseWorkingDirectoryURLAcceptsFileURLsAndPaths() throws {
        let bridge = try makeBridge()

        #expect(bridge.parseWorkingDirectoryURL("file:///Users/test/project")?.path == "/Users/test/project")
        #expect(bridge.parseWorkingDirectoryURL("file://localhost/Users/test/project")?.path == "/Users/test/project")
        #expect(bridge.parseWorkingDirectoryURL("file:///Users/test/My%20Project")?.path == "/Users/test/My Project")
        #expect(bridge.parseWorkingDirectoryURL("/Users/test/project")?.path == "/Users/test/project")
    }

    @Test("shell integration env injects zsh wrapper when resources are available")
    func shellIntegrationEnvInjectsZshWrapper() throws {
        let bridge = try makeBridge()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let zshDir = root.appendingPathComponent("shell-integration/zsh", isDirectory: true)
        try FileManager.default.createDirectory(at: zshDir, withIntermediateDirectories: true)

        let env = bridge.buildShellIntegrationEnvVars(
            forShell: "/bin/zsh",
            environment: ["ZDOTDIR": "/Users/test/.config/zsh"],
            resourcesPath: root.path
        )

        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COCXY_RESOURCES_DIR"] == root.path)
        #expect(env["COCXY_SHELL_INTEGRATION_DIR"] == root.appendingPathComponent("shell-integration").path)
        #expect(env["ZDOTDIR"] == zshDir.path)
        #expect(env["COCXY_ZSH_ORIG_ZDOTDIR"] == "/Users/test/.config/zsh")
    }

    @Test("shell integration env injects bash bootstrap when resources are available")
    func shellIntegrationEnvInjectsBashBootstrap() throws {
        let bridge = try makeBridge()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bashDir = root
            .appendingPathComponent("shell-integration", isDirectory: true)
            .appendingPathComponent("bash", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bashDir,
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(
            atPath: bashDir.appendingPathComponent(".bashrc").path,
            contents: Data()
        )

        let env = bridge.buildShellIntegrationEnvVars(
            forShell: "/bin/bash",
            environment: [
                "HOME": "/Users/test",
                "ZDOTDIR": "/Users/test/.config/zsh",
            ],
            resourcesPath: root.path
        )

        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COCXY_RESOURCES_DIR"] == root.path)
        #expect(env["HOME"] == bashDir.path)
        #expect(env["COCXY_BASH_ORIG_HOME"] == "/Users/test")
        #expect(env["ZDOTDIR"] == nil)
        #expect(env["COCXY_ZSH_ORIG_ZDOTDIR"] == nil)
    }

    @Test("shell integration env injects fish bootstrap when resources are available")
    func shellIntegrationEnvInjectsFishBootstrap() throws {
        let bridge = try makeBridge()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fishDir = root
            .appendingPathComponent("shell-integration", isDirectory: true)
            .appendingPathComponent("fish", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fishDir,
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(
            atPath: fishDir.appendingPathComponent("config.fish").path,
            contents: Data()
        )
        _ = FileManager.default.createFile(
            atPath: fishDir.appendingPathComponent("cocxy.fish").path,
            contents: Data()
        )

        let env = bridge.buildShellIntegrationEnvVars(
            forShell: "/opt/homebrew/bin/fish",
            environment: [
                "HOME": "/Users/test",
                "XDG_CONFIG_HOME": "/Users/test/.config",
            ],
            resourcesPath: root.path
        )

        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COCXY_RESOURCES_DIR"] == root.path)
        #expect(env["XDG_CONFIG_HOME"] == root.appendingPathComponent("shell-integration").path)
        #expect(env["COCXY_FISH_ORIG_HOME"] == "/Users/test")
        #expect(env["COCXY_FISH_ORIG_XDG_CONFIG_HOME"] == "/Users/test/.config")
    }
}

@MainActor
func makeBridge() throws -> CocxyCoreBridge {
    let bridge = CocxyCoreBridge()
    try bridge.initialize(config: makeConfig())
    return bridge
}

private func makeConfig() -> TerminalEngineConfig {
    TerminalEngineConfig(
        fontFamily: "Menlo",
        fontSize: 14,
        themeName: "Test",
        shell: "/bin/zsh",
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        windowPaddingX: 8,
        windowPaddingY: 4
    )
}

@MainActor
private final class RecordingClipboardService: ClipboardServiceProtocol {
    private let content: String?
    private(set) var readCallCount = 0

    init(content: String?) {
        self.content = content
    }

    func read() -> String? {
        readCallCount += 1
        return content
    }

    func write(_ text: String) {}

    func clear() {}
}

@MainActor
private func createSurface(
    using bridge: CocxyCoreBridge,
    command: String = "/bin/cat"
) throws -> (SurfaceID, NSView) {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
    let surfaceID = try bridge.createSurface(
        in: view,
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        command: command
    )
    return (surfaceID, view)
}

private func numberedLines(_ count: Int) -> String {
    (0..<count)
        .map { String(format: "line-%02d", $0) }
        .joined(separator: "\r\n") + "\r\n"
}

private func feed(_ text: String, to terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

func readPreedit(from terminal: OpaquePointer) -> String {
    let needed = cocxycore_terminal_preedit_text(terminal, nil, 0)
    guard needed > 0 else { return "" }

    var buffer = [UInt8](repeating: 0, count: needed)
    let copied = cocxycore_terminal_preedit_text(terminal, &buffer, buffer.count)
    return String(decoding: buffer.prefix(copied), as: UTF8.self)
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 1_500_000_000,
    pollNanoseconds: UInt64 = 50_000_000,
    condition: @escaping @Sendable @MainActor () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await MainActor.run(body: condition) {
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
    Issue.record("Timed out waiting for condition")
}

final class TestDataSink: @unchecked Sendable {
    var data = Data()
}
