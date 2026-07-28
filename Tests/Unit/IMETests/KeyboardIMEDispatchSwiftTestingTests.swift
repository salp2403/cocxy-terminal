// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import CocxyCoreKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Keyboard and IME dispatch", .serialized)
@MainActor
struct KeyboardIMEDispatchSwiftTestingTests {
    @Test("dead-key callbacks commit complete text before the key encoder")
    func deadKeyCallbacksCommitCompleteTextBeforeEncoder() async throws {
        let rawCat = try makeIMERawCatScript()
        defer { try? FileManager.default.removeItem(at: rawCat.rootDirectory) }
        let harness = try makeIMEViewHarness(command: rawCat.scriptURL.path)
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }
        try await waitUntil {
            FileManager.default.fileExists(atPath: rawCat.readyURL.path)
        }
        var deliveredInputCount = 0
        harness.bridge.inputDeliveryObserver = { surfaceID, event in
            guard surfaceID == harness.surfaceID, event == .delivered else { return }
            deliveredInputCount += 1
        }

        harness.view.keyEventInterpreterOverride = { [weak view = harness.view] event in
            switch event.characters {
            case "":
                view?.setMarkedText(
                    "`",
                    selectedRange: NSRange(location: 1, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            case "à":
                view?.insertText(
                    "à",
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            case "`q":
                view?.insertText(
                    "`q",
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            case "``":
                view?.insertText(
                    "``",
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            default:
                break
            }
        }

        harness.view.keyDown(with: makeIMEKeyEvent(characters: "", keyCode: 33))
        #expect(harness.view.hasMarkedText() == true)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == true)
        #expect(deliveredInputCount == 0)

        harness.view.keyDown(with: makeIMEKeyEvent(characters: "à", keyCode: 0))
        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)

        harness.view.setMarkedText(
            "`",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.keyDown(with: makeIMEKeyEvent(characters: "`q", keyCode: 12))

        harness.view.setMarkedText(
            "`",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.keyDown(with: makeIMEKeyEvent(characters: "``", keyCode: 33))

        let expected = Data("à`q``".utf8)
        try await waitUntil {
            output.data.range(of: expected) != nil
        }
        #expect(output.data.range(of: expected) != nil)
        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }

    @Test("Escape cancels composition while Ctrl-letter commits then sends control")
    func escapeAndControlHaveExplicitCompositionSemantics() async throws {
        let rawCat = try makeIMERawCatScript()
        defer { try? FileManager.default.removeItem(at: rawCat.rootDirectory) }
        let harness = try makeIMEViewHarness(command: rawCat.scriptURL.path)
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }
        try await waitUntil {
            FileManager.default.fileExists(atPath: rawCat.readyURL.path)
        }
        var interpretationCount = 0
        harness.view.keyEventInterpreterOverride = { _ in
            interpretationCount += 1
        }

        harness.view.setMarkedText(
            "`",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.keyDown(with: makeIMEKeyEvent(characters: "\u{1B}", keyCode: 53))

        #expect(interpretationCount == 0)
        #expect(output.data.isEmpty)
        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)

        harness.view.setMarkedText(
            "x",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.keyDown(with: makeIMEKeyEvent(
            characters: "\u{3}",
            charactersIgnoringModifiers: "c",
            modifiers: [.control],
            keyCode: 8
        ))

        let expected = Data([0x78, 0x03])
        try await waitUntil {
            output.data.range(of: expected) != nil
        }
        #expect(output.data.range(of: expected) != nil)
        #expect(interpretationCount == 0)
        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }

    @Test("resigning first responder clears local and engine preedit")
    func resignFirstResponderClearsPreedit() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(harness.view.resignFirstResponder() == true)

        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }

    @Test("a stale engine preedit is cleared before fallback key bytes")
    func staleEnginePreeditIsClearedBeforeFallbackKey() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        harness.bridge.sendPreeditText("stale", to: harness.surfaceID)
        harness.view.keyEventInterpreterOverride = { _ in }

        harness.view.keyDown(with: makeIMEKeyEvent(characters: "x", keyCode: 7))

        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }

    @Test("CJK selected range is converted from UTF-16 to UTF-8 bytes")
    func cjkCursorUsesUTF8ByteOffset() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(cocxycore_terminal_preedit_cursor_bytes(state.terminal) == 3)
    }

    @Test("multiple commits are coalesced and a following preedit remains active")
    func multipleCallbacksPreserveCommittedAndMarkedText() async throws {
        let rawCat = try makeIMERawCatScript()
        defer { try? FileManager.default.removeItem(at: rawCat.rootDirectory) }
        let harness = try makeIMEViewHarness(command: rawCat.scriptURL.path)
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }
        try await waitUntil {
            FileManager.default.fileExists(atPath: rawCat.readyURL.path)
        }
        var deliveryCount = 0
        harness.bridge.inputDeliveryObserver = { surfaceID, event in
            guard surfaceID == harness.surfaceID, event == .delivered else { return }
            deliveryCount += 1
        }

        harness.view.keyEventInterpreterOverride = { [weak view = harness.view] _ in
            view?.insertText("`", replacementRange: NSRange(location: NSNotFound, length: 0))
            view?.insertText("q", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        harness.view.keyDown(with: makeIMEKeyEvent(characters: "`q", keyCode: 12))

        try await waitUntil { output.data.range(of: Data("`q".utf8)) != nil }
        #expect(deliveryCount == 1)
        output.data.removeAll()

        harness.view.setMarkedText(
            "x",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.keyEventInterpreterOverride = { [weak view = harness.view] _ in
            view?.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
            view?.setMarkedText(
                "y",
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
        harness.view.keyDown(with: makeIMEKeyEvent(characters: "x", keyCode: 7))

        try await waitUntil { output.data.range(of: Data("x".utf8)) != nil }
        let snapshot = try #require(harness.bridge.preeditSnapshot(for: harness.surfaceID))
        #expect(deliveryCount == 2)
        #expect(harness.view.hasMarkedText())
        #expect(snapshot.active)
        #expect(snapshot.text == "y")
    }

    @Test("Tab and Backspace remain owned by an active input method")
    func tabAndBackspaceDoNotLeakDuringComposition() throws {
        let harness = try makeIMEViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        var deliveryCount = 0
        harness.bridge.inputDeliveryObserver = { surfaceID, _ in
            guard surfaceID == harness.surfaceID else { return }
            deliveryCount += 1
        }
        harness.view.setMarkedText(
            "候補",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.view.keyEventInterpreterOverride = { [weak view = harness.view] event in
            if event.keyCode == 51 {
                view?.setMarkedText(
                    "候",
                    selectedRange: NSRange(location: 1, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            }
        }

        harness.view.keyDown(with: makeIMEKeyEvent(characters: "\t", keyCode: 48))
        #expect(deliveryCount == 0)
        #expect(harness.view.hasMarkedText())

        harness.view.keyDown(with: makeIMEKeyEvent(characters: "\u{7F}", keyCode: 51))
        let snapshot = try #require(harness.bridge.preeditSnapshot(for: harness.surfaceID))
        #expect(deliveryCount == 0)
        #expect(snapshot.active)
        #expect(snapshot.text == "候")
    }

    @Test("Return submits once and Shift-Return inserts one newline")
    func returnCallbacksDoNotDuplicateTerminalInput() async throws {
        let rawCat = try makeIMERawCatScript()
        defer { try? FileManager.default.removeItem(at: rawCat.rootDirectory) }
        let harness = try makeIMEViewHarness(command: rawCat.scriptURL.path)
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }
        try await waitUntil {
            FileManager.default.fileExists(atPath: rawCat.readyURL.path)
        }
        var submitCount = 0
        harness.view.onUserInputSubmitted = { submitCount += 1 }
        harness.view.keyEventInterpreterOverride = { [weak view = harness.view] _ in
            view?.insertNewline(nil)
        }

        harness.view.keyDown(with: makeIMEKeyEvent(characters: "\r", keyCode: 36))
        try await waitUntil { output.data.contains(0x0D) }
        #expect(output.data == Data([0x0D]))
        #expect(submitCount == 1)

        output.data.removeAll()
        harness.view.keyDown(with: makeIMEKeyEvent(
            characters: "\r",
            modifiers: [.shift],
            keyCode: 36
        ))
        try await waitUntil { output.data.contains(0x0A) }
        #expect(output.data == Data([0x0A]))
        #expect(submitCount == 1)
    }
}

private func makeIMEKeyEvent(
    characters: String,
    charactersIgnoringModifiers: String? = nil,
    modifiers: NSEvent.ModifierFlags = [],
    keyCode: UInt16
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
        isARepeat: false,
        keyCode: keyCode
    )!
}

private func makeIMERawCatScript() throws -> (
    rootDirectory: URL,
    scriptURL: URL,
    readyURL: URL
) {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-ime-raw-cat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    let scriptURL = rootDirectory.appendingPathComponent("raw-cat.sh")
    let readyURL = rootDirectory.appendingPathComponent("ready")
    try """
    #!/bin/sh
    stty raw -echo
    : > '\(readyURL.path)'
    exec /bin/cat
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: scriptURL.path
    )
    return (rootDirectory, scriptURL, readyURL)
}
