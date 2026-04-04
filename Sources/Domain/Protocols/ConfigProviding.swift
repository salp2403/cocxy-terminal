// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ConfigProviding.swift - Contract for the configuration provider.

import Foundation
import Combine

// MARK: - Config Providing Protocol

/// Provides application configuration loaded from TOML files.
///
/// Reads `~/.config/cocxy/config.toml` as the primary source and applies
/// sensible defaults for any missing keys. Supports hot-reload: when the
/// file changes on disk, the new configuration is validated and published
/// to all subscribers.
///
/// If the config file does not exist on first launch, a default one is
/// created with documented defaults.
///
/// - SeeAlso: ADR-005 (TOML config format)
/// - SeeAlso: ARCHITECTURE.md Section 7.5
protocol ConfigProviding: AnyObject, Sendable {

    /// The current validated configuration snapshot.
    ///
    /// This is an immutable value type. When the configuration changes,
    /// a new instance is created and published via `configChangedPublisher`.
    var current: CocxyConfig { get }

    /// Publisher that emits the new configuration whenever it changes.
    ///
    /// Hot-reload triggers this when the TOML file is modified on disk.
    /// Manual calls to `reload()` also trigger it.
    var configChangedPublisher: AnyPublisher<CocxyConfig, Never> { get }

    /// Forces an immediate reload from disk.
    ///
    /// Useful after programmatic config changes or for testing.
    /// - Throws: `ConfigError` if the file cannot be read or parsed.
    func reload() throws
}

// MARK: - Configuration Model

/// Complete application configuration.
///
/// Each section maps to a TOML table in `~/.config/cocxy/config.toml`.
/// All fields have sensible defaults so the app works without any config file.
struct CocxyConfig: Codable, Sendable, Equatable {
    let general: GeneralConfig
    let appearance: AppearanceConfig
    let terminal: TerminalConfig
    let agentDetection: AgentDetectionConfig
    let notifications: NotificationConfig
    let quickTerminal: QuickTerminalConfig
    let keybindings: KeybindingsConfig
    let sessions: SessionsConfig

    /// Creates a configuration with all default values.
    static var defaults: CocxyConfig {
        CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
    }

    /// Returns a new configuration with per-project overrides applied.
    ///
    /// Only non-nil fields in `overrides` replace the corresponding global
    /// value. All other fields are preserved unchanged.
    ///
    /// - Note: `agentDetectionExtraPatterns` is stored on `ProjectConfig`
    ///   only and read separately by the detection engine; it is not merged
    ///   into `AgentDetectionConfig`.
    func applying(projectOverrides overrides: ProjectConfig) -> CocxyConfig {
        let mergedAppearance = AppearanceConfig(
            theme: appearance.theme,
            fontFamily: appearance.fontFamily,
            fontSize: overrides.fontSize ?? appearance.fontSize,
            tabPosition: appearance.tabPosition,
            windowPadding: overrides.windowPadding ?? appearance.windowPadding,
            windowPaddingX: overrides.windowPaddingX ?? appearance.windowPaddingX,
            windowPaddingY: overrides.windowPaddingY ?? appearance.windowPaddingY,
            backgroundOpacity: overrides.backgroundOpacity ?? appearance.backgroundOpacity,
            backgroundBlurRadius: overrides.backgroundBlurRadius ?? appearance.backgroundBlurRadius
        )

        let mergedKeybindings: KeybindingsConfig
        if let keyOverrides = overrides.keybindingOverrides {
            mergedKeybindings = KeybindingsConfig(
                newTab: keyOverrides["new-tab"] ?? keybindings.newTab,
                closeTab: keyOverrides["close-tab"] ?? keybindings.closeTab,
                nextTab: keyOverrides["next-tab"] ?? keybindings.nextTab,
                prevTab: keyOverrides["prev-tab"] ?? keybindings.prevTab,
                splitVertical: keyOverrides["split-vertical"] ?? keybindings.splitVertical,
                splitHorizontal: keyOverrides["split-horizontal"] ?? keybindings.splitHorizontal,
                gotoAttention: keyOverrides["goto-attention"] ?? keybindings.gotoAttention,
                toggleQuickTerminal: keyOverrides["toggle-quick-terminal"] ?? keybindings.toggleQuickTerminal
            )
        } else {
            mergedKeybindings = keybindings
        }

        return CocxyConfig(
            general: general,
            appearance: mergedAppearance,
            terminal: terminal,
            agentDetection: agentDetection,
            notifications: notifications,
            quickTerminal: quickTerminal,
            keybindings: mergedKeybindings,
            sessions: sessions
        )
    }
}

// MARK: - General Config

