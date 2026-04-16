// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PreferencesViewModel.swift - View model for editable preferences.

import Foundation
import Combine
import AppKit

// MARK: - Preferences View Model

/// View model that holds editable copies of all user-facing configuration
/// properties and can persist changes to disk.
///
/// Loaded from a `CocxyConfig` snapshot. When the user saves, it generates
/// a complete TOML string and writes it via the injected `ConfigFileProviding`,
/// then fires `onSave` so the caller can trigger a config reload.
///
/// ## Validation
///
/// Values are validated (clamped to valid ranges) at TOML generation time,
/// not at edit time. This allows the user to type freely without fighting
/// constraints on every keystroke.
///
/// ## Usage
///
/// ```swift
/// let vm = PreferencesViewModel(config: configService.current)
/// vm.onSave = { try? configService.reload() }
/// let view = PreferencesView(viewModel: vm)
/// ```
///
/// - SeeAlso: `PreferencesView` for the SwiftUI presentation.
/// - SeeAlso: `ConfigService` for config loading and hot-reload.
@MainActor
final class PreferencesViewModel: ObservableObject {

    // MARK: - General

    /// Path to the shell executable (e.g., "/bin/zsh").
    @Published var shell: String

    /// Default working directory for new terminals.
    @Published var workingDirectory: String

    /// Whether to confirm before closing a tab with a running process.
    @Published var confirmCloseProcess: Bool

    // MARK: - Appearance

    /// Name of the active theme (e.g., "catppuccin-mocha").
    @Published var theme: String

    /// Font family for terminal text (e.g., "JetBrainsMono Nerd Font Mono").
    @Published var fontFamily: String

    /// Font size in points. Clamped to 8...32 on save.
    @Published var fontSize: Double

    /// Tab bar position as a raw string ("left", "top", "hidden").
    @Published var tabPosition: String

    /// Uniform window padding in points. Clamped to 0...40 on save.
    @Published var windowPadding: Double
    /// Whether typographic ligatures are enabled.
    @Published var ligatures: Bool

    /// Window background opacity (0.3 = very transparent, 1.0 = fully opaque).
    /// Controls vibrancy on sidebar, tab strip, and status bar.
    @Published var backgroundOpacity: Double

    // MARK: - Agent Detection

    /// Master switch for agent detection.
    @Published var agentDetectionEnabled: Bool

    /// Whether to use OSC sequence detection.
    @Published var oscNotifications: Bool

    /// Whether to use pattern matching detection.
    @Published var patternMatching: Bool

    /// Whether to use timing heuristics.
    @Published var timingHeuristics: Bool

    /// Idle timeout in seconds. Clamped to 1...300 on save.
    @Published var idleTimeoutSeconds: Int

    // MARK: - Notifications

    /// Whether to send macOS system notifications.
    @Published var macosNotifications: Bool

    /// Whether to play a sound with notifications.
    @Published var sound: Bool

    /// Whether to show a badge on the tab.
    @Published var badgeOnTab: Bool

    /// Whether to flash the tab briefly on notification.
    @Published var flashTab: Bool

    /// Whether to show an unread count badge on the Dock icon.
    @Published var showDockBadge: Bool

    // MARK: - Read-Only Terminal Settings

    /// Scrollback buffer size from the saved config.
    var scrollbackLines: Int { savedConfig.terminal.scrollbackLines }

    /// Cursor style as a raw string from the saved config.
    var cursorStyle: String { savedConfig.terminal.cursorStyle.rawValue }

    /// Whether the cursor blinks, from the saved config.
    var cursorBlink: Bool { savedConfig.terminal.cursorBlink }
    /// Whether inline image file transfer is enabled.
    @Published var imageFileTransfer: Bool
    /// Whether sixel images are enabled.
    @Published var enableSixelImages: Bool
    /// Whether kitty images are enabled.
    @Published var enableKittyImages: Bool
    /// Inline image memory limit in MiB.
    @Published var imageMemoryLimitMB: Int

    // MARK: - Read-Only Keybindings

    /// New tab shortcut from the saved config.
    var keybindingNewTab: String { savedConfig.keybindings.newTab }

    /// Close tab shortcut from the saved config.
    var keybindingCloseTab: String { savedConfig.keybindings.closeTab }

    /// Next tab shortcut from the saved config.
    var keybindingNextTab: String { savedConfig.keybindings.nextTab }

