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
/// ## Limitations
///
/// - Multi-line commands: only handles the current visible line.
/// - Wide characters (CJK): each wide char occupies 2 columns.
/// - Tab characters: assumed to be 8-column aligned.
///
/// - SeeAlso: `TextSelectionManager` for the broader selection system.
/// - SeeAlso: `CocxyCoreView` for event integration.
@MainActor
final class IDECursorController {

    // MARK: - Properties

    /// The host view this controller enhances.
    private weak var hostView: NSView?

    /// Returns the current terminal font size.
    private let fontSizeProvider: () -> CGFloat

    /// Returns the **real** terminal cursor position `(row, col)` for the
    /// backing surface, read directly from CocxyCore. Falls back to `nil`
    /// when no terminal is attached.
    ///
    /// Used by `arrowKeysForClick` to compute click-to-position deltas from
    /// the authoritative shell cursor column instead of an internally
    /// tracked value that drifts against prompts rendered with escape
    /// sequences, colors, and wide characters.
    private let cursorPositionProvider: () -> (row: Int, col: Int)?

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

    /// The last known cursor column (0-based, within the line).
    /// Updated via cursor position reports or estimated from input.
    private(set) var cursorColumn: Int = 0

    /// Whether the cursor is currently on the prompt line.
    private(set) var isOnPromptLine: Bool = false

    /// The last known prompt row (0-based from top of visible area).
    private(set) var promptRow: Int = 0

    /// Padding from the left edge of the terminal view to the first column.
    var leftPadding: CGFloat = 0

    /// Padding from the top edge of the terminal view to the first row.
    var topPadding: CGFloat = 0

    // MARK: - Initialization

    init(
        hostView: NSView,
        fontSizeProvider: @escaping () -> CGFloat,
        cursorPositionProvider: @escaping () -> (row: Int, col: Int)? = { nil },
        arrowKeySender: @escaping ([ArrowDirection]) -> Void
    ) {
        self.hostView = hostView
        self.fontSizeProvider = fontSizeProvider
        self.cursorPositionProvider = cursorPositionProvider
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

    /// Called when a shell prompt is detected (OSC 133 ;A).
    ///
    /// Records the prompt row and column so subsequent click-to-position
    /// operations can validate that the click lands on the current prompt
    /// line. No visual indicator is installed — the real shell cursor drawn
    /// by CocxyCore is the only on-screen cursor marker.
    ///
    /// The row and column must come from the real terminal cursor position,
    /// not from a geometric heuristic over the view bounds, otherwise the
    /// click-to-position row comparison will never match.
    func shellPromptDetected(row: Int, column: Int) {
        promptRow = row
        promptColumn = column
        cursorColumn = column
        isOnPromptLine = true
    }

    /// Called when user input changes the cursor position.
    ///
    /// Tracks the cursor column so the next click-to-position uses an
    /// accurate baseline. This is called from the view layer after arrow
    /// keys and printable characters are delivered to the terminal.
    func cursorMoved(toColumn column: Int) {
        cursorColumn = column
    }

    /// Called when a command is executed (return key pressed).
    ///
    /// Clears the `isOnPromptLine` flag so future clicks (before a new
    /// prompt arrives) are not handled as cursor positioning.
    func commandExecuted() {
        isOnPromptLine = false
    }

    // MARK: - Click-to-Position

    /// Handles a click at the given location and returns the arrow keys
    /// needed to move the cursor to that position.
    ///
    /// The cursor column used for the delta is read from the **real**
    /// terminal state via `cursorPositionProvider` so that prompts with
    /// invisible escape sequences, colors, emojis or wide characters do
    /// not cause drift. The internally-tracked `cursorColumn` is kept in
    /// sync as a fallback for tests that inject the controller with no
    /// terminal backing.
    ///
    /// - Parameters:
    ///   - location: The click point in the terminal view's coordinate space.
    ///   - viewBounds: The bounds of the terminal view.
    /// - Returns: An array of `ArrowDirection` movements, or `nil` if the
    ///   click is not on the prompt line or cursor positioning is not
    ///   possible.
    func arrowKeysForClick(at location: CGPoint, viewBounds: NSRect) -> [ArrowDirection]? {
        guard isEnabled, isOnPromptLine else { return nil }

        // Convert click location to grid coordinates.
        let targetColumn = columnForX(location.x)
        let targetRow = rowForY(location.y)

        // Prefer the live terminal cursor position over the tracked
        // value. On prompts rendered by Prezto / Powerlevel10k / YADR the
        // tracked `cursorColumn` drifts by several columns because escape
        // sequences and emoji runs are counted differently by CocxyCore's
        // grid. Reading the real row/col eliminates that drift entirely.
        let liveCursor = cursorPositionProvider()
        let referenceRow = liveCursor?.row ?? promptRow
        let referenceCol = liveCursor?.col ?? cursorColumn

        // Only reposition if clicking on the current cursor row.
        guard targetRow == referenceRow else { return nil }

        // Ensure target is within the editable area (after prompt).
        let effectiveTarget = max(targetColumn, promptColumn)

        // Calculate the difference from the authoritative reference.
        let delta = effectiveTarget - referenceCol

        if delta == 0 { return [] }

        let direction: ArrowDirection = delta > 0 ? .right : .left
        return Array(repeating: direction, count: abs(delta))
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

        // Update our tracked cursor position to match the new shell cursor.
        // The live provider supersedes this value on the next click, but
        // maintaining it keeps the legacy fallback path consistent.
        let delta = arrows.count * (arrows[0] == .right ? 1 : -1)
        cursorColumn += delta

        return true
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
