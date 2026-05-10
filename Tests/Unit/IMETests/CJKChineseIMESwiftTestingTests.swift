// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CJK Chinese IME", .serialized)
@MainActor
struct CJKChineseIMESwiftTestingTests {

    @Test("pinyin composition stores marked text and caret")
    func pinyinCompositionStoresMarkedTextAndCaret() {
        var state = TextCompositionState()

        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))

        #expect(state.hasMarkedText == true)
        #expect(state.markedText == "ni")
        #expect(state.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("pinyin updates replace the active draft")
    func pinyinUpdatesReplaceTheActiveDraft() {
        var state = TextCompositionState()

        state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        state.setMarkedText("ni hao", selectedRange: NSRange(location: 6, length: 0))

        #expect(state.markedText == "ni hao")
        #expect(state.markedRange == NSRange(location: 0, length: 6))
        #expect(state.selectedRange == NSRange(location: 6, length: 0))
    }

    @Test("terminal preedit accepts Chinese candidate text")
    func terminalPreeditAcceptsChineseCandidateText() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "你",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(harness.view.hasMarkedText() == true)
        #expect(harness.view.markedRange() == NSRange(location: 0, length: 1))
        #expect(cocxycore_terminal_preedit_active(state.terminal) == true)
        #expect(readPreedit(from: state.terminal) == "你")
    }

    @Test("terminal commit sends Chinese characters and clears preedit")
    func terminalCommitSendsChineseCharactersAndClearsPreedit() async throws {
        let harness = try makeIMEViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.insertText("你\n", replacementRange: NSRange(location: NSNotFound, length: 0))

        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("你") == true
        }
        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
        #expect(readPreedit(from: state.terminal).isEmpty)
    }

    @Test("attributed Chinese marked text preserves the string payload")
    func attributedChineseMarkedTextPreservesTheStringPayload() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        let marked = NSAttributedString(string: "你好")

        harness.view.setMarkedText(
            marked,
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(harness.view.markedRange() == NSRange(location: 0, length: 2))
        #expect(readPreedit(from: state.terminal) == "你好")
    }
}

@MainActor
struct IMEViewHarness {
    let bridge: CocxyCoreBridge
    let viewModel: TerminalViewModel
    let view: CocxyCoreView
    let surfaceID: SurfaceID
}

@MainActor
func makeIMEViewHarness(command: String = "/bin/cat") throws -> IMEViewHarness {
    let bridge = try makeBridge()
    let viewModel = TerminalViewModel(engine: bridge)
    let view = CocxyCoreView(viewModel: viewModel)
    view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
    _ = view.layer

    let surfaceID = try bridge.createSurface(
        in: view,
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        command: command
    )
    viewModel.markRunning(surfaceID: surfaceID)
    view.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)

    return IMEViewHarness(
        bridge: bridge,
        viewModel: viewModel,
        view: view,
        surfaceID: surfaceID
    )
}
