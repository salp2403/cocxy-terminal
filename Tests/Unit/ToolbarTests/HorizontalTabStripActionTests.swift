// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HorizontalTabStripActionTests.swift - Tests for contextual action icons on the tab strip.

import XCTest
@testable import CocxyTerminal

@MainActor
final class HorizontalTabStripActionTests: XCTestCase {

    // MARK: - Action Callback Wiring

    func testOnSplitSideBySideCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onSplitSideBySide)
    }

    func testOnSplitStackedCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onSplitStacked)
    }

    func testOnOpenBrowserCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenBrowser)
    }

    func testOnOpenMarkdownCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenMarkdown)
    }

    func testOnAddEditorCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddEditor)
    }

    func testOnAddNotebookCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddNotebook)
    }

    func testOnAddWorkflowCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddWorkflow)
    }

    func testOnAddSessionReplayCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddSessionReplay)
    }

    func testOnOpenEditorCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenEditor)
    }

    func testOnOpenNotebookCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenNotebook)
    }

    func testOnOpenWorkflowCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenWorkflow)
    }

    func testOnOpenSessionReplayCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenSessionReplay)
    }

    func testOnReloadCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onReload)
    }

    func testOnGoBackCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onGoBack)
    }

    func testOnGoForwardCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onGoForward)
    }

    func testOnClosePanelCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onClosePanel)
    }

    func testOnToggleThemeModeCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onToggleThemeMode)
    }

    // MARK: - Callback Invocation

    func testOnSplitSideBySideCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onSplitSideBySide = { called = true }
        strip.onSplitSideBySide?()
        XCTAssertTrue(called)
    }

    func testOnSplitStackedCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onSplitStacked = { called = true }
        strip.onSplitStacked?()
        XCTAssertTrue(called)
    }

    func testOnOpenBrowserCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenBrowser = { called = true }
        strip.onOpenBrowser?()
        XCTAssertTrue(called)
    }

    func testOnOpenMarkdownCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenMarkdown = { called = true }
        strip.onOpenMarkdown?()
        XCTAssertTrue(called)
    }

    func testOnAddEditorCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddEditor = { called = true }
        strip.onAddEditor?()
        XCTAssertTrue(called)
    }

    func testOnAddNotebookCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddNotebook = { called = true }
        strip.onAddNotebook?()
        XCTAssertTrue(called)
    }

    func testOnAddWorkflowCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddWorkflow = { called = true }
        strip.onAddWorkflow?()
        XCTAssertTrue(called)
    }

    func testOnAddSessionReplayCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddSessionReplay = { called = true }
        strip.onAddSessionReplay?()
        XCTAssertTrue(called)
    }

    func testOnOpenEditorCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenEditor = { called = true }
        strip.onOpenEditor?()
        XCTAssertTrue(called)
    }

    func testOnOpenNotebookCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenNotebook = { called = true }
        strip.onOpenNotebook?()
        XCTAssertTrue(called)
    }

    func testOnOpenWorkflowCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenWorkflow = { called = true }
        strip.onOpenWorkflow?()
        XCTAssertTrue(called)
    }

    func testOnOpenSessionReplayCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenSessionReplay = { called = true }
        strip.onOpenSessionReplay?()
        XCTAssertTrue(called)
    }

    func testOnReloadCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onReload = { called = true }
        strip.onReload?()
        XCTAssertTrue(called)
    }

    func testOnGoBackCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onGoBack = { called = true }
        strip.onGoBack?()
        XCTAssertTrue(called)
    }

    func testOnGoForwardCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onGoForward = { called = true }
        strip.onGoForward?()
        XCTAssertTrue(called)
    }

    func testOnClosePanelCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onClosePanel = { called = true }
        strip.onClosePanel?()
        XCTAssertTrue(called)
    }

    func testOnToggleThemeModeCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onToggleThemeMode = { called = true }
        findThemeModeButton(in: strip)?.performClick(nil)
        XCTAssertTrue(called)
    }

    func testThemeModeButtonTooltipTracksTargetMode() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        let button = findThemeModeButton(in: strip)

        strip.setThemeMode(isLight: false)
        XCTAssertEqual(button?.toolTip, "Switch to light theme")

        strip.setThemeMode(isLight: true)
        XCTAssertEqual(button?.toolTip, "Switch to dark theme")
    }

    // MARK: - Action Icons Update

    func testUpdateActionIconsForTerminalPanelShowsEightActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let actionButtons = findActionButtons(in: strip)
        // Terminal: Split Side by Side, Split Stacked, Browser, Markdown, Editor, Notebook, Workflow, Replay
        XCTAssertEqual(actionButtons.count, 8)
    }

    func testUpdateActionIconsForTerminalWithCloseShowsNineActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: true)

        let actionButtons = findActionButtons(in: strip)
        // Terminal: Split Side by Side, Split Stacked, Browser, Markdown, Editor, Notebook, Workflow, Replay, Close
        XCTAssertEqual(actionButtons.count, 9)
    }

    func testUpdateActionIconsForBrowserPanelShowsFiveActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .browser, canClose: false)

        let actionButtons = findActionButtons(in: strip)
        // Browser: Split Side by Side, Split Stacked, Back, Forward, Reload
        XCTAssertEqual(actionButtons.count, 5)
    }

    func testUpdateActionIconsForBrowserWithCloseShowsSixActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .browser, canClose: true)

        let actionButtons = findActionButtons(in: strip)
        // Browser: Split Side by Side, Split Stacked, Back, Forward, Reload, Close
        XCTAssertEqual(actionButtons.count, 6)
    }

    func testUpdateActionIconsForMarkdownPanelShowsTwoActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .markdown, canClose: false)

        let actionButtons = findActionButtons(in: strip)
        // Markdown: Split Side by Side, Split Stacked
        XCTAssertEqual(actionButtons.count, 2)
    }

    func testUpdateActionIconsForMarkdownWithCloseShowsThreeActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .markdown, canClose: true)

        let actionButtons = findActionButtons(in: strip)
        // Markdown: Split Side by Side, Split Stacked, Close
        XCTAssertEqual(actionButtons.count, 3)
    }

    func testUpdateActionIconsForEditorPanelShowsTwoActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .editor, canClose: false)

        let actionButtons = findActionButtons(in: strip)
        XCTAssertEqual(actionButtons.count, 2)
    }

    func testTerminalActionIconsIncludeEditorButton() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let editorButton = findActionButtons(in: strip).first {
            $0.accessibilityLabel() == "action:openEditor"
        }

        XCTAssertEqual(editorButton?.toolTip, "Open Text Editor")
    }

    func testTerminalActionIconsIncludeNotebookAndWorkflowButtons() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let buttons = findActionButtons(in: strip)
        let notebookButton = buttons.first { $0.accessibilityLabel() == "action:openNotebook" }
        let workflowButton = buttons.first { $0.accessibilityLabel() == "action:openWorkflow" }

        XCTAssertEqual(notebookButton?.toolTip, "Open Notebook")
        XCTAssertEqual(workflowButton?.toolTip, "Open Workflow")
    }

    func testTerminalActionIconsIncludeSessionReplayButton() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let replayButton = findActionButtons(in: strip).first {
            $0.accessibilityLabel() == "action:openSessionReplay"
        }

        XCTAssertEqual(replayButton?.toolTip, "Open Session Replay")
    }

    func testUpdateActionIconsReplacesOldButtons() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))

        strip.updateActionIcons(panelType: .terminal, canClose: true)
        let terminalButtons = findActionButtons(in: strip)
        XCTAssertEqual(terminalButtons.count, 9)

        strip.updateActionIcons(panelType: .browser, canClose: false)
        let browserButtons = findActionButtons(in: strip)
        XCTAssertEqual(browserButtons.count, 5)
    }

    func testActionButtonsHaveTooltips() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let actionButtons = findActionButtons(in: strip)
        for button in actionButtons {
            XCTAssertNotNil(button.toolTip, "Action button should have a tooltip")
            XCTAssertFalse(button.toolTip?.isEmpty ?? true, "Tooltip should not be empty")
        }
    }

    func testSplitActionTooltipsMatchVisualOrientation() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let splitButtons = findActionButtons(in: strip).prefix(2)

        XCTAssertEqual(splitButtons.map(\.toolTip), ["Split Side by Side", "Split Stacked"] as [String?])
        XCTAssertEqual(splitButtons.map { $0.accessibilityLabel() }, ["action:splitSideBySide", "action:splitStacked"])
    }

    func testCloseFocusedPaneActionUsesPaneSpecificTooltip() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: true)

        let closeButton = findActionButtons(in: strip).first {
            $0.accessibilityLabel() == "action:closePanel"
        }

        XCTAssertEqual(closeButton?.toolTip, "Close Focused Pane")
    }

    func testActionButtonsHaveAccessibilityLabels() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let actionButtons = findActionButtons(in: strip)
        for button in actionButtons {
            let label = button.accessibilityLabel()
            XCTAssertNotNil(label, "Action button should have an accessibility label")
            XCTAssertFalse(label?.isEmpty ?? true, "Accessibility label should not be empty")
        }
    }

    // MARK: - Helpers

    private func findActionButtons(in view: NSView) -> [NSButton] {
        var result: [NSButton] = []
        findActionButtonsRecursive(in: view, result: &result)
        return result
    }

    private func findThemeModeButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityLabel() == "Toggle light or dark theme" {
            return button
        }
        for child in view.subviews {
            if let match = findThemeModeButton(in: child) {
                return match
            }
        }
        return nil
    }

    private func findActionButtonsRecursive(in view: NSView, result: inout [NSButton]) {
        if let button = view as? NSButton,
           button.accessibilityLabel()?.hasPrefix("action:") == true {
            result.append(button)
        }
        for child in view.subviews {
            findActionButtonsRecursive(in: child, result: &result)
        }
    }
}
