// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Combine
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

    @Test("historyTailLines returns only newest scrollback lines")
    func historyTailLinesReturnsOnlyNewestLines() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(numberedLines(12), to: state.terminal)

        let tail = bridge.historyTailLines(for: surfaceID, maxCount: 4)
        #expect(tail == ["line-08", "line-09", "line-10", "line-11"])
        #expect(bridge.historyTailLines(for: surfaceID, maxCount: 0).isEmpty)
        #expect(bridge.historyTailLines(for: SurfaceID(), maxCount: 4).isEmpty)
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

    @Test("hyperlink metadata exposes OSC 8 spans")
    func hyperlinkMetadataExposesOSC8Spans() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(
            "\u{001B}]8;id=docs;https://cocxy.dev/docs\u{0007}Click\u{001B}]8;;\u{0007} plain",
            to: state.terminal
        )

        let link = try #require(bridge.hyperlink(atRow: 0, column: 0, for: surfaceID))
        #expect(link.uri == "https://cocxy.dev/docs")
        #expect(link.params == "id=docs")
        #expect(link.row == 0)
        #expect(link.column == 0)
        #expect(link.length == 5)
        #expect(bridge.hyperlink(atRow: 0, column: 5, for: surfaceID) == nil)
    }

    @Test("hyperlink spans iterate in terminal order")
    func hyperlinkSpansIterateInTerminalOrder() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(
            "\u{001B}]8;id=one;https://one.example\u{0007}One\u{001B}]8;;\u{0007}\r\n" +
                "\u{001B}]8;id=two;https://two.example\u{0007}Two\u{001B}]8;;\u{0007}",
            to: state.terminal
        )

        let links = bridge.hyperlinkSpans(for: surfaceID)
        #expect(links.map(\.uri) == ["https://one.example", "https://two.example"])
        #expect(links.map(\.params) == ["id=one", "id=two"])
        #expect(links.map(\.row) == [0, 1])
        #expect(links.map(\.column) == [0, 0])
        #expect(links.map(\.length) == [3, 3])

        let limited = bridge.hyperlinkSpans(for: surfaceID, limit: 1)
        #expect(limited.map(\.uri) == ["https://one.example"])
    }

    @Test("session recording bridge writes local cast output")
    func sessionRecordingBridgeWritesLocalCastOutput() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))
        let directory = try makeTemporaryDirectory(named: "cocxy-session-recording")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordingURL = directory.appendingPathComponent("recording.cast")

        let recorder = try #require(bridge.startSessionRecording(
            for: surfaceID,
            outputURL: recordingURL,
            title: "Bridge smoke"
        ))

        feed("Bridge\r\nRecording", to: state.terminal)
        recorder.stop()

        #expect(recorder.isActive == false)
        #expect(recorder.bytesWritten > 0)

        let contents = try String(contentsOf: recordingURL, encoding: .utf8)
        #expect(contents.contains("\"version\":2"))
        #expect(contents.contains("\"title\":\"Bridge smoke\""))
        #expect(contents.contains("\"Bridge\\r\\nRecording\""))
    }

    @Test("session replay bridge feeds cast output into terminal")
    func sessionReplayBridgeFeedsCastOutputIntoTerminal() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))
        let directory = try makeTemporaryDirectory(named: "cocxy-session-replay")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordingURL = directory.appendingPathComponent("replay.cast")
        try """
        {"version":2,"width":40,"height":4,"timestamp":0,"title":"Replay"}
        [0.000000000,"o","Hi"]
        [1.500000000,"o","\\r\\nThere"]

        """.write(to: recordingURL, atomically: true, encoding: .utf8)

        #expect(bridge.replaySessionRecording(from: recordingURL, for: surfaceID))
        #expect(cocxycore_terminal_cell_char(state.terminal, 0, 0) == UInt32(UInt8(ascii: "H")))
        #expect(cocxycore_terminal_cell_char(state.terminal, 0, 1) == UInt32(UInt8(ascii: "i")))
        #expect(cocxycore_terminal_cell_char(state.terminal, 1, 0) == UInt32(UInt8(ascii: "T")))
    }

    @Test("session replay bridge exposes duration seek and speed controls")
    func sessionReplayBridgeExposesDurationSeekAndSpeedControls() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))
        let directory = try makeTemporaryDirectory(named: "cocxy-session-replay-controls")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordingURL = directory.appendingPathComponent("replay.cast")
        try """
        {"version":2,"width":40,"height":4,"timestamp":0,"title":"Replay"}
        [0.000000000,"o","Hi"]
        [1.500000000,"o","\\r\\nThere"]

        """.write(to: recordingURL, atomically: true, encoding: .utf8)

        #expect(bridge.sessionRecordingDuration(from: recordingURL, for: surfaceID) == 1_500_000_000)
        #expect(bridge.replaySessionRecording(
            from: recordingURL,
            for: surfaceID,
            seekNs: 1_000_000_000,
            speedMultiplier: 2
        ))
        #expect(cocxycore_terminal_cell_char(state.terminal, 0, 0) == UInt32(UInt8(ascii: "H")))
        #expect(cocxycore_terminal_cell_char(state.terminal, 1, 0) == UInt32(UInt8(ascii: "T")))
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
            iterm2Enabled: true,
            diskCacheDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cocxy-image-cache-test"),
            diskCacheLimitBytes: 64 * 1024 * 1024,
            to: surfaceID
        )

        let diagnostics = try #require(bridge.imageDiagnostics(for: surfaceID))
        #expect(diagnostics.memoryLimitBytes == 128 * 1024 * 1024)
        #expect(diagnostics.fileTransferEnabled == true)
        #expect(diagnostics.sixelEnabled == false)
        #expect(diagnostics.kittyEnabled == true)
        #expect(diagnostics.iterm2Enabled == true)
        #expect(diagnostics.diskCacheEnabled == true)
        #expect(diagnostics.diskCacheLimitBytes == 64 * 1024 * 1024)
    }

    @Test("image snapshots enumerate live image metadata in a stable order")
    func imageSnapshotsEnumerateLiveImages() async throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed("\u{1B}_Ga=T,f=32,s=1,v=1,i=7;/wAA/w==\u{1B}\\", to: state.terminal)
        feed("\u{1B}_Ga=T,f=32,s=1,v=1,i=11;AP8A/w==\u{1B}\\", to: state.terminal)
        #expect(cocxycore_image_set_alt_text(state.terminal, 7, "red dot") == true)

        try await waitUntil {
            bridge.imageSnapshots(for: surfaceID).count == 2
        }

        let snapshots = bridge.imageSnapshots(for: surfaceID)
        #expect(snapshots.map(\.imageID) == [7, 11])
        #expect(snapshots.first?.altText == "red dot")
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

    @Test("protocol message injection feeds semantic hooks locally")
    func protocolMessageInjectionFeedsSemanticHooksLocally() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        var hooks: [HookEvent] = []
        var cancellables = Set<AnyCancellable>()
        bridge.semanticAdapter.eventPublisher
            .sink { hooks.append($0) }
            .store(in: &cancellables)

        let payload = #"{"data":{"state":"working","agent_name":"Claude Code","task":"reviewing changes"}}"#
        #expect(bridge.injectProtocolV2Message(type: "agent.status", json: payload, to: surfaceID) == true)
        #expect(bridge.protocolDiagnostics(for: surfaceID)?.observed == true)
        #expect(hooks.contains { event in
            guard event.type == .sessionStart,
                  case .sessionStart(let data) = event.data else { return false }
            return data.agentType == "Claude Code"
        })
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
        #expect(diagnostics.bracketedPasteActive == false)
        #expect(diagnostics.mouseTrackingMode == 0)
        #expect(diagnostics.kittyKeyboardMode == 0)
        #expect(diagnostics.altScreen == false)
        #expect(diagnostics.preeditActive == false)
        #expect((0...5).contains(Int(diagnostics.cursorShape)))
        #expect(diagnostics.semanticBlockCount == 0)
    }

    @Test("ux polish bridge maps bell cursor paste and theme settings")
    func uxPolishBridgeMapsBellCursorPasteAndThemeSettings() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        #expect(bridge.bellMode(for: surfaceID) == .systemDefault)
        bridge.setBellMode(.muted, for: surfaceID)
        #expect(bridge.bellMode(for: surfaceID) == .muted)

        let genericBellURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cocxy-bridge-bell.wav")
        #expect(bridge.setBellAudioFile(genericBellURL, for: surfaceID))
        #expect(bridge.bellAudioFile(for: surfaceID) == genericBellURL.path)

        let eventBellURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cocxy-agent-waiting.aif")
        #expect(bridge.setBellAudioFile(eventBellURL, event: .agentWaiting, for: surfaceID))
        #expect(bridge.bellAudioFile(event: .agentWaiting, for: surfaceID) == eventBellURL.path)

        #expect(bridge.bracketedPasteActive(for: surfaceID) == false)
        bridge.withTerminalLock(surfaceID) { state in
            feed("\u{001B}[?2004h", to: state.terminal)
        }
        #expect(bridge.bracketedPasteActive(for: surfaceID) == true)

        bridge.setBracketedPasteForce(-1, for: surfaceID)
        let forcedDiagnostics = try #require(bridge.modeDiagnostics(for: surfaceID))
        #expect(forcedDiagnostics.bracketedPasteMode == true)
        #expect(forcedDiagnostics.bracketedPasteActive == false)

        bridge.setCursorShape(.outline, for: surfaceID)
        bridge.setCursorBlinkRateMs(225, for: surfaceID)
        bridge.setCursorColorOverride(0x10203040, for: surfaceID)
        #expect(bridge.cursorBlinkRateMs(for: surfaceID) == 225)

        let cursor = try #require(bridge.withTerminalLock(surfaceID) { state in
            var cursor = cocxycore_render_cursor()
            cocxycore_terminal_frame_cursor(state.terminal, &cursor)
            return cursor
        })
        #expect(cursor.shape == 6)
        #expect(cursor.color.r == 0x10)
        #expect(cursor.color.g == 0x20)
        #expect(cursor.color.b == 0x30)
        #expect(cursor.color.a == 0x40)

        bridge.applyTheme(makeUXPolishPalette(), to: surfaceID, transitionMs: 120)
        #expect(bridge.themeTransitionActive(for: surfaceID) == true)
        #expect(bridge.themeTransitionDurationMs(for: surfaceID) == 120)

        bridge.advanceThemeTransitionMs(120, for: surfaceID)
        #expect(bridge.themeTransitionActive(for: surfaceID) == false)

        let foreground = try #require(bridge.withTerminalLock(surfaceID) { state in
            var foreground = cocxycore_rgba()
            cocxycore_terminal_resolve_cell_colors(state.terminal, 0, 0, &foreground, nil)
            return foreground
        })
        #expect(foreground.r == 0x11)
        #expect(foreground.g == 0x22)
        #expect(foreground.b == 0x33)
    }

    @Test("color management bridge maps color space and profile settings")
    func colorManagementBridgeMapsColorSpaceAndProfileSettings() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }

        let initialDiagnostics = try #require(bridge.colorDiagnostics(for: surfaceID))
        #expect(initialDiagnostics.colorSpace == .srgb)
        #expect(initialDiagnostics.supportsWideGamut == true)
        #expect(initialDiagnostics.iccProfilePath == nil)

        bridge.setColorSpace(.displayP3, for: surfaceID)
        #expect(bridge.colorSpace(for: surfaceID) == .displayP3)
        #expect(bridge.colorDiagnostics(for: surfaceID)?.colorSpace == .displayP3)

        let profileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cocxy-display.icc")
        #expect(bridge.setICCProfilePath(profileURL, for: surfaceID))
        #expect(bridge.iccProfilePath(for: surfaceID) == profileURL.path)

        let foreground = try #require(bridge.withTerminalLock(surfaceID) { state in
            feed("x", to: state.terminal)
            cocxycore_terminal_set_theme(state.terminal, 255, 0, 0, 0, 0, 0, 255, 0, 0)
            var foreground = cocxycore_rgba()
            cocxycore_terminal_resolve_cell_colors(state.terminal, 0, 0, &foreground, nil)
            return foreground
        })
        #expect(foreground.r == 234)
        #expect(foreground.g == 51)
        #expect(foreground.b == 35)
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

    @Test("terminal viewport snapshot exposes row mapping and font metrics atomically")
    func terminalViewportSnapshotExposesRowMapping() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(numberedLines(40), to: state.terminal)

        let snapshot = try #require(bridge.terminalViewportSnapshot(for: surfaceID))
        #expect(snapshot.visibleStartRow == cocxycore_terminal_history_visible_start(state.terminal))
        #expect(snapshot.visibleRowCount == cocxycore_terminal_rows(state.terminal))
        #expect(snapshot.cellWidth > 0)
        #expect(snapshot.cellHeight > 0)
        #expect(snapshot.isAltScreen == false)
        #expect(bridge.terminalViewportSnapshot(for: SurfaceID()) == nil)
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

    @Test("shell diagnostics expose CocxyCore timing and multiplexer state")
    func shellDiagnosticsExposeCoreState() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge, command: "/bin/cat")
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        cocxycore_shell_set_preexec_warning_threshold_ns(state.terminal, 1)
        feed("\u{1B}]133;B\u{07}", to: state.terminal)
        Thread.sleep(forTimeInterval: 0.001)
        feed("\u{1B}]133;C\u{07}", to: state.terminal)
        feed("\u{1B}Pp\u{1B}]133;A\u{07}\u{1B}\\", to: state.terminal)

        let diagnostics = try #require(bridge.shellDiagnostics(for: surfaceID))
        #expect(diagnostics.avgPreexecLatencyNs > 0)
        #expect(diagnostics.maxPreexecLatencyNs >= diagnostics.avgPreexecLatencyNs)
        #expect(diagnostics.preexecWarningCount == 1)
        #expect(diagnostics.detectedScreen == true)
    }

    @Test("native agent patterns are registered into CocxyCore semantics")
    func nativeAgentPatternsAreRegisteredIntoCocxyCore() throws {
        let bridge = try makeBridge()
        bridge.updateNativeAgentPatterns(
            from: AgentConfigService.defaultAgentConfigs().map(AgentConfigService.compile)
        )
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        // Enter command-running state so an agent launch pattern can promote
        // the semantic state to agent_active inside CocxyCore.
        feed("\u{1B}]133;A\u{07}", to: state.terminal)
        feed("\u{1B}]133;B\u{07}", to: state.terminal)
        feed("\u{1B}]133;C\u{07}", to: state.terminal)
        feed("Welcome to Codex\r\n", to: state.terminal)

        let diagnostics = try #require(bridge.semanticDiagnostics(for: surfaceID))
        #expect(diagnostics.state == 4)
        #expect(diagnostics.currentBlockType == 5)
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

    @Test("clipboard read authorization copy follows configured app language")
    func clipboardReadAuthorizationCopyFollowsConfiguredAppLanguage() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        let copy = CocxyCoreBridge.localizedClipboardReadAuthorizationCopy(localizer: localizer)

        #expect(copy.messageText == "¿Permitir lectura del portapapeles?")
        #expect(copy.informativeText.contains("OSC 52"))
        #expect(copy.primaryButton == "Permitir")
        #expect(copy.secondaryButton == "Denegar")
    }

    @Test("parseWorkingDirectoryURL accepts file URLs and plain paths")
    func parseWorkingDirectoryURLAcceptsFileURLsAndPaths() throws {
        let bridge = try makeBridge()

        #expect(bridge.parseWorkingDirectoryURL("file:///Users/test/project")?.path == "/Users/test/project")
        #expect(bridge.parseWorkingDirectoryURL("file://localhost/Users/test/project")?.path == "/Users/test/project")
        #expect(bridge.parseWorkingDirectoryURL("file:///Users/test/My%20Project")?.path == "/Users/test/My Project")
        #expect(bridge.parseWorkingDirectoryURL("/Users/test/project")?.path == "/Users/test/project")
    }

    @Test("commandBlocks maps CocxyCore block metadata and output")
    func commandBlocksMapsCocxyCoreMetadataAndOutput() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(
            "\u{1B}]7;file://localhost/Users/dev/My%20Project\u{7}" +
            "\u{1B}]133;A\u{7}" +
            "$ " +
            "\u{1B}]133;B\u{7}" +
            "echo hello\r\n" +
            "\u{1B}]133;C\u{7}" +
            "hello\r\n" +
            "\u{1B}]133;D;0\u{7}",
            to: state.terminal
        )

        let blocks = bridge.commandBlocks(for: surfaceID, limit: 10)

        #expect(blocks.count == 1)
        let block = try #require(blocks.first)
        #expect(block.command == "echo hello")
        #expect(block.output == "hello")
        #expect(block.exitCode == 0)
        #expect(block.pwd == "/Users/dev/My Project")
        #expect(block.durationNs > 0)
        #expect(block.blockType == UInt8(COCXYCORE_BLOCK_COMMAND_OUTPUT.rawValue))

        let lookup = try #require(bridge.commandBlock(for: surfaceID, blockID: block.id))
        #expect(lookup == block)
        #expect(bridge.commandBlock(for: surfaceID, blockID: block.id + 1) == nil)
    }

    @Test("commandBlocks groups multiline commands into one block")
    func commandBlocksGroupsMultilineCommandsIntoOneBlock() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        feed(
            "\u{1B}]133;A\u{7}" +
            "$ " +
            "\u{1B}]133;B\u{7}" +
            "cat <<'EOF'\r\n" +
            "hello\r\n" +
            "EOF\r\n" +
            "\u{1B}]133;C\u{7}" +
            "hello\r\n" +
            "\u{1B}]133;D;0\u{7}",
            to: state.terminal
        )

        let block = try #require(bridge.commandBlocks(for: surfaceID, limit: 10).first)

        #expect(block.command == "cat <<'EOF'\nhello\nEOF")
        #expect(block.output == "hello")
        #expect(block.exitCode == 0)
    }

    @Test("latestCommandBlockOutputs exposes clean chronological context")
    func latestCommandBlockOutputsExposesCleanChronologicalContext() throws {
        let bridge = try makeBridge()
        let (surfaceID, _) = try createSurface(using: bridge)
        defer { bridge.destroySurface(surfaceID) }
        let state = try #require(bridge.surfaceState(for: surfaceID))

        for index in 0..<4 {
            feed(
                "\u{1B}]133;A\u{7}" +
                "\u{1B}]133;C\u{7}" +
                "\u{1B}[32mline-\(index)\u{1B}[0m\r\n" +
                "\u{1B}]133;D;0\u{7}",
                to: state.terminal
            )
        }

        let output = bridge.latestCommandBlockOutputs(for: surfaceID, limit: 3)

        #expect(output == "line-1\nline-2\nline-3")
        #expect(bridge.latestCommandBlockOutputs(for: surfaceID, limit: 0) == "")
        #expect(bridge.latestCommandBlockOutputs(for: SurfaceID(), limit: 3) == "")
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
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["TERM_PROGRAM"] == "CocxyTerminal")
        #expect(env["CLICOLOR"] == "1")
        #expect(env["COCXY_RESOURCES_DIR"] == root.path)
        #expect(env["COCXY_SHELL_INTEGRATION_DIR"] == root.appendingPathComponent("shell-integration").path)
        #expect(env["COCXY_CLAUDE_HOOKS"] == "1")
        #expect(env["ZDOTDIR"] == zshDir.path)
        #expect(env["COCXY_ZSH_ORIG_ZDOTDIR"] == "/Users/test/.config/zsh")
    }

    @Test("shell integration env reflects hook integration disable switches")
    func shellIntegrationEnvReflectsHookIntegrationDisableSwitches() throws {
        let bridge = try makeBridge()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let zshDir = root.appendingPathComponent("shell-integration/zsh", isDirectory: true)
        try FileManager.default.createDirectory(at: zshDir, withIntermediateDirectories: true)

        let env = bridge.buildShellIntegrationEnvVars(
            forShell: "/bin/zsh",
            environment: [:],
            resourcesPath: root.path,
            hookIntegration: HookIntegrationConfig(
                enabled: false,
                agents: [
                    .codex: HookIntegrationAgentConfig(enabled: false),
                    .opencode: HookIntegrationAgentConfig(enabled: false),
                ]
            )
        )

        #expect(env["COCXY_CLAUDE_HOOKS"] == "1")
        #expect(env["COCXY_HOOKS_DISABLED"] == "1")
        #expect(env["COCXY_CODEX_HOOKS_DISABLED"] == "1")
        #expect(env["COCXY_OPENCODE_HOOKS_DISABLED"] == "1")
        #expect(env["COCXY_PI_HOOKS_DISABLED"] == nil)
    }

    @Test("shell integration scripts encode command text in OSC 133 C")
    func shellIntegrationScriptsEncodeCommandTextInOSC133C() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let integrationRoot = packageRoot
            .appendingPathComponent("Resources/shell-integration", isDirectory: true)

        let scriptPaths = [
            "zsh/cocxy-integration",
            "bash/cocxy.bash",
            "fish/cocxy.fish",
        ]

        for path in scriptPaths {
            let scriptURL = integrationRoot.appendingPathComponent(path, isDirectory: false)
            let script = try String(contentsOf: scriptURL, encoding: .utf8)

            #expect(script.contains("133;C;"))
            #expect(script.contains("sanitized_command"))
            #expect(script.contains("cocxy-percent-v1:"))
            #expect(script.contains("%0A"))
            #expect(script.contains("%25"))
            if path.hasPrefix("zsh/") {
                #expect(script.contains("//\\%/%25"))
            }
        }
    }

    @Test("shell integration env routes browser opens through bundled CLI")
    func shellIntegrationEnvRoutesBrowserOpensThroughBundledCLI() throws {
        let bridge = try makeBridge()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cliPath = root.appendingPathComponent("cocxy", isDirectory: false).path
        FileManager.default.createFile(atPath: cliPath, contents: Data())

        let env = bridge.buildShellIntegrationEnvVars(
            forShell: "/bin/zsh",
            environment: ["BROWSER": "/usr/bin/open"],
            resourcesPath: root.path
        )

        let browserPath = try #require(env["BROWSER"])
        let script = try String(contentsOfFile: browserPath, encoding: .utf8)
        #expect(env["COCXY_ORIG_BROWSER"] == "/usr/bin/open")
        #expect(script.contains("browser navigate \"$@\""))
        #expect(script.contains(CocxyCoreBridge.browserOpenerScript(cliPath: cliPath)))

        try? FileManager.default.removeItem(atPath: browserPath)
        try? FileManager.default.removeItem(at: root)
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
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["TERM_PROGRAM"] == "CocxyTerminal")
        #expect(env["CLICOLOR"] == "1")
        #expect(env["COCXY_RESOURCES_DIR"] == root.path)
        #expect(env["COCXY_CLAUDE_HOOKS"] == "1")
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
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["TERM_PROGRAM"] == "CocxyTerminal")
        #expect(env["CLICOLOR"] == "1")
        #expect(env["COCXY_RESOURCES_DIR"] == root.path)
        #expect(env["COCXY_CLAUDE_HOOKS"] == "1")
        #expect(env["XDG_CONFIG_HOME"] == root.appendingPathComponent("shell-integration").path)
        #expect(env["COCXY_FISH_ORIG_HOME"] == "/Users/test")
        #expect(env["COCXY_FISH_ORIG_XDG_CONFIG_HOME"] == "/Users/test/.config")
    }

    @Test("terminal PTYs strip host NO_COLOR so agent TUIs can render their brand accents")
    func terminalPTYsStripHostNoColor() throws {
        #expect(CocxyCoreBridge.terminalEnvironmentKeysToUnset.contains("NO_COLOR"))
        #expect(CocxyCoreBridge.terminalEnvironmentKeysToUnset.contains("COCXY_HOOKS_DISABLED"))
        #expect(CocxyCoreBridge.terminalEnvironmentKeysToUnset.contains("COCXY_OPENCODE_HOOKS_DISABLED"))
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

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}

private func makeUXPolishPalette() -> ThemePalette {
    ThemePalette(
        background: "#010203",
        foreground: "#112233",
        cursor: "#445566",
        selectionBackground: "#778899",
        selectionForeground: "#ffffff",
        tabActiveBackground: "#202020",
        tabActiveForeground: "#f8f8f8",
        tabInactiveBackground: "#101010",
        tabInactiveForeground: "#a0a0a0",
        badgeAttention: "#ffaa00",
        badgeCompleted: "#00aa66",
        badgeError: "#cc2222",
        badgeWorking: "#2277cc",
        ansiColors: [
            "#000000", "#aa0000", "#00aa00", "#aa5500",
            "#0000aa", "#aa00aa", "#00aaaa", "#aaaaaa",
            "#555555", "#ff5555", "#55ff55", "#ffff55",
            "#5555ff", "#ff55ff", "#55ffff", "#ffffff"
        ]
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

private func makeTemporaryDirectory(named prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
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
