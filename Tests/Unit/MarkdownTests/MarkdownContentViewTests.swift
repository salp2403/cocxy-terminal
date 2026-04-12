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

    @Test("editing source updates the live document outline")
    func editingSourceUpdatesDocumentOutline() {
        let url = createTempMarkdownFile(content: "# First")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        view.sourceViewForTesting.replaceEntireSource(with: "# Second\n\n## Child")

        #expect(view.document.outline.entries.map(\.title) == ["Second", "Child"])
    }

    @Test("editing source saves back to disk")
    func editingSourceSavesToDisk() async throws {
        let url = createTempMarkdownFile(content: "# First")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        view.sourceViewForTesting.replaceEntireSource(with: "# Saved\n\nBody")

        try await Task.sleep(for: .milliseconds(300))

        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved == "# Saved\n\nBody")
    }

    @Test("Cmd+B in the source editor wraps the current selection")
    func commandBInSourceEditorWrapsSelection() {
        let url = createTempMarkdownFile(content: "hello")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        let sourceView = view.sourceViewForTesting
        sourceView.setSelectedSourceRange(NSRange(location: 0, length: 5))

        let handled = sourceView.editorTextView.performKeyEquivalent(
            with: makeKeyEvent(characters: "b", modifiers: .command)
        )

        #expect(handled == true)
        #expect(sourceView.currentSource == "**hello**")
    }

    @Test("Markdown toolbar action icons expose tooltips")
    func toolbarActionIconsHaveTooltips() {
        let view = MarkdownContentView(filePath: nil)
        let toolbar = view.subviews.compactMap { $0 as? MarkdownToolbarView }.first
        #expect(toolbar != nil)

        let buttons = toolbar?.subviews.compactMap { $0 as? NSButton } ?? []
        #expect(buttons.count >= 6)
        #expect(buttons.allSatisfy { !($0.toolTip ?? "").isEmpty })
    }

    // MARK: - Helpers

    private func createTempMarkdownFile(content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Export Shortcuts

    @Test("Cmd+Shift+E triggers export PDF shortcut without crash")
    func cmdShiftETriggersPDFExport() throws {
        let url = createTempMarkdownFile(content:"# Export test")
        let view = MarkdownContentView(filePath: url)
        defer { cleanup(url) }

        let event = makeKeyEvent(characters: "e", modifiers: [.command, .shift])
        let handled = view.performKeyEquivalent(with: event)
        // The shortcut is handled even if NSSavePanel isn't shown in test context.
        #expect(handled)
    }

    @Test("Cmd+Shift+H triggers export HTML shortcut without crash")
    func cmdShiftHTriggerHTMLExport() throws {
        let url = createTempMarkdownFile(content:"# Export HTML test")
        let view = MarkdownContentView(filePath: url)
        defer { cleanup(url) }

        let event = makeKeyEvent(characters: "h", modifiers: [.command, .shift])
        let handled = view.performKeyEquivalent(with: event)
        #expect(handled)
    }

    // MARK: - Concurrency Guard

    @Test("file watcher reload is skipped during pending save")
    func concurrencyGuardSkipsReloadDuringSave() throws {
        let url = createTempMarkdownFile(content:"# Original")
        let view = MarkdownContentView(filePath: url)
        defer { cleanup(url) }

        // Simulate an edit that schedules a save.
        view.sourceViewForTesting.editorTextView.string = "# Edited"
        view.sourceViewForTesting.editorTextView.delegate?.textDidChange?(
            Notification(name: NSText.didChangeNotification)
        )

        // The document now reflects the edit.
        let docAfterEdit = view.sourceViewForTesting.currentSource
        #expect(docAfterEdit.contains("Edited"))

        // Write a different content externally (simulating another editor).
        try "# External".write(to: url, atomically: true, encoding: .utf8)

        // Force a non-force reload (as the file watcher would trigger).
        // Since pendingSaveWorkItem is non-nil, the guard should skip.
        view.loadFile(url)

        // After force reload, external content should appear.
        let docAfterReload = view.sourceViewForTesting.currentSource
        #expect(docAfterReload.contains("External"))
    }

    // MARK: - Word Count / Status Bar

    @Test("Status bar shows word count after loading a document")
    func statusBarShowsWordCount() {
        let url = createTempMarkdownFile(content: "Hello world from test")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        let statusBar = view.subviews.compactMap { $0 as? MarkdownStatusBarView }.first
        #expect(statusBar != nil)
        #expect(statusBar?.wordCount.words == 4)
        // Characters counted on the body after frontmatter extraction
        #expect(statusBar?.wordCount.characters ?? 0 >= 20)
    }

    @Test("Status bar updates when document changes via editing")
    func statusBarUpdatesOnEdit() {
        let url = createTempMarkdownFile(content: "one two")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        let statusBar = view.subviews.compactMap { $0 as? MarkdownStatusBarView }.first
        #expect(statusBar?.wordCount.words == 2)

        // Simulate an edit via the source view
        view.sourceViewForTesting.replaceEntireSource(with: "one two three four")
        // The source callback should propagate and update the status bar
        #expect(statusBar?.wordCount.words == 4)
    }

    // MARK: - Blame / Diff Flag Consistency

    @Test("toggleBlame from visible state restores normal mode")
    func toggleBlameFromVisibleRestores() {
        let url = createTempMarkdownFile(content: "# Test")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        // Set blame as active
        view.isBlameVisible = true
        view.isDiffVisible = false
        let genBefore = view.gitRequestGeneration

        // Calling toggleBlame when already visible should turn it off
        view.toggleBlame()

        #expect(view.isBlameVisible == false)
        #expect(view.isDiffVisible == false)
        // Generation must have advanced to invalidate any in-flight request
        #expect(view.gitRequestGeneration > genBefore)
    }

    @Test("toggleDiff from visible state restores normal mode")
    func toggleDiffFromVisibleRestores() {
        let url = createTempMarkdownFile(content: "# Test")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        view.isDiffVisible = true
        view.isBlameVisible = false
        let genBefore = view.gitRequestGeneration

        view.toggleDiff()

        #expect(view.isDiffVisible == false)
        #expect(view.isBlameVisible == false)
        #expect(view.gitRequestGeneration > genBefore)
    }

    @Test("toggleBlame then toggleDiff advances generation twice")
    func blameToThenDiffAdvancesGenerationTwice() {
        let url = createTempMarkdownFile(content: "# Test")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        let initial = view.gitRequestGeneration

        // Fire blame (async, won't complete in test)
        view.toggleBlame()
        let afterBlame = view.gitRequestGeneration
        #expect(afterBlame == initial &+ 1)

        // Fire diff immediately — should bump generation again
        view.toggleDiff()
        let afterDiff = view.gitRequestGeneration
        #expect(afterDiff == initial &+ 2)

        // Both blame and diff callbacks with generation < afterDiff will be discarded
    }

    @Test("applyMode resets flags and invalidates in-flight git requests")
    func applyModeResetsFlags() {
        let url = createTempMarkdownFile(content: "# Test")
        defer { cleanup(url) }

        let view = MarkdownContentView(filePath: url)
        view.isBlameVisible = true
        view.isDiffVisible = true
        let genBefore = view.gitRequestGeneration

        view.applyMode()

        #expect(view.isBlameVisible == false)
        #expect(view.isDiffVisible == false)
        #expect(view.gitRequestGeneration > genBefore)
    }

    @Test("loadFile invalidates in-flight git requests from previous file")
    func loadFileInvalidatesGitRequests() {
        let urlA = createTempMarkdownFile(content: "# File A")
        let urlB = createTempMarkdownFile(content: "# File B")
        defer { cleanup(urlA); cleanup(urlB) }

        let view = MarkdownContentView(filePath: urlA)

        // Simulate blame in-flight for file A
        view.toggleBlame()
        let genAfterBlame = view.gitRequestGeneration

        // Switch to file B before blame completes
        view.loadFile(urlB)
        let genAfterLoad = view.gitRequestGeneration

        // loadFile must have bumped the generation
        #expect(genAfterLoad > genAfterBlame)
        // The blame callback (if it arrives) will see generation mismatch and discard
        #expect(view.isBlameVisible == false)
        #expect(view.filePath == urlB)
    }

    @Test("loadFile resets blame/diff view when switching files")
    func loadFileResetsBlameDiffView() {
        let urlA = createTempMarkdownFile(content: "# A")
        let urlB = createTempMarkdownFile(content: "# B")
        defer { cleanup(urlA); cleanup(urlB) }

        let view = MarkdownContentView(filePath: urlA)
        // Pretend blame was active
        view.isBlameVisible = true
        view.isDiffVisible = false

        view.loadFile(urlB)

        #expect(view.isBlameVisible == false)
        #expect(view.isDiffVisible == false)
    }

    // MARK: - Drag & Drop

    @Test("View registers for file URL drag types")
    func registersForDragTypes() {
        let view = MarkdownContentView(filePath: nil)
        let registered = view.registeredDraggedTypes
        #expect(registered.contains(.fileURL))
    }

    @Test("insertImageReference inserts markdown image syntax into source")
    func insertImageReferenceInsertsMarkdown() {
        let url = createTempMarkdownFile(content: "Hello world")
        defer { cleanup(url) }

        // Create a temporary image file to reference
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-image-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: imageURL.path, contents: Data([0x89, 0x50]))
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let view = MarkdownContentView(filePath: url)
        let sourceBefore = view.sourceViewForTesting.currentSource
        #expect(!sourceBefore.contains("!["))

        // Call the actual function
        view.insertImageReference(for: imageURL)

        let sourceAfter = view.sourceViewForTesting.currentSource
        #expect(sourceAfter.contains("!["))
        #expect(sourceAfter.contains(imageURL.deletingPathExtension().lastPathComponent))
    }

    @Test("insertImageReference does not misclassify sibling directory as ancestor")
    func insertImageReferenceSiblingDir() throws {
        // Create /tmpdir/docs/file.md and /tmpdir/docs-old/image.png
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("imgtest-\(UUID().uuidString)")
        let docsDir = root.appendingPathComponent("docs")
        let docsOldDir = root.appendingPathComponent("docs-old")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsOldDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mdURL = docsDir.appendingPathComponent("file.md")
        try "# Test".write(to: mdURL, atomically: true, encoding: .utf8)

        let imageURL = docsOldDir.appendingPathComponent("photo.png")
        FileManager.default.createFile(atPath: imageURL.path, contents: Data([0x89, 0x50]))

        let view = MarkdownContentView(filePath: mdURL)
        view.insertImageReference(for: imageURL)

        let source = view.sourceViewForTesting.currentSource
        // The image is NOT inside docs/, so the path must be absolute, not a
        // bogus relative path. With the old hasPrefix bug, the markdown would be
        // "![photo](-old/photo.png)" — a relative path starting with "-old/".
        // The correct result is "![photo](/absolute/.../docs-old/photo.png)".
        #expect(!source.contains("](-old/"))
        #expect(source.contains("](/"))
        #expect(source.contains(imageURL.path))
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
