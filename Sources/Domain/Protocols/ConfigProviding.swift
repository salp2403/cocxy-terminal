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
    let agent: AgentModeConfig
    let activity: ActivityConfig
    let voice: VoiceConfig
    let completions: CompletionConfig
    let codeReview: CodeReviewConfig
    let notifications: NotificationConfig
    let quickTerminal: QuickTerminalConfig
    let keybindings: KeybindingsConfig
    let sessions: SessionsConfig
    let worktree: WorktreeConfig
    let github: GitHubConfig
    let notes: NotesConfig
    let lsp: LSPConfig
    let vim: VimConfig
    let experimental: ExperimentalConfig

    init(
        general: GeneralConfig,
        appearance: AppearanceConfig,
        terminal: TerminalConfig,
        agentDetection: AgentDetectionConfig,
        agent: AgentModeConfig = .defaults,
        activity: ActivityConfig = .defaults,
        voice: VoiceConfig = .defaults,
        completions: CompletionConfig = .defaults,
        codeReview: CodeReviewConfig = .defaults,
        notifications: NotificationConfig,
        quickTerminal: QuickTerminalConfig,
        keybindings: KeybindingsConfig,
        sessions: SessionsConfig,
        worktree: WorktreeConfig = .defaults,
        github: GitHubConfig = .defaults,
        notes: NotesConfig = .defaults,
        lsp: LSPConfig = .defaults,
        vim: VimConfig = .defaults,
        experimental: ExperimentalConfig = .defaults
    ) {
        self.general = general
        self.appearance = appearance
        self.terminal = terminal
        self.agentDetection = agentDetection
        self.agent = agent
        self.activity = activity
        self.voice = voice
        self.completions = completions
        self.codeReview = codeReview
        self.notifications = notifications
        self.quickTerminal = quickTerminal
        self.keybindings = keybindings
        self.sessions = sessions
        self.worktree = worktree
        self.github = github
        self.notes = notes
        self.lsp = lsp
        self.vim = vim
        self.experimental = experimental
    }

    /// Creates a configuration with all default values.
    static var defaults: CocxyConfig {
        CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            agent: .defaults,
            activity: .defaults,
            voice: .defaults,
            completions: .defaults,
            codeReview: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            worktree: .defaults,
            github: .defaults,
            notes: .defaults,
            lsp: .defaults,
            vim: .defaults,
            experimental: .defaults
        )
    }

    // MARK: - Codable — tolerant decoding for backward compatibility

    /// Explicit `Codable` conformance so legacy config JSONs written
    /// before v0.1.81 (which do not carry newer keys) decode cleanly.
    /// Core legacy fields preserve their strict requirement; newly
    /// introduced sections use `decodeIfPresent` so users upgrading
    /// from older releases never hit a decode failure.
    private enum CodingKeys: String, CodingKey {
        case general, appearance, terminal, agentDetection, agent, activity, voice, completions, codeReview
        case notifications, quickTerminal, keybindings, sessions, worktree, github, notes, lsp, vim
        case experimental
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.general = try container.decode(GeneralConfig.self, forKey: .general)
        self.appearance = try container.decode(AppearanceConfig.self, forKey: .appearance)
        self.terminal = try container.decode(TerminalConfig.self, forKey: .terminal)
        self.agentDetection = try container.decode(AgentDetectionConfig.self, forKey: .agentDetection)
        self.agent = try container.decodeIfPresent(AgentModeConfig.self, forKey: .agent)
            ?? .defaults
        self.activity = try container.decodeIfPresent(ActivityConfig.self, forKey: .activity)
            ?? .defaults
        self.voice = try container.decodeIfPresent(VoiceConfig.self, forKey: .voice)
            ?? .defaults
        self.completions = try container.decodeIfPresent(CompletionConfig.self, forKey: .completions)
            ?? .defaults
        self.codeReview = try container.decodeIfPresent(CodeReviewConfig.self, forKey: .codeReview)
            ?? .defaults
        self.notifications = try container.decode(NotificationConfig.self, forKey: .notifications)
        self.quickTerminal = try container.decode(QuickTerminalConfig.self, forKey: .quickTerminal)
        self.keybindings = try container.decode(KeybindingsConfig.self, forKey: .keybindings)
        self.sessions = try container.decode(SessionsConfig.self, forKey: .sessions)
        self.worktree = try container.decodeIfPresent(WorktreeConfig.self, forKey: .worktree)
            ?? .defaults
        self.github = try container.decodeIfPresent(GitHubConfig.self, forKey: .github)
            ?? .defaults
        self.notes = try container.decodeIfPresent(NotesConfig.self, forKey: .notes)
            ?? .defaults
        self.lsp = try container.decodeIfPresent(LSPConfig.self, forKey: .lsp)
            ?? .defaults
        self.vim = try container.decodeIfPresent(VimConfig.self, forKey: .vim)
            ?? .defaults
        self.experimental = try container.decodeIfPresent(ExperimentalConfig.self, forKey: .experimental)
            ?? .defaults
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
            lightTheme: appearance.lightTheme,
            fontFamily: appearance.fontFamily,
            fontSize: overrides.fontSize ?? appearance.fontSize,
            tabPosition: appearance.tabPosition,
            windowPadding: overrides.windowPadding ?? appearance.windowPadding,
            windowPaddingX: overrides.windowPaddingX ?? appearance.windowPaddingX,
            windowPaddingY: overrides.windowPaddingY ?? appearance.windowPaddingY,
            ligatures: appearance.ligatures,
            fontThicken: appearance.fontThicken,
            backgroundOpacity: overrides.backgroundOpacity ?? appearance.backgroundOpacity,
            backgroundBlurRadius: overrides.backgroundBlurRadius ?? appearance.backgroundBlurRadius,
            transparencyChromeTheme: appearance.transparencyChromeTheme,
            auroraEnabled: appearance.auroraEnabled,
            // Status-bar UI preference: stays global (not overridable per-project)
            // for the same reason as auroraEnabled — it's a user choice, not a
            // project setting. Round-tripped here so the merge does not silently
            // reset the field to its default after `.cocxy.toml` overrides apply.
            rateLimitIndicatorEnabled: appearance.rateLimitIndicatorEnabled,
            quickSwitchMode: appearance.quickSwitchMode
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

        // Merge the [worktree] section with per-project overrides. Only
        // non-nil fields replace the corresponding global value —
        // `basePath` and `idLength` stay global (filesystem layout and
        // collision-avoidance concerns, not per-repo choices).
        let mergedWorktree = WorktreeConfig(
            enabled: overrides.worktreeEnabled ?? worktree.enabled,
            basePath: worktree.basePath,
            branchTemplate: overrides.worktreeBranchTemplate ?? worktree.branchTemplate,
            baseRef: overrides.worktreeBaseRef ?? worktree.baseRef,
            onClose: overrides.worktreeOnClose ?? worktree.onClose,
            openInNewTab: overrides.worktreeOpenInNewTab ?? worktree.openInNewTab,
            idLength: worktree.idLength,
            inheritProjectConfig: overrides.worktreeInheritProjectConfig
                ?? worktree.inheritProjectConfig,
            showBadge: overrides.worktreeShowBadge ?? worktree.showBadge
        )

        // Merge the [github] section. `autoRefreshInterval` and
        // `maxItems` stay global — they are client-tuning knobs whose
        // per-project override would only introduce confusion without
        // adding a real workflow. `enabled`, `includeDrafts`,
        // `defaultState` and `mergeEnabled` do make sense per-repo
        // (e.g. a closed-source repo might want `enabled = false`, or
        // a repo that requires GUI-only merges might disable the
        // in-panel merge for everyone working there).
        let mergedGitHub = GitHubConfig(
            enabled: overrides.githubEnabled ?? github.enabled,
            autoRefreshInterval: github.autoRefreshInterval,
            maxItems: github.maxItems,
            includeDrafts: overrides.githubIncludeDrafts ?? github.includeDrafts,
            defaultState: overrides.githubDefaultState ?? github.defaultState,
            mergeEnabled: overrides.githubMergeEnabled ?? github.mergeEnabled
        )

        return CocxyConfig(
            general: general,
            appearance: mergedAppearance,
            terminal: terminal,
            agentDetection: agentDetection,
            // Built-in Agent Mode is a global user preference. Project
            // overrides must not enable an LLM provider or auto-mode from
            // repository-local config.
            agent: agent,
            // Activity tracking is a global user privacy preference. A
            // repository must not be able to enable local activity recording
            // or token cost tracking on behalf of the user.
            activity: activity,
            // Voice input is a global user preference because microphone
            // access and locale selection must never be toggled by a repo.
            voice: voice,
            // Inline completions are a global user opt-in because the
            // provider can read local source text. Repository config must
            // not enable or route completions on the user's behalf.
            completions: completions,
            codeReview: codeReview,
            notifications: notifications,
            quickTerminal: quickTerminal,
            keybindings: mergedKeybindings,
            sessions: sessions,
            worktree: mergedWorktree,
            github: mergedGitHub,
            // Notes config is global by design (storage path, search
            // engine, shortcut, format, auto-save) — they are user-level
            // preferences, not project-level. Preserved verbatim through
            // the project-overrides merge so a `.cocxy.toml` cannot
            // accidentally clobber them.
            notes: notes,
            // LSP is also global/user-level. A project can have its own
            // language-server path later, but the privacy opt-in remains
            // the user's explicit choice.
            lsp: lsp,
            // Vim mode is a global editor preference. Project-level Vim
            // defaults can be added later, but terminal panes must never
            // infer Vim behavior from a repository file.
            vim: vim,
            experimental: experimental
        )
    }
}

