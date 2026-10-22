// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// IDECursorProviderDriftTests.swift
//
// Covers the atomic terminal-state provider used by CocxyCoreView. These tests
// protect against cursor drift from escape sequences and wide prompt glyphs.

import AppKit
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("IDECursorController terminalStateProvider")
struct IDECursorProviderDriftTests {

    // MARK: - Helpers

    /// Creates a layer-backed NSView so `handleClickToPosition` can
    /// operate on a real bounds rect, and returns the controller along
    /// with a mutable closure that the test can use to drive the
    /// cursorPositionProvider from the outside.
    private final class ProviderBox {
        var snapshot: TerminalCursorClickSnapshot?
    }

    private func makeController(initialCursor: (row: UInt16, col: UInt16)? = nil)
        -> (controller: IDECursorController, provider: ProviderBox, sentArrows: Captured)
    {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.wantsLayer = true
        _ = view.layer

        let provider = ProviderBox()
        provider.snapshot = initialCursor.map { cursor in
            let cellWidths = Array(repeating: UInt8(0), count: 100)
            let cellSemantics = Array(repeating: UInt8(2), count: 100)
            let rows = (UInt32(0)...UInt32(cursor.row)).map { absoluteRow in
                TerminalCursorClickRow(
                    absoluteRow: absoluteRow,
                    wrapped: absoluteRow < UInt32(cursor.row),
                    cellWidths: cellWidths,
                    cellSemantics: cellSemantics
                )
            }
            return TerminalCursorClickSnapshot(
                visibleStartRow: 0,
                historyMaxVisibleStart: 0,
                cursorScreenRow: cursor.row,
                cursorColumn: cursor.col,
                semanticState: 2,
                isAltScreen: false,
                mouseTrackingMode: 0,
                selectionActive: false,
                shellClickMode: 2,
                rows: rows
            )
        }

        let captured = Captured()

        let controller = IDECursorController(
            hostView: view,
            fontSizeProvider: { 14.0 },
            terminalStateProvider: { [provider] _ in provider.snapshot },
            arrowKeySender: { arrows in captured.arrows.append(contentsOf: arrows) }
        )
        controller.setCellDimensions(width: 8.0, height: 16.0)
        controller.leftPadding = 0
        controller.topPadding = 0
        return (controller, provider, captured)
    }

    /// Lightweight capture helper so assertions can inspect what the
    /// `arrowKeySender` closure received.
    private final class Captured {
        var arrows: [ArrowDirection] = []
    }

    // MARK: - Live cursor overrides tracked state

    @Test("arrowKeysForClick uses the live cursor column from the provider, not cursorColumn")
    func liveCursorOverridesTrackedColumn() {
        // Simulate a prompt where the internal tracker drifted to column 10
        // but the real shell cursor is at column 30 (e.g. because emojis
        // and ANSI escape sequences in the prompt inflated the real column
        // count).
        let (controller, provider, _) = makeController(initialCursor: (row: 0, col: 30))
        controller.commandInputStarted(at: TerminalGridPosition(
            screenRow: 0,
            absoluteRow: 0,
            column: 10
        ))
        // At this point the internal tracked cursorColumn is 10, but the
        // provider reports 30. The click-to-position math MUST use 30.
        _ = provider // keep alive

        // Click at column 15 on row 0 (cellWidth = 8, so x = 15*8 = 120).
        let arrows = controller.arrowKeysForClick(
            at: CGPoint(x: 120, y: 0),
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        // Delta from live cursor (30) to target (15) is -15, i.e. 15 lefts.
        // If the controller used the stale tracked cursorColumn (10),
        // it would compute +5 and send 5 rights — the wrong direction
        // and the wrong count.
        #expect(arrows?.count == 15, "Delta must be computed from live cursor col")
        #expect(arrows?.first == .left, "Live cursor ahead of target → move left")
    }

    // MARK: - Drift produces no excess arrow keys (bell prevention)

    @Test("click at live cursor column produces zero arrow keys (no bell)")
    func clickAtLiveCursorProducesZeroArrows() {
        // Prompt at column 5, tracker says column 5, but the real cursor
        // already moved forward to column 25 because the user typed some
        // text the controller did not see. Clicking exactly on column 25
        // must not generate any arrow keys — otherwise the shell beeps
        // because the arrows try to exit the editable region.
        let (controller, provider, captured) = makeController(initialCursor: (row: 0, col: 25))
        controller.commandInputStarted(at: TerminalGridPosition(
            screenRow: 0,
            absoluteRow: 0,
            column: 5
        ))
        _ = provider

        // Click at column 25 (x = 25*8 = 200).
        let handled = controller.handleClickToPosition(at: CGPoint(x: 200, y: 0))

        #expect(handled == true)
        #expect(captured.arrows.isEmpty,
                "Click on the live cursor column must not synthesise any movement")
    }

    // MARK: - Provider row gates click-to-position

    @Test("click on a soft-wrapped input row uses the live multiline offset")
    func clickOnWrappedInputRowUsesLiveOffset() {
        let (controller, provider, captured) = makeController(initialCursor: (row: 2, col: 5))
        controller.commandInputStarted(at: TerminalGridPosition(
            screenRow: 0,
            absoluteRow: 0,
            column: 5
        ))
        _ = provider

        let arrows = controller.arrowKeysForClick(
            at: CGPoint(x: 100, y: 8), // y=8 → row 0 (cellHeight = 16)
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        #expect(arrows?.count == 193)
        #expect(arrows?.first == .left)
        #expect(captured.arrows.isEmpty)
    }

    // MARK: - Missing state

    @Test("nil provider disables cursor synthesis")
    func nilProviderDisablesCursorSynthesis() {
        let (controller, provider, _) = makeController(initialCursor: nil)
        controller.commandInputStarted(at: TerminalGridPosition(
            screenRow: 0,
            absoluteRow: 0,
            column: 5
        ))
        _ = provider

        let arrows = controller.arrowKeysForClick(
            at: CGPoint(x: 80, y: 0), // column 10
            viewBounds: NSRect(x: 0, y: 0, width: 800, height: 600)
        )

        #expect(arrows == nil)
    }
}