    /// Previous tab shortcut from the saved config.
    var keybindingPrevTab: String { savedConfig.keybindings.prevTab }

    /// Split vertical shortcut from the saved config.
    var keybindingSplitVertical: String { savedConfig.keybindings.splitVertical }

    /// Split horizontal shortcut from the saved config.
    var keybindingSplitHorizontal: String { savedConfig.keybindings.splitHorizontal }

    /// Go to attention shortcut from the saved config.
    var keybindingGotoAttention: String { savedConfig.keybindings.gotoAttention }

    /// Quick terminal toggle shortcut from the saved config.
    var keybindingQuickTerminal: String { savedConfig.keybindings.toggleQuickTerminal }

    // MARK: - Read-only Context

    /// Theme names available for selection in the picker.
    let availableThemes: [String]

    /// Installed fixed-pitch font families available on this Mac.
    let availableFontFamilies: [String]

    /// Curated installed fonts surfaced as quick picks.
    let recommendedFontFamilies: [String]

    /// Curated fonts shipped directly inside the app bundle.
    let bundledFontFamilies: [String]

    /// Callback invoked after a successful save.
    var onSave: (() -> Void)?

    /// Callback invoked when the user discards unsaved changes.
    /// Restores all values to the original config snapshot.
    var onDiscard: (() -> Void)?

    // MARK: - Dirty Tracking

    /// Whether any setting has been modified since load or last save.
    ///
    /// Compares every editable property against the original config snapshot.
    /// Used to show an unsaved-changes alert when the user closes the window.
    var hasUnsavedChanges: Bool {
        let c = savedConfig
        return shell != c.general.shell
            || workingDirectory != c.general.workingDirectory
            || confirmCloseProcess != c.general.confirmCloseProcess
            || theme != c.appearance.theme
            || fontFamily != c.appearance.fontFamily
            || fontSize != c.appearance.fontSize
            || tabPosition != c.appearance.tabPosition.rawValue
            || windowPadding != c.appearance.windowPadding
            || ligatures != c.appearance.ligatures
            || backgroundOpacity != c.appearance.backgroundOpacity
            || imageFileTransfer != c.terminal.imageFileTransfer
            || enableSixelImages != c.terminal.enableSixelImages
            || enableKittyImages != c.terminal.enableKittyImages
            || imageMemoryLimitMB != c.terminal.imageMemoryLimitMB
            || agentDetectionEnabled != c.agentDetection.enabled
            || oscNotifications != c.agentDetection.oscNotifications
            || patternMatching != c.agentDetection.patternMatching
            || timingHeuristics != c.agentDetection.timingHeuristics
            || idleTimeoutSeconds != c.agentDetection.idleTimeoutSeconds
            || macosNotifications != c.notifications.macosNotifications
            || sound != c.notifications.sound
            || badgeOnTab != c.notifications.badgeOnTab
            || flashTab != c.notifications.flashTab
            || showDockBadge != c.notifications.showDockBadge
    }

    /// Reverts all editable properties to the original config snapshot.
    func discardChanges() {
        let c = savedConfig
        shell = c.general.shell
        workingDirectory = c.general.workingDirectory
        confirmCloseProcess = c.general.confirmCloseProcess
        theme = c.appearance.theme
        fontFamily = c.appearance.fontFamily
        fontSize = c.appearance.fontSize
        tabPosition = c.appearance.tabPosition.rawValue
        windowPadding = c.appearance.windowPadding
        ligatures = c.appearance.ligatures
        backgroundOpacity = c.appearance.backgroundOpacity
        imageFileTransfer = c.terminal.imageFileTransfer
        enableSixelImages = c.terminal.enableSixelImages
        enableKittyImages = c.terminal.enableKittyImages
        imageMemoryLimitMB = c.terminal.imageMemoryLimitMB
        agentDetectionEnabled = c.agentDetection.enabled
        oscNotifications = c.agentDetection.oscNotifications
        patternMatching = c.agentDetection.patternMatching
        timingHeuristics = c.agentDetection.timingHeuristics
        idleTimeoutSeconds = c.agentDetection.idleTimeoutSeconds
        macosNotifications = c.notifications.macosNotifications
        sound = c.notifications.sound
        badgeOnTab = c.notifications.badgeOnTab
        flashTab = c.notifications.flashTab
        showDockBadge = c.notifications.showDockBadge
    }