// MARK: - General Config

/// `[general]` section of the configuration.
struct GeneralConfig: Codable, Sendable, Equatable {
    /// Path to the shell executable.
    let shell: String
    /// Default working directory for new terminals.
    let workingDirectory: String
    /// Whether to confirm before closing a tab with a running process.
    let confirmCloseProcess: Bool

    static var defaults: GeneralConfig {
        GeneralConfig(
            shell: "/bin/zsh",
            workingDirectory: "~",
            confirmCloseProcess: true
        )
    }
}

// MARK: - Appearance Config

/// `[appearance]` section of the configuration.
struct AppearanceConfig: Codable, Sendable, Equatable {
    /// Name of the active (dark) theme.
    let theme: String
    /// Name of the light theme for auto-switch.
    let lightTheme: String
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
    /// Whether typographic ligatures should be enabled.
    let ligatures: Bool
    /// Whether to thicken font strokes during rasterization (font-thicken).
    ///
    /// Maps directly to CocxyCore's `cocxycore_terminal_set_thicken`, which
    /// toggles `CGContextSetShouldSmoothFonts` on the grayscale glyph atlas.
    /// Off by default so strokes stay thin; users who prefer a heavier look
    /// can enable it in Preferences.
    let fontThicken: Bool
    /// Window background opacity (0.0 = fully transparent, 1.0 = opaque).
    let backgroundOpacity: Double
    /// Background blur radius in points (0 = no blur).
    let backgroundBlurRadius: Double
    /// Forced NSAppearance applied to translucent chrome (sidebar, tab strip,
    /// status bar) when the window is transparent.
    ///
    /// Defaults to `.followSystem`, which preserves the current behavior:
    /// vibrancy views inherit the active `NSAppearance` from the running
    /// system / window chain. `.light` and `.dark` force the chrome to the
    /// chosen tint independently of the user's system appearance — useful
    /// when the terminal's transparency exposes a wallpaper whose tone
    /// doesn't suit the automatic vibrancy blend.
    ///
    /// When `backgroundOpacity >= 1.0` the setting has no visible effect
    /// because the chrome is not translucent.
    let transparencyChromeTheme: TransparencyChromeTheme

    /// Switch for the Aurora chrome (reimagined sidebar, status bar and
    /// command palette inspired by the Liquid Glass design system).
    ///
    /// Defaults to `true` for new installs and legacy configs that do not
    /// yet contain this key. Users can set it to `false` to return to the
    /// classic chrome (`TabBarView`, `StatusBarView`, `CommandPaletteView`).
    ///
    /// Hot-reloadable via `ConfigService.configChangedPublisher`.
    let auroraEnabled: Bool

    /// Switch for the status-bar rate-limit indicator pill.
    ///
    /// When `true` (default), the pill appears in the status bar whenever
    /// the active tab's resolved agent has a registered
    /// `RateLimitProviding` implementation that returns a non-nil
    /// snapshot. When `false`, the wiring in `refreshStatusBar()` clears
    /// the probe's active agent so the pill stays hidden regardless of
    /// the agent or its provider's snapshot.
    ///
    /// Defaults to `true` so legacy configs and fresh installs see the
    /// indicator without any extra opt-in. Hot-reloadable via
    /// `ConfigService.configChangedPublisher`.
    let rateLimitIndicatorEnabled: Bool

    /// QuickSwitch behavior behind the existing "go to attention" shortcut.
    ///
    /// Defaults to `.unified`, which opens the cross-surface switcher for
    /// terminal tabs, browser tabs, worktrees, and notes. `.tabsOnly` keeps
    /// the legacy unread-tab rotation path as a rollback lever.
    let quickSwitchMode: QuickSwitchMode

    /// Effective horizontal padding (prefers windowPaddingX, falls back to windowPadding).
    var effectivePaddingX: Double { windowPaddingX ?? windowPadding }
    /// Effective vertical padding (prefers windowPaddingY, falls back to windowPadding).
    var effectivePaddingY: Double { windowPaddingY ?? windowPadding }

