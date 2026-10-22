// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartCopyMenuBuilderTests.swift - Tests for the engine-backed terminal menu.

import XCTest
@testable import CocxyTerminal

@MainActor
final class SmartCopyMenuBuilderTests: XCTestCase {
    func testURLActionUsesExactEngineDetection() throws {
        let content = detected(
            kind: .url,
            text: "https://cocxy.dev/docs",
            target: "https://cocxy.dev/docs"
        )
        var activated: TerminalDetectedContent?
        let menu = SmartCopyMenuBuilder.buildMenu(
            detectedContent: content,
            copyText: "selected",
            lineText: "line",
            clipboardService: MockClipboardService(),
            activate: {
                activated = $0
                return true
            }
        )

        let item = try XCTUnwrap(menu.items.first)
        XCTAssertEqual(item.title, "Open URL: https://cocxy.dev/docs")
        try XCTUnwrap(item.representedObject as? SmartCopyAction).execute()
        XCTAssertEqual(activated, content)
    }

    func testCopyOnlyDetectionWritesEngineTarget() throws {
        let clipboard = MockClipboardService()
        let menu = SmartCopyMenuBuilder.buildMenu(
            detectedContent: detected(
                kind: .email,
                text: "dev@cocxy.dev",
                target: "dev@cocxy.dev"
            ),
            copyText: "",
            lineText: "",
            clipboardService: clipboard
        )

        try XCTUnwrap(menu.items.first?.representedObject as? SmartCopyAction).execute()
        XCTAssertEqual(clipboard.read(), "dev@cocxy.dev")
    }

    func testStandardActionsKeepSelectionLineAndPasteSeparate() throws {
        let clipboard = MockClipboardService()
        var pasteCount = 0
        let menu = SmartCopyMenuBuilder.buildMenu(
            detectedContent: nil,
            copyText: "selected text",
            lineText: "  complete line  \n",
            clipboardService: clipboard,
            paste: { pasteCount += 1 }
        )

        let copy = try XCTUnwrap(menu.items.first { $0.title == "Copy" })
        let paste = try XCTUnwrap(menu.items.first { $0.title == "Paste" })
        let copyLine = try XCTUnwrap(menu.items.first { $0.title == "Copy Line" })

        try XCTUnwrap(copy.representedObject as? SmartCopyAction).execute()
        XCTAssertEqual(clipboard.read(), "selected text")
        try XCTUnwrap(copyLine.representedObject as? SmartCopyAction).execute()
        XCTAssertEqual(clipboard.read(), "  complete line  ")
        try XCTUnwrap(paste.representedObject as? SmartCopyAction).execute()
        XCTAssertEqual(pasteCount, 1)
    }

    func testOpenActionIsDisabledWithoutHostActivation() throws {
        let menu = SmartCopyMenuBuilder.buildMenu(
            detectedContent: detected(kind: .filePath, text: "App.swift:42:7", target: "App.swift"),
            copyText: "App.swift:42:7",
            lineText: "App.swift:42:7",
            clipboardService: MockClipboardService()
        )

        XCTAssertFalse(try XCTUnwrap(menu.items.first).isEnabled)
    }

    func testBuildMenuLocalizesSpanishTitles() throws {
        let bundle = try XCTUnwrap(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let menu = SmartCopyMenuBuilder.buildMenu(
            detectedContent: detected(
                kind: .ipAddress,
                text: "127.0.0.1",
                target: "127.0.0.1"
            ),
            copyText: "selected",
            lineText: "line",
            clipboardService: MockClipboardService(),
            paste: {},
            localizer: spanish
        )

        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains("Copiar dirección IP: 127.0.0.1"))
        XCTAssertTrue(titles.contains("Copiar"))
        XCTAssertTrue(titles.contains("Pegar"))
        XCTAssertTrue(titles.contains("Copiar línea"))
    }

    private func detected(
        kind: TerminalDetectedContentKind,
        text: String,
        target: String
    ) -> TerminalDetectedContent {
        TerminalDetectedContent(
            kind: kind,
            text: text,
            target: target,
            startRow: 0,
            startColumn: 0,
            endRow: 0,
            endColumn: UInt16(clamping: max(0, text.utf8.count - 1)),
            line: kind == .filePath ? 42 : nil,
            column: kind == .filePath ? 7 : nil,
            isExplicitHyperlink: kind == .hyperlink
        )
    }
}

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}
