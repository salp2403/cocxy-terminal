// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalHostView.swift - Shared host-view contract for terminal engines.

import AppKit

// MARK: - Terminal Host View

/// Common contract implemented by terminal host views.
///
/// `CocxyCoreView` renders a terminal surface, participates in tab/split
/// lifecycle, and exposes the small set of hooks the window controller needs.
/// The protocol remains as a seam for tests and future host-view refactors.
@MainActor
protocol TerminalHostingView: AnyObject {
    var terminalViewModel: TerminalViewModel? { get }
    var onFileDrop: (([URL]) -> Bool)? { get set }
    var onUserInputSubmitted: (() -> Void)? { get set }

    func syncSizeWithTerminal()
    func showNotificationRing(color: NSColor)
    func hideNotificationRing()
    func handleShellPrompt(row: Int, column: Int)
    func updateInteractionMetrics()
    func configureSurfaceIfNeeded(
        bridge: any TerminalEngine,
        surfaceID: SurfaceID
    )
    func requestImmediateRedraw()

    /// Re-anchors the host view's CVDisplayLink (or equivalent render
    /// timing source) to the display currently hosting the window.
    ///
    /// Called as a safety net from `MainWindowController` window-change
    /// delegate methods so that detached or hidden surface views — which
    /// do NOT receive `NSWindow.didChangeScreenNotification` because
    /// they have no window reference — still get re-anchored when the
    /// user moves the window between displays. The view-local observer
    /// also calls this when the view is attached, so the operation must
    /// be idempotent.
    func refreshDisplayLinkAnchor()
}

typealias TerminalHostView = NSView & TerminalHostingView