    init(
        theme: String,
        lightTheme: String,
        fontFamily: String,
        fontSize: Double,
        tabPosition: TabPosition,
        windowPadding: Double,
        windowPaddingX: Double?,
        windowPaddingY: Double?,
        ligatures: Bool = true,
        fontThicken: Bool = false,
        backgroundOpacity: Double,
        backgroundBlurRadius: Double,
        transparencyChromeTheme: TransparencyChromeTheme = .followSystem,
        auroraEnabled: Bool = true,
        rateLimitIndicatorEnabled: Bool = true,
        quickSwitchMode: QuickSwitchMode = .unified
    ) {
        self.theme = theme
        self.lightTheme = lightTheme
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.tabPosition = tabPosition
        self.windowPadding = windowPadding
        self.windowPaddingX = windowPaddingX
        self.windowPaddingY = windowPaddingY
        self.ligatures = ligatures
        self.fontThicken = fontThicken
        self.backgroundOpacity = backgroundOpacity
        self.backgroundBlurRadius = backgroundBlurRadius
        self.transparencyChromeTheme = transparencyChromeTheme
        self.auroraEnabled = auroraEnabled
        self.rateLimitIndicatorEnabled = rateLimitIndicatorEnabled
        self.quickSwitchMode = quickSwitchMode
    }

    static var defaults: AppearanceConfig {
        AppearanceConfig(
            theme: "catppuccin-mocha",
            lightTheme: "catppuccin-latte",
            fontFamily: "JetBrainsMono Nerd Font Mono",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            ligatures: false,
            fontThicken: false,
            backgroundOpacity: 1.0,
            backgroundBlurRadius: 0,
            transparencyChromeTheme: .followSystem,
            auroraEnabled: true,
            rateLimitIndicatorEnabled: true,
            quickSwitchMode: .unified
        )
    }

    // MARK: - Codable

    /// Backwards-compatible decoding: configs persisted before the
    /// `transparencyChromeTheme`, `auroraEnabled`,
    /// `rateLimitIndicatorEnabled`, or `quickSwitchMode` keys existed decode
    /// cleanly with their runtime defaults.
    private enum CodingKeys: String, CodingKey {
        case theme
        case lightTheme
        case fontFamily
        case fontSize
        case tabPosition
        case windowPadding
        case windowPaddingX
        case windowPaddingY
        case ligatures
        case fontThicken
        case backgroundOpacity
        case backgroundBlurRadius
        case transparencyChromeTheme
        case auroraEnabled
        case rateLimitIndicatorEnabled
        case quickSwitchMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decode(String.self, forKey: .theme)
        self.lightTheme = try container.decode(String.self, forKey: .lightTheme)
        self.fontFamily = try container.decode(String.self, forKey: .fontFamily)
        self.fontSize = try container.decode(Double.self, forKey: .fontSize)
        self.tabPosition = try container.decode(TabPosition.self, forKey: .tabPosition)
        self.windowPadding = try container.decode(Double.self, forKey: .windowPadding)
        self.windowPaddingX = try container.decodeIfPresent(Double.self, forKey: .windowPaddingX)
        self.windowPaddingY = try container.decodeIfPresent(Double.self, forKey: .windowPaddingY)
        self.ligatures = try container.decode(Bool.self, forKey: .ligatures)
        self.fontThicken = try container.decodeIfPresent(Bool.self, forKey: .fontThicken) ?? false
        self.backgroundOpacity = try container.decode(Double.self, forKey: .backgroundOpacity)
        self.backgroundBlurRadius = try container.decode(Double.self, forKey: .backgroundBlurRadius)
        self.transparencyChromeTheme = try container.decodeIfPresent(
            TransparencyChromeTheme.self,
            forKey: .transparencyChromeTheme
        ) ?? .followSystem
        self.auroraEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .auroraEnabled
        ) ?? AppearanceConfig.defaults.auroraEnabled
        self.rateLimitIndicatorEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .rateLimitIndicatorEnabled
        ) ?? AppearanceConfig.defaults.rateLimitIndicatorEnabled
        self.quickSwitchMode = try container.decodeIfPresent(
            QuickSwitchMode.self,
            forKey: .quickSwitchMode
        ) ?? AppearanceConfig.defaults.quickSwitchMode
    }
}

/// Behavior selected for the keyboard/menu QuickSwitch action.
///
/// The kebab-case raw values are the TOML contract for
/// `[appearance].quickswitch-mode`.
enum QuickSwitchMode: String, Codable, Sendable, Equatable, CaseIterable {
    case unified
    case tabsOnly = "tabs-only"
}

/// Forced appearance for translucent chrome (sidebar, tab strip, status bar)
/// when the window background is transparent.
///
/// - `followSystem`: inherit the active NSAppearance (default, zero-effect).
/// - `light`: pin `NSAppearance.aqua` on every vibrancy view.
/// - `dark`: pin `NSAppearance.darkAqua` on every vibrancy view.
///
/// The kebab-case `rawValue` is the on-disk TOML contract; changing it is a
/// breaking change to the `transparency-chrome-theme` config key.
enum TransparencyChromeTheme: String, Codable, Sendable, Equatable, CaseIterable {
    case followSystem = "follow-system"
    case light
    case dark
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
    /// Policy for OSC 52 clipboard read requests initiated by terminal programs.
    let clipboardReadAccess: ClipboardReadAccess
    /// Maximum inline-image memory budget in MiB.
    let imageMemoryLimitMB: Int
    /// Whether inline image file-transfer mode is enabled.
    let imageFileTransfer: Bool
    /// Whether Sixel inline images are enabled.
    let enableSixelImages: Bool
    /// Whether Kitty inline images are enabled.
    let enableKittyImages: Bool
    /// Whether iTerm2 OSC 1337 inline images are enabled.
    let enableITerm2Images: Bool
    /// Optional directory for persistent inline-image cache data.
    /// Empty string disables disk persistence.
    let imageDiskCacheDirectory: String
    /// Maximum inline-image disk cache budget in MiB.
    let imageDiskCacheLimitMB: Int

    init(
        scrollbackLines: Int,
        cursorStyle: CursorStyle,
        cursorBlink: Bool,
        cursorOpacity: Double,
        mouseHideWhileTyping: Bool,
        copyOnSelect: Bool,
        clipboardPasteProtection: Bool,
        clipboardReadAccess: ClipboardReadAccess,
        imageMemoryLimitMB: Int = 256,
        imageFileTransfer: Bool = false,
        enableSixelImages: Bool = true,
        enableKittyImages: Bool = true,
        enableITerm2Images: Bool = true,
        imageDiskCacheDirectory: String = "",
        imageDiskCacheLimitMB: Int = 512
    ) {
        self.scrollbackLines = scrollbackLines
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.cursorOpacity = cursorOpacity
        self.mouseHideWhileTyping = mouseHideWhileTyping
        self.copyOnSelect = copyOnSelect
        self.clipboardPasteProtection = clipboardPasteProtection
        self.clipboardReadAccess = clipboardReadAccess
        self.imageMemoryLimitMB = imageMemoryLimitMB
        self.imageFileTransfer = imageFileTransfer
        self.enableSixelImages = enableSixelImages
        self.enableKittyImages = enableKittyImages
        self.enableITerm2Images = enableITerm2Images
        self.imageDiskCacheDirectory = imageDiskCacheDirectory
        self.imageDiskCacheLimitMB = imageDiskCacheLimitMB
    }