/// `[general]` section of the configuration.
/// Terminal engine backend selection.
///
/// Defaults to `.ghostty` for stability. Set to `.cocxycore` in
/// `[general]` config to use the native CocxyCore engine.
/// Takes effect on next app launch.
enum EngineType: String, Codable, Sendable, Equatable {
    case ghostty
    case cocxycore
}

struct GeneralConfig: Codable, Sendable, Equatable {
    /// Path to the shell executable.
    let shell: String
    /// Default working directory for new terminals.
    let workingDirectory: String
    /// Whether to confirm before closing a tab with a running process.
    let confirmCloseProcess: Bool
    /// Terminal engine backend. Default is ghostty for stability.
    let engineType: EngineType

    static var defaults: GeneralConfig {
        GeneralConfig(
            shell: "/bin/zsh",
            workingDirectory: "~",
            confirmCloseProcess: true,
            engineType: .ghostty
        )
    }
}

// MARK: - Appearance Config

/// `[appearance]` section of the configuration.
struct AppearanceConfig: Codable, Sendable, Equatable {
    /// Name of the active theme.
    let theme: String
    /// Font family for terminal text.
    let fontFamily: String
    /// Font size in points. Valid range: 6...72.
    let fontSize: Double
    /// Position of the tab bar.
    let tabPosition: TabPosition
    /// Padding inside the terminal surface in points (uniform fallback).
    let windowPadding: Double
    /// Horizontal padding in points. Overrides windowPadding for X axis.
    let windowPaddingX: Double?
    /// Vertical padding in points. Overrides windowPadding for Y axis.
    let windowPaddingY: Double?
    /// Window background opacity (0.0 = fully transparent, 1.0 = opaque).
    let backgroundOpacity: Double
    /// Background blur radius in points (0 = no blur).
    let backgroundBlurRadius: Double

    /// Effective horizontal padding (prefers windowPaddingX, falls back to windowPadding).
    var effectivePaddingX: Double { windowPaddingX ?? windowPadding }
    /// Effective vertical padding (prefers windowPaddingY, falls back to windowPadding).
    var effectivePaddingY: Double { windowPaddingY ?? windowPadding }

    static var defaults: AppearanceConfig {
        AppearanceConfig(
            theme: "catppuccin-mocha",
            fontFamily: "JetBrainsMono Nerd Font",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            backgroundOpacity: 1.0,
            backgroundBlurRadius: 0
        )
    }
}

/// Position of the tab bar in the window.
enum TabPosition: String, Codable, Sendable {
    /// Vertical tab bar on the left side (default).
    case left
    /// Horizontal tab bar at the top.
    case top
    /// Tab bar is hidden.
    case hidden
}

// MARK: - Terminal Config

/// `[terminal]` section of the configuration.
///
/// Settings that control the terminal emulator behavior (not appearance).
struct TerminalConfig: Codable, Sendable, Equatable {
    /// Number of lines to keep in the scrollback buffer.
    /// Set to 0 to disable scrollback.
    let scrollbackLines: Int
    /// Cursor style: block, bar, or underline.
    let cursorStyle: CursorStyle
    /// Whether the cursor blinks.
    let cursorBlink: Bool
    /// Cursor opacity (0.0 = invisible, 1.0 = fully opaque).
    let cursorOpacity: Double
    /// Whether to hide the mouse cursor while typing.
    let mouseHideWhileTyping: Bool
    /// Whether to auto-copy selected text to the clipboard.
    let copyOnSelect: Bool
    /// Whether to show a confirmation dialog when pasting text with newlines.
    let clipboardPasteProtection: Bool

    static var defaults: TerminalConfig {
        TerminalConfig(
            scrollbackLines: 10_000,
            cursorStyle: .bar,
            cursorBlink: true,
            cursorOpacity: 0.8,
            mouseHideWhileTyping: true,
            copyOnSelect: true,
            clipboardPasteProtection: true
        )
    }
}

/// Terminal cursor appearance style.
enum CursorStyle: String, Codable, Sendable {
    case block
    case bar
    case underline
}

// MARK: - Agent Detection Config

/// `[agent-detection]` section of the configuration.
struct AgentDetectionConfig: Codable, Sendable, Equatable {
    /// Master switch for agent detection.
    let enabled: Bool
    /// Whether to use OSC sequence detection (layer 1).
    let oscNotifications: Bool
    /// Whether to use pattern matching detection (layer 2).
    let patternMatching: Bool
    /// Whether to use timing heuristics (layer 3).
    let timingHeuristics: Bool
    /// Seconds of inactivity after which an agent is considered finished
    /// (timing heuristic fallback).
    let idleTimeoutSeconds: Int

