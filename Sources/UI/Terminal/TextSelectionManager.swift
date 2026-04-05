// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TextSelectionManager.swift - IDE-like text selection enhancements for the terminal.

import AppKit


// MARK: - Text Selection Manager

/// Coordinates IDE-like text selection features on top of the terminal surface.
///
/// Enhancements over default terminal selection:
/// - **Cmd+click** to open URLs and file paths detected under the cursor.
/// - **Auto-scroll** when dragging near the top/bottom edges of the terminal.
/// - **Selection highlight overlay** to highlight matches of selected text.
///
/// These features complement the host view's own selection handling and can
/// be layered on top without tying the logic to a specific engine.
///
/// - SeeAlso: `CocxyCoreView` for event routing.
/// - SeeAlso: `SelectionHighlightLayer` for visual overlays.
@MainActor
final class TextSelectionManager {

    // MARK: - Properties

    /// The terminal host view this manager enhances.
    private weak var hostView: NSView?

    /// Sends scroll requests when a drag selection reaches the view edges.
    private let scrollByRows: (Int) -> Void

    /// Timer for auto-scroll during edge drag.
    private var autoScrollTimer: Timer?

    /// The auto-scroll speed (points per tick). Increases near edges.
    private var autoScrollDelta: CGFloat = 0

    /// Distance from edge that triggers auto-scroll.
    private static let autoScrollEdgeMargin: CGFloat = 30

    /// Auto-scroll interval.
    private static let autoScrollInterval: TimeInterval = 1.0 / 30.0

    /// Whether a drag selection is currently in progress.
    private(set) var isDragging: Bool = false

    /// Provider for the current working directory of the terminal tab.
    /// Called when resolving relative paths detected by Cmd+click.
    /// Injected by the surface lifecycle code that knows the tab's CWD.
    var workingDirectoryProvider: (() -> URL?)?

    /// Regex pattern for detecting URLs in terminal output.
    // swiftlint:disable:next force_try
    private static let urlPattern: NSRegularExpression = {
        // Pattern is a compile-time constant; failure is a programming error.
        try! NSRegularExpression(
            pattern: #"https?://[^\s<>\"'\])}]+"#,
            options: .caseInsensitive
        )
    }()

