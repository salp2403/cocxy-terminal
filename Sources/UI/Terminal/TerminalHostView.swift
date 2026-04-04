// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalHostView.swift - Shared host-view contract for terminal engines.

import AppKit

// MARK: - Terminal Host View

/// Common contract implemented by engine-specific terminal host views.
///
/// `TerminalSurfaceView` and `CocxyCoreView` both render a terminal surface,
/// participate in tab/split lifecycle, and expose the same small set of hooks
/// the window controller needs. This keeps the rest of the UI layer agnostic
/// to whether the active engine is Ghostty or CocxyCore.
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

// MARK: - Terminal Host View Factory

@MainActor
enum TerminalHostViewFactory {
    static func makeView(
        engine: any TerminalEngine,
        viewModel: TerminalViewModel
    ) -> TerminalHostView {
        if engine is CocxyCoreBridge {
            return CocxyCoreView(viewModel: viewModel)
        }
        return TerminalSurfaceView(viewModel: viewModel)
    }
}
