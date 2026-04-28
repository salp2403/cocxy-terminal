// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotesOverlayViewSwiftTestingTests.swift - Lightweight UI contract
// checks for the docked Notes panel.

import CoreGraphics
import Testing
@testable import CocxyTerminal

@Suite("NotesOverlayView")
struct NotesOverlayViewSwiftTestingTests {

    @Test("panel width constants keep the note editor usable in the right-docked overlay")
    func panelWidthConstantsRespectUsabilityBounds() {
        #expect(NotesOverlayView.minimumPanelWidth >= 400)
        #expect(NotesOverlayView.minimumPanelWidth < NotesOverlayView.defaultPanelWidth)
        #expect(NotesOverlayView.defaultPanelWidth < NotesOverlayView.maximumPanelWidth)
        #expect(NotesOverlayView.maximumPanelWidth <= 900)
    }

    @Test("layout switches to stacked when the panel is compact so list and editor do not crush each other")
    func compactPanelUsesStackedLayout() {
        let compactWidth = NotesOverlayView.compactLayoutThreshold - 1

        #expect(NotesOverlayView.contentLayout(forPanelWidth: compactWidth) == .stacked)
    }

    @Test("default panel uses stacked layout because the docked notes pane prioritizes editor width")
    func defaultPanelUsesStackedLayout() {
        #expect(
            NotesOverlayView.contentLayout(
                forPanelWidth: NotesOverlayView.defaultPanelWidth
            ) == .stacked
        )
    }

    @Test("layout uses split view only when the panel has enough width for both list and editor")
    func widePanelUsesSplitLayout() {
        #expect(
            NotesOverlayView.contentLayout(
                forPanelWidth: NotesOverlayView.compactLayoutThreshold
            ) == .split
        )
        #expect(
            NotesOverlayView.contentLayout(
                forPanelWidth: NotesOverlayView.maximumPanelWidth
            ) == .split
        )
    }
}