    /// Regex pattern for detecting absolute and home-relative file paths.
    // swiftlint:disable:next force_try
    private static let filePathPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?:~|/)[/\w.\-@]+"#,
            options: []
        )
    }()

    /// Regex pattern for detecting relative file paths (./foo, ../foo, bare/path).
    // swiftlint:disable:next force_try
    private static let relativePathPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?<!\w)\.{0,2}/[\w.\-@/]+"#,
            options: []
        )
    }()

    // MARK: - Initialization

    init(hostView: NSView, scrollByRows: @escaping (Int) -> Void = { _ in }) {
        self.hostView = hostView
        self.scrollByRows = scrollByRows
    }

    // MARK: - Cmd+Click URL/Path Opening

    /// Handles a Cmd+click event by detecting and opening URLs/paths.
    ///
    /// Checks the clipboard content after the click and attempts to open it.
    ///
    /// - Parameters:
    ///   - location: Click location in the surface view.
    ///   - modifiers: Key modifiers at the time of click.
    /// - Returns: `true` if a URL/path was detected and opened (event consumed).
    func handleCmdClick(at location: CGPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.contains(.command) else { return false }

        // Some host views copy the current selection to the clipboard as part
        // of their click handling. Read it after a short delay, then detect
        // whether it is a URL or file path worth opening.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.attemptOpenFromClipboard()
        }

        return false // Let the event continue to the host view.
    }

    /// Reads the clipboard and attempts to open its content as a URL or file path.
    ///
    /// Called after Cmd+click with a delay to allow the host view to process
    /// selection updates and refresh the clipboard.
    private func attemptOpenFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 2048 else { return }

        // Check for URL first.
        if let url = detectURL(in: trimmed) {
            NSWorkspace.shared.open(url)
            return
        }

        // Then check for file path.
        if let filePath = detectFilePath(in: trimmed) {
            NSWorkspace.shared.open(filePath)
        }
    }

    /// Detects a URL in the given text.
    private func detectURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.urlPattern.firstMatch(in: text, range: range) else {
            return nil
        }
        let matchRange = Range(match.range, in: text)!
        return URL(string: String(text[matchRange]))
    }

    /// Detects a file path in the given text and returns its URL if the file exists.
    ///
    /// Resolution order:
    /// 1. Direct text as absolute or ~-expanded path.
    /// 2. Direct text resolved against the terminal's working directory.
    /// 3. Regex match for absolute/home paths, then resolved against CWD.
    /// 4. Regex match for relative paths (./foo, ../foo), resolved against CWD.
    private func detectFilePath(in text: String) -> URL? {
        var expanded = text
        if expanded.hasPrefix("~") {
            expanded = (expanded as NSString).expandingTildeInPath
        }

        // Try absolute path first.
        let absoluteURL = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: absoluteURL.path) {
            return absoluteURL
        }

        // Try relative path against working directory.
        if let cwd = workingDirectoryProvider?() {
            let resolvedURL = cwd.appendingPathComponent(text).standardized
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                return resolvedURL
            }
        }

        // Try regex match on the text.
        let range = NSRange(text.startIndex..., in: text)

        // Check absolute/home paths via regex.
        if let match = Self.filePathPattern.firstMatch(in: text, range: range),
           let matchRange = Range(match.range, in: text) {
            let pathStr = String(text[matchRange])
            let resolvedPath = (pathStr as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: resolvedPath) {
                return URL(fileURLWithPath: resolvedPath)
            }
            // Try relative to CWD.
            if let cwd = workingDirectoryProvider?() {
                let cwdResolved = cwd.appendingPathComponent(pathStr).standardized
                if FileManager.default.fileExists(atPath: cwdResolved.path) {
                    return cwdResolved
                }
            }
        }

        // Check relative paths (./foo, ../foo, foo/bar).
        if let match = Self.relativePathPattern.firstMatch(in: text, range: range),
           let matchRange = Range(match.range, in: text),
           let cwd = workingDirectoryProvider?() {
            let pathStr = String(text[matchRange])
            let resolvedURL = cwd.appendingPathComponent(pathStr).standardized
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                return resolvedURL
            }
        }

        return nil
    }

    // MARK: - Auto-Scroll During Drag

    /// Called when a drag starts. Begins monitoring for auto-scroll.
    func dragDidStart() {
        isDragging = true
    }

    /// Called continuously during a drag to check if auto-scroll is needed.
    ///
    /// When the mouse position is near the top or bottom edge of the view,
    /// starts a timer that sends scroll events to create smooth auto-scroll.
    ///
    /// - Parameter location: Current mouse position in the surface view's coordinates.
    func dragDidMove(to location: CGPoint) {
        guard isDragging, let view = hostView else { return }

        let viewHeight = view.bounds.height
        let margin = Self.autoScrollEdgeMargin

        if location.y < margin {
            // Near bottom (flipped coords): scroll down.
            let intensity = 1.0 - (location.y / margin)
            autoScrollDelta = -intensity * 10
            startAutoScrollIfNeeded()
        } else if location.y > viewHeight - margin {
            // Near top (flipped coords): scroll up.
            let intensity = (location.y - (viewHeight - margin)) / margin
            autoScrollDelta = intensity * 10
            startAutoScrollIfNeeded()
        } else {
            stopAutoScroll()
        }
    }

    /// Called when a drag ends. Stops auto-scroll.
    func dragDidEnd() {
        isDragging = false
        stopAutoScroll()
    }

    private func startAutoScrollIfNeeded() {
        guard autoScrollTimer == nil else { return }

        autoScrollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoScrollInterval,
            repeats: true
        ) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self?.performAutoScroll()
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDelta = 0
    }

    private func performAutoScroll() {
        let deltaRows = Int(autoScrollDelta.rounded(.toNearestOrAwayFromZero))
        guard deltaRows != 0 else { return }
        scrollByRows(deltaRows)
    }
}

// MARK: - Selection Highlight Layer

/// CALayer overlay that draws rectangles to highlight matched text.
///
/// Used by `TextSelectionManager` to visually indicate all occurrences
/// of selected text, similar to VS Code's selection highlighting.
///
/// The layer is transparent and positioned exactly over the terminal
/// content area. It does not intercept mouse events.
final class SelectionHighlightLayer: CALayer {

    /// The color used for highlight rectangles.
    var highlightColor: CGColor = CocxyColors.blue.withAlphaComponent(0.15).cgColor {
        didSet { setNeedsDisplay() }
    }

    /// The border color for highlight rectangles.
    var highlightBorderColor: CGColor = CocxyColors.blue.withAlphaComponent(0.3).cgColor {
        didSet { setNeedsDisplay() }
    }

    /// Rectangles to highlight (in layer coordinates).
    var highlightRects: [CGRect] = [] {
        didSet { setNeedsDisplay() }
    }

    override init() {
        super.init()
        isOpaque = false
        backgroundColor = CGColor.clear
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? SelectionHighlightLayer {
            highlightColor = other.highlightColor
            highlightBorderColor = other.highlightBorderColor
            highlightRects = other.highlightRects
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SelectionHighlightLayer does not support NSCoding")
    }

    override func draw(in ctx: CGContext) {
        guard !highlightRects.isEmpty else { return }

        ctx.setFillColor(highlightColor)
        ctx.setStrokeColor(highlightBorderColor)
        ctx.setLineWidth(1.0)

        for rect in highlightRects {
            let roundedRect = rect.insetBy(dx: -1, dy: -1)
            let path = CGPath(
                roundedRect: roundedRect,
                cornerWidth: 2, cornerHeight: 2,
                transform: nil
            )
            ctx.addPath(path)
            ctx.drawPath(using: .fillStroke)
        }
    }

    /// Clears all highlights.
    func clearHighlights() {
        highlightRects = []
    }
}