    // MARK: - Private

    /// The file provider used to persist configuration to disk.
    private let fileProvider: ConfigFileProviding

    /// The config snapshot used for dirty tracking and as source of truth for
    /// sections not exposed in the UI (terminal, quick-terminal, keybindings, sessions).
    /// Updated after each successful save so `hasUnsavedChanges` resets to false.
    private var savedConfig: CocxyConfig

    // MARK: - Initialization

    /// Creates a view model populated from the given configuration.
    ///
    /// - Parameters:
    ///   - config: The current configuration snapshot.
    ///   - fileProvider: Destination for writes. Defaults to disk.
    init(config: CocxyConfig, fileProvider: ConfigFileProviding = DiskConfigFileProvider()) {
        self.savedConfig = config
        self.fileProvider = fileProvider

        // General
        self.shell = config.general.shell
        self.workingDirectory = config.general.workingDirectory
        self.confirmCloseProcess = config.general.confirmCloseProcess

        // Appearance — resolve theme to display name for picker compatibility.
        // Config may store "catppuccin-mocha" but picker uses "Catppuccin Mocha".
        let themeNames = Self.defaultThemeNames()
        self.theme = Self.resolveDisplayName(for: config.appearance.theme, from: themeNames)
        self.fontFamily = config.appearance.fontFamily
        self.fontSize = config.appearance.fontSize
        self.tabPosition = config.appearance.tabPosition.rawValue
        self.windowPadding = config.appearance.windowPadding
        self.ligatures = config.appearance.ligatures
        self.backgroundOpacity = config.appearance.backgroundOpacity

        // Agent Detection
        self.agentDetectionEnabled = config.agentDetection.enabled
        self.oscNotifications = config.agentDetection.oscNotifications
        self.patternMatching = config.agentDetection.patternMatching
        self.timingHeuristics = config.agentDetection.timingHeuristics
        self.idleTimeoutSeconds = config.agentDetection.idleTimeoutSeconds

        // Notifications
        self.macosNotifications = config.notifications.macosNotifications
        self.sound = config.notifications.sound
        self.badgeOnTab = config.notifications.badgeOnTab
        self.flashTab = config.notifications.flashTab
        self.showDockBadge = config.notifications.showDockBadge
        self.imageFileTransfer = config.terminal.imageFileTransfer
        self.enableSixelImages = config.terminal.enableSixelImages
        self.enableKittyImages = config.terminal.enableKittyImages
        self.imageMemoryLimitMB = config.terminal.imageMemoryLimitMB

        // Available themes from built-in list.
        self.availableThemes = Self.defaultThemeNames()
        self.availableFontFamilies = FontFallbackResolver.availableFixedPitchFamilies()
        self.recommendedFontFamilies = FontFallbackResolver.recommendedFamilies()
        self.bundledFontFamilies = FontFallbackResolver.bundledFamilies
    }

    // MARK: - Font Resolution

    /// The concrete installed font family that will be used after fallback resolution.
    var effectiveFontFamily: String {
        FontFallbackResolver.resolvedFamily(for: fontFamily) ?? FontFallbackResolver.menlo
    }

    /// Whether the selected family is shipped with the app bundle.
    var isSelectedFontBundled: Bool {
        FontFallbackResolver.bundledFamilies.contains {
            $0.caseInsensitiveCompare(fontFamily) == .orderedSame
        }
    }

    /// Whether the resolved family comes from Cocxy's bundled set.
    var isEffectiveFontBundled: Bool {
        FontFallbackResolver.bundledFamilies.contains {
            $0.caseInsensitiveCompare(effectiveFontFamily) == .orderedSame
        }
    }

    /// Whether the user-entered family resolves directly without fallback.
    var isSelectedFontInstalled: Bool {
        FontFallbackResolver.isFontAvailable(fontFamily)
    }

    /// Human-friendly explanation of the effective font choice.
    var fontResolutionSummary: String {
        let effective = effectiveFontFamily
        if isSelectedFontInstalled, isSelectedFontBundled {
            return "Included with Cocxy: \(effective)"
        }
        if isSelectedFontInstalled {
            return "Using installed font: \(effective)"
        }
        if isEffectiveFontBundled {
            return "\"\(fontFamily)\" is not installed. Cocxy will fall back to bundled \(effective)."
        }
        return "\"\(fontFamily)\" is not installed. Cocxy will fall back to \(effective)."
    }

