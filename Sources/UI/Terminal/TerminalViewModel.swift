// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalViewModel.swift - Presentation logic for a terminal surface.

import Foundation
import Combine

// MARK: - Terminal View Model

/// Presentation logic for a single terminal surface.
///
/// Bridges the terminal engine output with the agent detection engine and
/// notification system. The view model does NOT import AppKit -- it works
/// with domain types only (per ADR-002).
///
/// ## Data flow
///
/// ```
/// Terminal engine output -> TerminalViewModel -> AgentDetectionEngine
///                                            -> NotificationManager
/// ```
///
/// ## Lifecycle
///
/// ```
/// TerminalViewModel()          -- Created (isRunning = false)
///   .markRunning(surfaceID:)   -- Surface active, shell spawned
///   .updateTitle(...)          -- Title changes from OSC callbacks
///   .markStopped()             -- Surface destroyed, shell exited
/// ```
///
/// - SeeAlso: ADR-002 (MVVM pattern)
/// - SeeAlso: `CocxyCoreView` (the view this model drives)
@MainActor
final class TerminalViewModel: ObservableObject {

    // MARK: - Published State

    /// Terminal title, updated via OSC 0/2 sequences from the shell.
    /// Bound to the tab label in the UI.
    @Published private(set) var title: String = "Terminal"

    /// Whether the terminal surface is actively running.
    /// Controls UI state like tab badges and close confirmation dialogs.
    @Published private(set) var isRunning: Bool = false

    /// Whether the user is currently scrolled back in the scrollback buffer.
    /// When true, new output should not auto-scroll to the bottom.
    @Published var isScrolledBack: Bool = false

    /// Current font size in points. Allows runtime zoom via Cmd+/-.
    /// Initialized from config, modified by zoom actions.
    @Published var currentFontSize: CGFloat = 14.0

    /// Last click count received from mouse events (1=single, 2=double, 3=triple).
    /// Used to determine selection mode: character, word, or line.
    private(set) var lastClickCount: Int = 0

    /// Whether the user is currently dragging to select text.
    private(set) var isDragging: Bool = false

    /// Whether to automatically copy selected text to clipboard on mouse-up.
    /// Configurable per-session; defaults to true (macOS terminal convention).
    var autoCopyOnSelect: Bool = true

    // MARK: - Surface State

    /// The ID of the active surface, or `nil` if no surface is running.
    private(set) var surfaceID: SurfaceID?

    // MARK: - Dependencies

    /// Reference to the terminal engine.
    /// Used to forward commands and query surface state.
    private(set) weak var engine: (any TerminalEngine)?

    /// Convenience accessor for callers that need the concrete CocxyCoreBridge.
    var cocxyCoreBridge: CocxyCoreBridge? { engine as? CocxyCoreBridge }

    // MARK: - Initialization

    /// Creates a TerminalViewModel with an optional engine reference.
    ///
    /// - Parameter engine: The terminal engine. Can be nil for testing
    ///   or when the engine has not been initialized yet.
    init(engine: (any TerminalEngine)? = nil) {
        self.engine = engine
    }

    // MARK: - State Updates

    /// Updates the terminal title.
    ///
    /// Called by the bridge's OSC handler when the shell sends a title change
    /// sequence (OSC 0 or OSC 2).
    ///
    /// - Parameter newTitle: The new title string from the terminal.
    func updateTitle(_ newTitle: String) {
        title = newTitle
    }

    /// Marks the terminal as running with the given surface ID.
    ///
    /// Called after a surface has been successfully created and the shell
    /// has been spawned.
    ///
    /// - Parameter surfaceID: The ID of the newly created surface.
    func markRunning(surfaceID: SurfaceID) {
        self.surfaceID = surfaceID
        self.isRunning = true
    }

    /// Marks the terminal as stopped and clears the surface reference.
    ///
    /// Called when the surface is destroyed, either because the shell exited
    /// or the user closed the tab.
    func markStopped() {
        self.surfaceID = nil
        self.isRunning = false
    }

    // MARK: - Mouse State

    /// Records a mouse-down event with its click count for selection mode.
    ///
    /// - Parameter clickCount: Number of consecutive clicks (1, 2, or 3).
    func recordMouseDown(clickCount: Int) {
        lastClickCount = clickCount
        isDragging = true
    }

    /// Records a mouse-up event, ending any active drag selection.
    func recordMouseUp() {
        isDragging = false
    }

    // MARK: - Font Size

    /// The minimum allowed font size in points.
    static let minimumFontSize: CGFloat = 6.0

    /// The maximum allowed font size in points.
    static let maximumFontSize: CGFloat = 72.0

    /// The font size step used for zoom in/out.
    static let fontSizeStep: CGFloat = 1.0

    /// The default font size restored by Cmd+0.
    private(set) var defaultFontSize: CGFloat = 14.0

    /// Sets the default font size from config. Used during initialization.
    ///
    /// - Parameter size: The configured font size in points.
    func setDefaultFontSize(_ size: CGFloat) {
        let clamped = max(Self.minimumFontSize, min(Self.maximumFontSize, size))
        defaultFontSize = clamped
        currentFontSize = clamped
    }

    /// Increases the font size by one step (Cmd++).
    @discardableResult
    func zoomIn() -> CGFloat {
        let newSize = min(currentFontSize + Self.fontSizeStep, Self.maximumFontSize)
        currentFontSize = newSize
        return currentFontSize
    }

    /// Decreases the font size by one step (Cmd+-).
    @discardableResult
    func zoomOut() -> CGFloat {
        let newSize = max(currentFontSize - Self.fontSizeStep, Self.minimumFontSize)
        currentFontSize = newSize
        return currentFontSize
    }

    /// Resets the font size to the configured default (Cmd+0).
    @discardableResult
    func resetZoom() -> CGFloat {
        currentFontSize = defaultFontSize
        return currentFontSize
    }

    /// Applies a runtime font size without changing the configured default.
    ///
    /// Used to keep every surface in a tab visually in sync when the user
    /// zooms the active terminal.
    func setCurrentFontSize(_ size: CGFloat) {
        currentFontSize = max(Self.minimumFontSize, min(Self.maximumFontSize, size))
    }

    // Agent state and detection are managed at the Tab model level
    // (Tab.agentState, Tab.detectedAgent) and wired through MainWindowController
    // which routes terminal output to the AgentDetectionEngine for ALL surfaces.
}
