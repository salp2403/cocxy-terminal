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
}

typealias TerminalHostView = NSView & TerminalHostingView
