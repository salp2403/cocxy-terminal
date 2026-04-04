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

    @Test("surfaceState returns nil for unknown surfaces")
    func surfaceStateReturnsNilForUnknownSurface() throws {
        let bridge = try makeBridge()
        #expect(bridge.surfaceState(for: SurfaceID()) == nil)
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