    // MARK: - Save

    /// Persists the current settings to the config file and fires `onSave`.
    ///
    /// Values are clamped to valid ranges before writing. Sections that are
    /// not editable in the UI (terminal, quick-terminal, keybindings, sessions)
    /// are preserved from the original config.
    ///
    /// - Throws: If the file provider cannot write to disk.
    func save() throws {
        let toml = generateToml()
        try fileProvider.writeConfigFile(toml)
        // Update the saved snapshot so hasUnsavedChanges resets to false.
        // This prevents the "unsaved changes" alert from appearing after save.
        updateSavedSnapshot()
        onSave?()
    }

    /// Updates the saved config snapshot to match the current editable values.
    ///
    /// Called after a successful save so that `hasUnsavedChanges` returns false
    /// until the user makes further edits.
    private func updateSavedSnapshot() {
        let clampedOpacity = min(max(backgroundOpacity, 0.3), 1.0)
        savedConfig = CocxyConfig(
            general: GeneralConfig(
                shell: shell,
                workingDirectory: workingDirectory,
                confirmCloseProcess: confirmCloseProcess
            ),
            appearance: AppearanceConfig(
                theme: theme,
                lightTheme: savedConfig.appearance.lightTheme,
                fontFamily: fontFamily,
                fontSize: fontSize,
                tabPosition: TabPosition(rawValue: tabPosition) ?? .left,
                windowPadding: windowPadding,
                windowPaddingX: savedConfig.appearance.windowPaddingX,
                windowPaddingY: savedConfig.appearance.windowPaddingY,
                ligatures: ligatures,
                backgroundOpacity: clampedOpacity,
                backgroundBlurRadius: savedConfig.appearance.backgroundBlurRadius
            ),
            terminal: TerminalConfig(
                scrollbackLines: savedConfig.terminal.scrollbackLines,
                cursorStyle: savedConfig.terminal.cursorStyle,
                cursorBlink: savedConfig.terminal.cursorBlink,
                cursorOpacity: savedConfig.terminal.cursorOpacity,
                mouseHideWhileTyping: savedConfig.terminal.mouseHideWhileTyping,
                copyOnSelect: savedConfig.terminal.copyOnSelect,
                clipboardPasteProtection: savedConfig.terminal.clipboardPasteProtection,
                clipboardReadAccess: savedConfig.terminal.clipboardReadAccess,
                imageMemoryLimitMB: imageMemoryLimitMB,
                imageFileTransfer: imageFileTransfer,
                enableSixelImages: enableSixelImages,
                enableKittyImages: enableKittyImages
            ),
            agentDetection: AgentDetectionConfig(
                enabled: agentDetectionEnabled,
                oscNotifications: oscNotifications,
                patternMatching: patternMatching,
                timingHeuristics: timingHeuristics,
                idleTimeoutSeconds: idleTimeoutSeconds
            ),
            notifications: NotificationConfig(
                macosNotifications: macosNotifications,
                sound: sound,
                badgeOnTab: badgeOnTab,
                flashTab: flashTab,
                showDockBadge: showDockBadge,
                soundFinished: savedConfig.notifications.soundFinished,
                soundAttention: savedConfig.notifications.soundAttention,
                soundError: savedConfig.notifications.soundError
            ),
            quickTerminal: savedConfig.quickTerminal,
            keybindings: savedConfig.keybindings,
            sessions: savedConfig.sessions
        )
    }

    // MARK: - TOML Generation

