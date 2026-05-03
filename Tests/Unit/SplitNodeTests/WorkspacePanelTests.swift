// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkspacePanelTests.swift - Tests for workspace panel type support.

import XCTest
@testable import CocxyTerminal

// MARK: - PanelType Tests

@MainActor
final class PanelTypeTests: XCTestCase {

    // MARK: - PanelType Enum

    func testPanelTypeRawValues() {
        XCTAssertEqual(PanelType.terminal.rawValue, "terminal")
        XCTAssertEqual(PanelType.browser.rawValue, "browser")
        XCTAssertEqual(PanelType.markdown.rawValue, "markdown")
        XCTAssertEqual(PanelType.editor.rawValue, "editor")
        XCTAssertEqual(PanelType.notebook.rawValue, "notebook")
        XCTAssertEqual(PanelType.workflow.rawValue, "workflow")
    }

    func testPanelTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original = PanelType.browser
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PanelType.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - PanelInfo

    func testPanelInfoTerminalDefault() {
        let info = PanelInfo.terminal
        XCTAssertEqual(info.type, .terminal)
        XCTAssertNil(info.initialURL)
        XCTAssertNil(info.filePath)
    }

    func testPanelInfoBrowserWithDefaultURL() {
        let info = PanelInfo.browser()
        XCTAssertEqual(info.type, .browser)
        XCTAssertEqual(info.initialURL?.absoluteString, "http://localhost:3000")
    }

    func testPanelInfoBrowserWithCustomURL() {
        let url = URL(string: "http://localhost:8080")!
        let info = PanelInfo.browser(url: url)
        XCTAssertEqual(info.type, .browser)
        XCTAssertEqual(info.initialURL, url)
    }

    func testPanelInfoMarkdownWithPath() {
        let path = URL(fileURLWithPath: "/tmp/README.md")
        let info = PanelInfo.markdown(path: path)
        XCTAssertEqual(info.type, .markdown)
        XCTAssertEqual(info.filePath, path)
    }

    func testPanelInfoEditorWithPath() {
        let path = URL(fileURLWithPath: "/tmp/App.swift")
        let info = PanelInfo.editor(path: path)
        XCTAssertEqual(info.type, .editor)
        XCTAssertEqual(info.filePath, path)
    }

    func testPanelInfoNotebookWithPath() {
        let path = URL(fileURLWithPath: "/tmp/demo.cocxynb")
        let info = PanelInfo.notebook(path: path)
        XCTAssertEqual(info.type, .notebook)
        XCTAssertEqual(info.filePath, path)
    }

    func testPanelInfoWorkflowWithPath() {
        let path = URL(fileURLWithPath: "/tmp/ci.toml")
        let info = PanelInfo.workflow(path: path)
        XCTAssertEqual(info.type, .workflow)
        XCTAssertEqual(info.filePath, path)
    }
}

// MARK: - SplitManager Panel Type Tests

@MainActor
final class SplitManagerPanelTests: XCTestCase {

    // MARK: - Panel Type Tracking

    func testDefaultPanelTypeIsTerminal() {
        let manager = SplitManager()
        let leaves = manager.rootNode.allLeafIDs()
        let contentID = leaves[0].terminalID

        XCTAssertEqual(manager.panelType(for: contentID), .terminal)
    }

    func testSplitFocusedDefaultsToTerminal() {
        let manager = SplitManager()
        let newID = manager.splitFocused(direction: .horizontal)

        XCTAssertNotNil(newID)
        XCTAssertEqual(manager.panelType(for: newID!), .terminal)
        XCTAssertTrue(manager.panelTypes.isEmpty,
                      "Terminal panels should not be stored in panelTypes map")
    }

    func testSplitFocusedWithBrowserTracksType() {
        let manager = SplitManager()
        let newID = manager.splitFocusedWithPanel(
            direction: .horizontal,
            panel: .browser()
        )

        XCTAssertNotNil(newID)
        XCTAssertEqual(manager.panelType(for: newID!), .browser)
        XCTAssertNotNil(manager.panelTypes[newID!])
    }

    func testSplitFocusedWithMarkdownTracksType() {
        let manager = SplitManager()
        let path = URL(fileURLWithPath: "/tmp/README.md")
        let newID = manager.splitFocusedWithPanel(
            direction: .vertical,
            panel: .markdown(path: path)
        )

        XCTAssertNotNil(newID)
        XCTAssertEqual(manager.panelType(for: newID!), .markdown)
        let info = manager.panelInfo(for: newID!)
        XCTAssertEqual(info.filePath, path)
    }

