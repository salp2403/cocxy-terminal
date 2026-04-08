// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteCoordinator.swift - Coordinator connecting Command Palette actions to real managers.

import Foundation

// MARK: - Command Palette Coordinating Protocol

/// Contract for coordinating Command Palette actions with the real application managers.
///
/// Each method maps to a built-in action in the Command Palette. The coordinator
/// holds weak references to the underlying managers (TabManager, SplitManager, etc.)
/// and delegates each call to the appropriate manager method.
///
/// This protocol decouples the `CommandPaletteEngine` from concrete manager types,
/// enabling clean testing and preventing circular dependencies.
///
/// - SeeAlso: `CommandPaletteEngineImpl` (consumes this coordinator)
/// - SeeAlso: `CommandPaletteCoordinatorImpl` (concrete implementation)
@MainActor
protocol CommandPaletteCoordinating: AnyObject {
    /// Open a new terminal tab.
    func newTab()

    /// Close the currently active tab.
    func closeTab()

    /// Switch to the next tab.
    func nextTab()

    /// Switch to the previous tab.
    func previousTab()

    /// Split the focused pane vertically.
    func splitVertical()

    /// Split the focused pane horizontally.
    func splitHorizontal()

    /// Toggle the agent dashboard panel visibility.
    func toggleDashboard()

    /// Toggle the quick terminal overlay.
    func toggleQuickTerminal()

    /// Jump to the most urgent unread/attention tab.
    func performQuickSwitch()

    /// Switch the active theme by name.
    ///
    /// - Parameter name: The display name of the theme to apply.
    func switchTheme(name: String)

    /// Open the scrollback search overlay.
    func showScrollbackSearch()

    /// Open the timeline panel.
    func showTimeline()
}

// MARK: - Command Palette Coordinator Implementation

/// Concrete coordinator that connects Command Palette actions to real managers.
///
/// Holds weak references to avoid retain cycles. When a manager reference is nil,
/// the corresponding action is a silent no-op.
///
/// - SeeAlso: `CommandPaletteCoordinating`
@MainActor
final class CommandPaletteCoordinatorImpl: CommandPaletteCoordinating {

    // MARK: - Dependencies (weak to avoid retain cycles)

    private weak var tabManager: TabManager?
    private weak var splitManager: SplitManager?
    private weak var dashboardViewModel: AgentDashboardViewModel?
    private weak var themeEngine: ThemeEngineImpl?

    /// Closure for full tab cleanup (surface destruction, buffer cleanup, etc.).
    /// When set, `closeTab()` delegates here instead of calling `tabManager.removeTab` directly.
    var onCloseTab: ((TabID) -> Void)?

    /// Closure for creating a tab with full surface wiring (PTY, view, handlers).
    /// Without this, `newTab()` only creates the domain model.
    var onNewTab: (() -> Void)?

    /// Closures for AppKit-layer overlays that cannot be referenced from the domain layer.
    var onQuickTerminal: (() -> Void)?
    var onQuickSwitch: (() -> Void)?
    var onScrollbackSearch: (() -> Void)?
    var onTimeline: (() -> Void)?

    // MARK: - Initialization

    /// Creates a coordinator wired to the real managers.
    ///
    /// - Parameters:
    ///   - tabManager: The tab manager for tab operations.
    ///   - splitManager: The split manager for pane split operations.
    ///   - dashboardViewModel: The dashboard ViewModel for visibility toggle.
    ///   - themeEngine: The theme engine for theme switching. Nil if not yet available.
    init(
        tabManager: TabManager,
        splitManager: SplitManager,
        dashboardViewModel: AgentDashboardViewModel,
        themeEngine: ThemeEngineImpl?
    ) {
        self.tabManager = tabManager
        self.splitManager = splitManager
        self.dashboardViewModel = dashboardViewModel
        self.themeEngine = themeEngine
    }

    // MARK: - CommandPaletteCoordinating

    func newTab() {
        if let onNewTab {
            onNewTab()
        } else {
            tabManager?.addTab()
        }
    }

    func closeTab() {
        guard let tabManager = tabManager,
              let activeId = tabManager.activeTabID else { return }
        if let onCloseTab {
            onCloseTab(activeId)
        } else {
            tabManager.removeTab(id: activeId)
        }
    }

    func nextTab() {
        tabManager?.nextTab()
    }

    func previousTab() {
        tabManager?.previousTab()
    }

    func splitVertical() {
        splitManager?.splitFocused(direction: .vertical)
    }

    func splitHorizontal() {
        splitManager?.splitFocused(direction: .horizontal)
    }

    func toggleDashboard() {
        dashboardViewModel?.toggleVisibility()
    }

    func toggleQuickTerminal() {
        onQuickTerminal?()
    }

    func performQuickSwitch() {
        onQuickSwitch?()
    }

    func switchTheme(name: String) {
        try? themeEngine?.apply(themeName: name)
    }

    func showScrollbackSearch() {
        onScrollbackSearch?()
    }

    func showTimeline() {
        onTimeline?()
    }
}