    static var defaults: TerminalConfig {
        TerminalConfig(
            scrollbackLines: 10_000,
            cursorStyle: .bar,
            cursorBlink: true,
            cursorOpacity: 0.8,
            mouseHideWhileTyping: true,
            copyOnSelect: true,
            clipboardPasteProtection: true,
            clipboardReadAccess: .prompt,
            imageMemoryLimitMB: 256,
            imageFileTransfer: false,
            enableSixelImages: true,
            enableKittyImages: true,
            enableITerm2Images: true,
            imageDiskCacheDirectory: "",
            imageDiskCacheLimitMB: 512
        )
    }

    enum CodingKeys: String, CodingKey {
        case scrollbackLines
        case cursorStyle
        case cursorBlink
        case cursorOpacity
        case mouseHideWhileTyping
        case copyOnSelect
        case clipboardPasteProtection
        case clipboardReadAccess
        case imageMemoryLimitMB
        case imageFileTransfer
        case enableSixelImages
        case enableKittyImages
        case enableITerm2Images
        case imageDiskCacheDirectory
        case imageDiskCacheLimitMB
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scrollbackLines: try container.decodeIfPresent(Int.self, forKey: .scrollbackLines)
                ?? defaults.scrollbackLines,
            cursorStyle: try container.decodeIfPresent(CursorStyle.self, forKey: .cursorStyle)
                ?? defaults.cursorStyle,
            cursorBlink: try container.decodeIfPresent(Bool.self, forKey: .cursorBlink)
                ?? defaults.cursorBlink,
            cursorOpacity: try container.decodeIfPresent(Double.self, forKey: .cursorOpacity)
                ?? defaults.cursorOpacity,
            mouseHideWhileTyping: try container.decodeIfPresent(Bool.self, forKey: .mouseHideWhileTyping)
                ?? defaults.mouseHideWhileTyping,
            copyOnSelect: try container.decodeIfPresent(Bool.self, forKey: .copyOnSelect)
                ?? defaults.copyOnSelect,
            clipboardPasteProtection: try container.decodeIfPresent(Bool.self, forKey: .clipboardPasteProtection)
                ?? defaults.clipboardPasteProtection,
            clipboardReadAccess: try container.decodeIfPresent(ClipboardReadAccess.self, forKey: .clipboardReadAccess)
                ?? defaults.clipboardReadAccess,
            imageMemoryLimitMB: try container.decodeIfPresent(Int.self, forKey: .imageMemoryLimitMB)
                ?? defaults.imageMemoryLimitMB,
            imageFileTransfer: try container.decodeIfPresent(Bool.self, forKey: .imageFileTransfer)
                ?? defaults.imageFileTransfer,
            enableSixelImages: try container.decodeIfPresent(Bool.self, forKey: .enableSixelImages)
                ?? defaults.enableSixelImages,
            enableKittyImages: try container.decodeIfPresent(Bool.self, forKey: .enableKittyImages)
                ?? defaults.enableKittyImages,
            enableITerm2Images: try container.decodeIfPresent(Bool.self, forKey: .enableITerm2Images)
                ?? defaults.enableITerm2Images,
            imageDiskCacheDirectory: try container.decodeIfPresent(String.self, forKey: .imageDiskCacheDirectory)
                ?? defaults.imageDiskCacheDirectory,
            imageDiskCacheLimitMB: try container.decodeIfPresent(Int.self, forKey: .imageDiskCacheLimitMB)
                ?? defaults.imageDiskCacheLimitMB
        )
    }
}

/// Terminal cursor appearance style.
enum CursorStyle: String, Codable, Sendable {
    case block
    case bar
    case underline
}

/// Policy controlling whether terminal programs may read the system clipboard
/// via OSC 52 clipboard-query sequences.
enum ClipboardReadAccess: String, Codable, Sendable, Equatable {
    /// Ask the user before returning clipboard contents to the terminal.
    case prompt
    /// Allow clipboard reads without prompting.
    case allow
    /// Deny clipboard reads and return an empty response.
    case deny
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

// MARK: - Agent Mode Config

/// Provider identifiers for built-in Agent Mode.
///
/// Raw values are the TOML contract for `[agent].preferred-provider`.
/// Foundation Models is intentionally first and default because it is the
/// only zero-cloud option; API providers are selected only when the user
/// explicitly configures them and stores their own key locally.
enum AgentProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case foundationModelsOnDevice = "foundation-models-on-device"
    case anthropic
    case openai
    case google
}

/// Fallback behavior when the configured provider is Foundation Models
/// but the current OS/hardware cannot use it.
///
/// The initial policy is deliberately frictional: require the user to
/// choose another provider rather than silently routing prompts to a
/// cloud API.
enum FoundationModelsFallbackPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case requireExplicitChoice = "require-explicit-choice"
}

/// Runtime provider selection after applying platform capability checks.
enum AgentProviderResolution: Sendable, Equatable {
    case provider(AgentProviderKind)
    case explicitChoiceRequired
}

/// Local conversation history encryption policy.
enum AgentConversationEncryptionMode: String, Codable, Sendable, Equatable, CaseIterable {
    case disabled
    case masterPassword = "master-password"
}

/// `[agent]` section for built-in Agent Mode.
///
/// This is a configuration foundation only. It does not make Agent Mode
/// reachable by itself: `enabled` defaults to false, `autoMode` defaults
/// to false, and Foundation Models fallback never selects a remote
/// provider implicitly.
struct AgentModeConfig: Codable, Sendable, Equatable {
    static let minMaxIterations = 1
    static let maxMaxIterations = 50

    let enabled: Bool
    let preferredProvider: AgentProviderKind
    let foundationModelsFallback: FoundationModelsFallbackPolicy
    let autoMode: Bool
    let computerUseConfirm: Bool
    let maxIterations: Int
    let conversationStorageDir: String
    let conversationEncryption: AgentConversationEncryptionMode

    static var defaults: AgentModeConfig {
        AgentModeConfig(
            enabled: false,
            preferredProvider: .foundationModelsOnDevice,
            foundationModelsFallback: .requireExplicitChoice,
            autoMode: false,
            computerUseConfirm: true,
            maxIterations: 8,
            conversationStorageDir: "~/.config/cocxy/agent/conversations",
            conversationEncryption: .disabled
        )
    }

