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

    // MARK: - Updates

    /// Sparkle update channel selected by the user.
    @Published var updateChannel: ChannelKind

    // MARK: - Appearance

    /// Name of the dark/system theme (e.g., "catppuccin-mocha" or "system").
    @Published var theme: String

    /// Name of the light theme used by the one-click/system light mode switch.
    @Published var lightTheme: String

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

    /// App UI language policy for localizable Cocxy strings.
    @Published var appLanguage: AppLanguage

    // MARK: - UX Polish

    /// Whether shortcut hints stay visible without hover.
    @Published var alwaysShowShortcutHints: Bool

    /// Whether the shortcut hint debug placement overlay is visible.
    @Published var shortcutHintDebugOverlay: Bool

    /// Horizontal shortcut hint offset in points.
    @Published var shortcutHintOffsetX: Double

    /// Vertical shortcut hint offset in points.
    @Published var shortcutHintOffsetY: Double

    /// Shortcut hint scale multiplier.
    @Published var shortcutHintScale: Double

    // MARK: - Command Corrections

    /// Master switch for local command-failure suggestions.
    @Published var commandCorrectionsEnabled: Bool

    /// Maximum edit distance for command-name typo suggestions.
    @Published var commandCorrectionsEditDistanceThreshold: Int

    /// Whether on-device Foundation Models may be used when available.
    @Published var commandCorrectionsFoundationModelsEnabled: Bool

    /// Whether the active user-configured agent may be asked for fallback suggestions.
    @Published var commandCorrectionsAgentFallback: Bool

    /// Whether suggestions appear automatically after failed commands.
    @Published var commandCorrectionsAutoShowOnFailure: Bool

    /// Whether suggestion confidence is displayed in the UI.
    @Published var commandCorrectionsShowConfidenceBadge: Bool

    /// Maximum suggestions shown in one correction prompt.
    @Published var commandCorrectionsMaxSuggestionsShown: Int

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

    // MARK: - Spotlight

    /// Master opt-in for local macOS Spotlight indexing.
    @Published var spotlightIndexingEnabled: Bool

    /// Whether command history is included when Spotlight indexing is enabled.
    @Published var spotlightIndexCommandHistory: Bool

    /// Whether Agent Mode conversations are included when Spotlight indexing is enabled.
    @Published var spotlightIndexAgentConversations: Bool

    /// Whether command output is included in command-history Spotlight documents.
    @Published var spotlightIncludeCommandOutput: Bool

    /// Whether working directories are included in command-history Spotlight documents.
    @Published var spotlightIncludeWorkingDirectories: Bool

    /// Whether tool names and tool call IDs are included in conversation documents.
    @Published var spotlightIncludeToolMetadata: Bool

    // MARK: - Activity

    /// Master opt-in for local activity dashboard persistence.
    @Published var activityTrackingEnabled: Bool

    /// Whether local token usage and estimated costs are recorded.
    @Published var activityCostTrackingEnabled: Bool

    /// Local input-token rate in micro-dollars per million tokens.
    @Published var activityInputCostMicrosPerMillionTokens: Int64

    /// Local output-token rate in micro-dollars per million tokens.
    @Published var activityOutputCostMicrosPerMillionTokens: Int64

    // MARK: - Session Replay

    /// Master opt-in for local terminal session recording and replay.
    @Published var sessionReplayEnabled: Bool

    /// Whether new terminal sessions should be recorded automatically.
    @Published var sessionReplayAutoRecord: Bool

    /// Explicit user consent required before automatic recording can start.
    @Published var sessionReplayConsentGranted: Bool

    /// Local directory where session recording bundles are stored.
    @Published var sessionReplayStorageDirectory: String

    /// Per-recording byte limit. Clamped by `SessionReplayConfig` on save.
    @Published var sessionReplayMaxRecordingBytes: Int

    // MARK: - iCloud Sync

    /// Master opt-in for encrypted iCloud Drive sync.
    @Published var iCloudSyncEnabled: Bool

    /// Safe folder name created inside the user's iCloud Drive.
    @Published var iCloudSyncDirectoryName: String

    /// Whether artifacts must be encrypted before export. Pinned on in UI.
    @Published var iCloudSyncEncryptionRequired: Bool

    /// Artifact classes selected for encrypted sync export.
    @Published var iCloudSyncArtifactKinds: Set<ICloudSyncArtifactKind>

    /// Draft master password for encrypted iCloud Sync exports.
    @Published var iCloudSyncMasterPasswordDraft: String

    /// Short status for the last iCloud Sync secret action.
    @Published var iCloudSyncMasterPasswordStatus: String?

    /// Short status for the last manual iCloud Sync export action.
    @Published var iCloudSyncExportStatus: String?

    /// Short status for the last manual iCloud Sync import action.
    @Published var iCloudSyncImportStatus: String?

    /// Conflicts found during the last manual iCloud Sync import.
    @Published var iCloudSyncConflicts: [ICloudSyncImportConflict]

    // MARK: - Local Backups

    /// Master switch for local automatic backups.
    @Published var backupEnabled: Bool

    /// Local directory where timestamped backup snapshots are written.
    @Published var backupStorageDirectory: String

    /// Number of latest daily snapshots retained before monthly pruning.
    @Published var backupDailyRetentionCount: Int

    /// Number of older monthly representative snapshots retained.
    @Published var backupMonthlyRetentionCount: Int

    /// Artifact classes selected for local backup.
    @Published var backupArtifactKinds: [BackupArtifactKind]

    /// Timestamped local backups discovered in the configured storage folder.
    @Published private(set) var backupSnapshots: [BackupSnapshotSummary]

    /// Selected backup snapshot ID for a manual restore.
    @Published private(set) var selectedBackupSnapshotID: BackupSnapshotSummary.ID?

    /// Selected artifact kind for a manual restore.
    @Published private(set) var selectedBackupArtifactKind: BackupArtifactKind?

    /// Short status for the last manual local backup restore action.
    @Published var backupRestoreStatus: String?

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

    // MARK: - Git Assistant

    /// Master toggle for local-first commit message and pull request drafts.
    @Published var gitAssistantEnabled: Bool

    /// Provider selected for Git Assistant calls.
    @Published var gitAssistantDefaultProvider: AgentProviderKind

    /// Maximum diff lines included in one prompt. Clamped on save.
    @Published var gitAssistantMaxDiffLines: Int

    /// Commit/PR wording style requested from the provider.
    @Published var gitAssistantPromptStyle: GitAssistantPromptStyle

    /// Whether the create-PR flow may pre-fill a draft automatically.
    @Published var gitAssistantAutoGeneratePRBodyOnCreate: Bool

    /// Whether staged changes may trigger commit message generation.
    @Published var gitAssistantAutoGenerateCommitMessageOnStage: Bool

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

    /// Dark-capable themes plus the system-following sentinel.
    let availableDarkThemes: [String]

    /// Light-capable themes available for the paired light-mode picker.
    let availableLightThemes: [String]

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

    /// Local app languages exposed in Preferences.
    let availableAppLanguages: [AppLanguage]

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
            || updateChannel != c.updates.channel
            || !Self.themeNamesMatch(theme, c.appearance.theme)
            || !Self.themeNamesMatch(lightTheme, c.appearance.lightTheme)
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
            || appLanguage != c.appearance.appLanguage
            || uxPolishHasUnsavedChanges(comparedTo: c.uxPolish)
            || commandCorrectionsHasUnsavedChanges(comparedTo: c.commandCorrections)
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
            || spotlightHasUnsavedChanges(comparedTo: c.spotlight)
            || activityHasUnsavedChanges(comparedTo: c.activity)
            || sessionReplayHasUnsavedChanges(comparedTo: c.sessionReplay)
            || iCloudSyncHasUnsavedChanges(comparedTo: c.iCloudSync)
            || backupHasUnsavedChanges(comparedTo: c.backup)
            || codeReviewAutoShowOnSessionEnd != c.codeReview.autoShowOnSessionEnd
            || macosNotifications != c.notifications.macosNotifications
            || sound != c.notifications.sound
            || badgeOnTab != c.notifications.badgeOnTab
            || flashTab != c.notifications.flashTab
            || showDockBadge != c.notifications.showDockBadge
            || worktreeHasUnsavedChanges(comparedTo: c.worktree)
            || githubHasUnsavedChanges(comparedTo: c.github)
            || gitAssistantHasUnsavedChanges(comparedTo: c.gitAssistant)
            || notesHasUnsavedChanges(comparedTo: c.notes)
            || lspHasUnsavedChanges(comparedTo: c.lsp)
            || vimHasUnsavedChanges(comparedTo: c.vim)
            || hasUnsavedMCPConfigChanges
            || (pendingKeybindings != nil && pendingKeybindings != c.keybindings)
    }

    var hasUnsavedMCPConfigChanges: Bool {
        mcpConfigText != savedMCPConfigText
    }

    func localizedString(_ key: AppLocalizationKey) -> String {
        appLocalizer().string(key)
    }

    func localizedString(_ key: String, fallback: String) -> String {
        appLocalizer().string(key, fallback: fallback)
    }

    func appLocalizer() -> AppLocalizer {
        AppLocalizer(languagePreference: appLanguage, bundle: appLocalizationBundle)
    }

    func localizedCursorStyle() -> String {
        switch savedConfig.terminal.cursorStyle {
        case .block:
            return localizedString("preferences.terminal.cursorStyle.block", fallback: "Block")
        case .bar:
            return localizedString("preferences.terminal.cursorStyle.bar", fallback: "Bar")
        case .underline:
            return localizedString("preferences.terminal.cursorStyle.underline", fallback: "Underline")
        }
    }

    func localizedLSPInstallDetail(for server: LSPServerConfiguration) -> String {
        if let command = server.installSuggestion.command {
            return command
        }
        return localizedString(
            "preferences.lsp.install.\(server.languageID)",
            fallback: server.installSuggestion.message
        )
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
        lightTheme = Self.resolveDisplayName(for: c.appearance.lightTheme, from: availableThemes)
        fontFamily = c.appearance.fontFamily
        fontSize = c.appearance.fontSize
        tabPosition = c.appearance.tabPosition.rawValue
        windowPadding = c.appearance.windowPadding
        ligatures = c.appearance.ligatures
        fontThicken = c.appearance.fontThicken
        backgroundOpacity = c.appearance.backgroundOpacity
        transparencyChromeTheme = c.appearance.transparencyChromeTheme
        auroraEnabled = c.appearance.auroraEnabled
        auroraSidebarDisplayMode = c.appearance.auroraSidebarDisplayMode
        auroraSidebarPrimaryInfo = c.appearance.auroraSidebarPrimaryInfo
        rateLimitIndicatorEnabled = c.appearance.rateLimitIndicatorEnabled
        quickSwitchMode = c.appearance.quickSwitchMode
        appLanguage = c.appearance.appLanguage
        alwaysShowShortcutHints = c.uxPolish.alwaysShowShortcutHints
        shortcutHintDebugOverlay = c.uxPolish.shortcutHintDebugOverlay
        shortcutHintOffsetX = c.uxPolish.shortcutHintOffsetX
        shortcutHintOffsetY = c.uxPolish.shortcutHintOffsetY
        shortcutHintScale = c.uxPolish.shortcutHintScale
        commandCorrectionsEnabled = c.commandCorrections.enabled
        commandCorrectionsEditDistanceThreshold = c.commandCorrections.editDistanceThreshold
        commandCorrectionsFoundationModelsEnabled = c.commandCorrections.foundationModelsEnabled
        commandCorrectionsAgentFallback = c.commandCorrections.agentFallback
        commandCorrectionsAutoShowOnFailure = c.commandCorrections.autoShowOnFailure
        commandCorrectionsShowConfidenceBadge = c.commandCorrections.showConfidenceBadge
        commandCorrectionsMaxSuggestionsShown = c.commandCorrections.maxSuggestionsShown
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
        spotlightIndexingEnabled = c.spotlight.enabled
        spotlightIndexCommandHistory = c.spotlight.indexCommandHistory
        spotlightIndexAgentConversations = c.spotlight.indexAgentConversations
        spotlightIncludeCommandOutput = c.spotlight.includeCommandOutput
        spotlightIncludeWorkingDirectories = c.spotlight.includeWorkingDirectories
        spotlightIncludeToolMetadata = c.spotlight.includeToolMetadata
        activityTrackingEnabled = c.activity.enabled
        activityCostTrackingEnabled = c.activity.costTrackingEnabled
        activityInputCostMicrosPerMillionTokens = c.activity.inputCostMicrosPerMillionTokens
        activityOutputCostMicrosPerMillionTokens = c.activity.outputCostMicrosPerMillionTokens
        sessionReplayEnabled = c.sessionReplay.enabled
        sessionReplayAutoRecord = c.sessionReplay.autoRecord
        sessionReplayConsentGranted = c.sessionReplay.consentGranted
        sessionReplayStorageDirectory = c.sessionReplay.storageDirectory
        sessionReplayMaxRecordingBytes = c.sessionReplay.maxRecordingBytes
        iCloudSyncEnabled = c.iCloudSync.enabled
        iCloudSyncDirectoryName = c.iCloudSync.syncDirectoryName
        iCloudSyncEncryptionRequired = c.iCloudSync.encryptionRequired
        iCloudSyncArtifactKinds = Set(c.iCloudSync.artifactKinds)
        backupEnabled = c.backup.enabled
        backupStorageDirectory = c.backup.storageDirectory
        backupDailyRetentionCount = c.backup.dailyRetentionCount
        backupMonthlyRetentionCount = c.backup.monthlyRetentionCount
        backupArtifactKinds = c.backup.artifactKinds
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
        gitAssistantEnabled = c.gitAssistant.enabled
        gitAssistantDefaultProvider = c.gitAssistant.defaultProvider
        gitAssistantMaxDiffLines = c.gitAssistant.maxDiffLines
        gitAssistantPromptStyle = c.gitAssistant.promptStyle
        gitAssistantAutoGeneratePRBodyOnCreate = c.gitAssistant.autoGeneratePRBodyOnCreate
        gitAssistantAutoGenerateCommitMessageOnStage = c.gitAssistant.autoGenerateCommitMessageOnStage
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

    /// Local secret facade for the iCloud Sync master password.
    private let iCloudSyncSecrets: ICloudSyncSecrets

    /// Manual encrypted export runner for iCloud Sync.
    private let iCloudSyncExporter: any ICloudSyncExporting

    /// Manual encrypted import runner for iCloud Sync.
    private let iCloudSyncImporter: any ICloudSyncImporting

    /// Manual iCloud Sync conflict resolver.
    private let iCloudSyncConflictResolver: any ICloudSyncConflictResolving

    /// Local artifact roots scanned by manual iCloud Sync export.
    private let iCloudSyncArtifactRoots: ICloudSyncArtifactRoots

    /// Destination for local backups created before accepting a remote conflict.
    private let iCloudSyncConflictBackupRoot: URL

    /// Local-only backup manager used for manual restore actions.
    private let localBackupManager: LocalBackupManager

    /// Local artifact roots restored by explicit backup actions.
    private let backupArtifactRoots: BackupArtifactRoots

    /// Resolves Voice locale availability without any network fallback.
    private let voiceLocaleResolver: VoiceLocaleResolver

    /// User-managed MCP config file location.
    private let mcpConfigURL: URL

    /// Parser/writer for `mcp.json`.
    private let mcpConfigLoader: MCPServerConfigLoader

    /// Bundle containing app localization resources.
    private let appLocalizationBundle: Bundle

    /// Last loaded or successfully saved MCP JSON text.
    private var savedMCPConfigText: String = MCPServerConfigLoader.defaultConfigText

    /// Dedicated editor model for the Keybindings preferences tab.
    ///
    /// Constructed lazily on first access so view models used purely for
    /// programmatic saves (e.g., CLI-driven) do not pay the cost.
    lazy var keybindingsEditor: KeybindingsEditorViewModel = {
        KeybindingsEditorViewModel(config: savedConfig, persistence: self, localizer: appLocalizer())
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
        iCloudSyncSecrets: ICloudSyncSecrets = ICloudSyncSecrets(),
        iCloudSyncExporter: any ICloudSyncExporting = ICloudSyncExportService(),
        iCloudSyncImporter: any ICloudSyncImporting = ICloudSyncImportService(),
        iCloudSyncConflictResolver: any ICloudSyncConflictResolving = ICloudSyncConflictResolutionService(),
        iCloudSyncArtifactRoots: ICloudSyncArtifactRoots = .defaults(),
        iCloudSyncConflictBackupRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/icloud-conflict-backups", isDirectory: true),
        localBackupManager: LocalBackupManager = LocalBackupManager(),
        backupArtifactRoots: BackupArtifactRoots = .defaults(),
        mcpConfigURL: URL = MCPServerConfigLoader().defaultConfigURL(),
        mcpConfigLoader: MCPServerConfigLoader = MCPServerConfigLoader(),
        appLocalizationBundle: Bundle = .main
    ) {
        self.savedConfig = config
        self.fileProvider = fileProvider
        self.voiceLocaleResolver = voiceLocaleResolver
        self.agentSecrets = agentSecrets
        self.iCloudSyncSecrets = iCloudSyncSecrets
        self.iCloudSyncExporter = iCloudSyncExporter
        self.iCloudSyncImporter = iCloudSyncImporter
        self.iCloudSyncConflictResolver = iCloudSyncConflictResolver
        self.iCloudSyncArtifactRoots = iCloudSyncArtifactRoots
        self.iCloudSyncConflictBackupRoot = iCloudSyncConflictBackupRoot.standardizedFileURL
        self.localBackupManager = localBackupManager
        self.backupArtifactRoots = backupArtifactRoots
        self.mcpConfigURL = mcpConfigURL
        self.mcpConfigLoader = mcpConfigLoader
        self.appLocalizationBundle = appLocalizationBundle

        // General
        self.shell = config.general.shell
        self.workingDirectory = config.general.workingDirectory
        self.confirmCloseProcess = config.general.confirmCloseProcess

        // Updates
        self.updateChannel = config.updates.channel

        // Appearance — resolve theme to display name for picker compatibility.
        // Config may store "catppuccin-mocha" but picker uses "Catppuccin Mocha".
        let themeNames = Self.defaultThemeNames()
        self.theme = Self.resolveDisplayName(for: config.appearance.theme, from: themeNames)
        self.lightTheme = Self.resolveDisplayName(for: config.appearance.lightTheme, from: themeNames)
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
        self.appLanguage = config.appearance.appLanguage
        self.alwaysShowShortcutHints = config.uxPolish.alwaysShowShortcutHints
        self.shortcutHintDebugOverlay = config.uxPolish.shortcutHintDebugOverlay
        self.shortcutHintOffsetX = config.uxPolish.shortcutHintOffsetX
        self.shortcutHintOffsetY = config.uxPolish.shortcutHintOffsetY
        self.shortcutHintScale = config.uxPolish.shortcutHintScale
        self.commandCorrectionsEnabled = config.commandCorrections.enabled
        self.commandCorrectionsEditDistanceThreshold = config.commandCorrections.editDistanceThreshold
        self.commandCorrectionsFoundationModelsEnabled = config.commandCorrections.foundationModelsEnabled
        self.commandCorrectionsAgentFallback = config.commandCorrections.agentFallback
        self.commandCorrectionsAutoShowOnFailure = config.commandCorrections.autoShowOnFailure
        self.commandCorrectionsShowConfidenceBadge = config.commandCorrections.showConfidenceBadge
        self.commandCorrectionsMaxSuggestionsShown = config.commandCorrections.maxSuggestionsShown

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

        // Spotlight
        self.spotlightIndexingEnabled = config.spotlight.enabled
        self.spotlightIndexCommandHistory = config.spotlight.indexCommandHistory
        self.spotlightIndexAgentConversations = config.spotlight.indexAgentConversations
        self.spotlightIncludeCommandOutput = config.spotlight.includeCommandOutput
        self.spotlightIncludeWorkingDirectories = config.spotlight.includeWorkingDirectories
        self.spotlightIncludeToolMetadata = config.spotlight.includeToolMetadata

        // Activity
        self.activityTrackingEnabled = config.activity.enabled
        self.activityCostTrackingEnabled = config.activity.costTrackingEnabled
        self.activityInputCostMicrosPerMillionTokens = config.activity.inputCostMicrosPerMillionTokens
        self.activityOutputCostMicrosPerMillionTokens = config.activity.outputCostMicrosPerMillionTokens

        // Session Replay
        self.sessionReplayEnabled = config.sessionReplay.enabled
        self.sessionReplayAutoRecord = config.sessionReplay.autoRecord
        self.sessionReplayConsentGranted = config.sessionReplay.consentGranted
        self.sessionReplayStorageDirectory = config.sessionReplay.storageDirectory
        self.sessionReplayMaxRecordingBytes = config.sessionReplay.maxRecordingBytes

        // iCloud Sync
        self.iCloudSyncEnabled = config.iCloudSync.enabled
        self.iCloudSyncDirectoryName = config.iCloudSync.syncDirectoryName
        self.iCloudSyncEncryptionRequired = config.iCloudSync.encryptionRequired
        self.iCloudSyncArtifactKinds = Set(config.iCloudSync.artifactKinds)
        self.iCloudSyncMasterPasswordDraft = ""
        self.iCloudSyncMasterPasswordStatus = nil
        self.iCloudSyncExportStatus = nil
        self.iCloudSyncImportStatus = nil
        self.iCloudSyncConflicts = []

        // Local Backups
        self.backupEnabled = config.backup.enabled
        self.backupStorageDirectory = config.backup.storageDirectory
        self.backupDailyRetentionCount = config.backup.dailyRetentionCount
        self.backupMonthlyRetentionCount = config.backup.monthlyRetentionCount
        self.backupArtifactKinds = config.backup.artifactKinds
        self.backupSnapshots = []
        self.selectedBackupSnapshotID = nil
        self.selectedBackupArtifactKind = nil
        self.backupRestoreStatus = nil

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

        // Git Assistant
        self.gitAssistantEnabled = config.gitAssistant.enabled
        self.gitAssistantDefaultProvider = config.gitAssistant.defaultProvider
        self.gitAssistantMaxDiffLines = config.gitAssistant.maxDiffLines
        self.gitAssistantPromptStyle = config.gitAssistant.promptStyle
        self.gitAssistantAutoGeneratePRBodyOnCreate = config.gitAssistant.autoGeneratePRBodyOnCreate
        self.gitAssistantAutoGenerateCommitMessageOnStage = config.gitAssistant.autoGenerateCommitMessageOnStage

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
        self.availableDarkThemes = Self.defaultDarkThemeNames()
        self.availableLightThemes = Self.defaultLightThemeNames()
        self.availableFontFamilies = FontFallbackResolver.availableFixedPitchFamilies()
        self.recommendedFontFamilies = FontFallbackResolver.recommendedFamilies()
        self.bundledFontFamilies = FontFallbackResolver.bundledFamilies
        self.availableLSPLanguages = LSPLanguageRegistry.defaults.servers
        self.availableVoiceLocales = voiceLocaleResolver.supportedLocaleOptions()
        self.availableAppLanguages = AppLanguage.allCases
        self.availableCompletionLanguageIDs = CompletionConfig.defaults.enabledLanguageIDs
        loadInitialMCPConfig()
    }

    // MARK: - Agent Provider Secrets

    func saveAgentAPIKeyDraft(for provider: AgentProviderKind) throws {
        try agentSecrets.saveAPIKey(agentAPIKeyDraft, for: provider)
        agentAPIKeyDraft = ""
        agentAPIKeyStatus = String(
            format: localizedString("preferences.agentMode.apiKey.saved.status", fallback: "%@ API key saved."),
            Self.agentProviderDisplayName(provider)
        )
    }

    func deleteAgentAPIKey(for provider: AgentProviderKind) throws {
        try agentSecrets.deleteAPIKey(for: provider)
        agentAPIKeyStatus = String(
            format: localizedString("preferences.agentMode.apiKey.deleted.status", fallback: "%@ API key deleted."),
            Self.agentProviderDisplayName(provider)
        )
    }

    func hasSavedAgentAPIKey(for provider: AgentProviderKind) -> Bool {
        (try? agentSecrets.hasAPIKey(for: provider)) ?? false
    }

    func saveAgentConversationMasterPasswordDraft() throws {
        try agentSecrets.saveConversationMasterPassword(agentConversationMasterPasswordDraft)
        agentConversationMasterPasswordDraft = ""
        agentConversationMasterPasswordStatus = localizedString(
            "preferences.agentMode.masterPassword.saved.status",
            fallback: "Conversation master password saved."
        )
    }

    func deleteAgentConversationMasterPassword() throws {
        try agentSecrets.deleteConversationMasterPassword()
        agentConversationMasterPasswordStatus = localizedString(
            "preferences.agentMode.masterPassword.deleted.status",
            fallback: "Conversation master password deleted."
        )
    }

    func hasSavedAgentConversationMasterPassword() -> Bool {
        (try? agentSecrets.hasConversationMasterPassword()) ?? false
    }

    // MARK: - iCloud Sync Secrets

    func saveICloudSyncMasterPasswordDraft() throws {
        try iCloudSyncSecrets.saveMasterPassword(iCloudSyncMasterPasswordDraft)
        iCloudSyncMasterPasswordDraft = ""
        iCloudSyncMasterPasswordStatus = localizedString(
            "preferences.iCloud.masterPassword.saved.status",
            fallback: "iCloud Sync master password saved."
        )
    }

    func deleteICloudSyncMasterPassword() throws {
        try iCloudSyncSecrets.deleteMasterPassword()
        iCloudSyncMasterPasswordStatus = localizedString(
            "preferences.iCloud.masterPassword.deleted.status",
            fallback: "iCloud Sync master password deleted."
        )
    }

    func hasSavedICloudSyncMasterPassword() -> Bool {
        (try? iCloudSyncSecrets.hasMasterPassword()) ?? false
    }

    func exportICloudSyncArtifactsNow() throws -> ICloudSyncExportOutcome {
        let config = buildICloudSyncConfigFromViewModel()
        guard config.enabled else {
            iCloudSyncExportStatus = localizedString(
                "preferences.iCloud.status.disabled",
                fallback: "iCloud Sync is disabled."
            )
            return .disabled
        }
        guard let password = try iCloudSyncSecrets.masterPassword() else {
            throw ICloudSyncManualRunError.masterPasswordUnavailable
        }

        let outcome = try iCloudSyncExporter.exportLocalArtifacts(
            config: config,
            roots: iCloudSyncArtifactRoots,
            password: password
        )
        switch outcome {
        case .disabled:
            iCloudSyncExportStatus = localizedString(
                "preferences.iCloud.status.disabled",
                fallback: "iCloud Sync is disabled."
            )
        case .unavailable:
            iCloudSyncExportStatus = localizedString(
                "preferences.iCloud.status.unavailable",
                fallback: "iCloud Drive is unavailable."
            )
        case .exported(let result):
            iCloudSyncExportStatus = localizedICloudExportStatus(count: result.writtenArtifactURLs.count)
        }
        return outcome
    }

    func importICloudSyncArtifactsNow() throws -> ICloudSyncImportOutcome {
        let config = buildICloudSyncConfigFromViewModel()
        guard config.enabled else {
            iCloudSyncImportStatus = localizedString(
                "preferences.iCloud.status.disabled",
                fallback: "iCloud Sync is disabled."
            )
            iCloudSyncConflicts = []
            return .disabled
        }
        guard let password = try iCloudSyncSecrets.masterPassword() else {
            throw ICloudSyncManualRunError.masterPasswordUnavailable
        }

        let outcome = try iCloudSyncImporter.importRemoteArtifacts(
            config: config,
            roots: iCloudSyncArtifactRoots,
            password: password
        )
        switch outcome {
        case .disabled:
            iCloudSyncImportStatus = localizedString(
                "preferences.iCloud.status.disabled",
                fallback: "iCloud Sync is disabled."
            )
            iCloudSyncConflicts = []
        case .unavailable:
            iCloudSyncImportStatus = localizedString(
                "preferences.iCloud.status.unavailable",
                fallback: "iCloud Drive is unavailable."
            )
            iCloudSyncConflicts = []
        case .imported(let result):
            iCloudSyncConflicts = result.conflicts
            if result.conflicts.isEmpty {
                iCloudSyncImportStatus = localizedICloudImportStatus(
                    artifactCount: result.importedArtifactURLs.count
                )
            } else {
                iCloudSyncImportStatus = localizedICloudImportConflictStatus(
                    artifactCount: result.importedArtifactURLs.count,
                    conflictCount: result.conflicts.count
                )
            }
        }
        return outcome
    }

    func resolveICloudSyncConflict(
        _ conflict: ICloudSyncImportConflict,
        resolution: ICloudSyncConflictResolution
    ) throws -> ICloudSyncConflictResolutionOutcome {
        let config = buildICloudSyncConfigFromViewModel()
        guard config.enabled else {
            iCloudSyncImportStatus = localizedString(
                "preferences.iCloud.status.disabled",
                fallback: "iCloud Sync is disabled."
            )
            return .disabled
        }
        let password: String
        if resolution == .useRemote {
            guard let savedPassword = try iCloudSyncSecrets.masterPassword() else {
                throw ICloudSyncManualRunError.masterPasswordUnavailable
            }
            password = savedPassword
        } else {
            password = ""
        }

        let outcome = try iCloudSyncConflictResolver.resolveConflict(
            config: config,
            conflict: conflict,
            resolution: resolution,
            roots: iCloudSyncArtifactRoots,
            backupRoot: iCloudSyncConflictBackupRoot,
            password: password
        )
        switch outcome {
        case .disabled:
            iCloudSyncImportStatus = localizedString(
                "preferences.iCloud.status.disabled",
                fallback: "iCloud Sync is disabled."
            )
        case .unavailable:
            iCloudSyncImportStatus = localizedString(
                "preferences.iCloud.status.unavailable",
                fallback: "iCloud Drive is unavailable."
            )
        case .resolved(let result):
            iCloudSyncConflicts.removeAll { $0 == result.conflict }
            iCloudSyncImportStatus = String(
                format: localizedString(
                    "preferences.iCloud.status.resolvedConflict",
                    fallback: "Resolved conflict for %@."
                ),
                result.conflict.remote.relativePath
            )
        }
        return outcome
    }

    private func localizedICloudExportStatus(count: Int) -> String {
        if count == 1 {
            return localizedString(
                "preferences.iCloud.status.exported.one",
                fallback: "Exported 1 encrypted artifact."
            )
        }
        return String(
            format: localizedString(
                "preferences.iCloud.status.exported.many",
                fallback: "Exported %d encrypted artifacts."
            ),
            count
        )
    }

    private func localizedICloudImportStatus(artifactCount: Int) -> String {
        if artifactCount == 1 {
            return localizedString(
                "preferences.iCloud.status.imported.one",
                fallback: "Imported 1 encrypted artifact."
            )
        }
        return String(
            format: localizedString(
                "preferences.iCloud.status.imported.many",
                fallback: "Imported %d encrypted artifacts."
            ),
            artifactCount
        )
    }

    private func localizedICloudImportConflictStatus(
        artifactCount: Int,
        conflictCount: Int
    ) -> String {
        switch (artifactCount == 1, conflictCount == 1) {
        case (true, true):
            return localizedString(
                "preferences.iCloud.status.imported.conflict.oneOne",
                fallback: "Imported 1 encrypted artifact; 1 conflict requires manual resolution."
            )
        case (true, false):
            return String(
                format: localizedString(
                    "preferences.iCloud.status.imported.conflict.oneMany",
                    fallback: "Imported 1 encrypted artifact; %d conflicts require manual resolution."
                ),
                conflictCount
            )
        case (false, true):
            return String(
                format: localizedString(
                    "preferences.iCloud.status.imported.conflict.manyOne",
                    fallback: "Imported %d encrypted artifacts; 1 conflict requires manual resolution."
                ),
                artifactCount
            )
        case (false, false):
            return String(
                format: localizedString(
                    "preferences.iCloud.status.imported.conflict.manyMany",
                    fallback: "Imported %d encrypted artifacts; %d conflicts require manual resolution."
                ),
                artifactCount,
                conflictCount
            )
        }
    }

    // MARK: - MCP Config Editing

    func validateMCPConfigDraft() throws {
        let servers = try mcpConfigLoader.validateConfigText(mcpConfigText)
        mcpConfiguredServers = servers
        mcpConfigStatus = mcpStatusMessage(
            singularKey: "preferences.mcp.status.valid.one",
            pluralKey: "preferences.mcp.status.valid.many",
            fallbackSingular: "Valid 1 MCP server.",
            fallbackPlural: "Valid %d MCP servers.",
            serverCount: servers.count
        )
    }

    func reloadMCPConfig() {
        loadInitialMCPConfig()
    }

    func saveMCPConfig() throws {
        let servers = try mcpConfigLoader.writeConfigText(mcpConfigText, to: mcpConfigURL)
        savedMCPConfigText = mcpConfigText
        mcpConfiguredServers = servers
        mcpConfigStatus = mcpStatusMessage(
            singularKey: "preferences.mcp.status.saved.one",
            pluralKey: "preferences.mcp.status.saved.many",
            fallbackSingular: "Saved 1 MCP server.",
            fallbackPlural: "Saved %d MCP servers.",
            serverCount: servers.count
        )
    }

    func mcpServerSummary(for server: MCPServer) -> String {
        let state = server.enabled
            ? localizedString("preferences.mcp.server.enabled", fallback: "Enabled")
            : localizedString("preferences.mcp.server.disabled", fallback: "Disabled")
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

    var localizedFontResolutionSummary: String {
        let effective = effectiveFontFamily
        if isSelectedFontInstalled, isSelectedFontBundled {
            return String(
                format: localizedString(
                    "preferences.appearance.fontResolution.included",
                    fallback: "Included with Cocxy: %@"
                ),
                effective
            )
        }
        if isSelectedFontInstalled {
            return String(
                format: localizedString(
                    "preferences.appearance.fontResolution.installed",
                    fallback: "Using installed font: %@"
                ),
                effective
            )
        }
        if isEffectiveFontBundled {
            return String(
                format: localizedString(
                    "preferences.appearance.fontResolution.fallbackBundled",
                    fallback: "\"%@\" is not installed. Cocxy will fall back to bundled %@."
                ),
                fontFamily,
                effective
            )
        }
        return String(
            format: localizedString(
                "preferences.appearance.fontResolution.fallback",
                fallback: "\"%@\" is not installed. Cocxy will fall back to %@."
            ),
            fontFamily,
            effective
        )
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
            mcpConfigStatus = String(
                format: localizedString(
                    "preferences.mcp.load.failed",
                    fallback: "Failed to load MCP config: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func restoreSavedMCPConfigDraft() {
        mcpConfigText = savedMCPConfigText
        do {
            let servers = try mcpConfigLoader.validateConfigText(savedMCPConfigText)
            mcpConfiguredServers = servers
            mcpConfigStatus = mcpStatusMessage(
                singularKey: "preferences.mcp.status.loaded.one",
                pluralKey: "preferences.mcp.status.loaded.many",
                fallbackSingular: "Loaded 1 MCP server.",
                fallbackPlural: "Loaded %d MCP servers.",
                serverCount: servers.count
            )
        } catch {
            mcpConfiguredServers = []
            mcpConfigStatus = String(
                format: localizedString(
                    "preferences.mcp.validate.failed",
                    fallback: "Invalid MCP config: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func mcpStatusMessage(
        singularKey: String,
        pluralKey: String,
        fallbackSingular: String,
        fallbackPlural: String,
        serverCount: Int
    ) -> String {
        if serverCount == 1 {
            return localizedString(singularKey, fallback: fallbackSingular)
        }
        return String(
            format: localizedString(pluralKey, fallback: fallbackPlural),
            serverCount
        )
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
        let sessionReplay = buildSessionReplayConfigFromViewModel()
        let iCloudSync = buildICloudSyncConfigFromViewModel()
        let backup = buildBackupConfigFromViewModel()
        let voice = buildVoiceConfigFromViewModel()
        let completions = buildCompletionConfigFromViewModel()
        let spotlight = buildSpotlightConfigFromViewModel()
        let uxPolish = buildUXPolishConfigFromViewModel()
        let commandCorrections = buildCommandCorrectionsConfigFromViewModel()
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
            updates: UpdatesConfig(channel: updateChannel),
            appearance: AppearanceConfig(
                theme: theme,
                lightTheme: lightTheme,
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
                quickSwitchMode: quickSwitchMode,
                appLanguage: appLanguage
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
            commandCorrections: commandCorrections,
            security: savedConfig.security,
            uxPolish: uxPolish,
            agent: agent,
            backup: backup,
            activity: activity,
            sessionReplay: sessionReplay,
            voice: voice,
            iCloudSync: iCloudSync,
            completions: completions,
            spotlight: spotlight,
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
            gitAssistant: buildGitAssistantSettingsFromViewModel(),
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
        sessionReplayAutoRecord = sessionReplay.autoRecord
        sessionReplayConsentGranted = sessionReplay.consentGranted
        sessionReplayStorageDirectory = sessionReplay.storageDirectory
        sessionReplayMaxRecordingBytes = sessionReplay.maxRecordingBytes
        iCloudSyncDirectoryName = iCloudSync.syncDirectoryName
        iCloudSyncEncryptionRequired = iCloudSync.encryptionRequired
        iCloudSyncArtifactKinds = Set(iCloudSync.artifactKinds)
        backupStorageDirectory = backup.storageDirectory
        backupDailyRetentionCount = backup.dailyRetentionCount
        backupMonthlyRetentionCount = backup.monthlyRetentionCount
        backupArtifactKinds = backup.artifactKinds
        voiceLocaleIdentifier = voice.localeIdentifier
        completionIdleDelaySeconds = completions.idleDelaySeconds
        completionMaxContextUTF16Length = completions.maxContextUTF16Length
        completionEnabledLanguageIDs = Set(completions.enabledLanguageIDs)
        spotlightIndexingEnabled = spotlight.enabled
        spotlightIndexCommandHistory = spotlight.indexCommandHistory
        spotlightIndexAgentConversations = spotlight.indexAgentConversations
        spotlightIncludeCommandOutput = spotlight.includeCommandOutput
        spotlightIncludeWorkingDirectories = spotlight.includeWorkingDirectories
        spotlightIncludeToolMetadata = spotlight.includeToolMetadata
        shortcutHintOffsetX = uxPolish.shortcutHintOffsetX
        shortcutHintOffsetY = uxPolish.shortcutHintOffsetY
        shortcutHintScale = uxPolish.shortcutHintScale
        let gitAssistant = buildGitAssistantSettingsFromViewModel()
        gitAssistantMaxDiffLines = gitAssistant.maxDiffLines
        commandCorrectionsEditDistanceThreshold = commandCorrections.editDistanceThreshold
        commandCorrectionsMaxSuggestionsShown = commandCorrections.maxSuggestionsShown
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

    private func buildCommandCorrectionsConfigFromViewModel() -> CommandCorrectionsConfig {
        CommandCorrectionsConfig(
            enabled: commandCorrectionsEnabled,
            editDistanceThreshold: commandCorrectionsEditDistanceThreshold,
            foundationModelsEnabled: commandCorrectionsFoundationModelsEnabled,
            agentFallback: commandCorrectionsAgentFallback,
            autoShowOnFailure: commandCorrectionsAutoShowOnFailure,
            showConfidenceBadge: commandCorrectionsShowConfidenceBadge,
            maxSuggestionsShown: commandCorrectionsMaxSuggestionsShown
        )
    }

    private func commandCorrectionsHasUnsavedChanges(comparedTo config: CommandCorrectionsConfig) -> Bool {
        buildCommandCorrectionsConfigFromViewModel() != config
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

    private func buildSpotlightConfigFromViewModel() -> SpotlightIndexConfig {
        SpotlightIndexConfig(
            enabled: spotlightIndexingEnabled,
            indexCommandHistory: spotlightIndexCommandHistory,
            indexAgentConversations: spotlightIndexAgentConversations,
            includeCommandOutput: spotlightIndexingEnabled
                && spotlightIndexCommandHistory
                && spotlightIncludeCommandOutput,
            includeWorkingDirectories: spotlightIndexingEnabled
                && spotlightIndexCommandHistory
                && spotlightIncludeWorkingDirectories,
            includeToolMetadata: spotlightIndexingEnabled
                && spotlightIndexAgentConversations
                && spotlightIncludeToolMetadata
        )
    }

    private func spotlightHasUnsavedChanges(comparedTo config: SpotlightIndexConfig) -> Bool {
        let spotlight = buildSpotlightConfigFromViewModel()
        return spotlight.enabled != config.enabled
            || spotlight.indexCommandHistory != config.indexCommandHistory
            || spotlight.indexAgentConversations != config.indexAgentConversations
            || spotlight.includeCommandOutput != config.includeCommandOutput
            || spotlight.includeWorkingDirectories != config.includeWorkingDirectories
            || spotlight.includeToolMetadata != config.includeToolMetadata
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

    private func buildSessionReplayConfigFromViewModel() -> SessionReplayConfig {
        SessionReplayConfig(
            enabled: sessionReplayEnabled,
            autoRecord: sessionReplayEnabled && sessionReplayAutoRecord,
            consentGranted: sessionReplayEnabled && sessionReplayAutoRecord && sessionReplayConsentGranted,
            storageDirectory: sessionReplayStorageDirectory,
            maxRecordingBytes: sessionReplayMaxRecordingBytes
        )
    }

    private func sessionReplayHasUnsavedChanges(comparedTo config: SessionReplayConfig) -> Bool {
        let replay = buildSessionReplayConfigFromViewModel()
        return replay.enabled != config.enabled
            || replay.autoRecord != config.autoRecord
            || replay.consentGranted != config.consentGranted
            || replay.storageDirectory != config.storageDirectory
            || replay.maxRecordingBytes != config.maxRecordingBytes
    }

    private func buildICloudSyncConfigFromViewModel() -> ICloudSyncConfig {
        ICloudSyncConfig(
            enabled: iCloudSyncEnabled,
            syncDirectoryName: iCloudSyncDirectoryName,
            encryptionRequired: true,
            artifactKinds: Self.sortedICloudSyncArtifactKinds(from: iCloudSyncArtifactKinds),
            conflictPolicy: .manual
        )
    }

    private func iCloudSyncHasUnsavedChanges(comparedTo config: ICloudSyncConfig) -> Bool {
        let sync = buildICloudSyncConfigFromViewModel()
        return sync.enabled != config.enabled
            || sync.syncDirectoryName != config.syncDirectoryName
            || sync.encryptionRequired != config.encryptionRequired
            || sync.artifactKinds != config.artifactKinds
            || sync.conflictPolicy != config.conflictPolicy
    }

    private func buildBackupConfigFromViewModel() -> BackupConfig {
        BackupConfig(
            enabled: backupEnabled,
            storageDirectory: backupStorageDirectory,
            dailyRetentionCount: backupDailyRetentionCount,
            monthlyRetentionCount: backupMonthlyRetentionCount,
            artifactKinds: backupArtifactKinds
        )
    }

    private func backupHasUnsavedChanges(comparedTo config: BackupConfig) -> Bool {
        let backup = buildBackupConfigFromViewModel()
        return backup.enabled != config.enabled
            || backup.storageDirectory != config.storageDirectory
            || backup.dailyRetentionCount != config.dailyRetentionCount
            || backup.monthlyRetentionCount != config.monthlyRetentionCount
            || backup.artifactKinds != config.artifactKinds
    }

    func isBackupArtifactKindEnabled(_ kind: BackupArtifactKind) -> Bool {
        backupArtifactKinds.contains(kind)
    }

    func setBackupArtifactKind(_ kind: BackupArtifactKind, enabled: Bool) {
        var next = backupArtifactKinds
        if enabled {
            next.append(kind)
        } else {
            guard next.count > 1 else { return }
            next.removeAll { $0 == kind }
        }
        backupArtifactKinds = BackupConfig.normalizedArtifactKinds(next)
    }

    var selectedBackupSnapshot: BackupSnapshotSummary? {
        guard let selectedBackupSnapshotID else { return nil }
        return backupSnapshots.first { $0.id == selectedBackupSnapshotID }
    }

    var selectedBackupSnapshotArtifactKinds: [BackupArtifactKind] {
        selectedBackupSnapshot?.artifacts.map(\.kind) ?? []
    }

    var canRestoreSelectedBackupArtifact: Bool {
        selectedBackupSnapshot != nil
            && selectedBackupArtifactKind != nil
            && !hasUnsavedChanges
    }

    func refreshBackupSnapshots() {
        do {
            let snapshots = try localBackupManager.availableBackups(storageDirectory: backupStorageDirectory)
            backupSnapshots = snapshots
            selectBackupSnapshot(id: snapshots.first(where: { $0.id == selectedBackupSnapshotID })?.id ?? snapshots.first?.id)
            backupRestoreStatus = snapshots.isEmpty
                ? localizedString(
                    "preferences.backup.restore.noBackups",
                    fallback: "No local backups found."
                )
                : nil
        } catch {
            backupSnapshots = []
            selectBackupSnapshot(id: nil)
            backupRestoreStatus = String(
                format: localizedString(
                    "preferences.backup.restore.failed",
                    fallback: "Backup restore failed: %@"
                ),
                error.localizedDescription
            )
        }
    }

    func selectBackupSnapshot(id: BackupSnapshotSummary.ID?) {
        selectedBackupSnapshotID = id
        let availableKinds = selectedBackupSnapshotArtifactKinds
        if let selectedBackupArtifactKind, availableKinds.contains(selectedBackupArtifactKind) {
            return
        }
        selectedBackupArtifactKind = availableKinds.first
    }

    func selectBackupArtifactKind(_ kind: BackupArtifactKind?) {
        guard let kind else {
            selectedBackupArtifactKind = nil
            return
        }
        selectedBackupArtifactKind = selectedBackupSnapshotArtifactKinds.contains(kind)
            ? kind
            : selectedBackupSnapshotArtifactKinds.first
    }

    func restoreSelectedBackupArtifact() {
        guard !hasUnsavedChanges else {
            backupRestoreStatus = localizedString(
                "preferences.backup.restore.unsaved",
                fallback: "Save or discard preference changes before restoring a backup."
            )
            return
        }
        guard let snapshot = selectedBackupSnapshot else {
            backupRestoreStatus = localizedString(
                "preferences.backup.restore.missingSnapshot",
                fallback: "Select a backup before restoring."
            )
            return
        }
        guard let kind = selectedBackupArtifactKind else {
            backupRestoreStatus = localizedString(
                "preferences.backup.restore.missingArtifact",
                fallback: "Select an artifact before restoring."
            )
            return
        }

        do {
            let result = try localBackupManager.restore(kind: kind, from: snapshot.backupURL, to: backupArtifactRoots)
            backupRestoreStatus = backupRestoreSuccessStatus(for: result)
            if kind == .settings {
                try reloadSettingsAfterBackupRestore()
                onSave?()
            }
        } catch {
            backupRestoreStatus = String(
                format: localizedString(
                    "preferences.backup.restore.failed",
                    fallback: "Backup restore failed: %@"
                ),
                error.localizedDescription
            )
        }
    }

    func isICloudSyncArtifactKindEnabled(_ kind: ICloudSyncArtifactKind) -> Bool {
        iCloudSyncArtifactKinds.contains(kind)
    }

    func setICloudSyncArtifactKind(_ kind: ICloudSyncArtifactKind, enabled: Bool) {
        var next = iCloudSyncArtifactKinds
        if enabled {
            next.insert(kind)
        } else {
            next.remove(kind)
        }
        iCloudSyncArtifactKinds = next
    }

    private static func sortedICloudSyncArtifactKinds(
        from kinds: Set<ICloudSyncArtifactKind>
    ) -> [ICloudSyncArtifactKind] {
        ICloudSyncArtifactKind.allCases.filter { kinds.contains($0) }
    }

    func backupArtifactDisplayName(_ kind: BackupArtifactKind) -> String {
        switch kind {
        case .settings:
            return localizedString("preferences.backup.artifact.settings", fallback: "Settings")
        case .notebooks:
            return localizedString("preferences.backup.artifact.notebooks", fallback: "Notebooks")
        case .workflows:
            return localizedString("preferences.backup.artifact.workflows", fallback: "Workflows")
        case .skills:
            return localizedString("preferences.backup.artifact.skills", fallback: "Custom skills")
        case .notes:
            return localizedString("preferences.backup.artifact.notes", fallback: "Notes")
        case .macros:
            return localizedString("preferences.backup.artifact.macros", fallback: "Macros and snippets")
        case .themes:
            return localizedString("preferences.backup.artifact.themes", fallback: "Custom themes")
        case .encryptedSSHHosts:
            return localizedString("preferences.backup.artifact.encryptedSSHHosts", fallback: "Encrypted SSH hosts")
        case .aiConversations:
            return localizedString("preferences.backup.artifact.aiConversations", fallback: "AI conversations")
        }
    }

    func backupSnapshotDisplayName(_ snapshot: BackupSnapshotSummary) -> String {
        String(
            format: localizedString(
                "preferences.backup.restore.snapshot.title",
                fallback: "%@ - %d files"
            ),
            localizedBackupSnapshotDate(snapshot.createdAt),
            snapshot.totalFileCount
        )
    }

    private func localizedBackupSnapshotDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocalizer().locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func backupRestoreSuccessStatus(for result: BackupRestoreResult) -> String {
        let artifactName = backupArtifactDisplayName(result.kind)
        if result.restoredFiles == 1 {
            return String(
                format: localizedString(
                    "preferences.backup.restore.status.restored.one",
                    fallback: "Restored %@ from 1 file."
                ),
                artifactName
            )
        }
        return String(
            format: localizedString(
                "preferences.backup.restore.status.restored.many",
                fallback: "Restored %@ from %d files."
            ),
            artifactName,
            result.restoredFiles
        )
    }

    private func reloadSettingsAfterBackupRestore() throws {
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()
        savedConfig = service.current
        discardChanges()
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

    /// Builds the `[git-assistant]` settings from editable fields. The
    /// initializer clamps the diff budget to its safe prompt range.
    private func buildGitAssistantSettingsFromViewModel() -> GitAssistantSettings {
        GitAssistantSettings(
            enabled: gitAssistantEnabled,
            defaultProvider: gitAssistantDefaultProvider,
            maxDiffLines: gitAssistantMaxDiffLines,
            promptStyle: gitAssistantPromptStyle,
            autoGeneratePRBodyOnCreate: gitAssistantAutoGeneratePRBodyOnCreate,
            autoGenerateCommitMessageOnStage: gitAssistantAutoGenerateCommitMessageOnStage
        )
    }

    private func gitAssistantHasUnsavedChanges(comparedTo config: GitAssistantSettings) -> Bool {
        gitAssistantEnabled != config.enabled
            || gitAssistantDefaultProvider != config.defaultProvider
            || gitAssistantMaxDiffLines != config.maxDiffLines
            || gitAssistantPromptStyle != config.promptStyle
            || gitAssistantAutoGeneratePRBodyOnCreate != config.autoGeneratePRBodyOnCreate
            || gitAssistantAutoGenerateCommitMessageOnStage != config.autoGenerateCommitMessageOnStage
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

    private func buildUXPolishConfigFromViewModel() -> UXPolishConfig {
        UXPolishConfig(
            alwaysShowShortcutHints: alwaysShowShortcutHints,
            shortcutHintDebugOverlay: shortcutHintDebugOverlay,
            shortcutHintOffsetX: min(max(shortcutHintOffsetX, -120), 120),
            shortcutHintOffsetY: min(max(shortcutHintOffsetY, -120), 120),
            shortcutHintScale: min(max(shortcutHintScale, 0.5), 2.0)
        )
    }

    private func uxPolishHasUnsavedChanges(comparedTo config: UXPolishConfig) -> Bool {
        alwaysShowShortcutHints != config.alwaysShowShortcutHints
            || shortcutHintDebugOverlay != config.shortcutHintDebugOverlay
            || shortcutHintOffsetX != config.shortcutHintOffsetX
            || shortcutHintOffsetY != config.shortcutHintOffsetY
            || shortcutHintScale != config.shortcutHintScale
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
        let sessionReplay = buildSessionReplayConfigFromViewModel()
        let iCloudSync = buildICloudSyncConfigFromViewModel()
        let backup = buildBackupConfigFromViewModel()
        let voice = buildVoiceConfigFromViewModel()
        let completions = buildCompletionConfigFromViewModel()
        let spotlight = buildSpotlightConfigFromViewModel()
        let uxPolish = buildUXPolishConfigFromViewModel()
        let commandCorrections = buildCommandCorrectionsConfigFromViewModel()
        let lsp = buildLSPConfigFromViewModel()
        let vim = buildVimConfigFromViewModel()
        let gitAssistant = buildGitAssistantSettingsFromViewModel()
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

        [updates]
        channel = "\(updateChannel.rawValue)"

        [appearance]
        theme = "\(theme)"
        light-theme = "\(lightTheme)"
        app-language = "\(appLanguage.rawValue)"
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

        [command-corrections]
        enabled = \(commandCorrections.enabled)
        edit-distance-threshold = \(commandCorrections.editDistanceThreshold)
        foundation-models-enabled = \(commandCorrections.foundationModelsEnabled)
        agent-fallback = \(commandCorrections.agentFallback)
        auto-show-on-failure = \(commandCorrections.autoShowOnFailure)
        show-confidence-badge = \(commandCorrections.showConfidenceBadge)
        max-suggestions-shown = \(commandCorrections.maxSuggestionsShown)

        [security]
        require-signed-templates = \(defaults.security.requireSignedTemplates)
        require-signed-macros = \(defaults.security.requireSignedMacros)
        require-signed-plugins = \(defaults.security.requireSignedPlugins)
        warn-on-unsigned = \(defaults.security.warnOnUnsigned)
        trust-on-first-use = \(defaults.security.trustOnFirstUse)

        [security.sandbox]
        plugins-strict = \(defaults.security.sandbox.pluginsStrict)
        agents-isolated = \(defaults.security.sandbox.agentsIsolated)
        mcp-isolated = \(defaults.security.sandbox.mcpIsolated)
        audit-log-enabled = \(defaults.security.sandbox.auditLogEnabled)
        warn-on-grant = \(defaults.security.sandbox.warnOnGrant)

        [ux-polish]
        always-show-shortcut-hints = \(uxPolish.alwaysShowShortcutHints)
        shortcut-hint-debug-overlay = \(uxPolish.shortcutHintDebugOverlay)
        shortcut-hint-offset-x = \(Self.tomlNumber(uxPolish.shortcutHintOffsetX))
        shortcut-hint-offset-y = \(Self.tomlNumber(uxPolish.shortcutHintOffsetY))
        shortcut-hint-scale = \(Self.tomlNumber(uxPolish.shortcutHintScale))

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

        [spotlight]
        enabled = \(spotlight.enabled)
        index-command-history = \(spotlight.indexCommandHistory)
        index-agent-conversations = \(spotlight.indexAgentConversations)
        include-command-output = \(spotlight.includeCommandOutput)
        include-working-directories = \(spotlight.includeWorkingDirectories)
        include-tool-metadata = \(spotlight.includeToolMetadata)

        [activity]
        enabled = \(activity.enabled)
        cost-tracking = \(activity.costTrackingEnabled)
        storage-directory = "\(activity.storageDirectory)"
        input-cost-micros-per-million-tokens = \(activity.inputCostMicrosPerMillionTokens)
        output-cost-micros-per-million-tokens = \(activity.outputCostMicrosPerMillionTokens)

        [session-replay]
        enabled = \(sessionReplay.enabled)
        auto-record = \(sessionReplay.autoRecord)
        consent-granted = \(sessionReplay.consentGranted)
        storage-directory = "\(sessionReplay.storageDirectory)"
        max-recording-bytes = \(sessionReplay.maxRecordingBytes)

        [icloud-sync]
        enabled = \(iCloudSync.enabled)
        sync-directory-name = "\(iCloudSync.syncDirectoryName)"
        encryption-required = \(iCloudSync.encryptionRequired)
        artifact-kinds = \(Self.tomlStringArray(iCloudSync.artifactKinds.map(\.rawValue)))
        conflict-policy = "\(iCloudSync.conflictPolicy.rawValue)"

        [backup]
        enabled = \(backup.enabled)
        storage-directory = "\(backup.storageDirectory)"
        daily-retention-count = \(backup.dailyRetentionCount)
        monthly-retention-count = \(backup.monthlyRetentionCount)
        artifact-kinds = \(Self.tomlStringArray(backup.artifactKinds.map(\.rawValue)))

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

        [rich-input]
        enabled = \(savedConfig.richInput.enabled)
        auto-show-on-multiline-paste = \(savedConfig.richInput.autoShowOnMultilinePaste)
        default-shortcut = "\(savedConfig.richInput.defaultShortcut)"
        attachments-cache-ttl-days = \(savedConfig.richInput.attachmentsCacheTTLDays)
        attachments-max-size-mb = \(savedConfig.richInput.attachmentsMaxSizeMB)
        preserve-drafts-per-tab = \(savedConfig.richInput.preserveDraftsPerTab)

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

        [git-assistant]
        enabled = \(gitAssistant.enabled)
        default-provider = "\(gitAssistant.defaultProvider.rawValue)"
        max-diff-lines = \(gitAssistant.maxDiffLines)
        prompt-style = "\(gitAssistant.promptStyle.rawValue)"
        auto-generate-pr-body-on-create = \(gitAssistant.autoGeneratePRBodyOnCreate)
        auto-generate-commit-message-on-stage = \(gitAssistant.autoGenerateCommitMessageOnStage)

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

    private static func defaultDarkThemeNames() -> [String] {
        [
            "system",
            "Catppuccin Mocha",
            "Catppuccin Frappe",
            "Catppuccin Macchiato",
            "One Dark",
            "Solarized Dark",
            "Dracula",
            "Nord",
            "Gruvbox Dark",
            "Tokyo Night",
        ]
    }

    private static func defaultLightThemeNames() -> [String] {
        [
            "Catppuccin Latte",
            "Solarized Light",
        ]
    }

    func displayNameForThemePickerValue(_ value: String) -> String {
        ThemeSelectionResolver.isSystemAlias(value)
            ? localizedString("preferences.appearance.followSystem", fallback: "Follow System")
            : value
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
