// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownContentViewTests.swift - Tests for the Clearly+ markdown viewer.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("MarkdownContentView", .serialized)
@MainActor
struct MarkdownContentViewTests {

    // MARK: - Initialization

    @Test("init with nil path sets filePath to nil")
    func initWithNilPath() {
        let view = MarkdownContentView(filePath: nil)
        #expect(view.filePath == nil)
    }

    @Test("init with valid path sets filePath")
    func initWithValidPath() {
        let url = createTempMarkdownFile(content: "# Hello")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        #expect(view.filePath == url)
    }

    @Test("init creates the toolbar, outline and content subviews")
    func initCreatesSubviews() {
        let view = MarkdownContentView(filePath: nil)
        // Toolbar + outline + content container
        #expect(view.subviews.count >= 3)
    }

    @Test("view uses layer-backed drawing")
    func layerBacking() {
        let view = MarkdownContentView(filePath: nil)
        #expect(view.wantsLayer == true)
    }

    // MARK: - File Loading

    @Test("loadFile updates filePath and parses content")
    func loadFileUpdatesPathAndDocument() {
        let url = createTempMarkdownFile(content: "# First\n\n## Second\n")
        defer { cleanup(url) }

        let view = MarkdownContentView()
        view.loadFile(url)

        #expect(view.filePath == url)
        #expect(view.document.outline.entries.count == 2)
        #expect(view.document.outline.entries[0].title == "First")
        #expect(view.document.outline.entries[1].title == "Second")
    }

    @Test("loadFile with invalid path does not crash and records error")
    func loadInvalidFile() {
        let view = MarkdownContentView()
        let badURL = URL(fileURLWithPath: "/nonexistent/path/to/file.md")
        view.loadFile(badURL)
        #expect(view.filePath == badURL)
        #expect(view.document.source.contains("Failed to load"))
    }

    @Test("loading multiple files replaces state")
    func loadMultipleFiles() {
        let url1 = createTempMarkdownFile(content: "# First")
        let url2 = createTempMarkdownFile(content: "# Second\n## Child")
        defer {
            cleanup(url1)
            cleanup(url2)
        }

        let view = MarkdownContentView()
        view.loadFile(url1)
        #expect(view.document.outline.entries.first?.title == "First")

        view.loadFile(url2)
        #expect(view.document.outline.entries.first?.title == "Second")
        #expect(view.document.outline.entries.count == 2)
    }

    // MARK: - Mode Switching

    @Test("mode defaults to source")
    func defaultModeIsSource() {
        let view = MarkdownContentView()
        #expect(view.mode == .source)
    }

    @Test("Cmd+2 switches to preview mode")
    func cmd2SwitchesToPreview() {
        let view = MarkdownContentView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let event = makeKeyEvent(characters: "2", modifiers: .command)
        view.keyDown(with: event)

        #expect(view.mode == .preview)
    }

    @Test("Cmd+3 switches to split mode")
    func cmd3SwitchesToSplit() {
        let view = MarkdownContentView()
        let event = makeKeyEvent(characters: "3", modifiers: .command)
        view.keyDown(with: event)
        #expect(view.mode == .split)
    }

    @Test("Cmd+1 returns to source mode")
    func cmd1ReturnsToSource() {
        let view = MarkdownContentView()
        view.keyDown(with: makeKeyEvent(characters: "2", modifiers: .command))
        #expect(view.mode == .preview)
        view.keyDown(with: makeKeyEvent(characters: "1", modifiers: .command))
        #expect(view.mode == .source)
    }

    // MARK: - Outline Toggle

    @Test("outline is visible by default")
    func outlineVisibleByDefault() {
        let view = MarkdownContentView()
        #expect(view.isOutlineVisible == true)
    }

    @Test("Cmd+Shift+O toggles outline visibility")
    func cmdShiftOTogglesOutline() {
        let view = MarkdownContentView()
        let event = makeKeyEvent(characters: "o", modifiers: [.command, .shift])

        view.keyDown(with: event)
        #expect(view.isOutlineVisible == false)

        view.keyDown(with: event)
        #expect(view.isOutlineVisible == true)
    }

    // MARK: - Helpers

    private func createTempMarkdownFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeKeyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }
}