    func testSplitFocusedWithEditorTracksType() {
        let manager = SplitManager()
        let path = URL(fileURLWithPath: "/tmp/App.swift")
        let newID = manager.splitFocusedWithPanel(
            direction: .vertical,
            panel: .editor(path: path)
        )

        XCTAssertNotNil(newID)
        XCTAssertEqual(manager.panelType(for: newID!), .editor)
        let info = manager.panelInfo(for: newID!)
        XCTAssertEqual(info.filePath, path)
    }

    func testSplitFocusedWithNotebookTracksType() {
        let manager = SplitManager()
        let path = URL(fileURLWithPath: "/tmp/demo.cocxynb")
        let newID = manager.splitFocusedWithPanel(
            direction: .vertical,
            panel: .notebook(path: path)
        )

        XCTAssertNotNil(newID)
        XCTAssertEqual(manager.panelType(for: newID!), .notebook)
        let info = manager.panelInfo(for: newID!)
        XCTAssertEqual(info.filePath, path)
    }

    func testSplitFocusedWithWorkflowTracksType() {
        let manager = SplitManager()
        let path = URL(fileURLWithPath: "/tmp/ci.toml")
        let newID = manager.splitFocusedWithPanel(
            direction: .vertical,
            panel: .workflow(path: path)
        )

        XCTAssertNotNil(newID)
        XCTAssertEqual(manager.panelType(for: newID!), .workflow)
        let info = manager.panelInfo(for: newID!)
        XCTAssertEqual(info.filePath, path)
    }

    func testCloseFocusedCleansPanelType() {
        let manager = SplitManager()
        let browserID = manager.splitFocusedWithPanel(
            direction: .horizontal,
            panel: .browser()
        )

        XCTAssertNotNil(browserID)
        XCTAssertEqual(manager.panelType(for: browserID!), .browser)

        // Focus is on the browser pane (the new one), close it.
        manager.closeFocused()

        XCTAssertEqual(manager.rootNode.leafCount, 1)
        XCTAssertNil(manager.panelTypes[browserID!],
                     "Panel type should be removed after closing")
    }

    func testMultiplePanelTypes() {
        let manager = SplitManager()

        // Split with browser.
        let browserID = manager.splitFocusedWithPanel(
            direction: .horizontal,
            panel: .browser()
        )
        XCTAssertNotNil(browserID)

        // Focus back to original terminal and split with markdown.
        let leaves = manager.rootNode.allLeafIDs()
        let terminalLeaf = leaves.first { $0.terminalID != browserID }
        if let leaf = terminalLeaf {
            manager.focusLeaf(id: leaf.leafID)
        }

        let mdID = manager.splitFocusedWithPanel(
            direction: .vertical,
            panel: PanelInfo(type: .markdown)
        )
        XCTAssertNotNil(mdID)

        XCTAssertEqual(manager.rootNode.leafCount, 3)
        XCTAssertEqual(manager.panelType(for: browserID!), .browser)
        XCTAssertEqual(manager.panelType(for: mdID!), .markdown)
    }

    func testSplitWithPanelRespectsMaxPaneCount() {
        let manager = SplitManager()

        // Fill up to max pane count.
        for _ in 1..<SplitManager.maxPaneCount {
            manager.splitFocusedWithPanel(
                direction: .horizontal,
                panel: .browser()
            )
        }

        XCTAssertEqual(manager.rootNode.leafCount, SplitManager.maxPaneCount)

        // One more should return nil and not increase count.
        let overflowID = manager.splitFocusedWithPanel(
            direction: .horizontal,
            panel: .browser()
        )
        XCTAssertNil(overflowID, "Splitting beyond max pane count should return nil")
        XCTAssertEqual(manager.rootNode.leafCount, SplitManager.maxPaneCount)
    }

    func testPanelInfoForUnregisteredIDReturnsTerminal() {
        let manager = SplitManager()
        let randomID = UUID()

        XCTAssertEqual(manager.panelInfo(for: randomID), .terminal)
    }

    // MARK: - SplitKeyboardAction with Panels

    func testHandleSplitActionWithBrowser() {
        let manager = SplitManager()
        let initialCount = manager.rootNode.leafCount

        manager.handleSplitAction(.splitWithBrowser)

        XCTAssertEqual(manager.rootNode.leafCount, initialCount + 1)
        // The new pane should be a browser.
        let leaves = manager.rootNode.allLeafIDs()
        let browserLeaves = leaves.filter { manager.panelType(for: $0.terminalID) == .browser }
        XCTAssertEqual(browserLeaves.count, 1)
    }
}