    init(
        enabled: Bool = false,
        preferredProvider: AgentProviderKind = .foundationModelsOnDevice,
        foundationModelsFallback: FoundationModelsFallbackPolicy = .requireExplicitChoice,
        autoMode: Bool = false,
        computerUseConfirm: Bool = true,
        maxIterations: Int = 8,
        conversationStorageDir: String = "~/.config/cocxy/agent/conversations",
        conversationEncryption: AgentConversationEncryptionMode = .disabled
    ) {
        self.enabled = enabled
        self.preferredProvider = preferredProvider
        self.foundationModelsFallback = foundationModelsFallback
        self.autoMode = autoMode
        self.computerUseConfirm = computerUseConfirm
        self.maxIterations = Self.clampedMaxIterations(maxIterations)
        let trimmedStorageDir = conversationStorageDir.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conversationStorageDir = trimmedStorageDir.isEmpty
            ? Self.defaultConversationStorageDir
            : conversationStorageDir
        self.conversationEncryption = conversationEncryption
    }

    /// Resolves the configured provider without importing platform-only
    /// Foundation Models symbols into common configuration code.
    func effectiveProvider(foundationModelsAvailable: Bool) -> AgentProviderResolution {
        guard preferredProvider == .foundationModelsOnDevice else {
            return .provider(preferredProvider)
        }

        if foundationModelsAvailable {
            return .provider(.foundationModelsOnDevice)
        }

        switch foundationModelsFallback {
        case .requireExplicitChoice:
            return .explicitChoiceRequired
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case preferredProvider
        case foundationModelsFallback
        case autoMode
        case computerUseConfirm
        case maxIterations
        case conversationStorageDir
        case conversationEncryption
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AgentModeConfig.defaults
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? defaults.enabled
        self.preferredProvider = try container.decodeIfPresent(AgentProviderKind.self, forKey: .preferredProvider)
            ?? defaults.preferredProvider
        self.foundationModelsFallback = try container.decodeIfPresent(
            FoundationModelsFallbackPolicy.self,
            forKey: .foundationModelsFallback
        ) ?? defaults.foundationModelsFallback
        self.autoMode = try container.decodeIfPresent(Bool.self, forKey: .autoMode)
            ?? defaults.autoMode
        self.computerUseConfirm = try container.decodeIfPresent(Bool.self, forKey: .computerUseConfirm)
            ?? defaults.computerUseConfirm
        let rawMaxIterations = try container.decodeIfPresent(Int.self, forKey: .maxIterations)
            ?? defaults.maxIterations
        self.maxIterations = Self.clampedMaxIterations(rawMaxIterations)
        let rawStorageDir = try container.decodeIfPresent(String.self, forKey: .conversationStorageDir)
            ?? defaults.conversationStorageDir
        let trimmedStorageDir = rawStorageDir.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conversationStorageDir = trimmedStorageDir.isEmpty
            ? defaults.conversationStorageDir
            : rawStorageDir
        self.conversationEncryption = try container.decodeIfPresent(
            AgentConversationEncryptionMode.self,
            forKey: .conversationEncryption
        ) ?? defaults.conversationEncryption
    }

    private static let defaultConversationStorageDir = "~/.config/cocxy/agent/conversations"

    private static func clampedMaxIterations(_ value: Int) -> Int {
        min(max(value, minMaxIterations), maxMaxIterations)
    }
}

// MARK: - Completion Config

enum CompletionProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case foundationModelsOnDevice = "foundation-models-on-device"
}

/// `[completions]` section for inline editor completions.
///
/// Inline AI completions default off. The only v1 foundation provider is
/// Foundation Models on-device; unsupported systems should leave the feature
/// inert rather than falling back to a network provider implicitly.
struct CompletionConfig: Codable, Sendable, Equatable {
    static let minIdleDelaySeconds = 0.05
    static let maxIdleDelaySeconds = 2.0
    static let minContextUTF16Length = 256
    static let maxContextUTF16Length = 20_000

    let inlineAIEnabled: Bool
    let provider: CompletionProviderKind
    let idleDelaySeconds: Double
    let maxContextUTF16Length: Int
    let enabledLanguageIDs: [String]

    static var defaults: CompletionConfig {
        CompletionConfig(
            inlineAIEnabled: false,
            provider: .foundationModelsOnDevice,
            idleDelaySeconds: 0.2,
            maxContextUTF16Length: 4_000,
            enabledLanguageIDs: [
                "c",
                "cpp",
                "go",
                "javascript",
                "python",
                "rust",
                "swift",
                "typescript",
                "zig",
            ]
        )
    }

    init(
        inlineAIEnabled: Bool = false,
        provider: CompletionProviderKind = .foundationModelsOnDevice,
        idleDelaySeconds: Double = 0.2,
        maxContextUTF16Length: Int = 4_000,
        enabledLanguageIDs: [String] = CompletionConfig.defaults.enabledLanguageIDs
    ) {
        self.inlineAIEnabled = inlineAIEnabled
        self.provider = provider
        self.idleDelaySeconds = Self.clampedIdleDelay(idleDelaySeconds)
        self.maxContextUTF16Length = Self.clampedContextLength(maxContextUTF16Length)
        self.enabledLanguageIDs = Self.normalizedLanguageIDs(enabledLanguageIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case inlineAIEnabled
        case provider
        case idleDelaySeconds
        case maxContextUTF16Length
        case enabledLanguageIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CompletionConfig.defaults
        self.inlineAIEnabled = try container.decodeIfPresent(Bool.self, forKey: .inlineAIEnabled)
            ?? defaults.inlineAIEnabled
        self.provider = try container.decodeIfPresent(CompletionProviderKind.self, forKey: .provider)
            ?? defaults.provider
        self.idleDelaySeconds = Self.clampedIdleDelay(
            try container.decodeIfPresent(Double.self, forKey: .idleDelaySeconds)
                ?? defaults.idleDelaySeconds
        )
        self.maxContextUTF16Length = Self.clampedContextLength(
            try container.decodeIfPresent(Int.self, forKey: .maxContextUTF16Length)
                ?? defaults.maxContextUTF16Length
        )
        self.enabledLanguageIDs = Self.normalizedLanguageIDs(
            try container.decodeIfPresent([String].self, forKey: .enabledLanguageIDs)
                ?? defaults.enabledLanguageIDs
        )
    }

    func allows(languageID: String?) -> Bool {
        guard let normalized = languageID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty,
              !Self.markupLanguageIDs.contains(normalized)
        else {
            return false
        }
        return enabledLanguageIDs.contains(normalized)
    }

    private static let markupLanguageIDs: Set<String> = [
        "markdown",
        "md",
        "plaintext",
        "text",
    ]

    private static func clampedIdleDelay(_ value: Double) -> Double {
        min(max(value, minIdleDelaySeconds), maxIdleDelaySeconds)
    }

    private static func clampedContextLength(_ value: Int) -> Int {
        min(max(value, minContextUTF16Length), maxContextUTF16Length)
    }

    private static func normalizedLanguageIDs(_ rawLanguageIDs: [String]) -> [String] {
        Array(Set(rawLanguageIDs.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })).sorted()
    }
}

