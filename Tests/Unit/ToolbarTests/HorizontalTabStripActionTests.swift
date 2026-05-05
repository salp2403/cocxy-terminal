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

    func testOnAddAIEditHistoryCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddAIEditHistory)
    }

    func testOnAddTemplatesCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddTemplates)
    }

    func testOnAddMacrosCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddMacros)
    }

    func testOnAddDBCloudCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onAddDBCloud)
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

    func testOnOpenAIEditHistoryCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenAIEditHistory)
    }

    func testOnOpenTemplatesCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenTemplates)
    }

    func testOnOpenMacrosCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenMacros)
    }

    func testOnOpenDBCloudCallbackDefaultIsNil() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        XCTAssertNil(strip.onOpenDBCloud)
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

    func testOnAddAIEditHistoryCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddAIEditHistory = { called = true }
        strip.onAddAIEditHistory?()
        XCTAssertTrue(called)
    }

    func testOnAddTemplatesCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddTemplates = { called = true }
        strip.onAddTemplates?()
        XCTAssertTrue(called)
    }

    func testOnAddMacrosCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddMacros = { called = true }
        strip.onAddMacros?()
        XCTAssertTrue(called)
    }

    func testOnAddDBCloudCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onAddDBCloud = { called = true }
        strip.onAddDBCloud?()
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

    func testOnOpenAIEditHistoryCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenAIEditHistory = { called = true }
        strip.onOpenAIEditHistory?()
        XCTAssertTrue(called)
    }

    func testOnOpenTemplatesCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenTemplates = { called = true }
        strip.onOpenTemplates?()
        XCTAssertTrue(called)
    }

    func testOnOpenMacrosCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenMacros = { called = true }
        strip.onOpenMacros?()
        XCTAssertTrue(called)
    }

    func testOnOpenDBCloudCallbackFires() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        var called = false
        strip.onOpenDBCloud = { called = true }
        strip.onOpenDBCloud?()
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

    func testUpdateActionIconsForTerminalPanelShowsTwelveActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let actionButtons = findActionButtons(in: strip)
        XCTAssertEqual(actionButtons.count, 12)
    }

    func testUpdateActionIconsForTerminalWithCloseShowsThirteenActions() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: true)

        let actionButtons = findActionButtons(in: strip)
        XCTAssertEqual(actionButtons.count, 13)
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

    func testTerminalActionIconsIncludeAIEditHistoryButton() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let historyButton = findActionButtons(in: strip).first {
            $0.accessibilityLabel() == "action:openAIEditHistory"
        }

        XCTAssertEqual(historyButton?.toolTip, "Open Edit History")
    }

    func testTerminalActionIconsIncludeTemplatesButton() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let templatesButton = findActionButtons(in: strip).first {
            $0.accessibilityLabel() == "action:openTemplates"
        }

        XCTAssertEqual(templatesButton?.toolTip, "Open Templates")
    }

    func testTerminalActionIconsIncludeMacrosButton() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let macrosButton = findActionButtons(in: strip).first {
            $0.accessibilityLabel() == "action:openMacros"
        }

        XCTAssertEqual(macrosButton?.toolTip, "Open Macros")
    }

    func testTerminalActionIconsIncludeDBCloudButton() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(panelType: .terminal, canClose: false)

        let dbCloudButton = findActionButtons(in: strip).first {
            $0.accessibilityLabel() == "action:openDBCloud"
        }

        XCTAssertEqual(dbCloudButton?.toolTip, "Open DB/Cloud Helpers")
    }

    func testUpdateActionIconsReplacesOldButtons() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))

        strip.updateActionIcons(panelType: .terminal, canClose: true)
        let terminalButtons = findActionButtons(in: strip)
        XCTAssertEqual(terminalButtons.count, 13)

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

    func testPaneCreationControlsDisableAtMaxPaneCount() {
        let strip = HorizontalTabStripView(frame: NSRect(x: 0, y: 0, width: 800, height: 30))
        strip.updateActionIcons(
            panelType: .terminal,
            canClose: true,
            canAddPane: false,
            maxPaneCount: 4
        )

        let buttons = findActionButtons(in: strip)
        let splitButton = buttons.first { $0.accessibilityLabel() == "action:splitSideBySide" }
        let notebookButton = buttons.first { $0.accessibilityLabel() == "action:openNotebook" }
        let closeButton = buttons.first { $0.accessibilityLabel() == "action:closePanel" }
        let addButton = findAddPanelButton(in: strip)

        XCTAssertFalse(splitButton?.isEnabled ?? true)
        XCTAssertEqual(splitButton?.toolTip, "Maximum of 4 panes reached")
        XCTAssertFalse(notebookButton?.isEnabled ?? true)
        XCTAssertEqual(notebookButton?.toolTip, "Maximum of 4 panes reached")
        XCTAssertTrue(closeButton?.isEnabled ?? false)
        XCTAssertFalse(addButton?.isEnabled ?? true)
        XCTAssertEqual(addButton?.toolTip, "Maximum of 4 panes reached")
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

    private func findAddPanelButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityLabel() == "Add Panel"
            || button.accessibilityLabel() == "Maximum of 4 panes reached" {
            return button
        }
        for child in view.subviews {
            if let match = findAddPanelButton(in: child) {
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
