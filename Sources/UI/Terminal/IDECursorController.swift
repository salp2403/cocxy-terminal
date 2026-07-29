// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// IDECursorController.swift - IDE-like cursor positioning in the terminal prompt.

import AppKit

// MARK: - IDE Cursor Controller

/// Provides IDE-like cursor positioning within the terminal's command line.
///
/// ## The Problem
///
/// In a traditional terminal, clicking somewhere on the command line doesn't
/// move the cursor to that position. Users must use arrow keys to navigate.
/// This is the single biggest UX gap between terminal editors and IDE text fields.
///
/// ## The Solution
///
/// When the user clicks within the current prompt line, this controller:
/// 1. Detects the current cursor column position (tracked from the shell).
/// 2. Calculates the target column from the click coordinates.
/// 3. Sends the correct number of arrow key presses to move the shell cursor.
///
/// The real shell cursor — drawn by `CocxyCoreBridge` / `MetalTerminalRenderer`
/// via the Metal glyph atlas — is the only on-screen cursor indicator. It
/// already blinks naturally. This controller does NOT render its own blink
/// layer; an earlier incarnation did, and it caused a persistent double-cursor
/// regression where the synthetic blink drifted away from the real cursor on
/// every click.
///
/// ## Requirements
///
/// - Shell must report prompt position via **OSC 133** (shell integration).
/// - Terminal font must be monospaced (all columns have equal width).
/// - Only works on the current command line (not scrollback).
///
/// - SeeAlso: `CocxyCoreView` for event integration.
@MainActor
final class IDECursorController {

    // MARK: - Properties

    /// The host view this controller enhances.
    private weak var hostView: NSView?

    /// Returns the current terminal font size.
    private let fontSizeProvider: () -> CGFloat

    /// Returns one atomic snapshot of the core state needed to validate and
    /// calculate a click. Reading these fields under one terminal lock avoids
    /// mixing a cursor from one frame with semantic or viewport state from
    /// another.
    private let terminalStateProvider: (UInt32) -> TerminalCursorClickSnapshot?

    /// Sends the requested arrow-key movement to the active terminal engine.
    private let arrowKeySender: ([ArrowDirection]) -> Void

    /// Whether IDE cursor positioning is currently enabled.
    var isEnabled: Bool = true

    /// The estimated character cell width in points.
    /// Calculated from the terminal font size.
    private(set) var cellWidth: CGFloat = 8.4

    /// The estimated character cell height in points.
    private(set) var cellHeight: CGFloat = 16.8

    /// The last known prompt column (0-based, from OSC 133).
    /// This is the column where the prompt text ends and user input begins.
    private(set) var promptColumn: Int = 0

    /// The last estimated cursor column (0-based, within the line).
    /// Kept for diagnostics and view-layer bookkeeping; click deltas always use
    /// the atomic terminal snapshot instead of this estimate.
    private(set) var cursorColumn: Int = 0

    /// Whether the cursor is currently on the prompt line.
    var isOnPromptLine: Bool { inputStartPosition != nil }

    /// The last known prompt row (0-based from top of visible area).
    private(set) var promptRow: Int = 0

    /// OSC 133;A position captured synchronously by the core callback.
    private(set) var promptPosition: TerminalGridPosition?

    /// OSC 133;B position where editable command input begins.
    private(set) var inputStartPosition: TerminalGridPosition?

    /// Padding from the left edge of the terminal view to the first column.
    var leftPadding: CGFloat = 0

    /// Padding from the top edge of the terminal view to the first row.
    var topPadding: CGFloat = 0

    // MARK: - Initialization

    init(
        hostView: NSView,
        fontSizeProvider: @escaping () -> CGFloat,
        terminalStateProvider: @escaping (UInt32) -> TerminalCursorClickSnapshot?,
        arrowKeySender: @escaping ([ArrowDirection]) -> Void
    ) {
        self.hostView = hostView
        self.fontSizeProvider = fontSizeProvider
        self.terminalStateProvider = terminalStateProvider
        self.arrowKeySender = arrowKeySender
        updateCellDimensions()
    }

    // MARK: - Cell Dimensions

    /// Updates the cell dimensions based on the current font size.
    func updateCellDimensions() {
        let fontSize = fontSizeProvider()
        // Standard monospace font metrics: width ~0.6x height, height ~1.2x size.
        cellWidth = fontSize * 0.6
        cellHeight = fontSize * 1.2
    }

    /// Updates cell dimensions from explicit values.
    func setCellDimensions(width: CGFloat, height: CGFloat) {
        cellWidth = width
        cellHeight = height
    }

    // MARK: - Prompt Tracking

