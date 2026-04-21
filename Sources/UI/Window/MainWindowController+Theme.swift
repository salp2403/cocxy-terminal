// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Theme.swift - Theme cycling and config application.

import AppKit

// MARK: - Transparency Chrome Theme -> NSAppearance

extension TransparencyChromeTheme {

    /// Resolves the enum to a forced `NSAppearance` for translucent chrome.
    ///
    /// - Returns: `NSAppearance.aqua` for `.light`, `.darkAqua` for `.dark`,
    ///   and `nil` for `.followSystem` so vibrancy views inherit the
    ///   active appearance from the window chain.
    var vibrancyAppearance: NSAppearance? {
        switch self {
        case .followSystem:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Theme Management

/// Extension that handles terminal color scheme cycling and
/// configuration change application.
extension MainWindowController {

    /// Cycles through terminal color schemes in place.
    ///
    /// CocxyCore applies theme updates without tearing down live surfaces, so
    /// PTYs and scrollback remain intact while the palette changes.
    func toggleTheme() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        activeThemeIndex = (activeThemeIndex + 1) % Self.themeNames.count
        let targetName = Self.themeNames[activeThemeIndex]

        appDelegate.switchTheme(to: targetName)
    }

    /// Applies configuration changes to the window.
    ///
    /// Updates the window background, tab position, vibrancy, and triggers
    /// a bridge restart when embedded-at-init properties have changed
    /// (theme, font, padding, cursor, shell).
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

        // Propagate config to the notification stack so preference changes
        // take effect immediately (macOS notifications, sounds, dock badge).
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.notificationManager?.updateConfig(config)
            appDelegate.notificationAdapter?.updateConfig(config)
            appDelegate.dockBadgeController?.updateConfig(config)
        }

        // Apply vibrancy/opacity changes to all chrome components.
        applyEffectiveAppearance(config.appearance)

        // Toggle Aurora chrome visibility (no-op while flag is off and
        // the controller has not been instantiated yet).
        applyAuroraChromeIfNeeded(for: config.appearance)

        // Determine which runtime-facing terminal settings changed. CocxyCore
        // can apply theme, font, ligature and image-transport updates in
        // place, while shell defaults only affect surfaces created after
        // the change.
        //
        // IMPORTANT: every flag in this predicate MUST be handled by
        // `AppDelegate.applyBridgeConfigurationChanges(from:to:)` below,
        // and vice versa — any flag handled there that is missing here
        // will be silently dropped because `applyBridgeConfigurationChanges`
        // is never invoked. The `ligatures` flag was the canonical example:
        // before this predicate listed it, toggling "Enable ligatures" in
        // preferences did nothing visible until another unrelated change
        // happened to flip this flag. The image settings listed below had
        // the same latent bug — they are applied by `applyImageSettings`
        // in the bridge, but the predicate never detected that they had
        // changed, so toggling file transfer / Sixel / Kitty / memory
        // limit silently failed until the user also changed a font or
        // theme.
        let old = lastAppliedConfig
        let runtimeTerminalConfigChanged =
            old?.appearance.theme != config.appearance.theme ||
            old?.appearance.fontFamily != config.appearance.fontFamily ||
            old?.appearance.fontSize != config.appearance.fontSize ||
            old?.appearance.ligatures != config.appearance.ligatures ||
            old?.appearance.fontThicken != config.appearance.fontThicken ||
            old?.appearance.windowPadding != config.appearance.windowPadding ||
            old?.appearance.windowPaddingX != config.appearance.windowPaddingX ||
            old?.appearance.windowPaddingY != config.appearance.windowPaddingY ||
            old?.general.shell != config.general.shell ||
            old?.terminal.clipboardReadAccess != config.terminal.clipboardReadAccess ||
            old?.terminal.imageMemoryLimitMB != config.terminal.imageMemoryLimitMB ||
            old?.terminal.imageFileTransfer != config.terminal.imageFileTransfer ||
            old?.terminal.enableSixelImages != config.terminal.enableSixelImages ||
            old?.terminal.enableKittyImages != config.terminal.enableKittyImages

        lastAppliedConfig = config

        if runtimeTerminalConfigChanged,
           let appDelegate = NSApp.delegate as? AppDelegate,
           appDelegate.windowController === self {
            appDelegate.applyBridgeConfigurationChanges(from: old, to: config)
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

        // The Aurora chrome mounts its sidebar as an overlay inside
        // `tabBarView`. Hiding that container (`.top` or `.hidden`)
        // would hide Aurora too, since a hidden parent hides every
        // child. While the feature flag is on, force the sidebar to
        // stay visible so Aurora has a canvas to render on.
        // `auroraEnabled = false` restores the user's preference
        // immediately on the next config reload.
        let auroraEnabled = isAuroraChromeActive || configService?.current.appearance.auroraEnabled == true
        let effective: TabPosition = auroraEnabled ? .left : position

        // The strip is the workspace toolbar (split pane tabs, browser/markdown
        // icons). It is always visible alongside whichever tab navigation mode
        // is active. Only `.hidden` hides everything.
        switch effective {
        case .left:
            sidebar.isHidden = false
            strip.isHidden = false
            // Do not force-reset the divider on initial window setup or after
            // a user resize; that can fight autosave/restoration. Only restore
            // the default width when a previous `.top` / `.hidden` layout
            // collapsed the sidebar to zero and the user explicitly returns to
            // the classic left sidebar.
            if sidebar.frame.width < 1 {
                splitView.setPosition(Self.sidebarWidth, ofDividerAt: 0)
            }
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
