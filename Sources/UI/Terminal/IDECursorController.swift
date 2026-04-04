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
/// 1. Detects the current cursor column position (from the shell).
/// 2. Calculates the target column from the click coordinates.
/// 3. Sends the correct number of arrow key presses to move the cursor.
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
/// - SeeAlso: `TerminalSurfaceView` for event integration.
@MainActor
final class IDECursorController {

    // MARK: - Properties

    /// The host view this controller enhances.
    private weak var hostView: NSView?

    /// Returns the current terminal font size.
    private let fontSizeProvider: () -> CGFloat

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

    /// The visual indicator layer that blinks on the prompt line.
    /// Lazily installed into the surface view's layer hierarchy.
    private var indicatorLayer: IDECursorIndicatorLayer?

    // MARK: - Initialization

    init(
        hostView: NSView,
        fontSizeProvider: @escaping () -> CGFloat,
        arrowKeySender: @escaping ([ArrowDirection]) -> Void
    ) {
        self.hostView = hostView
        self.fontSizeProvider = fontSizeProvider
        self.arrowKeySender = arrowKeySender
        updateCellDimensions()
    }

    convenience init(surfaceView: TerminalSurfaceView) {
        self.init(
            hostView: surfaceView,
            fontSizeProvider: { [weak surfaceView] in
                surfaceView?.viewModel.currentFontSize ?? 14.0
            },
            arrowKeySender: { [weak surfaceView] arrows in
                guard let surfaceView,
                      let surfaceID = surfaceView.viewModel.surfaceID,
                      let bridge = surfaceView.viewModel.ghosttyBridge,
                      !arrows.isEmpty else { return }

                let csiCode = arrows[0] == .left ? "D" : "C"
                for _ in arrows {
                    bridge.performBindingAction("csi:\(csiCode)", on: surfaceID)
                }
            }
        )
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
    /// Records the prompt position for cursor calculations and activates the blink indicator.
    func shellPromptDetected(row: Int, column: Int) {
        promptRow = row
        promptColumn = column
        cursorColumn = column
        isOnPromptLine = true
        installIndicatorIfNeeded()
        updateIndicatorPosition()
        indicatorLayer?.startBlinking()
    }

    /// Called when user input changes the cursor position.
    /// Tracks the cursor column for relative movement calculations.
    func cursorMoved(toColumn column: Int) {
        cursorColumn = column
        updateIndicatorPosition()
    }

    /// Called when a command is executed (return key pressed).
    /// Marks that the cursor is no longer on the prompt line and stops the blink indicator.
    func commandExecuted() {
        isOnPromptLine = false
        indicatorLayer?.stopBlinking()
    }

    // MARK: - Indicator Layer Management

    /// Installs the IDE cursor indicator layer into the surface view if not already present.
    private func installIndicatorIfNeeded() {
        guard indicatorLayer == nil, let layer = hostView?.layer else { return }
        let indicator = IDECursorIndicatorLayer()
        indicator.cursorHeight = cellHeight
        layer.addSublayer(indicator)
        indicatorLayer = indicator
    }

    /// Updates the indicator layer position to match the current cursor column and prompt row.
    ///
    /// The layer frame is sized to exactly one cell row at the prompt position.
    /// Since `TerminalSurfaceView.isFlipped == true`, y increases downward,
    /// so `promptRow * cellHeight` places the layer at the correct row.
    private func updateIndicatorPosition() {
        guard let indicator = indicatorLayer, isOnPromptLine,
              let viewBounds = hostView?.bounds else { return }
        let rowY = topPadding + CGFloat(promptRow) * cellHeight
        indicator.frame = CGRect(
            x: 0, y: rowY,
            width: viewBounds.width, height: cellHeight
        )
        indicator.cursorX = leftPadding + CGFloat(cursorColumn) * cellWidth
        indicator.cursorHeight = cellHeight
        indicator.setNeedsDisplay()
    }

    // MARK: - Click-to-Position

    /// Handles a click at the given location and returns the arrow keys
    /// needed to move the cursor to that position.
    ///
    /// - Parameters:
    ///   - location: The click point in the terminal view's coordinate space.
    ///   - viewBounds: The bounds of the terminal view.
    /// - Returns: An array of `ArrowDirection` movements, or nil if the click
    ///   is not on the prompt line or cursor positioning is not possible.
    func arrowKeysForClick(at location: CGPoint, viewBounds: NSRect) -> [ArrowDirection]? {
        guard isEnabled, isOnPromptLine else { return nil }

        // Convert click location to grid coordinates.
        let targetColumn = columnForX(location.x)
        let targetRow = rowForY(location.y)

        // Only reposition if clicking on the prompt row.
        guard targetRow == promptRow else { return nil }

        // Ensure target is within the editable area (after prompt).
        let effectiveTarget = max(targetColumn, promptColumn)

        // Calculate the difference.
        let delta = effectiveTarget - cursorColumn

        if delta == 0 { return [] }

        let direction: ArrowDirection = delta > 0 ? .right : .left
        return Array(repeating: direction, count: abs(delta))
    }

    /// Sends arrow keys to the terminal to reposition the cursor.
    ///
    /// - Parameter location: Click location in the terminal view.
    /// - Returns: `true` if arrow keys were sent (click was on prompt line).
    func handleClickToPosition(at location: CGPoint) -> Bool {
        guard let view = hostView else {
            return false
        }

        guard let arrows = arrowKeysForClick(at: location, viewBounds: view.bounds) else {
            return false
        }

        guard !arrows.isEmpty else {
            // Already at the right position.
            return true
        }

        arrowKeySender(arrows)

        // Update our tracked cursor position.
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

// MARK: - IDE Cursor Visual Layer

/// CALayer that renders an IDE-style cursor indicator on the prompt line.
///
/// Shows a thin vertical line (I-beam) at the cursor position, with a subtle
/// blink animation. Only visible when the cursor is on the prompt line.
final class IDECursorIndicatorLayer: CALayer {

    /// The cursor color (matches the theme accent).
    var cursorColor: CGColor = CocxyColors.blue.cgColor {
        didSet { setNeedsDisplay() }
    }

    /// The cursor position in the layer (x coordinate).
    var cursorX: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    /// The cursor height.
    var cursorHeight: CGFloat = 16 {
        didSet { setNeedsDisplay() }
    }

    /// The cursor width (thin line for I-beam).
    static let cursorWidth: CGFloat = 2

    /// Whether the cursor is currently visible (for blink).
    var isCursorVisible: Bool = true {
        didSet { opacity = isCursorVisible ? 1.0 : 0.0 }
    }

    override init() {
        super.init()
        isOpaque = false
        backgroundColor = CGColor.clear
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? IDECursorIndicatorLayer {
            cursorColor = other.cursorColor
            cursorX = other.cursorX
            cursorHeight = other.cursorHeight
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IDECursorIndicatorLayer does not support NSCoding")
    }

    override func draw(in ctx: CGContext) {
        let rect = CGRect(
            x: cursorX,
            y: (bounds.height - cursorHeight) / 2,
            width: Self.cursorWidth,
            height: cursorHeight
        )
        ctx.setFillColor(cursorColor)
        ctx.fill(rect)
    }

    /// Starts a blink animation.
    func startBlinking() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        add(animation, forKey: "blink")
    }

    /// Stops the blink animation.
    func stopBlinking() {
        removeAnimation(forKey: "blink")
        opacity = 1.0
    }
}
