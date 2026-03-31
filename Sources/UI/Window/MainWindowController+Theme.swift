// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Theme.swift - Theme cycling and config application.

import AppKit

// MARK: - Theme Management

/// Extension that handles terminal color scheme cycling and
/// configuration change application.
extension MainWindowController {

    /// Cycles through terminal color schemes by recreating the terminal engine.
    ///
    /// This destroys all ghostty surfaces, creates a new bridge with the target
    /// theme palette, and recreates surfaces for every tab. Shell sessions restart
    /// but working directories are preserved.
    func toggleTheme() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        activeThemeIndex = (activeThemeIndex + 1) % Self.themeNames.count
        let targetName = Self.themeNames[activeThemeIndex]

        appDelegate.switchTheme(to: targetName)
    }

    /// Applies configuration changes to the window.
    ///
    /// Updates the window background color, tab position, and triggers
    /// a theme switch when the theme has changed.
    ///
    /// - Parameter config: The new configuration to apply.
    func applyConfig(_ config: CocxyConfig) {
        let themeName = config.appearance.theme

        let backgroundColor: NSColor
        if let theme = try? ThemeEngineImpl().themeByName(themeName) {
            backgroundColor = CodableColor(hex: theme.palette.background).nsColor
        } else {
            backgroundColor = CocxyColors.base
        }

        window?.backgroundColor = backgroundColor

        // Apply tab position changes.
        if let sidebar = tabBarView,
           let strip = horizontalTabStripView {
            applyTabPosition(config.appearance.tabPosition, sidebar: sidebar, strip: strip)
        }

        // Apply notification toggle changes to tab bar.
        tabBarView?.flashTabEnabled = config.notifications.flashTab
        tabBarView?.badgeOnTabEnabled = config.notifications.badgeOnTab

        // Apply vibrancy/opacity changes to all chrome components.
        applyEffectiveAppearance(config.appearance)

        // Detect theme change and trigger surface recreation.
        let currentThemeName = activeThemeIndex < Self.themeNames.count
            ? Self.themeNames[activeThemeIndex] : nil
        if currentThemeName != themeName {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.switchTheme(to: themeName)
            }
        }
    }

    // MARK: - Tab Position

    /// Applies the tab position setting by showing/hiding the sidebar and tab strip.
    ///
    /// Uses `NSSplitView.setPosition(_:ofDividerAt:)` to collapse/expand the
    /// sidebar instead of relying solely on `isHidden`. Without explicit divider
    /// repositioning, `NSSplitView` leaves a visual gap where the sidebar was.
    ///
    /// - Parameters:
    ///   - position: The desired tab bar position.
    ///   - sidebar: The vertical sidebar view.
    ///   - strip: The horizontal tab strip view.
    func applyTabPosition(_ position: TabPosition, sidebar: NSView, strip: NSView) {
        guard let splitView = mainSplitView else { return }

        // The strip is the workspace toolbar (split pane tabs, browser/markdown
        // icons). It is always visible alongside whichever tab navigation mode
        // is active. Only `.hidden` hides everything.
        switch position {
        case .left:
            sidebar.isHidden = false
            strip.isHidden = false
            // Don't call setPosition here — the sidebar already has its correct
            // frame from configureWindow. Calling setPosition before the window
            // has its final size (e.g., restored from autosave) causes the
            // NSSplitView to miscalculate the terminal area width.
        case .top:
            sidebar.isHidden = true
            strip.isHidden = false
            splitView.setPosition(0, ofDividerAt: 0)
        case .hidden:
            sidebar.isHidden = true
            strip.isHidden = true
            splitView.setPosition(0, ofDividerAt: 0)
        }

        splitView.adjustSubviews()
    }
}