    /// Generates a complete TOML configuration string from the current values.
    ///
    /// Clamps numeric values to their valid ranges. Non-editable sections are
    /// taken from the original config snapshot to avoid data loss.
    func generateToml() -> String {
        let clampedFontSize = Int(min(max(fontSize, 8), 32))
        let clampedPadding = Int(min(max(windowPadding, 0), 40))
        let clampedOpacity = min(max(backgroundOpacity, 0.3), 1.0)
        let clampedTimeout = min(max(idleTimeoutSeconds, 1), 300)
        let clampedImageMemoryLimitMB = min(max(imageMemoryLimitMB, 1), 4096)

        let defaults = savedConfig

        return """
        # Cocxy Terminal Configuration
        # Documentation: ~/.config/cocxy/

        [general]
        shell = "\(shell)"
        working-directory = "\(workingDirectory)"
        confirm-close-process = \(confirmCloseProcess)

        [appearance]
        theme = "\(theme)"
        light-theme = "\(defaults.appearance.lightTheme)"
        font-family = "\(fontFamily)"
        font-size = \(clampedFontSize)
        tab-position = "\(tabPosition)"
        window-padding = \(clampedPadding)
        ligatures = \(ligatures)
        background-opacity = \(String(format: "%.2f", clampedOpacity))

        [terminal]
        scrollback-lines = \(defaults.terminal.scrollbackLines)
        cursor-style = "\(defaults.terminal.cursorStyle.rawValue)"
        cursor-blink = \(defaults.terminal.cursorBlink)
        clipboard-paste-protection = \(defaults.terminal.clipboardPasteProtection)
        clipboard-read-access = "\(defaults.terminal.clipboardReadAccess.rawValue)"
        image-memory-limit-mb = \(clampedImageMemoryLimitMB)
        image-file-transfer = \(imageFileTransfer)
        enable-sixel-images = \(enableSixelImages)
        enable-kitty-images = \(enableKittyImages)

        [agent-detection]
        enabled = \(agentDetectionEnabled)
        osc-notifications = \(oscNotifications)
        pattern-matching = \(patternMatching)
        timing-heuristics = \(timingHeuristics)
        idle-timeout-seconds = \(clampedTimeout)

        [notifications]
        macos-notifications = \(macosNotifications)
        sound = \(sound)
        badge-on-tab = \(badgeOnTab)
        flash-tab = \(flashTab)
        show-dock-badge = \(showDockBadge)
        sound-finished = "\(savedConfig.notifications.soundFinished)"
        sound-attention = "\(savedConfig.notifications.soundAttention)"
        sound-error = "\(savedConfig.notifications.soundError)"

        [quick-terminal]
        hotkey = "\(defaults.quickTerminal.hotkey)"
        position = "\(defaults.quickTerminal.position.rawValue)"
        height-percentage = \(defaults.quickTerminal.heightPercentage)

        [keybindings]
        new-tab = "\(defaults.keybindings.newTab)"
        close-tab = "\(defaults.keybindings.closeTab)"
        next-tab = "\(defaults.keybindings.nextTab)"
        prev-tab = "\(defaults.keybindings.prevTab)"
        split-vertical = "\(defaults.keybindings.splitVertical)"
        split-horizontal = "\(defaults.keybindings.splitHorizontal)"
        goto-attention = "\(defaults.keybindings.gotoAttention)"
        toggle-quick-terminal = "\(defaults.keybindings.toggleQuickTerminal)"

        [sessions]
        auto-save = \(defaults.sessions.autoSave)
        auto-save-interval = \(defaults.sessions.autoSaveInterval)
        restore-on-launch = \(defaults.sessions.restoreOnLaunch)
        """
    }

    // MARK: - Theme Names

    /// Returns the default list of built-in theme display names.
    ///
    /// These MUST match the `name` field in `ThemeEngine`'s built-in theme
    /// definitions so that `themeByName()` can resolve them.
    private static func defaultThemeNames() -> [String] {
        [
            "Catppuccin Mocha",
            "Catppuccin Latte",
            "Catppuccin Frappe",
            "Catppuccin Macchiato",
            "One Dark",
            "Solarized Dark",
            "Solarized Light",
            "Dracula",
            "Nord",
            "Gruvbox Dark",
            "Tokyo Night",
        ]
    }

    /// Resolves a config theme name to the matching display name.
    ///
    /// Config files may store kebab-case names ("catppuccin-mocha") while the
    /// picker uses display names ("Catppuccin Mocha"). This method normalizes
    /// both and returns the display name if a match is found, or the original
    /// name as fallback (for custom themes).
    private static func resolveDisplayName(for configName: String, from displayNames: [String]) -> String {
        // Exact match first.
        if displayNames.contains(configName) {
            return configName
        }
        // Normalized match: strip hyphens/spaces, lowercase.
        let normalized = configName.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        for displayName in displayNames {
            let displayNormalized = displayName.lowercased()
                .replacingOccurrences(of: " ", with: "")
            if normalized == displayNormalized {
                return displayName
            }
        }
        return configName
    }
}