    /// Records OSC 133;A and clears any editable range left by the preceding
    /// command. Clicks remain disabled until OSC 133;B supplies the real input
    /// start position.
    func shellPromptDetected(at position: TerminalGridPosition) {
        promptPosition = position
        inputStartPosition = nil
        promptRow = Int(position.screenRow)
        promptColumn = Int(position.column)
        cursorColumn = Int(position.column)
    }

    /// Records the first editable cell reported by OSC 133;B.
    func commandInputStarted(at position: TerminalGridPosition) {
        inputStartPosition = position
        promptRow = Int(position.screenRow)
        promptColumn = Int(position.column)
        cursorColumn = Int(position.column)
    }

    /// Called when user input changes the cursor position.
    ///
    /// Tracks the view layer's latest cursor estimate after arrow keys and
    /// printable characters are delivered to the terminal. The estimate is
    /// never used to authorize or calculate a click-to-position movement.
    func cursorMoved(toColumn column: Int) {
        cursorColumn = column
    }

    /// Called when a command is executed (return key pressed).
    ///
    /// Clears the `isOnPromptLine` flag so future clicks (before a new
    /// prompt arrives) are not handled as cursor positioning.
    func commandExecuted() {
        inputStartPosition = nil
    }

    // MARK: - Click-to-Position

    /// Handles a click at the given location and returns the arrow keys
    /// needed to move the cursor to that position.
    ///
    /// The cursor, viewport, semantic state, selection state and row cell
    /// widths are read together from the **real** terminal through
    /// `terminalStateProvider`. This prevents drift from invisible escape
    /// sequences, colors, emojis, wide characters or mixed-frame reads.
    ///
    /// - Parameters:
    ///   - location: The click point in the terminal view's coordinate space.
    ///   - viewBounds: The bounds of the terminal view.
    /// - Returns: An array of `ArrowDirection` movements, or `nil` if the
    ///   click is not on the prompt line or cursor positioning is not
    ///   possible.
    func arrowKeysForClick(at location: CGPoint, viewBounds: NSRect) -> [ArrowDirection]? {
        guard isEnabled,
              let inputStartPosition,
              let terminalState = terminalStateProvider(inputStartPosition.absoluteRow),
              Self.clickableSemanticStates.contains(terminalState.semanticState),
              !terminalState.isAltScreen,
              terminalState.mouseTrackingMode == 0,
              !terminalState.selectionActive,
              terminalState.visibleStartRow == terminalState.historyMaxVisibleStart else {
            return nil
        }

        // Convert click location to grid coordinates.
        guard viewBounds.contains(location) else { return nil }
        let targetScreenRow = rowForY(location.y)
        guard let targetScreenRowValue = UInt32(exactly: targetScreenRow) else { return nil }
        let (targetAbsoluteRow, targetOverflowed) = terminalState.visibleStartRow
            .addingReportingOverflow(targetScreenRowValue)
        guard !targetOverflowed else { return nil }
        let cursorAbsoluteRow = terminalState.cursorAbsoluteRow
        let inputStartAbsoluteRow = inputStartPosition.absoluteRow

        let inputStartColumn = Int(inputStartPosition.column)
        let cursorColumn = Int(terminalState.cursorColumn)
        guard inputStartAbsoluteRow <= targetAbsoluteRow,
              targetAbsoluteRow <= cursorAbsoluteRow,
              inputStartAbsoluteRow <= cursorAbsoluteRow else {
            return nil
        }

        switch terminalState.shellClickMode {
        case 1:
            guard inputStartAbsoluteRow == cursorAbsoluteRow,
                  targetAbsoluteRow == cursorAbsoluteRow else { return nil }
        case 2:
            break
        default:
            return nil
        }

        let expectedRowCount = UInt64(cursorAbsoluteRow) - UInt64(inputStartAbsoluteRow) + 1
        guard expectedRowCount == terminalState.rows.count else { return nil }

        var rowInputColumns: [[Int]] = []
        var rowInputOffsets: [Int] = []
        var inputCellCount = 0
        rowInputColumns.reserveCapacity(terminalState.rows.count)
        rowInputOffsets.reserveCapacity(terminalState.rows.count)

        for (index, row) in terminalState.rows.enumerated() {
            let expectedAbsoluteRow = inputStartAbsoluteRow + UInt32(index)
            guard row.absoluteRow == expectedAbsoluteRow,
                  row.cellWidths.count == row.cellSemantics.count else { return nil }
            if index < terminalState.rows.count - 1, !row.wrapped {
                return nil
            }

            let minimumColumn = index == 0 ? inputStartColumn : 0
            guard minimumColumn <= row.cellWidths.count else { return nil }
            let columns = Self.inputColumns(in: row, minimum: minimumColumn)
            if index < terminalState.rows.count - 1, columns.isEmpty {
                return nil
            }
            rowInputOffsets.append(inputCellCount)
            rowInputColumns.append(columns)
            inputCellCount += columns.count
        }

        guard let cursorRow = terminalState.rows.last,
              cursorColumn <= cursorRow.cellWidths.count,
              !(cursorAbsoluteRow == inputStartAbsoluteRow && cursorColumn < inputStartColumn),
              !Self.isContinuationCell(at: cursorColumn, in: cursorRow.cellWidths) else {
            return nil
        }

        let cursorRowIndex = terminalState.rows.count - 1
        let cursorLogicalOffset = rowInputOffsets[cursorRowIndex]
            + rowInputColumns[cursorRowIndex].count { $0 < cursorColumn }

        let targetRowIndex = Int(targetAbsoluteRow - inputStartAbsoluteRow)
        let targetRow = terminalState.rows[targetRowIndex]
        let targetMinimumColumn = targetRowIndex == 0 ? inputStartColumn : 0
        var targetColumn = min(columnForX(location.x), targetRow.cellWidths.count)
        targetColumn = max(targetColumn, targetMinimumColumn)
        targetColumn = Self.leadingColumn(
            for: targetColumn,
            cellWidths: targetRow.cellWidths,
            minimum: targetMinimumColumn
        )

        let targetColumns = rowInputColumns[targetRowIndex]
        let targetLogicalOffset: Int
        if targetColumns.isEmpty {
            guard targetRowIndex == 0 else { return nil }
            targetLogicalOffset = 0
        } else {
            targetLogicalOffset = rowInputOffsets[targetRowIndex]
                + targetColumns.count { $0 < targetColumn }
        }

        guard targetLogicalOffset != cursorLogicalOffset else { return [] }

        let movementCount = abs(targetLogicalOffset - cursorLogicalOffset)
        guard movementCount > 0 else { return [] }

        let direction: ArrowDirection = targetLogicalOffset > cursorLogicalOffset ? .right : .left
        return Array(repeating: direction, count: movementCount)
    }