// MARK: - Activity Config

/// `[activity]` section for local-only activity and token usage tracking.
///
/// Disabled by default. When enabled, records stay on this Mac under the
/// configured storage directory and are only exported by explicit user action.
struct ActivityConfig: Codable, Sendable, Equatable {
    let enabled: Bool
    let costTrackingEnabled: Bool
    let storageDirectory: String
    let inputCostMicrosPerMillionTokens: Int64
    let outputCostMicrosPerMillionTokens: Int64

    static var defaults: ActivityConfig {
        ActivityConfig(
            enabled: false,
            costTrackingEnabled: false,
            storageDirectory: "~/.config/cocxy/activity",
            inputCostMicrosPerMillionTokens: 0,
            outputCostMicrosPerMillionTokens: 0
        )
    }

    init(
        enabled: Bool = false,
        costTrackingEnabled: Bool = false,
        storageDirectory: String = "~/.config/cocxy/activity",
        inputCostMicrosPerMillionTokens: Int64 = 0,
        outputCostMicrosPerMillionTokens: Int64 = 0
    ) {
        self.enabled = enabled
        self.costTrackingEnabled = costTrackingEnabled
        let trimmedStorage = storageDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        self.storageDirectory = trimmedStorage.isEmpty
            ? Self.defaults.storageDirectory
            : trimmedStorage
        self.inputCostMicrosPerMillionTokens = max(0, inputCostMicrosPerMillionTokens)
        self.outputCostMicrosPerMillionTokens = max(0, outputCostMicrosPerMillionTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case costTrackingEnabled
        case storageDirectory
        case inputCostMicrosPerMillionTokens
        case outputCostMicrosPerMillionTokens
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            costTrackingEnabled: try container.decodeIfPresent(Bool.self, forKey: .costTrackingEnabled)
                ?? defaults.costTrackingEnabled,
            storageDirectory: try container.decodeIfPresent(String.self, forKey: .storageDirectory)
                ?? defaults.storageDirectory,
            inputCostMicrosPerMillionTokens: try container.decodeIfPresent(
                Int64.self,
                forKey: .inputCostMicrosPerMillionTokens
            ) ?? defaults.inputCostMicrosPerMillionTokens,
            outputCostMicrosPerMillionTokens: try container.decodeIfPresent(
                Int64.self,
                forKey: .outputCostMicrosPerMillionTokens
            ) ?? defaults.outputCostMicrosPerMillionTokens
        )
    }

    var privacyPolicy: ActivityPrivacyPolicy {
        ActivityPrivacyPolicy(
            activityTrackingEnabled: enabled,
            tokenCostTrackingEnabled: enabled && costTrackingEnabled
        )
    }

    func tokenCostRate(provider: String, model: String) -> TokenCostRate {
        TokenCostRate(
            provider: provider,
            model: model,
            inputMicrosPerMillionTokens: inputCostMicrosPerMillionTokens,
            outputMicrosPerMillionTokens: outputCostMicrosPerMillionTokens
        )
    }
}

// MARK: - Voice Config

/// `[voice]` section for local Voice input.
///
/// Disabled by default and locale-aware without introducing a backend
/// dependency. The `"system"` sentinel means Cocxy resolves against the
/// user's current macOS locale and the locales supported by Speech on the
/// current machine; any explicit locale is a manual override.
struct VoiceConfig: Codable, Sendable, Equatable {
    static let systemLocaleIdentifier = "system"

    let enabled: Bool
    let localeIdentifier: String

    static var defaults: VoiceConfig {
        VoiceConfig(enabled: false, localeIdentifier: systemLocaleIdentifier)
    }

    init(
        enabled: Bool = false,
        localeIdentifier: String = systemLocaleIdentifier
    ) {
        self.enabled = enabled
        self.localeIdentifier = Self.normalizedLocaleIdentifier(localeIdentifier)
    }

    static func normalizedLocaleIdentifier(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return systemLocaleIdentifier }
        guard trimmed.caseInsensitiveCompare(systemLocaleIdentifier) != .orderedSame else {
            return systemLocaleIdentifier
        }

        let foundationIdentifier = trimmed.replacingOccurrences(of: "-", with: "_")
        return Locale(identifier: foundationIdentifier).identifier
            .replacingOccurrences(of: "_", with: "-")
    }
}

// MARK: - Code Review Config

/// `[code-review]` section of the configuration.
struct CodeReviewConfig: Codable, Sendable, Equatable {
    /// Whether the agent review panel should auto-open when a tracked agent session ends.
    let autoShowOnSessionEnd: Bool

