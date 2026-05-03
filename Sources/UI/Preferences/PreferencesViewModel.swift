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
    /// Whether font stroke thickening is enabled (maps to font-thicken).
    @Published var fontThicken: Bool

    /// Window background opacity (0.3 = very transparent, 1.0 = fully opaque).
    /// Controls vibrancy on sidebar, tab strip, and status bar.
    @Published var backgroundOpacity: Double

    /// Forced chrome appearance while the window is transparent.
    ///
    /// Has no visible effect when `backgroundOpacity >= 1.0`.
    /// Default `.followSystem` preserves the pre-existing behaviour where
    /// translucent chrome inherits the active system appearance.
    @Published var transparencyChromeTheme: TransparencyChromeTheme

    /// Whether the experimental Aurora chrome is enabled.
    @Published var auroraEnabled: Bool
    /// Density/layout mode for the Aurora vertical sidebar.
    @Published var auroraSidebarDisplayMode: AuroraSidebarDisplayMode
    /// Signal promoted into Aurora sidebar session rows.
    @Published var auroraSidebarPrimaryInfo: AuroraSidebarPrimaryInfo

    /// Whether the status-bar rate-limit indicator pill is enabled.
    ///
    /// When `false`, `MainWindowController.refreshStatusBar()` clears
    /// the active agent on the probe service so the pill stays hidden
    /// regardless of the agent or its provider's snapshot. Hot-reloads
    /// through the standard config publisher pipeline.
    @Published var rateLimitIndicatorEnabled: Bool

    /// QuickSwitch behavior for the go-to-attention shortcut.
    @Published var quickSwitchMode: QuickSwitchMode

    /// Whether the chrome theme picker should be interactive.
    ///
    /// Mirrors the runtime rule: the override only matters while the
    /// window is translucent, so we disable the picker when fully opaque
    /// so users aren't surprised by an apparently dead control.
    var isTransparencyChromeThemeEditable: Bool {
        backgroundOpacity < 1.0
    }

    /// Whether the classic tab-position picker should be interactive.
    ///
    /// Aurora owns its own workspace sidebar while enabled. The classic
    /// `left/top/hidden` preference is still preserved on disk, but it is only
    /// applied when Aurora is off.
    var isClassicTabPositionEditable: Bool {
        !auroraEnabled
    }

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

    // MARK: - Agent Mode

    /// Master opt-in for built-in local Agent Mode.
    @Published var agentModeEnabled: Bool

    /// Preferred provider for built-in Agent Mode.
    @Published var agentPreferredProvider: AgentProviderKind

    /// Whether Agent Mode may continue approved actions automatically.
    @Published var agentAutoMode: Bool

    /// Whether Computer Use tool calls require explicit per-action approval.
    @Published var agentComputerUseConfirm: Bool

    /// Maximum provider/tool iterations for one Agent Mode turn.
    @Published var agentMaxIterations: Int

    /// Local conversation history storage directory.
    @Published var agentConversationStorageDir: String

    /// Local conversation history encryption policy.
    @Published var agentConversationEncryption: AgentConversationEncryptionMode

    /// Draft API key for the currently selected remote provider.
    @Published var agentAPIKeyDraft: String

    /// Short status for the last provider-key save/delete action.
    @Published var agentAPIKeyStatus: String?

    /// Draft master password for optional conversation encryption.
    @Published var agentConversationMasterPasswordDraft: String

    /// Short status for the last conversation encryption secret action.
    @Published var agentConversationMasterPasswordStatus: String?

    // MARK: - MCP Servers

    /// Raw JSON for the user-managed MCP server config file.
    @Published var mcpConfigText: String = MCPServerConfigLoader.defaultConfigText

    /// Short validation/save status for MCP config editing.
    @Published var mcpConfigStatus: String?

    /// Parsed preview of the current MCP draft after load, validate, or save.
    @Published private(set) var mcpConfiguredServers: [MCPServer] = []

    // MARK: - Voice Input

    /// Master opt-in for local Voice input.
    @Published var voiceEnabled: Bool

    /// `"system"` or a normalized locale identifier selected by the user.
    @Published var voiceLocaleIdentifier: String

    // MARK: - Inline Completions

    /// Master opt-in for local inline AI completions in editor tabs.
    @Published var completionInlineAIEnabled: Bool

    /// Idle delay before the editor asks the local provider for a suggestion.
    @Published var completionIdleDelaySeconds: Double

    /// Maximum UTF-16 context window sent to the local completion provider.
    @Published var completionMaxContextUTF16Length: Int

    /// Normalized language IDs eligible for inline completions.
    @Published var completionEnabledLanguageIDs: Set<String>

    // MARK: - Activity

    /// Master opt-in for local activity dashboard persistence.
    @Published var activityTrackingEnabled: Bool

    /// Whether local token usage and estimated costs are recorded.
    @Published var activityCostTrackingEnabled: Bool

    /// Local input-token rate in micro-dollars per million tokens.
    @Published var activityInputCostMicrosPerMillionTokens: Int64

    /// Local output-token rate in micro-dollars per million tokens.
    @Published var activityOutputCostMicrosPerMillionTokens: Int64

    // MARK: - Code Review

    /// Whether Cocxy opens the Code Review panel automatically when an
    /// agent session finishes with changes.
    @Published var codeReviewAutoShowOnSessionEnd: Bool

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
    /// Whether iTerm2 OSC 1337 images are enabled.
    @Published var enableITerm2Images: Bool
    /// Inline image memory limit in MiB.
    @Published var imageMemoryLimitMB: Int
    /// Optional directory for persistent inline-image cache data.
    @Published var imageDiskCacheDirectory: String
    /// Inline image disk cache limit in MiB.
    @Published var imageDiskCacheLimitMB: Int

    // MARK: - Language Servers

    /// Master opt-in for local Language Server Protocol clients.
    @Published var lspEnabled: Bool

    /// Normalized language IDs that may start LSP clients when LSP is enabled.
    @Published var lspEnabledLanguageIDs: Set<String>

    // MARK: - Editor

    /// Master opt-in for editor-only Vim key handling.
    @Published var vimEnabled: Bool

    // MARK: - Worktree (v0.1.81)

    /// Master toggle for the per-agent worktree feature. When `false`,
    /// every `cocxy worktree-*` verb refuses with a hint pointing here.
    @Published var worktreeEnabled: Bool

    /// Base directory for worktree storage (supports `~`).
    @Published var worktreeBasePath: String

    /// Branch template with `{agent}`/`{id}`/`{date}` placeholders.
    @Published var worktreeBranchTemplate: String

    /// Base ref for `git worktree add` (e.g., `HEAD`, `main`).
    @Published var worktreeBaseRef: String

    /// Behaviour when the tab owning a worktree closes. Stored as the
    /// enum's raw value so the Picker binding stays simple.
    @Published var worktreeOnClose: String

    /// Whether `cocxy worktree-add` opens a new tab for the worktree.
    @Published var worktreeOpenInNewTab: Bool

    /// Random id length. Clamped to `[minIDLength, maxIDLength]` on save.
    @Published var worktreeIDLength: Int

    /// Whether `.cocxy.toml` lookup falls back to the origin repo from
    /// within a worktree.
    @Published var worktreeInheritProjectConfig: Bool

    /// Whether the tab bar and Aurora sidebar show a worktree badge.
    @Published var worktreeShowBadge: Bool

    // MARK: - GitHub (v0.1.84)

    /// Master toggle for the GitHub pane and `cocxy github` CLI verbs.
    @Published var githubEnabled: Bool

    /// Seconds between silent pane refreshes while the pane is visible.
    /// `0` disables auto-refresh entirely. Clamped to
    /// `[GitHubConfig.minAutoRefreshInterval, GitHubConfig.maxAutoRefreshInterval]` on save.
    @Published var githubAutoRefreshInterval: Int

    /// Maximum rows requested from `gh pr list` / `gh issue list`.
    /// Clamped to `[GitHubConfig.minMaxItems, GitHubConfig.maxMaxItems]` on save.
    @Published var githubMaxItems: Int

    /// Whether draft pull requests show in the list.
    @Published var githubIncludeDrafts: Bool

    /// Default `--state` value on first load (`open`, `closed`,
    /// `merged` or `all`). Falls back to `"open"` on save if the user
    /// enters an unknown value.
    @Published var githubDefaultState: String

    /// Master toggle for the in-panel PR merge feature (v0.1.86).
    /// When `false`, the Code Review panel and the GitHub pane hide
    /// every "Merge PR" affordance and the `cocxy github pr-merge`
    /// CLI verb returns an actionable error pointing here.
    @Published var githubMergeEnabled: Bool

    // MARK: - Notes

    @Published var notesEnabled: Bool
    @Published var notesFormat: String
    @Published var notesSearchEngine: String
    @Published var notesStorageDir: String
    @Published var notesShortcut: String
    @Published var notesAutoSave: Bool
    @Published var notesAutoSaveIntervalSeconds: Double

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

    /// Local language-server metadata exposed in Preferences.
    let availableLSPLanguages: [LSPServerConfiguration]

    /// Local Speech locales exposed in Preferences.
    let availableVoiceLocales: [VoiceLocaleOption]

    /// Local code languages exposed for inline completion opt-in.
    let availableCompletionLanguageIDs: [String]

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
            || !Self.themeNamesMatch(theme, c.appearance.theme)
            || fontFamily != c.appearance.fontFamily
            || fontSize != c.appearance.fontSize
            || tabPosition != c.appearance.tabPosition.rawValue
            || windowPadding != c.appearance.windowPadding
            || ligatures != c.appearance.ligatures
            || fontThicken != c.appearance.fontThicken
            || backgroundOpacity != c.appearance.backgroundOpacity
            || transparencyChromeTheme != c.appearance.transparencyChromeTheme
            || auroraEnabled != c.appearance.auroraEnabled
            || auroraSidebarDisplayMode != c.appearance.auroraSidebarDisplayMode
            || auroraSidebarPrimaryInfo != c.appearance.auroraSidebarPrimaryInfo
            || rateLimitIndicatorEnabled != c.appearance.rateLimitIndicatorEnabled
            || quickSwitchMode != c.appearance.quickSwitchMode
            || imageFileTransfer != c.terminal.imageFileTransfer
            || enableSixelImages != c.terminal.enableSixelImages
            || enableKittyImages != c.terminal.enableKittyImages
            || enableITerm2Images != c.terminal.enableITerm2Images
            || imageMemoryLimitMB != c.terminal.imageMemoryLimitMB
            || imageDiskCacheDirectory != c.terminal.imageDiskCacheDirectory
            || imageDiskCacheLimitMB != c.terminal.imageDiskCacheLimitMB
            || agentDetectionEnabled != c.agentDetection.enabled
            || oscNotifications != c.agentDetection.oscNotifications
            || patternMatching != c.agentDetection.patternMatching
            || timingHeuristics != c.agentDetection.timingHeuristics
            || idleTimeoutSeconds != c.agentDetection.idleTimeoutSeconds
            || agentModeHasUnsavedChanges(comparedTo: c.agent)
            || voiceHasUnsavedChanges(comparedTo: c.voice)
            || completionHasUnsavedChanges(comparedTo: c.completions)
            || activityHasUnsavedChanges(comparedTo: c.activity)
            || codeReviewAutoShowOnSessionEnd != c.codeReview.autoShowOnSessionEnd
            || macosNotifications != c.notifications.macosNotifications
            || sound != c.notifications.sound
            || badgeOnTab != c.notifications.badgeOnTab
            || flashTab != c.notifications.flashTab
            || showDockBadge != c.notifications.showDockBadge
            || worktreeHasUnsavedChanges(comparedTo: c.worktree)
            || githubHasUnsavedChanges(comparedTo: c.github)
            || notesHasUnsavedChanges(comparedTo: c.notes)
            || lspHasUnsavedChanges(comparedTo: c.lsp)
            || vimHasUnsavedChanges(comparedTo: c.vim)
            || hasUnsavedMCPConfigChanges
            || (pendingKeybindings != nil && pendingKeybindings != c.keybindings)
    }

    var hasUnsavedMCPConfigChanges: Bool {
        mcpConfigText != savedMCPConfigText
    }

    var mcpConfigPath: String {
        mcpConfigURL.path
    }

    /// Reverts all editable properties to the original config snapshot.
    func discardChanges() {
        let c = savedConfig
        shell = c.general.shell
        workingDirectory = c.general.workingDirectory
        confirmCloseProcess = c.general.confirmCloseProcess
        theme = Self.resolveDisplayName(for: c.appearance.theme, from: availableThemes)
        fontFamily = c.appearance.fontFamily
        fontSize = c.appearance.fontSize
        tabPosition = c.appearance.tabPosition.rawValue
        windowPadding = c.appearance.windowPadding
        ligatures = c.appearance.ligatures
        fontThicken = c.appearance.fontThicken
        backgroundOpacity = c.appearance.backgroundOpacity
        transparencyChromeTheme = c.appearance.transparencyChromeTheme
        auroraEnabled = c.appearance.auroraEnabled
        rateLimitIndicatorEnabled = c.appearance.rateLimitIndicatorEnabled
        quickSwitchMode = c.appearance.quickSwitchMode
        imageFileTransfer = c.terminal.imageFileTransfer
        enableSixelImages = c.terminal.enableSixelImages
        enableKittyImages = c.terminal.enableKittyImages
        enableITerm2Images = c.terminal.enableITerm2Images
        imageMemoryLimitMB = c.terminal.imageMemoryLimitMB
        imageDiskCacheDirectory = c.terminal.imageDiskCacheDirectory
        imageDiskCacheLimitMB = c.terminal.imageDiskCacheLimitMB
        agentDetectionEnabled = c.agentDetection.enabled
        oscNotifications = c.agentDetection.oscNotifications
        patternMatching = c.agentDetection.patternMatching
        timingHeuristics = c.agentDetection.timingHeuristics
        idleTimeoutSeconds = c.agentDetection.idleTimeoutSeconds
        agentModeEnabled = c.agent.enabled
        agentPreferredProvider = c.agent.preferredProvider
        agentAutoMode = c.agent.autoMode
        agentComputerUseConfirm = c.agent.computerUseConfirm
        agentMaxIterations = c.agent.maxIterations
        agentConversationStorageDir = c.agent.conversationStorageDir
        agentConversationEncryption = c.agent.conversationEncryption
        voiceEnabled = c.voice.enabled
        voiceLocaleIdentifier = c.voice.localeIdentifier
        completionInlineAIEnabled = c.completions.inlineAIEnabled
        completionIdleDelaySeconds = c.completions.idleDelaySeconds
        completionMaxContextUTF16Length = c.completions.maxContextUTF16Length
        completionEnabledLanguageIDs = Set(c.completions.enabledLanguageIDs)
        activityTrackingEnabled = c.activity.enabled
        activityCostTrackingEnabled = c.activity.costTrackingEnabled
        activityInputCostMicrosPerMillionTokens = c.activity.inputCostMicrosPerMillionTokens
        activityOutputCostMicrosPerMillionTokens = c.activity.outputCostMicrosPerMillionTokens
        codeReviewAutoShowOnSessionEnd = c.codeReview.autoShowOnSessionEnd
        macosNotifications = c.notifications.macosNotifications
        sound = c.notifications.sound
        badgeOnTab = c.notifications.badgeOnTab
        flashTab = c.notifications.flashTab
        showDockBadge = c.notifications.showDockBadge
        worktreeEnabled = c.worktree.enabled
        worktreeBasePath = c.worktree.basePath
        worktreeBranchTemplate = c.worktree.branchTemplate
        worktreeBaseRef = c.worktree.baseRef
        worktreeOnClose = c.worktree.onClose.rawValue
        worktreeOpenInNewTab = c.worktree.openInNewTab
        worktreeIDLength = c.worktree.idLength
        worktreeInheritProjectConfig = c.worktree.inheritProjectConfig
        worktreeShowBadge = c.worktree.showBadge
        githubEnabled = c.github.enabled
        githubAutoRefreshInterval = c.github.autoRefreshInterval
        githubMaxItems = c.github.maxItems
        githubIncludeDrafts = c.github.includeDrafts
        githubDefaultState = c.github.defaultState
        githubMergeEnabled = c.github.mergeEnabled
        notesEnabled = c.notes.enabled
        notesFormat = c.notes.format.rawValue
        notesSearchEngine = c.notes.searchEngine.rawValue
        notesStorageDir = c.notes.storageDir
        notesShortcut = c.notes.shortcut
        notesAutoSave = c.notes.autoSave
        notesAutoSaveIntervalSeconds = c.notes.autoSaveIntervalSeconds
        lspEnabled = c.lsp.enabled
        lspEnabledLanguageIDs = Set(c.lsp.enabledLanguageIDs)
        vimEnabled = c.vim.enabled
        restoreSavedMCPConfigDraft()
        pendingKeybindings = nil
    }

    // MARK: - Private

    /// The file provider used to persist configuration to disk.
    private let fileProvider: ConfigFileProviding

    /// The config snapshot used for dirty tracking and as source of truth for
    /// sections not exposed in the UI (terminal, quick-terminal, keybindings, sessions).
    /// Updated after each successful save so `hasUnsavedChanges` resets to false.
    private var savedConfig: CocxyConfig

    /// Pending keybindings applied via `applyKeybindings(_:)` but not yet
    /// persisted. When `nil` the writer emits `savedConfig.keybindings`.
    private var pendingKeybindings: KeybindingsConfig?

    /// Local secret facade for provider API keys. Production uses Keychain;
    /// tests inject an in-memory store.
    private let agentSecrets: AgentSecrets

    /// Resolves Voice locale availability without any network fallback.
    private let voiceLocaleResolver: VoiceLocaleResolver

    /// User-managed MCP config file location.
    private let mcpConfigURL: URL

    /// Parser/writer for `mcp.json`.
    private let mcpConfigLoader: MCPServerConfigLoader

    /// Last loaded or successfully saved MCP JSON text.
    private var savedMCPConfigText: String = MCPServerConfigLoader.defaultConfigText

    /// Dedicated editor model for the Keybindings preferences tab.
    ///
    /// Constructed lazily on first access so view models used purely for
    /// programmatic saves (e.g., CLI-driven) do not pay the cost.
    lazy var keybindingsEditor: KeybindingsEditorViewModel = {
        KeybindingsEditorViewModel(config: savedConfig, persistence: self)
    }()

    // MARK: - Initialization

    /// Creates a view model populated from the given configuration.
    ///
    /// - Parameters:
    ///   - config: The current configuration snapshot.
    ///   - fileProvider: Destination for writes. Defaults to disk.
    init(
        config: CocxyConfig,
        fileProvider: ConfigFileProviding = DiskConfigFileProvider(),
        voiceLocaleResolver: VoiceLocaleResolver = .live(),
        agentSecrets: AgentSecrets = AgentSecrets(),
        mcpConfigURL: URL = MCPServerConfigLoader().defaultConfigURL(),
        mcpConfigLoader: MCPServerConfigLoader = MCPServerConfigLoader()
    ) {
        self.savedConfig = config
        self.fileProvider = fileProvider
        self.voiceLocaleResolver = voiceLocaleResolver
        self.agentSecrets = agentSecrets
        self.mcpConfigURL = mcpConfigURL
        self.mcpConfigLoader = mcpConfigLoader

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
        self.fontThicken = config.appearance.fontThicken
        self.backgroundOpacity = config.appearance.backgroundOpacity
        self.transparencyChromeTheme = config.appearance.transparencyChromeTheme
        self.auroraEnabled = config.appearance.auroraEnabled
        self.auroraSidebarDisplayMode = config.appearance.auroraSidebarDisplayMode
        self.auroraSidebarPrimaryInfo = config.appearance.auroraSidebarPrimaryInfo
        self.rateLimitIndicatorEnabled = config.appearance.rateLimitIndicatorEnabled
        self.quickSwitchMode = config.appearance.quickSwitchMode

        // Agent Detection
        self.agentDetectionEnabled = config.agentDetection.enabled
        self.oscNotifications = config.agentDetection.oscNotifications
        self.patternMatching = config.agentDetection.patternMatching
        self.timingHeuristics = config.agentDetection.timingHeuristics
        self.idleTimeoutSeconds = config.agentDetection.idleTimeoutSeconds

        // Agent Mode
        self.agentModeEnabled = config.agent.enabled
        self.agentPreferredProvider = config.agent.preferredProvider
        self.agentAutoMode = config.agent.autoMode
        self.agentComputerUseConfirm = config.agent.computerUseConfirm
        self.agentMaxIterations = config.agent.maxIterations
        self.agentConversationStorageDir = config.agent.conversationStorageDir
        self.agentConversationEncryption = config.agent.conversationEncryption
        self.agentAPIKeyDraft = ""
        self.agentAPIKeyStatus = nil
        self.agentConversationMasterPasswordDraft = ""
        self.agentConversationMasterPasswordStatus = nil

        // Voice Input
        self.voiceEnabled = config.voice.enabled
        self.voiceLocaleIdentifier = config.voice.localeIdentifier

        // Inline Completions
        self.completionInlineAIEnabled = config.completions.inlineAIEnabled
        self.completionIdleDelaySeconds = config.completions.idleDelaySeconds
        self.completionMaxContextUTF16Length = config.completions.maxContextUTF16Length
        self.completionEnabledLanguageIDs = Set(config.completions.enabledLanguageIDs)

        // Activity
        self.activityTrackingEnabled = config.activity.enabled
        self.activityCostTrackingEnabled = config.activity.costTrackingEnabled
        self.activityInputCostMicrosPerMillionTokens = config.activity.inputCostMicrosPerMillionTokens
        self.activityOutputCostMicrosPerMillionTokens = config.activity.outputCostMicrosPerMillionTokens

        // Code Review
        self.codeReviewAutoShowOnSessionEnd = config.codeReview.autoShowOnSessionEnd

        // Notifications
        self.macosNotifications = config.notifications.macosNotifications
        self.sound = config.notifications.sound
        self.badgeOnTab = config.notifications.badgeOnTab
        self.flashTab = config.notifications.flashTab
        self.showDockBadge = config.notifications.showDockBadge
        self.imageFileTransfer = config.terminal.imageFileTransfer
        self.enableSixelImages = config.terminal.enableSixelImages
        self.enableKittyImages = config.terminal.enableKittyImages
        self.enableITerm2Images = config.terminal.enableITerm2Images
        self.imageMemoryLimitMB = config.terminal.imageMemoryLimitMB
        self.imageDiskCacheDirectory = config.terminal.imageDiskCacheDirectory
        self.imageDiskCacheLimitMB = config.terminal.imageDiskCacheLimitMB

        // Worktree (v0.1.81)
        self.worktreeEnabled = config.worktree.enabled
        self.worktreeBasePath = config.worktree.basePath
        self.worktreeBranchTemplate = config.worktree.branchTemplate
        self.worktreeBaseRef = config.worktree.baseRef
        self.worktreeOnClose = config.worktree.onClose.rawValue
        self.worktreeOpenInNewTab = config.worktree.openInNewTab
        self.worktreeIDLength = config.worktree.idLength
        self.worktreeInheritProjectConfig = config.worktree.inheritProjectConfig
        self.worktreeShowBadge = config.worktree.showBadge

        // GitHub (v0.1.84 — base) and v0.1.86 (mergeEnabled)
        self.githubEnabled = config.github.enabled
        self.githubAutoRefreshInterval = config.github.autoRefreshInterval
        self.githubMaxItems = config.github.maxItems
        self.githubIncludeDrafts = config.github.includeDrafts
        self.githubDefaultState = config.github.defaultState
        self.githubMergeEnabled = config.github.mergeEnabled

        // Notes
        self.notesEnabled = config.notes.enabled
        self.notesFormat = config.notes.format.rawValue
        self.notesSearchEngine = config.notes.searchEngine.rawValue
        self.notesStorageDir = config.notes.storageDir
        self.notesShortcut = config.notes.shortcut
        self.notesAutoSave = config.notes.autoSave
        self.notesAutoSaveIntervalSeconds = config.notes.autoSaveIntervalSeconds
        self.lspEnabled = config.lsp.enabled
        self.lspEnabledLanguageIDs = Set(config.lsp.enabledLanguageIDs)
        self.vimEnabled = config.vim.enabled

        // Available themes from built-in list.
        self.availableThemes = Self.defaultThemeNames()
        self.availableFontFamilies = FontFallbackResolver.availableFixedPitchFamilies()
        self.recommendedFontFamilies = FontFallbackResolver.recommendedFamilies()
        self.bundledFontFamilies = FontFallbackResolver.bundledFamilies
        self.availableLSPLanguages = LSPLanguageRegistry.defaults.servers
        self.availableVoiceLocales = voiceLocaleResolver.supportedLocaleOptions()
        self.availableCompletionLanguageIDs = CompletionConfig.defaults.enabledLanguageIDs
        loadInitialMCPConfig()
    }

    // MARK: - Agent Provider Secrets

    func saveAgentAPIKeyDraft(for provider: AgentProviderKind) throws {
        try agentSecrets.saveAPIKey(agentAPIKeyDraft, for: provider)
        agentAPIKeyDraft = ""
        agentAPIKeyStatus = "\(Self.agentProviderDisplayName(provider)) API key saved."
    }

    func deleteAgentAPIKey(for provider: AgentProviderKind) throws {
        try agentSecrets.deleteAPIKey(for: provider)
        agentAPIKeyStatus = "\(Self.agentProviderDisplayName(provider)) API key deleted."
    }

    func hasSavedAgentAPIKey(for provider: AgentProviderKind) -> Bool {
        (try? agentSecrets.hasAPIKey(for: provider)) ?? false
    }

    func saveAgentConversationMasterPasswordDraft() throws {
        try agentSecrets.saveConversationMasterPassword(agentConversationMasterPasswordDraft)
        agentConversationMasterPasswordDraft = ""
        agentConversationMasterPasswordStatus = "Conversation master password saved."
    }

    func deleteAgentConversationMasterPassword() throws {
        try agentSecrets.deleteConversationMasterPassword()
        agentConversationMasterPasswordStatus = "Conversation master password deleted."
    }

    func hasSavedAgentConversationMasterPassword() -> Bool {
        (try? agentSecrets.hasConversationMasterPassword()) ?? false
    }

    // MARK: - MCP Config Editing

    func validateMCPConfigDraft() throws {
        let servers = try mcpConfigLoader.validateConfigText(mcpConfigText)
        mcpConfiguredServers = servers
        mcpConfigStatus = mcpStatusMessage(prefix: "Valid", serverCount: servers.count)
    }

    func reloadMCPConfig() {
        loadInitialMCPConfig()
    }

    func saveMCPConfig() throws {
        let servers = try mcpConfigLoader.writeConfigText(mcpConfigText, to: mcpConfigURL)
        savedMCPConfigText = mcpConfigText
        mcpConfiguredServers = servers
        mcpConfigStatus = mcpStatusMessage(prefix: "Saved", serverCount: servers.count)
    }

    func mcpServerSummary(for server: MCPServer) -> String {
        let state = server.enabled ? "Enabled" : "Disabled"
        switch server.transport {
        case .stdio:
            return "\(state) stdio"
        case .http:
            return "\(state) HTTP"
        }
    }

    // MARK: - LSP Selection

    func isLSPLanguageEnabled(_ languageID: String) -> Bool {
        let normalized = Self.normalizedLSPLanguageID(languageID)
        return !normalized.isEmpty && lspEnabledLanguageIDs.contains(normalized)
    }

    func setLSPLanguage(_ languageID: String, enabled: Bool) {
        let normalized = Self.normalizedLSPLanguageID(languageID)
        guard !normalized.isEmpty else { return }

        var next = lspEnabledLanguageIDs
        if enabled {
            next.insert(normalized)
        } else {
            next.remove(normalized)
        }
        lspEnabledLanguageIDs = next
    }

    // MARK: - Voice Locale Resolution

    var resolvedVoiceLocale: VoiceLocaleResolution {
        voiceLocaleResolver.resolve(config: buildVoiceConfigFromViewModel())
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
    /// not directly editable here (terminal, quick-terminal, sessions)
    /// are preserved from the original config. Keybindings are taken from
    /// the pending value set via `applyKeybindings(_:)` when present, and
    /// from the saved snapshot otherwise.
    ///
    /// - Throws: If the file provider cannot write to disk.
    func save() throws {
        normalizeImageSettingsForSave()
        if hasUnsavedMCPConfigChanges {
            _ = try mcpConfigLoader.validateConfigText(mcpConfigText)
        }
        let toml = generateToml()
        try fileProvider.writeConfigFile(toml)
        if hasUnsavedMCPConfigChanges {
            try saveMCPConfig()
        }
        // Update the saved snapshot so hasUnsavedChanges resets to false.
        // This prevents the "unsaved changes" alert from appearing after save.
        updateSavedSnapshot()
        onSave?()
    }

    /// Registers pending keybinding edits to be emitted on the next `save()`.
    ///
    /// `KeybindingsEditorViewModel` owns the editable state for shortcuts
    /// and funnels the final result through this entry point so the shared
    /// `save()` writes a single, consistent TOML file.
    ///
    /// Calling this multiple times overwrites earlier pending values; the
    /// last call wins.
    func applyKeybindings(_ keybindings: KeybindingsConfig) {
        pendingKeybindings = keybindings
    }

    /// The keybindings that will be persisted on the next save.
    ///
    /// Returns the pending value if any edits have been staged via
    /// `applyKeybindings(_:)`, otherwise the last-saved snapshot.
    var effectiveKeybindings: KeybindingsConfig {
        pendingKeybindings ?? savedConfig.keybindings
    }

    /// Normalizes free-form image settings before persisting them.
    private func normalizeImageSettingsForSave() {
        imageMemoryLimitMB = min(max(imageMemoryLimitMB, 1), 4096)
        imageDiskCacheDirectory = imageDiskCacheDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
        imageDiskCacheLimitMB = min(max(imageDiskCacheLimitMB, 1), 8192)
    }

    private func loadInitialMCPConfig() {
        do {
            let text = try mcpConfigLoader.loadConfigText(from: mcpConfigURL)
            savedMCPConfigText = text
            mcpConfigText = text
            restoreSavedMCPConfigDraft()
        } catch {
            savedMCPConfigText = MCPServerConfigLoader.defaultConfigText
            mcpConfigText = savedMCPConfigText
            mcpConfiguredServers = []
            mcpConfigStatus = "Failed to load MCP config: \(error.localizedDescription)"
        }
    }

    private func restoreSavedMCPConfigDraft() {
        mcpConfigText = savedMCPConfigText
        do {
            let servers = try mcpConfigLoader.validateConfigText(savedMCPConfigText)
            mcpConfiguredServers = servers
            mcpConfigStatus = mcpStatusMessage(prefix: "Loaded", serverCount: servers.count)
        } catch {
            mcpConfiguredServers = []
            mcpConfigStatus = "Invalid MCP config: \(error.localizedDescription)"
        }
    }

    private func mcpStatusMessage(prefix: String, serverCount: Int) -> String {
        if serverCount == 1 {
            return "\(prefix) 1 MCP server."
        }
        return "\(prefix) \(serverCount) MCP servers."
    }

    /// Updates the saved config snapshot to match the current editable values.
    ///
    /// Called after a successful save so that `hasUnsavedChanges` returns false
    /// until the user makes further edits.
    private func updateSavedSnapshot() {
        let clampedOpacity = min(max(backgroundOpacity, 0.3), 1.0)
        let clampedImageMemoryLimitMB = min(max(imageMemoryLimitMB, 1), 4096)
        let clampedImageDiskCacheLimitMB = min(max(imageDiskCacheLimitMB, 1), 8192)
        let normalizedImageDiskCacheDirectory = imageDiskCacheDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = buildAgentModeConfigFromViewModel()
        let activity = buildActivityConfigFromViewModel()
        let voice = buildVoiceConfigFromViewModel()
        let completions = buildCompletionConfigFromViewModel()
        let notes = buildNotesConfigFromViewModel()
        let keybindings = (pendingKeybindings ?? savedConfig.keybindings)
            .applyingFallbackShortcut(
                actionId: KeybindingActionCatalog.windowNotes.id,
                shortcut: notes.shortcut
            )
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
                fontThicken: fontThicken,
                backgroundOpacity: clampedOpacity,
                backgroundBlurRadius: savedConfig.appearance.backgroundBlurRadius,
                transparencyChromeTheme: transparencyChromeTheme,
                auroraEnabled: auroraEnabled,
                auroraSidebarDisplayMode: auroraSidebarDisplayMode,
                auroraSidebarPrimaryInfo: auroraSidebarPrimaryInfo,
                rateLimitIndicatorEnabled: rateLimitIndicatorEnabled,
                quickSwitchMode: quickSwitchMode
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
                imageMemoryLimitMB: clampedImageMemoryLimitMB,
                imageFileTransfer: imageFileTransfer,
                enableSixelImages: enableSixelImages,
                enableKittyImages: enableKittyImages,
                enableITerm2Images: enableITerm2Images,
                imageDiskCacheDirectory: normalizedImageDiskCacheDirectory,
                imageDiskCacheLimitMB: clampedImageDiskCacheLimitMB
            ),
            agentDetection: AgentDetectionConfig(
                enabled: agentDetectionEnabled,
                oscNotifications: oscNotifications,
                patternMatching: patternMatching,
                timingHeuristics: timingHeuristics,
                idleTimeoutSeconds: idleTimeoutSeconds
            ),
            agent: agent,
            activity: activity,
            voice: voice,
            iCloudSync: savedConfig.iCloudSync,
            completions: completions,
            codeReview: buildCodeReviewConfigFromViewModel(),
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
            keybindings: keybindings,
            sessions: savedConfig.sessions,
            worktree: buildWorktreeConfigFromViewModel(),
            github: buildGitHubConfigFromViewModel(),
            notes: notes,
            lsp: buildLSPConfigFromViewModel(),
            vim: buildVimConfigFromViewModel(),
            experimental: savedConfig.experimental
        )
        agentComputerUseConfirm = agent.computerUseConfirm
        agentMaxIterations = agent.maxIterations
        agentConversationStorageDir = agent.conversationStorageDir
        agentConversationEncryption = agent.conversationEncryption
        activityCostTrackingEnabled = activity.costTrackingEnabled
        activityInputCostMicrosPerMillionTokens = activity.inputCostMicrosPerMillionTokens
        activityOutputCostMicrosPerMillionTokens = activity.outputCostMicrosPerMillionTokens
        voiceLocaleIdentifier = voice.localeIdentifier
        completionIdleDelaySeconds = completions.idleDelaySeconds
        completionMaxContextUTF16Length = completions.maxContextUTF16Length
        completionEnabledLanguageIDs = Set(completions.enabledLanguageIDs)
        pendingKeybindings = nil
    }

    /// Builds the `[code-review]` section from editable preferences.
    private func buildCodeReviewConfigFromViewModel() -> CodeReviewConfig {
        CodeReviewConfig(autoShowOnSessionEnd: codeReviewAutoShowOnSessionEnd)
    }

    /// Builds the `[agent]` section from editable preferences while keeping
    /// the fallback policy pinned to the saved local-first policy.
    private func buildAgentModeConfigFromViewModel() -> AgentModeConfig {
        AgentModeConfig(
            enabled: agentModeEnabled,
            preferredProvider: agentPreferredProvider,
            foundationModelsFallback: savedConfig.agent.foundationModelsFallback,
            autoMode: agentAutoMode,
            computerUseConfirm: agentComputerUseConfirm,
            maxIterations: agentMaxIterations,
            conversationStorageDir: agentConversationStorageDir,
            conversationEncryption: agentConversationEncryption
        )
    }

    private func agentModeHasUnsavedChanges(comparedTo config: AgentModeConfig) -> Bool {
        agentModeEnabled != config.enabled
            || agentPreferredProvider != config.preferredProvider
            || agentAutoMode != config.autoMode
            || agentComputerUseConfirm != config.computerUseConfirm
            || agentMaxIterations != config.maxIterations
            || agentConversationStorageDir != config.conversationStorageDir
            || agentConversationEncryption != config.conversationEncryption
    }

    private func buildVoiceConfigFromViewModel() -> VoiceConfig {
        VoiceConfig(
            enabled: voiceEnabled,
            localeIdentifier: voiceLocaleIdentifier
        )
    }

    private func voiceHasUnsavedChanges(comparedTo config: VoiceConfig) -> Bool {
        voiceEnabled != config.enabled
            || VoiceConfig.normalizedLocaleIdentifier(voiceLocaleIdentifier) != config.localeIdentifier
    }

    private func buildCompletionConfigFromViewModel() -> CompletionConfig {
        CompletionConfig(
            inlineAIEnabled: completionInlineAIEnabled,
            provider: .foundationModelsOnDevice,
            idleDelaySeconds: completionIdleDelaySeconds,
            maxContextUTF16Length: completionMaxContextUTF16Length,
            enabledLanguageIDs: Array(completionEnabledLanguageIDs)
        )
    }

    private func completionHasUnsavedChanges(comparedTo config: CompletionConfig) -> Bool {
        let completions = buildCompletionConfigFromViewModel()
        return completions.inlineAIEnabled != config.inlineAIEnabled
            || completions.provider != config.provider
            || completions.idleDelaySeconds != config.idleDelaySeconds
            || completions.maxContextUTF16Length != config.maxContextUTF16Length
            || completions.enabledLanguageIDs != config.enabledLanguageIDs
    }

    func isCompletionLanguageEnabled(_ languageID: String) -> Bool {
        let normalized = Self.normalizedCompletionLanguageID(languageID)
        return !normalized.isEmpty && completionEnabledLanguageIDs.contains(normalized)
    }

    func setCompletionLanguage(_ languageID: String, enabled: Bool) {
        let normalized = Self.normalizedCompletionLanguageID(languageID)
        guard !normalized.isEmpty else { return }

        var next = completionEnabledLanguageIDs
        if enabled {
            next.insert(normalized)
        } else {
            next.remove(normalized)
        }
        completionEnabledLanguageIDs = next
    }

    private func buildActivityConfigFromViewModel() -> ActivityConfig {
        ActivityConfig(
            enabled: activityTrackingEnabled,
            costTrackingEnabled: activityTrackingEnabled && activityCostTrackingEnabled,
            storageDirectory: savedConfig.activity.storageDirectory,
            inputCostMicrosPerMillionTokens: activityInputCostMicrosPerMillionTokens,
            outputCostMicrosPerMillionTokens: activityOutputCostMicrosPerMillionTokens
        )
    }

    private func activityHasUnsavedChanges(comparedTo config: ActivityConfig) -> Bool {
        let activity = buildActivityConfigFromViewModel()
        return activity.enabled != config.enabled
            || activity.costTrackingEnabled != config.costTrackingEnabled
            || activity.inputCostMicrosPerMillionTokens != config.inputCostMicrosPerMillionTokens
            || activity.outputCostMicrosPerMillionTokens != config.outputCostMicrosPerMillionTokens
    }

    private static func agentProviderDisplayName(_ provider: AgentProviderKind) -> String {
        switch provider {
        case .foundationModelsOnDevice:
            return "Foundation Models"
        case .anthropic:
            return "Anthropic"
        case .openai:
            return "OpenAI"
        case .google:
            return "Google"
        }
    }

    /// Builds a `WorktreeConfig` value from the editable view-model
    /// fields. Clamps `idLength` and falls back to safe defaults for
    /// empty string fields so a user cannot save an impossible config.
    private func buildWorktreeConfigFromViewModel() -> WorktreeConfig {
        let defaults = WorktreeConfig.defaults
        let clampedLength = min(
            max(worktreeIDLength, WorktreeConfig.minIDLength),
            WorktreeConfig.maxIDLength
        )
        let trimmedBasePath = worktreeBasePath.trimmingCharacters(in: .whitespaces)
        let trimmedTemplate = worktreeBranchTemplate.trimmingCharacters(in: .whitespaces)
        let trimmedBaseRef = worktreeBaseRef.trimmingCharacters(in: .whitespaces)

        return WorktreeConfig(
            enabled: worktreeEnabled,
            basePath: trimmedBasePath.isEmpty ? defaults.basePath : trimmedBasePath,
            branchTemplate: trimmedTemplate.isEmpty ? defaults.branchTemplate : trimmedTemplate,
            baseRef: trimmedBaseRef.isEmpty ? defaults.baseRef : trimmedBaseRef,
            onClose: WorktreeOnClose(rawValue: worktreeOnClose) ?? defaults.onClose,
            openInNewTab: worktreeOpenInNewTab,
            idLength: clampedLength,
            inheritProjectConfig: worktreeInheritProjectConfig,
            showBadge: worktreeShowBadge
        )
    }

    /// Compares every editable `[worktree]` field against the saved
    /// snapshot. This intentionally compares the raw UI values instead
    /// of the clamped save output so the Save/Discard controls become
    /// available as soon as the user changes a Worktrees preference.
    private func worktreeHasUnsavedChanges(comparedTo config: WorktreeConfig) -> Bool {
        worktreeEnabled != config.enabled
            || worktreeBasePath != config.basePath
            || worktreeBranchTemplate != config.branchTemplate
            || worktreeBaseRef != config.baseRef
            || worktreeOnClose != config.onClose.rawValue
            || worktreeOpenInNewTab != config.openInNewTab
            || worktreeIDLength != config.idLength
            || worktreeInheritProjectConfig != config.inheritProjectConfig
            || worktreeShowBadge != config.showBadge
    }

    /// Builds a `GitHubConfig` value from the editable view-model
    /// fields. Clamps numeric ranges and coerces an invalid default
    /// state back to `"open"` so the user cannot accidentally save a
    /// value `gh` will reject.
    private func buildGitHubConfigFromViewModel() -> GitHubConfig {
        let defaults = GitHubConfig.defaults
        let clampedRefresh = min(
            max(githubAutoRefreshInterval, GitHubConfig.minAutoRefreshInterval),
            GitHubConfig.maxAutoRefreshInterval
        )
        let clampedMaxItems = min(
            max(githubMaxItems, GitHubConfig.minMaxItems),
            GitHubConfig.maxMaxItems
        )
        let normalisedState = githubDefaultState.lowercased()
        let validatedState = GitHubConfig.allowedDefaultStates.contains(normalisedState)
            ? normalisedState
            : defaults.defaultState

        return GitHubConfig(
            enabled: githubEnabled,
            autoRefreshInterval: clampedRefresh,
            maxItems: clampedMaxItems,
            includeDrafts: githubIncludeDrafts,
            defaultState: validatedState,
            mergeEnabled: githubMergeEnabled
        )
    }

    /// Compares every editable `[github]` field against the saved
    /// snapshot. Mirrors `worktreeHasUnsavedChanges` — raw UI values,
    /// not the clamped save output — so Save/Discard light up the
    /// instant the user changes anything.
    private func githubHasUnsavedChanges(comparedTo config: GitHubConfig) -> Bool {
        githubEnabled != config.enabled
            || githubAutoRefreshInterval != config.autoRefreshInterval
            || githubMaxItems != config.maxItems
            || githubIncludeDrafts != config.includeDrafts
            || githubDefaultState != config.defaultState
            || githubMergeEnabled != config.mergeEnabled
    }

    /// Builds a `NotesConfig` value from the editable view-model fields.
    /// Enum-backed values are coerced to their safe defaults and the
    /// auto-save interval is clamped to match `ConfigService`.
    private func buildNotesConfigFromViewModel() -> NotesConfig {
        let defaults = NotesConfig.defaults
        let trimmedStorageDir = notesStorageDir.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShortcut = notesShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedInterval = min(max(notesAutoSaveIntervalSeconds, 0.1), 60)
        return NotesConfig(
            enabled: notesEnabled,
            format: NoteFormat.parse(notesFormat),
            searchEngine: NoteSearchEngineKind.parse(notesSearchEngine),
            storageDir: trimmedStorageDir.isEmpty ? defaults.storageDir : trimmedStorageDir,
            shortcut: normalizedNotesShortcut(trimmedShortcut),
            autoSave: notesAutoSave,
            autoSaveIntervalSeconds: clampedInterval
        )
    }

    private func normalizedNotesShortcut(_ rawShortcut: String) -> String {
        let raw = rawShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let parsed = KeybindingShortcut.parse(raw),
              parsed.isAssignableToMenuItem
        else {
            return NotesConfig.defaults.shortcut
        }
        return parsed.canonical
    }

    private func notesHasUnsavedChanges(comparedTo config: NotesConfig) -> Bool {
        notesEnabled != config.enabled
            || notesFormat != config.format.rawValue
            || notesSearchEngine != config.searchEngine.rawValue
            || notesStorageDir != config.storageDir
            || notesShortcut != config.shortcut
            || notesAutoSave != config.autoSave
            || notesAutoSaveIntervalSeconds != config.autoSaveIntervalSeconds
    }

    private func buildLSPConfigFromViewModel() -> LSPConfig {
        LSPConfig(
            enabled: lspEnabled,
            enabledLanguageIDs: Self.sortedLSPLanguageIDs(from: lspEnabledLanguageIDs)
        )
    }

    private func lspHasUnsavedChanges(comparedTo config: LSPConfig) -> Bool {
        lspEnabled != config.enabled
            || Self.sortedLSPLanguageIDs(from: lspEnabledLanguageIDs) != config.enabledLanguageIDs
    }

    private func buildVimConfigFromViewModel() -> VimConfig {
        VimConfig(enabled: vimEnabled)
    }

    private func vimHasUnsavedChanges(comparedTo config: VimConfig) -> Bool {
        vimEnabled != config.enabled
    }

    // MARK: - TOML Generation

    /// Generates a complete TOML configuration string from the current values.
    ///
    /// Clamps numeric values to their valid ranges. Non-editable sections are
    /// taken from the original config snapshot to avoid data loss. Pending
    /// keybindings registered via `applyKeybindings(_:)` take precedence
    /// over the saved snapshot.
    func generateToml() -> String {
        let clampedFontSize = Int(min(max(fontSize, 8), 32))
        let clampedPadding = Int(min(max(windowPadding, 0), 40))
        let clampedOpacity = min(max(backgroundOpacity, 0.3), 1.0)
        let clampedTimeout = min(max(idleTimeoutSeconds, 1), 300)
        let clampedImageMemoryLimitMB = min(max(imageMemoryLimitMB, 1), 4096)
        let clampedImageDiskCacheLimitMB = min(max(imageDiskCacheLimitMB, 1), 8192)
        let normalizedImageDiskCacheDirectory = imageDiskCacheDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let defaults = savedConfig
        let keybindings = pendingKeybindings ?? defaults.keybindings
        let notes = buildNotesConfigFromViewModel()
        let agent = buildAgentModeConfigFromViewModel()
        let activity = buildActivityConfigFromViewModel()
        let voice = buildVoiceConfigFromViewModel()
        let completions = buildCompletionConfigFromViewModel()
        let lsp = buildLSPConfigFromViewModel()
        let vim = buildVimConfigFromViewModel()
        let windowPaddingXLine = defaults.appearance.windowPaddingX.map {
            "window-padding-x = \(Self.tomlNumber($0))\n"
        } ?? ""
        let windowPaddingYLine = defaults.appearance.windowPaddingY.map {
            "window-padding-y = \(Self.tomlNumber($0))\n"
        } ?? ""

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
        \(windowPaddingXLine)\(windowPaddingYLine)ligatures = \(ligatures)
        font-thicken = \(fontThicken)
        background-opacity = \(Self.tomlNumber(clampedOpacity))
        background-blur-radius = \(Self.tomlNumber(defaults.appearance.backgroundBlurRadius))
        transparency-chrome-theme = "\(transparencyChromeTheme.rawValue)"
        aurora-enabled = \(auroraEnabled)
        aurora-sidebar-display-mode = "\(auroraSidebarDisplayMode.rawValue)"
        aurora-sidebar-primary-info = "\(auroraSidebarPrimaryInfo.rawValue)"
        rate-limit-indicator-enabled = \(rateLimitIndicatorEnabled)
        quickswitch-mode = "\(quickSwitchMode.rawValue)"

        [terminal]
        scrollback-lines = \(defaults.terminal.scrollbackLines)
        cursor-style = "\(defaults.terminal.cursorStyle.rawValue)"
        cursor-blink = \(defaults.terminal.cursorBlink)
        cursor-opacity = \(Self.tomlNumber(defaults.terminal.cursorOpacity))
        mouse-hide-while-typing = \(defaults.terminal.mouseHideWhileTyping)
        copy-on-select = \(defaults.terminal.copyOnSelect)
        clipboard-paste-protection = \(defaults.terminal.clipboardPasteProtection)
        clipboard-read-access = "\(defaults.terminal.clipboardReadAccess.rawValue)"
        image-memory-limit-mb = \(clampedImageMemoryLimitMB)
        image-file-transfer = \(imageFileTransfer)
        enable-sixel-images = \(enableSixelImages)
        enable-kitty-images = \(enableKittyImages)
        enable-iterm2-images = \(enableITerm2Images)
        image-disk-cache-directory = \(Self.tomlString(normalizedImageDiskCacheDirectory))
        image-disk-cache-limit-mb = \(clampedImageDiskCacheLimitMB)

        [agent-detection]
        enabled = \(agentDetectionEnabled)
        osc-notifications = \(oscNotifications)
        pattern-matching = \(patternMatching)
        timing-heuristics = \(timingHeuristics)
        idle-timeout-seconds = \(clampedTimeout)

        [agent]
        enabled = \(agent.enabled)
        preferred-provider = "\(agent.preferredProvider.rawValue)"
        foundation-models-fallback = "\(agent.foundationModelsFallback.rawValue)"
        auto-mode = \(agent.autoMode)
        computer-use-confirm = \(agent.computerUseConfirm)
        max-iterations = \(agent.maxIterations)
        conversation-storage-dir = "\(agent.conversationStorageDir)"
        conversation-encryption = "\(agent.conversationEncryption.rawValue)"

        [voice]
        enabled = \(voice.enabled)
        locale = "\(voice.localeIdentifier)"

        [completions]
        inline-ai = \(completions.inlineAIEnabled)
        provider = "\(completions.provider.rawValue)"
        idle-delay-seconds = \(Self.tomlNumber(completions.idleDelaySeconds))
        max-context-utf16-length = \(completions.maxContextUTF16Length)
        enabled-languages = \(Self.tomlStringArray(completions.enabledLanguageIDs))

        [activity]
        enabled = \(activity.enabled)
        cost-tracking = \(activity.costTrackingEnabled)
        storage-directory = "\(activity.storageDirectory)"
        input-cost-micros-per-million-tokens = \(activity.inputCostMicrosPerMillionTokens)
        output-cost-micros-per-million-tokens = \(activity.outputCostMicrosPerMillionTokens)

        [code-review]
        auto-show-on-session-end = \(codeReviewAutoShowOnSessionEnd)

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
        enabled = \(defaults.quickTerminal.enabled)
        hotkey = "\(defaults.quickTerminal.hotkey)"
        position = "\(defaults.quickTerminal.position.rawValue)"
        height-percentage = \(defaults.quickTerminal.heightPercentage)
        hide-on-deactivate = \(defaults.quickTerminal.hideOnDeactivate)
        working-directory = "\(defaults.quickTerminal.workingDirectory)"
        animation-duration = \(Self.tomlNumber(defaults.quickTerminal.animationDuration))
        screen = "\(defaults.quickTerminal.screen.rawValue)"

        \(keybindings.tomlSection())

        [sessions]
        auto-save = \(defaults.sessions.autoSave)
        auto-save-interval = \(defaults.sessions.autoSaveInterval)
        restore-on-launch = \(defaults.sessions.restoreOnLaunch)

        [worktree]
        enabled = \(worktreeEnabled)
        base-path = "\(worktreeBasePath.trimmingCharacters(in: .whitespaces).isEmpty ? defaults.worktree.basePath : worktreeBasePath)"
        branch-template = "\(worktreeBranchTemplate.trimmingCharacters(in: .whitespaces).isEmpty ? defaults.worktree.branchTemplate : worktreeBranchTemplate)"
        base-ref = "\(worktreeBaseRef.trimmingCharacters(in: .whitespaces).isEmpty ? defaults.worktree.baseRef : worktreeBaseRef)"
        on-close = "\(WorktreeOnClose(rawValue: worktreeOnClose)?.rawValue ?? defaults.worktree.onClose.rawValue)"
        open-in-new-tab = \(worktreeOpenInNewTab)
        id-length = \(min(max(worktreeIDLength, WorktreeConfig.minIDLength), WorktreeConfig.maxIDLength))
        inherit-project-config = \(worktreeInheritProjectConfig)
        show-badge = \(worktreeShowBadge)

        [github]
        enabled = \(githubEnabled)
        auto-refresh-interval = \(min(max(githubAutoRefreshInterval, GitHubConfig.minAutoRefreshInterval), GitHubConfig.maxAutoRefreshInterval))
        max-items = \(min(max(githubMaxItems, GitHubConfig.minMaxItems), GitHubConfig.maxMaxItems))
        include-drafts = \(githubIncludeDrafts)
        default-state = "\(GitHubConfig.allowedDefaultStates.contains(githubDefaultState.lowercased()) ? githubDefaultState.lowercased() : defaults.github.defaultState)"
        merge-enabled = \(githubMergeEnabled)

        [notes]
        enabled = \(notes.enabled)
        format = "\(notes.format.rawValue)"
        search-engine = "\(notes.searchEngine.rawValue)"
        storage-dir = "\(notes.storageDir)"
        shortcut = "\(notes.shortcut)"
        auto-save = \(notes.autoSave)
        auto-save-interval-seconds = \(Self.tomlNumber(notes.autoSaveIntervalSeconds))

        [lsp]
        enabled = \(lsp.enabled)
        enabled-languages = \(Self.tomlStringArray(lsp.enabledLanguageIDs))

        [vim]
        enabled = \(vim.enabled)

        [experimental]
        pip-enabled = \(defaults.experimental.pipEnabled)
        pty-daemon = \(defaults.experimental.ptyDaemonEnabled)
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

    /// Compares config/raw theme names and picker display names as the same
    /// semantic value. Without this, opening Preferences on a default config
    /// (`catppuccin-mocha`) marks the window dirty because the picker displays
    /// `Catppuccin Mocha`.
    private static func themeNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizeThemeName(lhs) == normalizeThemeName(rhs)
    }

    private static func normalizeThemeName(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizedLSPLanguageID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedCompletionLanguageID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sortedLSPLanguageIDs(from ids: Set<String>) -> [String] {
        Array(ids.map(normalizedLSPLanguageID).filter { !$0.isEmpty }).sorted()
    }

    private static func tomlStringArray(_ values: [String]) -> String {
        guard !values.isEmpty else { return "[]" }
        let items = values.map { value in
            tomlString(value)
        }
        return "[\(items.joined(separator: ", "))]"
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func tomlNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 {
            return String(Int(rounded))
        }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