    /// Sends arrow keys to the terminal to reposition the cursor.
    ///
    /// Returns `true` when the click was on the current prompt line and the
    /// cursor movement (if any) has been requested via `arrowKeySender`.
    /// The real shell cursor drawn by CocxyCore moves asynchronously once
    /// the terminal processes the injected arrow keys; this controller does
    /// not render its own cursor overlay.
    ///
    /// - Parameter location: Click location in the terminal view.
    /// - Returns: `true` if the click was handled (click was on prompt line).
    func handleClickToPosition(at location: CGPoint) -> Bool {
        guard let view = hostView else {
            return false
        }

        guard let arrows = arrowKeysForClick(at: location, viewBounds: view.bounds) else {
            return false
        }

        guard !arrows.isEmpty else {
            // Click already at the current cursor column.
            return true
        }

        arrowKeySender(arrows)

        return true
    }

    private static let clickableSemanticStates: Set<UInt8> = [1, 2]
    private static let inputSemantic: UInt8 = 2

    private static func inputColumns(
        in row: TerminalCursorClickRow,
        minimum: Int
    ) -> [Int] {
        row.cellSemantics.indices.compactMap { column in
            guard column >= minimum,
                  row.cellSemantics[column] == inputSemantic,
                  row.cellWidths[column] != 2 else { return nil }
            return column
        }
    }

    private static func isContinuationCell(at column: Int, in cellWidths: [UInt8]) -> Bool {
        column < cellWidths.count && cellWidths[column] == 2
    }

    private static func leadingColumn(
        for column: Int,
        cellWidths: [UInt8],
        minimum: Int
    ) -> Int {
        var result = column
        while result > minimum, isContinuationCell(at: result, in: cellWidths) {
            result -= 1
        }
        return result
    }

    // MARK: - Coordinate Conversion

    /// Converts an X position to a column index.
    func columnForX(_ x: CGFloat) -> Int {
        guard cellWidth > 0 else { return 0 }
        return max(0, Int((x - leftPadding) / cellWidth))
    }

    /// Converts a Y position to a row index.
    func rowForY(_ y: CGFloat) -> Int {
        guard cellHeight > 0 else { return 0 }
        return max(0, Int((y - topPadding) / cellHeight))
    }

    /// Converts a column index to an X position (center of the cell).
    func xForColumn(_ column: Int) -> CGFloat {
        return leftPadding + (CGFloat(column) + 0.5) * cellWidth
    }

    /// Converts a row index to a Y position (center of the cell).
    func yForRow(_ row: Int) -> CGFloat {
        return topPadding + (CGFloat(row) + 0.5) * cellHeight
    }
}

// MARK: - Arrow Direction

/// Direction for cursor movement via arrow keys.
enum ArrowDirection: Sendable {
    case left
    case right
}