    static var defaults: CodeReviewConfig {
        CodeReviewConfig(autoShowOnSessionEnd: true)
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
//
// The `KeybindingsConfig` struct lives in `Sources/Domain/Models/KeybindingsConfig.swift`
// to keep this file focused on the protocol and the root `CocxyConfig` type.

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

// MARK: - Worktree Config

/// Behaviour when the tab owning a cocxy-managed worktree closes.
///
/// `keep` is the default so no uncommitted work is ever lost silently;
/// users must invoke `cocxy worktree remove` or `prune` explicitly. The
/// remaining values are opt-in conveniences.
enum WorktreeOnClose: String, Codable, Sendable, Equatable {
    /// Leave the worktree on disk. Orphaned from the tab but intact.
    /// Default behaviour.
    case keep
    /// Ask the user what to do via a confirmation dialog.
    case prompt
    /// Remove the worktree automatically if and only if `git status`
    /// reports it clean. Dirty worktrees fall back to `keep`.
    case remove
}

/// `[worktree]` section of the configuration.
///
/// Controls the per-agent git worktree feature introduced in v0.1.81.
/// Every field has a safe default so existing users see no behavioural
/// change after the upgrade — in particular, `enabled` defaults to
/// `false`, which causes every worktree CLI verb to refuse with an
/// actionable error until the user opts in.
struct WorktreeConfig: Codable, Sendable, Equatable {
    /// Master toggle for the worktree feature. When `false`, CLI verbs
    /// and palette actions refuse with a message pointing the user to
    /// this setting. All other fields are ignored until this is `true`.
    let enabled: Bool

    /// Base directory where worktrees are stored. Tilde expansion is
    /// performed at use time (never persisted expanded). The final
    /// worktree path is `<basePath>/<repo-hash>/<worktreeID>/`.
    let basePath: String

    /// Branch name template for new worktrees. Placeholders:
    ///   - `{agent}` → detected agent name (sanitised) or `"worktree"`.
    ///   - `{id}`    → short unique identifier (length = `idLength`).
    ///   - `{date}`  → `YYYY-MM-DD` in system time zone.
    let branchTemplate: String

    /// Base ref to branch off when creating a worktree. Special values:
    ///   - `"HEAD"` → current HEAD of the origin repo (default).
    ///   - `"main"` → the detected default branch (main/master).
    /// Any other string is passed to `git worktree add -b <branch> <ref>`
    /// verbatim, so valid refs include tags, SHAs, and remote branches.
    let baseRef: String

    /// What to do when the tab owning the worktree closes.
    let onClose: WorktreeOnClose

    /// When `true`, `cocxy worktree add` opens a new tab pointing at the
    /// new worktree. When `false`, the current tab switches its working
    /// directory to the worktree path instead.
    let openInNewTab: Bool

    /// Length of the random component of the worktree ID. Clamped to the
    /// range `[4, 12]`. Collisions trigger a retry with `idLength + 1`.
    let idLength: Int

    /// When `true`, `ProjectConfigService` also walks the origin repo for
    /// `.cocxy.toml` when none is found inside the worktree tree. This
    /// lets per-project settings carry over to worktrees without
    /// duplicating the file.
    let inheritProjectConfig: Bool

    /// When `true`, the tab bar and Aurora session row show a worktree
    /// badge on tabs with `worktreeID != nil`.
    let showBadge: Bool

    /// Lower bound enforced on `idLength` when parsing/clamping.
    static let minIDLength: Int = 4
    /// Upper bound enforced on `idLength` when parsing/clamping.
    static let maxIDLength: Int = 12

    static var defaults: WorktreeConfig {
        WorktreeConfig(
            enabled: false,
            basePath: "~/.cocxy/worktrees",
            branchTemplate: "cocxy/{agent}/{id}",
            baseRef: "HEAD",
            onClose: .keep,
            openInNewTab: true,
            idLength: 6,
            inheritProjectConfig: true,
            showBadge: true
        )
    }
}

// MARK: - GitHub Config

/// `[github]` section of the configuration.
///
/// Controls the inline GitHub pane (Cmd+Option+G) introduced in
/// v0.1.84 plus the `cocxy github` CLI verbs. Every field has a safe
/// default so a fresh install sees the pane enabled with sensible
/// auto-refresh, but `gh` itself is never invoked until the user
/// explicitly opens the pane or calls a CLI verb.
///
/// Authentication is delegated to `gh auth status` — Cocxy never
/// stores a GitHub token of its own, and toggling `enabled = false`
/// here is enough to stop every subprocess invocation dead.
struct GitHubConfig: Codable, Sendable, Equatable {

    /// Master switch for the GitHub pane and CLI verbs. When `false`,
    /// the overlay refuses to open and every `cocxy github ...` verb
    /// returns an actionable error pointing here.
    let enabled: Bool

    /// Seconds between silent background refreshes while the pane is
    /// visible. `0` disables auto-refresh entirely (the pane still
    /// refreshes on manual toggle or worktree change). Clamped to
    /// `[0, 3600]` by the parser.
    let autoRefreshInterval: Int

    /// Maximum number of rows requested from `gh pr list` /
    /// `gh issue list`. Clamped to `[1, 200]` by the parser to match
    /// the upstream hard limit.
    let maxItems: Int

    /// When `true`, draft pull requests show in the list. When
    /// `false`, the service filters them out post-decode because
    /// `gh` does not expose a `--hide-drafts` flag.
    let includeDrafts: Bool

    /// Default `--state` value used on first load. Valid values are
    /// `open`, `closed`, `merged` (PR list only) and `all`. Unknown
    /// values fall back to `open` in the parser.
    let defaultState: String

    /// Master switch for the in-panel PR merge feature (v0.1.86).
    /// When `false`, the Code Review panel and the GitHub pane hide
    /// every "Merge PR" affordance and the `cocxy github pr-merge`
    /// CLI verb returns an actionable error pointing here. The flag
    /// is a defensive safety net so a future regression in the merge
    /// flow can be neutralised by a config tweak instead of a hot-fix
    /// release.
    let mergeEnabled: Bool

    /// Lower bound enforced on `autoRefreshInterval` by the parser.
    static let minAutoRefreshInterval: Int = 0
    /// Upper bound enforced on `autoRefreshInterval`. One hour keeps
    /// the ceiling friendly for long-running sessions while still
    /// guaranteeing at least one refresh per hour.
    static let maxAutoRefreshInterval: Int = 3600
    /// Lower bound enforced on `maxItems`.
    static let minMaxItems: Int = 1
    /// Upper bound enforced on `maxItems`. Matches the `gh` CLI hard
    /// cap documented in `gh pr list --help`.
    static let maxMaxItems: Int = 200
    /// Valid `defaultState` values. Kept here so the parser and the
    /// Preferences UI share a single source of truth.
    static let allowedDefaultStates: [String] = ["open", "closed", "merged", "all"]

    init(
        enabled: Bool = true,
        autoRefreshInterval: Int = 60,
        maxItems: Int = 30,
        includeDrafts: Bool = true,
        defaultState: String = "open",
        mergeEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.autoRefreshInterval = autoRefreshInterval
        self.maxItems = maxItems
        self.includeDrafts = includeDrafts
        self.defaultState = defaultState
        self.mergeEnabled = mergeEnabled
    }

    static var defaults: GitHubConfig {
        GitHubConfig(
            enabled: true,
            autoRefreshInterval: 60,
            maxItems: 30,
            includeDrafts: true,
            defaultState: "open",
            mergeEnabled: true
        )
    }

    // MARK: - Codable — tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case enabled, autoRefreshInterval, maxItems, includeDrafts, defaultState
        case mergeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GitHubConfig.defaults
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        self.autoRefreshInterval = try container.decodeIfPresent(Int.self, forKey: .autoRefreshInterval) ?? defaults.autoRefreshInterval
        self.maxItems = try container.decodeIfPresent(Int.self, forKey: .maxItems) ?? defaults.maxItems
        self.includeDrafts = try container.decodeIfPresent(Bool.self, forKey: .includeDrafts) ?? defaults.includeDrafts
        self.defaultState = try container.decodeIfPresent(String.self, forKey: .defaultState) ?? defaults.defaultState
        self.mergeEnabled = try container.decodeIfPresent(Bool.self, forKey: .mergeEnabled) ?? defaults.mergeEnabled
    }
}

// MARK: - Notes Config

/// `[notes]` section of the configuration.
///
/// Controls the per-workspace notes feature: storage location, on-disk
/// format, the search backend, the shortcut that opens the editor, and
/// the auto-save behaviour. All knobs are global (user-level) — no
/// per-project override exists, by design — so a `.cocxy.toml` cannot
/// accidentally redirect notes onto a different folder for one repo.
struct NotesConfig: Codable, Sendable, Equatable {