    static var defaults: AgentDetectionConfig {
        AgentDetectionConfig(
            enabled: true,
            oscNotifications: true,
            patternMatching: true,
            timingHeuristics: true,
            idleTimeoutSeconds: 5
        )
    }
}

// MARK: - Notification Config

/// `[notifications]` section of the configuration.
struct NotificationConfig: Codable, Sendable, Equatable {
    /// Whether to send macOS system notifications.
    let macosNotifications: Bool
    /// Whether to play a sound with notifications.
    let sound: Bool
    /// Whether to show a badge on the tab.
    let badgeOnTab: Bool
    /// Whether to flash the tab briefly on notification.
    let flashTab: Bool
    /// Whether to show an unread count badge on the Dock icon.
    let showDockBadge: Bool
    /// Sound name for agent-finished notifications. "default" uses the system default.
    let soundFinished: String
    /// Sound name for agent-needs-attention notifications. "default" uses the system default.
    let soundAttention: String
    /// Sound name for agent-error notifications. "default" uses the system default.
    let soundError: String

    static var defaults: NotificationConfig {
        NotificationConfig(
            macosNotifications: true,
            sound: true,
            badgeOnTab: true,
            flashTab: true,
            showDockBadge: true,
            soundFinished: "Sounds/cocxy-finished.caf",
            soundAttention: "Sounds/cocxy-attention.caf",
            soundError: "Sounds/cocxy-error.caf"
        )
    }
}

// MARK: - Quick Terminal Config

/// `[quick-terminal]` section of the configuration.
struct QuickTerminalConfig: Codable, Sendable, Equatable {
    /// Whether the quick terminal feature is enabled.
    let enabled: Bool
    /// Keyboard shortcut to toggle the quick terminal.
    let hotkey: String
    /// Edge from which the quick terminal slides in.
    let position: QuickTerminalPosition
    /// Height of the quick terminal as a percentage of the screen (1-100).
    let heightPercentage: Int
    /// Whether the quick terminal hides when the app loses focus.
    let hideOnDeactivate: Bool
    /// Default working directory for the quick terminal session.
    let workingDirectory: String
    /// Animation duration in seconds for slide in/out.
    let animationDuration: Double
    /// Which screen to show the quick terminal on.
    let screen: QuickTerminalScreen

    static var defaults: QuickTerminalConfig {
        QuickTerminalConfig(
            enabled: true,
            hotkey: "cmd+grave",
            position: .top,
            heightPercentage: 40,
            hideOnDeactivate: true,
            workingDirectory: "~",
            animationDuration: 0.15,
            screen: .mouse
        )
    }
}

/// Which screen to show the quick terminal on.
enum QuickTerminalScreen: String, Codable, Sendable {
    /// The screen where the mouse cursor is.
    case mouse
    /// The main screen.
    case main
}

/// Edge of the screen for the quick terminal panel.
enum QuickTerminalPosition: String, Codable, Sendable {
    case top, bottom, left, right
}

// MARK: - Keybindings Config

/// `[keybindings]` section of the configuration.
struct KeybindingsConfig: Codable, Sendable, Equatable {
    let newTab: String
    let closeTab: String
    let nextTab: String
    let prevTab: String
    let splitVertical: String
    let splitHorizontal: String
    let gotoAttention: String
    let toggleQuickTerminal: String

    static var defaults: KeybindingsConfig {
        KeybindingsConfig(
            newTab: "cmd+t",
            closeTab: "cmd+w",
            nextTab: "cmd+shift+]",
            prevTab: "cmd+shift+[",
            splitVertical: "cmd+d",
            splitHorizontal: "cmd+shift+d",
            gotoAttention: "cmd+shift+u",
            toggleQuickTerminal: "cmd+grave"
        )
    }
}

// MARK: - Sessions Config

/// `[sessions]` section of the configuration.
struct SessionsConfig: Codable, Sendable, Equatable {
    /// Whether to auto-save the session periodically.
    let autoSave: Bool
    /// Interval in seconds between auto-saves.
    let autoSaveInterval: Int
    /// Whether to restore the last session on launch.
    let restoreOnLaunch: Bool

    static var defaults: SessionsConfig {
        SessionsConfig(
            autoSave: true,
            autoSaveInterval: 30,
            restoreOnLaunch: true
        )
    }
}

// MARK: - Config Errors

/// Errors that can occur during configuration operations.
enum ConfigError: Error, Sendable {
    /// The config file could not be read from disk.
    case readFailed(path: String, reason: String)
    /// The TOML content could not be parsed.
    case parseFailed(reason: String)
    /// A config value is out of its valid range.
    case validationFailed(key: String, reason: String)
    /// The config file could not be written (for creating defaults).
    case writeFailed(path: String, reason: String)
}
