// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AdaptivePanelToolbarSwiftTestingTests.swift - Compact split-panel toolbar contracts.

import Testing
@testable import CocxyTerminal

@Suite("Adaptive panel toolbar")
struct AdaptivePanelToolbarSwiftTestingTests {
    @Test("compact split panes switch actions to icon-only before labels truncate")
    func compactSplitPanesUseIconOnlyActions() {
        #expect(AdaptivePanelToolbarPresentation.resolve(width: 280) == .init(
            usesCompactActions: true,
            showsStatus: false
        ))
        #expect(AdaptivePanelToolbarPresentation.resolve(width: 320) == .init(
            usesCompactActions: true,
            showsStatus: true
        ))
    }

    @Test("wide split panes keep action labels and status text visible")
    func wideSplitPanesKeepLabelsAndStatus() {
        #expect(AdaptivePanelToolbarPresentation.resolve(width: 420) == .init(
            usesCompactActions: false,
            showsStatus: true
        ))
    }

    @Test("editor result panels stack vertically before columns become unreadable")
    func editorResultPanelsStackVerticallyBeforeColumnsBecomeUnreadable() {
        #expect(AdaptiveEditorResultPanelLayout.resolve(width: 520) == .init(
            stacksVertically: true
        ))
        #expect(AdaptiveEditorResultPanelLayout.resolve(width: 700) == .init(
            stacksVertically: false
        ))
        #expect(AdaptiveEditorResultPanelLayout.resolve(width: 920) == .init(
            stacksVertically: false
        ))
    }
}
