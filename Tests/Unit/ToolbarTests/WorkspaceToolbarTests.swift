// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkspaceToolbarTests.swift - Tests for workspace toolbar controller.

import XCTest
@testable import CocxyTerminal

@MainActor
final class WorkspaceToolbarTests: XCTestCase {

    // MARK: - Panel Tab Info

    func testPanelTabInfoTerminalSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .terminal, title: "Terminal 1", isFocused: true
        )
        XCTAssertEqual(tab.symbolName, "terminal")
    }

    func testPanelTabInfoBrowserSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .browser, title: "Browser", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "globe")
    }

    func testPanelTabInfoMarkdownSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .markdown, title: "Markdown", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "doc.text")
    }

    func testPanelTabInfoEditorSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .editor, title: "Editor", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "doc.plaintext")
    }

    func testPanelTabInfoNotebookSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .notebook, title: "Notebook", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "book")
    }

    func testPanelTabInfoWorkflowSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .workflow, title: "Workflow", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "arrow.triangle.branch")
    }

    func testPanelTabInfoSessionReplaySymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .sessionReplay, title: "Replay", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "record.circle")
    }

    func testPanelTabInfoAIEditHistorySymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .aiEditHistory, title: "Edit History", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "clock.arrow.circlepath")
    }

    func testPanelTabInfoTemplatesSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .templates, title: "Templates", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "square.grid.2x2")
    }

    func testPanelTabInfoMacrosSymbol() {
        let tab = PanelTabInfo(
            leafID: UUID(), contentID: UUID(),
            panelType: .macros, title: "Macros", isFocused: false
        )
        XCTAssertEqual(tab.symbolName, "keyboard")
    }

    // MARK: - Toolbar Visibility

    func testToolbarVisibleWithSinglePane() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()

        controller.update(splitManager: manager)

        XCTAssertTrue(controller.isVisible,
                      "Toolbar should always be visible, even with a single pane")
        XCTAssertEqual(controller.panelTabs.count, 1)
    }

    func testToolbarVisibleWithMultiplePanes() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        controller.update(splitManager: manager)

        XCTAssertTrue(controller.isVisible,
                      "Toolbar should be visible with multiple panes")
        XCTAssertEqual(controller.panelTabs.count, 2)
    }

    func testToolbarStaysVisibleWhenBackToSinglePane() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()

        // Split then close — toolbar stays visible.
        manager.splitFocused(direction: .horizontal)
        controller.update(splitManager: manager)
        XCTAssertTrue(controller.isVisible)

        manager.closeFocused()
        controller.update(splitManager: manager)
        XCTAssertTrue(controller.isVisible,
                      "Toolbar should remain visible even with single pane")
        XCTAssertEqual(controller.panelTabs.count, 1)
    }

    // MARK: - Panel Tab Content

    func testPanelTabsReflectSplitState() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()

        // Add a browser panel.
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .browser())

        controller.update(splitManager: manager)

        XCTAssertEqual(controller.panelTabs.count, 2)

        let terminalTabs = controller.panelTabs.filter { $0.panelType == .terminal }
        let browserTabs = controller.panelTabs.filter { $0.panelType == .browser }
        XCTAssertEqual(terminalTabs.count, 1)
        XCTAssertEqual(browserTabs.count, 1)
    }

    func testFocusedPanelIsMarked() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        controller.update(splitManager: manager)

        let focused = controller.panelTabs.filter { $0.isFocused }
        XCTAssertEqual(focused.count, 1, "Exactly one tab should be focused")
    }

    func testPanelTabTitles() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .browser())

        controller.update(splitManager: manager)

        let titles = controller.panelTabs.map { $0.title }
        XCTAssertTrue(titles.contains("Terminal 1"))
        XCTAssertTrue(titles.contains("Browser"))
    }

    func testPanelTabTitlesUseCustomPanelTitle() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        let contentID = manager.splitFocusedWithPanel(
            direction: .horizontal,
            panel: .subagent(id: "sub-1", sessionId: "session-1")
        )
        XCTAssertNotNil(contentID)
        manager.setPanelTitle(for: contentID!, title: "Research")

        controller.update(splitManager: manager)

        let subagentTabs = controller.panelTabs.filter { $0.panelType == .subagent }
        XCTAssertEqual(subagentTabs.count, 1)
        XCTAssertEqual(subagentTabs.first?.title, "Research")
    }

    func testPanelTabTitlesKeepCustomTitleWhenLocalizerChanges() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        let contentID = manager.splitFocusedWithPanel(
            direction: .horizontal,
            panel: .subagent(id: "sub-1", sessionId: "session-1")
        )
        XCTAssertNotNil(contentID)
        manager.setPanelTitle(for: contentID!, title: "Research")
        controller.update(splitManager: manager)

        controller.updateLocalizer(AppLocalizer(languagePreference: .spanish))

        let subagentTabs = controller.panelTabs.filter { $0.panelType == .subagent }
        XCTAssertEqual(subagentTabs.count, 1)
        XCTAssertEqual(subagentTabs.first?.title, "Research")
    }

    func testPanelTabTitlesLocalizeToSpanish() throws {
        let bundle = try XCTUnwrap(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window, localizer: localizer)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .browser())

        controller.update(splitManager: manager)

        let titles = controller.panelTabs.map(\.title)
        XCTAssertTrue(titles.contains("Terminal 1"))
        XCTAssertTrue(titles.contains("Navegador"))
        XCTAssertEqual(WorkspaceToolbarController.localizedAddPanel(using: localizer), "Agregar panel")
        XCTAssertEqual(
            WorkspaceToolbarController.localizedAddPanelTooltip(using: localizer),
            "Dividir con un panel nuevo"
        )
    }

    func testEditorPanelTabTitle() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .editor())

        controller.update(splitManager: manager)

        let editorTabs = controller.panelTabs.filter { $0.panelType == .editor }
        XCTAssertEqual(editorTabs.count, 1)
        XCTAssertEqual(editorTabs.first?.title, "Editor")
    }

    func testNotebookAndWorkflowPanelTabTitles() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .notebook())
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .workflow())

        controller.update(splitManager: manager)

        let titlesByType = Dictionary(uniqueKeysWithValues: controller.panelTabs.map { ($0.panelType, $0.title) })
        XCTAssertEqual(titlesByType[.notebook], "Notebook")
        XCTAssertEqual(titlesByType[.workflow], "Workflow")
    }

    func testSessionReplayPanelTabTitle() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .sessionReplay())

        controller.update(splitManager: manager)

        let replayTabs = controller.panelTabs.filter { $0.panelType == .sessionReplay }
        XCTAssertEqual(replayTabs.count, 1)
        XCTAssertEqual(replayTabs.first?.title, "Replay")
    }

    func testAIEditHistoryPanelTabTitle() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .aiEditHistory())

        controller.update(splitManager: manager)

        let historyTabs = controller.panelTabs.filter { $0.panelType == .aiEditHistory }
        XCTAssertEqual(historyTabs.count, 1)
        XCTAssertEqual(historyTabs.first?.title, "Edit History")
    }

    func testTemplatesPanelTabTitle() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .templates())

        controller.update(splitManager: manager)

        let templateTabs = controller.panelTabs.filter { $0.panelType == .templates }
        XCTAssertEqual(templateTabs.count, 1)
        XCTAssertEqual(templateTabs.first?.title, "Templates")
    }

    func testMacrosPanelTabTitle() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocusedWithPanel(direction: .horizontal, panel: .macros())

        controller.update(splitManager: manager)

        let macroTabs = controller.panelTabs.filter { $0.panelType == .macros }
        XCTAssertEqual(macroTabs.count, 1)
        XCTAssertEqual(macroTabs.first?.title, "Macros")
    }

    // MARK: - Callbacks

    func testPanelSelectedCallbackFires() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        controller.update(splitManager: manager)

        var selectedLeafID: UUID?
        controller.onPanelSelected = { leafID in
            selectedLeafID = leafID
        }

        // Simulate selection of first tab.
        let firstTab = controller.panelTabs[0]
        controller.onPanelSelected?(firstTab.leafID)

        XCTAssertEqual(selectedLeafID, firstTab.leafID)
    }

    func testHideForceHides() {
        let window = NSWindow()
        let controller = WorkspaceToolbarController(window: window)
        let manager = SplitManager()
        manager.splitFocused(direction: .horizontal)

        controller.update(splitManager: manager)
        XCTAssertTrue(controller.isVisible)

        controller.hide()
        XCTAssertFalse(controller.isVisible)
    }

    private func localizationBundle() -> Bundle? {
        Bundle(url: repositoryRoot().appendingPathComponent("Resources/Localization", isDirectory: true))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