    /// Master switch. When `false`, the wiring layer skips registering
    /// the shortcut, hides the sidebar section, and never instantiates
    /// the store / search engine.
    let enabled: Bool

    /// On-disk format used by the store when persisting notes. See
    /// `NoteFormat` for the trade-offs between the two formats.
    let format: NoteFormat

    /// Backend the search bar uses when the user types a query. See
    /// `NoteSearchEngineKind` for the trade-offs between the three
    /// implementations.
    let searchEngine: NoteSearchEngineKind

    /// Directory where every workspace's notes folder lives. Tilde
    /// (`~`) is expanded by the consumer at use time so the canonical
    /// representation in TOML stays portable across users.
    let storageDir: String

    /// Keyboard shortcut that opens the notes overlay. Stored as a
    /// canonical lower-case `cmd+alt+n` string and parsed by the
    /// keybindings layer at install time.
    let shortcut: String

    /// Whether the editor auto-saves on edit (debounced) or only on
    /// explicit save. Defaults to `true` so users do not lose work.
    let autoSave: Bool

    /// Debounce window for `autoSave` in seconds. Used as the
    /// `autoSaveInterval` of the underlying `NoteStore`. Stored as
    /// `Double` so users can pick `0.5` for a snappy save without
    /// having to opt out of auto-save altogether.
    let autoSaveIntervalSeconds: Double

    /// Sensible defaults for a fresh install or a config that did not
    /// declare the `[notes]` section. Match the values the
    /// `generateDefaultToml` template emits so a user who has never
    /// edited their config sees the same behaviour as the documented
    /// defaults.
    static var defaults: NotesConfig {
        NotesConfig(
            enabled: true,
            format: .markdown,
            searchEngine: .grep,
            storageDir: "~/.config/cocxy/notes",
            shortcut: "cmd+alt+n",
            autoSave: true,
            autoSaveIntervalSeconds: 5
        )
    }

    init(
        enabled: Bool = true,
        format: NoteFormat = .markdown,
        searchEngine: NoteSearchEngineKind = .grep,
        storageDir: String = "~/.config/cocxy/notes",
        shortcut: String = "cmd+alt+n",
        autoSave: Bool = true,
        autoSaveIntervalSeconds: Double = 5
    ) {
        self.enabled = enabled
        self.format = format
        self.searchEngine = searchEngine
        self.storageDir = storageDir
        self.shortcut = shortcut
        self.autoSave = autoSave
        self.autoSaveIntervalSeconds = autoSaveIntervalSeconds
    }

    // MARK: - Codable — tolerant decoding

    /// Backwards-compatible decoding so configs persisted before the
    /// `[notes]` section existed decode cleanly with their runtime
    /// defaults. Every key is optional with a fallback so a damaged or
    /// truncated TOML never blocks the load path.
    private enum CodingKeys: String, CodingKey {
        case enabled
        case format
        case searchEngine
        case storageDir
        case shortcut
        case autoSave
        case autoSaveIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotesConfig.defaults
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? defaults.enabled
        self.format = try container.decodeIfPresent(NoteFormat.self, forKey: .format)
            ?? defaults.format
        self.searchEngine = try container.decodeIfPresent(NoteSearchEngineKind.self, forKey: .searchEngine)
            ?? defaults.searchEngine
        self.storageDir = try container.decodeIfPresent(String.self, forKey: .storageDir)
            ?? defaults.storageDir
        self.shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
            ?? defaults.shortcut
        self.autoSave = try container.decodeIfPresent(Bool.self, forKey: .autoSave)
            ?? defaults.autoSave
        self.autoSaveIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .autoSaveIntervalSeconds)
            ?? defaults.autoSaveIntervalSeconds
    }
}

// MARK: - LSP Config

/// `[lsp]` section of the configuration.
///
/// LSP is opt-in because language servers receive local document text and
/// workspace URIs. The master `enabled` switch must be true and each language
/// must appear in `enabledLanguageIDs` before `LSPManager` will plan a client.
struct LSPConfig: Codable, Sendable, Equatable {
    let enabled: Bool
    let enabledLanguageIDs: [String]

    static let defaults = LSPConfig(enabled: false, enabledLanguageIDs: [])

    init(enabled: Bool = false, enabledLanguageIDs: [String] = []) {
        self.enabled = enabled
        self.enabledLanguageIDs = LSPConfig.normalizedLanguageIDs(enabledLanguageIDs)
    }

    var managerConfiguration: LSPManager.Configuration {
        guard enabled else { return .defaults }
        return LSPManager.Configuration(enabledLanguageIDs: Set(enabledLanguageIDs))
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case enabledLanguageIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LSPConfig.defaults
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? defaults.enabled
        let rawLanguageIDs = try container.decodeIfPresent([String].self, forKey: .enabledLanguageIDs)
            ?? defaults.enabledLanguageIDs
        self.enabledLanguageIDs = LSPConfig.normalizedLanguageIDs(rawLanguageIDs)
    }

    private static func normalizedLanguageIDs(_ rawLanguageIDs: [String]) -> [String] {
        Array(Set(rawLanguageIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })).sorted()
    }
}

// MARK: - Vim Config

/// `[vim]` section of the configuration.
///
/// Vim mode is editor-only and defaults off so existing editor typing remains
/// unchanged after upgrade. Enabling this flag does not affect terminal panes.
struct VimConfig: Codable, Sendable, Equatable {
    let enabled: Bool

    static let defaults = VimConfig(enabled: false)

    init(enabled: Bool = false) {
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VimConfig.defaults
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? defaults.enabled
    }
}

// MARK: - Experimental Config

/// `[experimental]` feature gates for architecture-heavy P5 work.
///
/// These flags default to `false` so risky surface lifecycle features
/// cannot become reachable until their implementation and smoke matrix
/// are explicitly complete. They are intentionally global, not per-project:
/// PIP and daemon mode affect process/window ownership, not repository
/// behaviour. Explicit per-tab daemon dogfood goes through `Tab` metadata
/// and does not change these defaults.
struct ExperimentalConfig: Codable, Sendable, Equatable {
    let pipEnabled: Bool
    let ptyDaemonEnabled: Bool

    static var defaults: ExperimentalConfig {
        ExperimentalConfig(pipEnabled: false, ptyDaemonEnabled: false)
    }

    init(pipEnabled: Bool = false, ptyDaemonEnabled: Bool = false) {
        self.pipEnabled = pipEnabled
        self.ptyDaemonEnabled = ptyDaemonEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case pipEnabled
        case ptyDaemonEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ExperimentalConfig.defaults
        self.pipEnabled = try container.decodeIfPresent(Bool.self, forKey: .pipEnabled)
            ?? defaults.pipEnabled
        self.ptyDaemonEnabled = try container.decodeIfPresent(Bool.self, forKey: .ptyDaemonEnabled)
            ?? defaults.ptyDaemonEnabled
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
