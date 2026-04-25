// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ConfigService.swift - TOML configuration loading, validation and hot-reload.

import Foundation
@preconcurrency import Combine

// MARK: - Config File Providing Protocol

/// Abstraction over filesystem access for configuration files.
///
/// Allows injecting test doubles that hold config content in memory
/// instead of reading from disk.
protocol ConfigFileProviding: AnyObject, Sendable {
    /// Reads the configuration file content.
    ///
    /// - Returns: The raw TOML string, or `nil` if the file does not exist.
    func readConfigFile() -> String?

    /// Writes configuration content to the config file.
    ///
    /// Creates parent directories if needed.
    /// - Parameter content: The TOML string to write.
    /// - Throws: If the file cannot be written.
    func writeConfigFile(_ content: String) throws
}

// MARK: - Disk Config File Provider

/// Production implementation that reads/writes `~/.config/cocxy/config.toml`.
final class DiskConfigFileProvider: ConfigFileProviding {

    private let configDirectoryPath: String
    private let configFilePath: String

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        configDirectoryPath = "\(homeDirectory)/.config/cocxy"
        configFilePath = "\(configDirectoryPath)/config.toml"
    }

    func readConfigFile() -> String? {
        guard FileManager.default.fileExists(atPath: configFilePath) else {
            return nil
        }
        return try? String(contentsOfFile: configFilePath, encoding: .utf8)
    }

    func writeConfigFile(_ content: String) throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: configDirectoryPath) {
            try fileManager.createDirectory(
                atPath: configDirectoryPath,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try content.write(
            toFile: configFilePath,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configFilePath
        )
    }
}

// MARK: - Config Service

/// Concrete implementation of `ConfigProviding`.
///
/// Loads configuration from `~/.config/cocxy/config.toml`, validates all
/// values, applies defaults for missing keys, and publishes changes
/// via Combine.
///
/// If the config file does not exist on first launch, creates a documented
/// default file.
///
/// - SeeAlso: ADR-005 (TOML config format)
/// - SeeAlso: `ConfigProviding` protocol
final class ConfigService: ConfigProviding {

    // MARK: - Properties

    private let fileProvider: ConfigFileProviding
    private let parser: TOMLParser
    private let configSubject: CurrentValueSubject<CocxyConfig, Never>

    /// The current validated configuration snapshot.
    var current: CocxyConfig {
        configSubject.value
    }

    /// Publisher that emits the new configuration whenever it changes.
    var configChangedPublisher: AnyPublisher<CocxyConfig, Never> {
        configSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    /// Creates a ConfigService with a custom file provider.
    ///
    /// - Parameter fileProvider: The source of configuration file content.
    ///   Defaults to `DiskConfigFileProvider` for production use.
    init(
        fileProvider: ConfigFileProviding = DiskConfigFileProvider()
    ) {
        self.fileProvider = fileProvider
        self.parser = TOMLParser()
        self.configSubject = CurrentValueSubject(.defaults)
    }

    // MARK: - Loading

    /// Forces an immediate reload from disk.
    ///
    /// If the config file does not exist, writes a default config and uses defaults.
    /// If the file is malformed, logs a warning and uses defaults.
    /// Invalid values are clamped to valid ranges (not rejected).
    ///
    /// - Throws: `ConfigError.writeFailed` if the default config cannot be written.

    func reload() throws {
        guard let rawContent = fileProvider.readConfigFile() else {
            configSubject.send(.defaults)
            try createDefaultConfigFile()
            return
        }

        let config = parseAndValidate(rawContent)
        configSubject.send(config)
    }

    /// Hot-reload variant that preserves current config when the file is invalid.
    ///
    /// Unlike `reload()`, this method first validates the TOML content before
    /// applying it. If the file is malformed (e.g., mid-edit in vim), the
    /// current config remains intact rather than falling back to defaults.
    ///
    /// Use this method for file-watcher callbacks. Use `reload()` only for
    /// cold-start initialization where defaults are acceptable.
    func reloadIfValid() {
        guard let rawContent = fileProvider.readConfigFile() else { return }

        do {
            _ = try parser.parse(rawContent)
        } catch {
            // TOML is invalid — preserve current config.
            return
        }

        let config = parseAndValidate(rawContent)
        configSubject.send(config)
    }

    // MARK: - Default Config File Creation

    /// Creates the default config file via the file provider.
    private func createDefaultConfigFile() throws {
        let defaultToml = ConfigService.generateDefaultToml()
        try fileProvider.writeConfigFile(defaultToml)
    }

    /// Generates a documented TOML string with all default values.
    ///
    /// Used both for creating the initial config file and for tests.
    static func generateDefaultToml() -> String {
        let defaults = CocxyConfig.defaults
        return """
        # Cocxy Terminal Configuration
        # Documentation: ~/.config/cocxy/

        [general]
        shell = "\(defaults.general.shell)"
        working-directory = "\(defaults.general.workingDirectory)"
        confirm-close-process = \(defaults.general.confirmCloseProcess)

        [appearance]
        theme = "\(defaults.appearance.theme)"
        light-theme = "\(defaults.appearance.lightTheme)"
        font-family = "\(defaults.appearance.fontFamily)"
        font-size = \(defaults.appearance.fontSize)
        tab-position = "\(defaults.appearance.tabPosition.rawValue)"
        window-padding = \(defaults.appearance.windowPadding)
        background-opacity = \(defaults.appearance.backgroundOpacity)
        background-blur-radius = \(defaults.appearance.backgroundBlurRadius)
        ligatures = \(defaults.appearance.ligatures)
        font-thicken = \(defaults.appearance.fontThicken)
        # follow-system (default) inherits the active NSAppearance for the
        # translucent chrome when background-opacity < 1.0. Set to "light"
        # or "dark" to pin sidebar / tab strip / status bar independently
        # of the macOS appearance.
        transparency-chrome-theme = "\(defaults.appearance.transparencyChromeTheme.rawValue)"
        # Aurora chrome is the default redesigned sidebar, status bar and
        # command palette. Set this to false to return to the classic
        # sidebar / status bar while keeping the rest of the terminal
        # behavior unchanged.
        aurora-enabled = \(defaults.appearance.auroraEnabled)

        [terminal]
        scrollback-lines = \(defaults.terminal.scrollbackLines)
        cursor-style = "\(defaults.terminal.cursorStyle.rawValue)"
        cursor-blink = \(defaults.terminal.cursorBlink)
        cursor-opacity = \(defaults.terminal.cursorOpacity)
        mouse-hide-while-typing = \(defaults.terminal.mouseHideWhileTyping)
        copy-on-select = \(defaults.terminal.copyOnSelect)
        clipboard-paste-protection = \(defaults.terminal.clipboardPasteProtection)
        clipboard-read-access = "\(defaults.terminal.clipboardReadAccess.rawValue)"
        image-memory-limit-mb = \(defaults.terminal.imageMemoryLimitMB)
        image-file-transfer = \(defaults.terminal.imageFileTransfer)
        enable-sixel-images = \(defaults.terminal.enableSixelImages)
        enable-kitty-images = \(defaults.terminal.enableKittyImages)

        [agent-detection]
        enabled = \(defaults.agentDetection.enabled)
        osc-notifications = \(defaults.agentDetection.oscNotifications)
        pattern-matching = \(defaults.agentDetection.patternMatching)
        timing-heuristics = \(defaults.agentDetection.timingHeuristics)
        idle-timeout-seconds = \(defaults.agentDetection.idleTimeoutSeconds)

        [code-review]
        auto-show-on-session-end = \(defaults.codeReview.autoShowOnSessionEnd)

        [notifications]
        macos-notifications = \(defaults.notifications.macosNotifications)
        sound = \(defaults.notifications.sound)
        badge-on-tab = \(defaults.notifications.badgeOnTab)
        flash-tab = \(defaults.notifications.flashTab)
        show-dock-badge = \(defaults.notifications.showDockBadge)
        sound-finished = "\(defaults.notifications.soundFinished)"
        sound-attention = "\(defaults.notifications.soundAttention)"
        sound-error = "\(defaults.notifications.soundError)"

        [quick-terminal]
        enabled = \(defaults.quickTerminal.enabled)
        hotkey = "\(defaults.quickTerminal.hotkey)"
        position = "\(defaults.quickTerminal.position.rawValue)"
        height-percentage = \(defaults.quickTerminal.heightPercentage)
        hide-on-deactivate = \(defaults.quickTerminal.hideOnDeactivate)
        working-directory = "\(defaults.quickTerminal.workingDirectory)"
        animation-duration = \(defaults.quickTerminal.animationDuration)
        screen = "\(defaults.quickTerminal.screen.rawValue)"

        \(defaults.keybindings.tomlSection())

        [sessions]
        auto-save = \(defaults.sessions.autoSave)
        auto-save-interval = \(defaults.sessions.autoSaveInterval)
        restore-on-launch = \(defaults.sessions.restoreOnLaunch)

        [worktree]
        # Per-agent git worktree feature (v0.1.81).
        # When false (default), all `cocxy worktree` CLI verbs and palette
        # actions refuse with a helpful message instead of mutating state.
        # Opt in to get per-agent isolated worktrees without leaving Cocxy.
        enabled = \(defaults.worktree.enabled)
        # Base directory for worktree storage. Final path is
        # `<base-path>/<repo-hash>/<worktree-id>/`. Tilde is expanded at
        # use time.
        base-path = "\(defaults.worktree.basePath)"
        # Branch name template. Placeholders: {agent} (detected agent name,
        # sanitised), {id} (short unique id), {date} (YYYY-MM-DD).
        branch-template = "\(defaults.worktree.branchTemplate)"
        # Base ref to branch off when creating a worktree. "HEAD" (default)
        # checks out from the origin repo's current HEAD. "main" uses the
        # detected default branch. Any other valid git ref is passed
        # through unchanged.
        base-ref = "\(defaults.worktree.baseRef)"
        # Behaviour when the tab owning the worktree closes. "keep"
        # (default, never destructive), "prompt" (asks before removing),
        # or "remove" (auto-remove if clean, keep if dirty).
        on-close = "\(defaults.worktree.onClose.rawValue)"
        # When true, `cocxy worktree add` opens a new tab for the
        # worktree. When false, the current tab switches to the worktree
        # path instead.
        open-in-new-tab = \(defaults.worktree.openInNewTab)
        # Length of the random component of the worktree id. Clamped to
        # [\(WorktreeConfig.minIDLength), \(WorktreeConfig.maxIDLength)]. Collisions retry with length + 1.
        id-length = \(defaults.worktree.idLength)
        # When true, ProjectConfigService also walks the origin repo for
        # .cocxy.toml when none is found inside the worktree tree. Lets
        # per-project settings carry over to worktrees without duplication.
        inherit-project-config = \(defaults.worktree.inheritProjectConfig)
        # When true, the tab bar and Aurora session row show a worktree
        # badge on tabs with an active worktree.
        show-badge = \(defaults.worktree.showBadge)

        [github]
        # GitHub pane (Cmd+Option+G) plus the `cocxy github` CLI verbs
        # (v0.1.84). Authentication is delegated to `gh auth status` —
        # Cocxy never stores GitHub tokens of its own. Set `enabled`
        # to false to stop every `gh` invocation dead.
        enabled = \(defaults.github.enabled)
        # Seconds between silent background refreshes while the pane is
        # visible. 0 disables auto-refresh entirely. Clamped to
        # [\(GitHubConfig.minAutoRefreshInterval), \(GitHubConfig.maxAutoRefreshInterval)].
        auto-refresh-interval = \(defaults.github.autoRefreshInterval)
        # Maximum rows pulled from `gh pr list` / `gh issue list` per
        # refresh. Clamped to [\(GitHubConfig.minMaxItems), \(GitHubConfig.maxMaxItems)] to match gh's own cap.
        max-items = \(defaults.github.maxItems)
        # When true, draft pull requests show in the list. When false,
        # they are filtered out client-side.
        include-drafts = \(defaults.github.includeDrafts)
        # Default --state value used on first load. Allowed: open,
        # closed, merged (pull requests only), all.
        default-state = "\(defaults.github.defaultState)"
        # Master switch for the in-panel PR merge feature (v0.1.86).
        # Set to false to hide every "Merge PR" button in the Code
        # Review panel and the GitHub pane, and to disable the
        # `cocxy github pr-merge` CLI verb. The flag is a defensive
        # safety net; leave it on for normal operation.
        merge-enabled = \(defaults.github.mergeEnabled)
        """
    }

    // MARK: - Parsing and Validation

    /// Parses TOML content and validates all values, using defaults for missing
    /// or invalid entries.
    ///
    /// Never throws -- malformed TOML falls back to defaults silently.
    private func parseAndValidate(_ rawContent: String) -> CocxyConfig {
        let parsed: [String: TOMLValue]
        do {
            parsed = try parser.parse(rawContent)
        } catch {
            // Malformed TOML: use all defaults
            return .defaults
        }

        let general = parseGeneralConfig(from: parsed)
        let appearance = parseAppearanceConfig(from: parsed)
        let terminal = parseTerminalConfig(from: parsed)
        let agentDetection = parseAgentDetectionConfig(from: parsed)
        let codeReview = parseCodeReviewConfig(from: parsed)
        let notifications = parseNotificationConfig(from: parsed)
        let quickTerminal = parseQuickTerminalConfig(from: parsed)
        let keybindings = parseKeybindingsConfig(from: parsed)
        let sessions = parseSessionsConfig(from: parsed)
        let worktree = parseWorktreeConfig(from: parsed)
        let github = parseGitHubConfig(from: parsed)

        return CocxyConfig(
            general: general,
            appearance: appearance,
            terminal: terminal,
            agentDetection: agentDetection,
            codeReview: codeReview,
            notifications: notifications,
            quickTerminal: quickTerminal,
            keybindings: keybindings,
            sessions: sessions,
            worktree: worktree,
            github: github
        )
    }

    // MARK: - Section Parsers

    /// Extracts a table from the parsed TOML by section name.
    ///
    /// - Returns: The table dictionary, or empty if the section does not exist.
    private func extractTable(
        _ sectionName: String,
        from parsed: [String: TOMLValue]
    ) -> [String: TOMLValue] {
        guard case .table(let table) = parsed[sectionName] else {
            return [:]
        }
        return table
    }

    /// Parses the `[general]` section.
    private func parseGeneralConfig(from parsed: [String: TOMLValue]) -> GeneralConfig {
        let table = extractTable("general", from: parsed)
        let defaults = GeneralConfig.defaults

        return GeneralConfig(
            shell: stringValue(table["shell"]) ?? defaults.shell,
            workingDirectory: stringValue(table["working-directory"]) ?? defaults.workingDirectory,
            confirmCloseProcess: boolValue(table["confirm-close-process"]) ?? defaults.confirmCloseProcess
        )
    }

    /// Parses the `[appearance]` section with validation.
    private func parseAppearanceConfig(from parsed: [String: TOMLValue]) -> AppearanceConfig {
        let table = extractTable("appearance", from: parsed)
        let defaults = AppearanceConfig.defaults

        let rawFontSize = doubleValue(table["font-size"]) ?? defaults.fontSize
        let validatedFontSize = clamp(rawFontSize, min: 6.0, max: 72.0)

        let rawWindowPadding = doubleValue(table["window-padding"]) ?? defaults.windowPadding
        let validatedWindowPadding = max(0.0, rawWindowPadding)

        let tabPositionString = stringValue(table["tab-position"])
        let tabPosition = tabPositionString.flatMap { TabPosition(rawValue: $0) } ?? defaults.tabPosition

        let rawOpacity = doubleValue(table["background-opacity"]) ?? defaults.backgroundOpacity
        let rawBlur = doubleValue(table["background-blur-radius"]) ?? defaults.backgroundBlurRadius
        let chromeTheme = parseTransparencyChromeTheme(table["transparency-chrome-theme"])

        return AppearanceConfig(
            theme: stringValue(table["theme"]) ?? defaults.theme,
            lightTheme: stringValue(table["light-theme"]) ?? defaults.lightTheme,
            fontFamily: stringValue(table["font-family"]) ?? defaults.fontFamily,
            fontSize: validatedFontSize,
            tabPosition: tabPosition,
            windowPadding: validatedWindowPadding,
            windowPaddingX: doubleValue(table["window-padding-x"]),
            windowPaddingY: doubleValue(table["window-padding-y"]),
            ligatures: boolValue(table["ligatures"]) ?? defaults.ligatures,
            fontThicken: boolValue(table["font-thicken"]) ?? defaults.fontThicken,
            backgroundOpacity: clamp(rawOpacity, min: 0.1, max: 1.0),
            backgroundBlurRadius: clamp(rawBlur, min: 0, max: 100),
            transparencyChromeTheme: chromeTheme,
            auroraEnabled: boolValue(table["aurora-enabled"]) ?? defaults.auroraEnabled
        )
    }

    /// Parses the `transparency-chrome-theme` value tolerantly.
    ///
    /// Accepts strings matching `TransparencyChromeTheme.rawValue`
    /// (`"follow-system"`, `"light"`, `"dark"`). Everything else — unknown
    /// strings, wrong TOML types, missing key — falls back to
    /// `.followSystem` with a single diagnostic log. This preserves the
    /// zero-break contract: older configs and typos never crash the app
    /// and never alter the chrome appearance.
    private func parseTransparencyChromeTheme(_ value: TOMLValue?) -> TransparencyChromeTheme {
        guard let value else {
            return .followSystem
        }
        switch value {
        case .string(let raw):
            if let parsed = TransparencyChromeTheme(rawValue: raw) {
                return parsed
            }
            NSLog(
                "[ConfigService] Unknown transparency-chrome-theme value %@; falling back to follow-system.",
                raw
            )
            return .followSystem
        default:
            NSLog(
                "[ConfigService] transparency-chrome-theme must be a string; falling back to follow-system."
            )
            return .followSystem
        }
    }

    /// Parses the `[terminal]` section with validation.
    private func parseTerminalConfig(from parsed: [String: TOMLValue]) -> TerminalConfig {
        let table = extractTable("terminal", from: parsed)
        let defaults = TerminalConfig.defaults

        let rawScrollback = intValue(table["scrollback-lines"]) ?? defaults.scrollbackLines
        let validatedScrollback = max(0, rawScrollback)
        let rawImageMemoryLimit = intValue(table["image-memory-limit-mb"]) ?? defaults.imageMemoryLimitMB
        let validatedImageMemoryLimit = max(1, rawImageMemoryLimit)

        let cursorStyleStr = stringValue(table["cursor-style"])
        let cursorStyle = cursorStyleStr.flatMap { CursorStyle(rawValue: $0) } ?? defaults.cursorStyle

        return TerminalConfig(
            scrollbackLines: validatedScrollback,
            cursorStyle: cursorStyle,
            cursorBlink: boolValue(table["cursor-blink"]) ?? defaults.cursorBlink,
            cursorOpacity: clamp(
                doubleValue(table["cursor-opacity"]) ?? defaults.cursorOpacity,
                min: 0.0, max: 1.0
            ),
            mouseHideWhileTyping: boolValue(table["mouse-hide-while-typing"]) ?? defaults.mouseHideWhileTyping,
            copyOnSelect: boolValue(table["copy-on-select"]) ?? defaults.copyOnSelect,
            clipboardPasteProtection: boolValue(table["clipboard-paste-protection"]) ?? defaults.clipboardPasteProtection,
            clipboardReadAccess: stringValue(table["clipboard-read-access"])
                .flatMap { ClipboardReadAccess(rawValue: $0) }
                ?? defaults.clipboardReadAccess,
            imageMemoryLimitMB: validatedImageMemoryLimit,
            imageFileTransfer: boolValue(table["image-file-transfer"]) ?? defaults.imageFileTransfer,
            enableSixelImages: boolValue(table["enable-sixel-images"]) ?? defaults.enableSixelImages,
            enableKittyImages: boolValue(table["enable-kitty-images"]) ?? defaults.enableKittyImages
        )
    }

    /// Parses the `[agent-detection]` section with validation.
    private func parseAgentDetectionConfig(from parsed: [String: TOMLValue]) -> AgentDetectionConfig {
        let table = extractTable("agent-detection", from: parsed)
        let defaults = AgentDetectionConfig.defaults

        let rawTimeout = intValue(table["idle-timeout-seconds"]) ?? defaults.idleTimeoutSeconds
        let validatedTimeout = max(1, rawTimeout)

        return AgentDetectionConfig(
            enabled: boolValue(table["enabled"]) ?? defaults.enabled,
            oscNotifications: boolValue(table["osc-notifications"]) ?? defaults.oscNotifications,
            patternMatching: boolValue(table["pattern-matching"]) ?? defaults.patternMatching,
            timingHeuristics: boolValue(table["timing-heuristics"]) ?? defaults.timingHeuristics,
            idleTimeoutSeconds: validatedTimeout
        )
    }

    /// Parses the `[notifications]` section.
    private func parseCodeReviewConfig(from parsed: [String: TOMLValue]) -> CodeReviewConfig {
        let table = extractTable("code-review", from: parsed)
        let defaults = CodeReviewConfig.defaults

        return CodeReviewConfig(
            autoShowOnSessionEnd: boolValue(table["auto-show-on-session-end"]) ?? defaults.autoShowOnSessionEnd
        )
    }

    /// Parses the `[notifications]` section.
    private func parseNotificationConfig(from parsed: [String: TOMLValue]) -> NotificationConfig {
        let table = extractTable("notifications", from: parsed)
        let defaults = NotificationConfig.defaults

        return NotificationConfig(
            macosNotifications: boolValue(table["macos-notifications"]) ?? defaults.macosNotifications,
            sound: boolValue(table["sound"]) ?? defaults.sound,
            badgeOnTab: boolValue(table["badge-on-tab"]) ?? defaults.badgeOnTab,
            flashTab: boolValue(table["flash-tab"]) ?? defaults.flashTab,
            showDockBadge: boolValue(table["show-dock-badge"]) ?? defaults.showDockBadge,
            soundFinished: stringValue(table["sound-finished"]) ?? defaults.soundFinished,
            soundAttention: stringValue(table["sound-attention"]) ?? defaults.soundAttention,
            soundError: stringValue(table["sound-error"]) ?? defaults.soundError
        )
    }

    /// Parses the `[quick-terminal]` section with validation.
    private func parseQuickTerminalConfig(from parsed: [String: TOMLValue]) -> QuickTerminalConfig {
        let table = extractTable("quick-terminal", from: parsed)
        let defaults = QuickTerminalConfig.defaults

        let rawHeight = intValue(table["height-percentage"]) ?? defaults.heightPercentage
        let validatedHeight = clamp(rawHeight, min: 10, max: 100)

        let positionString = stringValue(table["position"])
        let position = positionString.flatMap { QuickTerminalPosition(rawValue: $0) } ?? defaults.position

        let screenString = stringValue(table["screen"])
        let screen = screenString.flatMap { QuickTerminalScreen(rawValue: $0) } ?? defaults.screen
        let rawAnimDuration = doubleValue(table["animation-duration"]) ?? defaults.animationDuration

        return QuickTerminalConfig(
            enabled: boolValue(table["enabled"]) ?? defaults.enabled,
            hotkey: stringValue(table["hotkey"]) ?? defaults.hotkey,
            position: position,
            heightPercentage: validatedHeight,
            hideOnDeactivate: boolValue(table["hide-on-deactivate"]) ?? defaults.hideOnDeactivate,
            workingDirectory: stringValue(table["working-directory"]) ?? defaults.workingDirectory,
            animationDuration: clamp(rawAnimDuration, min: 0.0, max: 2.0),
            screen: screen
        )
    }

    /// Parses the `[keybindings]` section.
    ///
    /// Accepts two key styles side-by-side for forward compatibility:
    ///   1. Legacy kebab-case fields (`new-tab = "cmd+t"`) mapped to the eight
    ///      typed properties on `KeybindingsConfig`.
    ///   2. Dotted catalog ids (`"split.close" = "cmd+shift+w"`) that appear
    ///      as quoted TOML keys. These end up in `customOverrides`.
    ///
    /// If both key styles reference the same action (e.g., `new-tab` and
    /// `"tab.new"` both present), the dotted value wins because it is the
    /// canonical form the editor writes back.
    private func parseKeybindingsConfig(from parsed: [String: TOMLValue]) -> KeybindingsConfig {
        let table = extractTable("keybindings", from: parsed)
        let defaults = KeybindingsConfig.defaults

        // Legacy typed fields populate their dedicated properties.
        var newTab = stringValue(table["new-tab"]) ?? defaults.newTab
        var closeTab = stringValue(table["close-tab"]) ?? defaults.closeTab
        var nextTab = stringValue(table["next-tab"]) ?? defaults.nextTab
        var prevTab = stringValue(table["prev-tab"]) ?? defaults.prevTab
        var splitVertical = stringValue(table["split-vertical"]) ?? defaults.splitVertical
        var splitHorizontal = stringValue(table["split-horizontal"]) ?? defaults.splitHorizontal
        var gotoAttention = stringValue(table["goto-attention"]) ?? defaults.gotoAttention
        var toggleQuickTerminal = stringValue(table["toggle-quick-terminal"]) ?? defaults.toggleQuickTerminal

        // Dotted-id entries can override either a legacy field or land in
        // `customOverrides`. Walk every key in the TOML table once.
        var customOverrides: [String: String] = [:]
        let legacyActionIds: Set<String> = Set(KeybindingActionCatalog.legacyFieldMapping.values)
        let kebabKeys: Set<String> = Set(KeybindingActionCatalog.legacyFieldMapping.keys)

        for (rawKey, rawValue) in table {
            guard case .string(let canonical) = rawValue else { continue }
            // Quoted TOML keys arrive with their surrounding double quotes
            // (e.g., `\"tab.new\"`). Normalize before lookup.
            let key = Self.unquoteKey(rawKey)

            // Legacy kebab keys already handled above.
            if kebabKeys.contains(key) { continue }

            // Only accept ids the editor knows about to avoid storing junk.
            guard let action = KeybindingAction.catalogEntry(for: key) else { continue }

            if legacyActionIds.contains(key) {
                switch key {
                case KeybindingActionCatalog.tabNew.id: newTab = canonical
                case KeybindingActionCatalog.tabClose.id: closeTab = canonical
                case KeybindingActionCatalog.tabNext.id: nextTab = canonical
                case KeybindingActionCatalog.tabPrevious.id: prevTab = canonical
                case KeybindingActionCatalog.splitVertical.id: splitVertical = canonical
                case KeybindingActionCatalog.splitHorizontal.id: splitHorizontal = canonical
                case KeybindingActionCatalog.remoteGoToAttention.id: gotoAttention = canonical
                case KeybindingActionCatalog.windowQuickTerminal.id: toggleQuickTerminal = canonical
                default: break
                }
            } else if canonical != action.defaultShortcut.canonical {
                customOverrides[action.id] = canonical
            }
        }

        return KeybindingsConfig(
            newTab: newTab,
            closeTab: closeTab,
            nextTab: nextTab,
            prevTab: prevTab,
            splitVertical: splitVertical,
            splitHorizontal: splitHorizontal,
            gotoAttention: gotoAttention,
            toggleQuickTerminal: toggleQuickTerminal,
            customOverrides: customOverrides
        )
    }

    /// Parses the `[sessions]` section with validation.
    private func parseSessionsConfig(from parsed: [String: TOMLValue]) -> SessionsConfig {
        let table = extractTable("sessions", from: parsed)
        let defaults = SessionsConfig.defaults

        let rawInterval = intValue(table["auto-save-interval"]) ?? defaults.autoSaveInterval
        let validatedInterval = max(5, rawInterval)

        return SessionsConfig(
            autoSave: boolValue(table["auto-save"]) ?? defaults.autoSave,
            autoSaveInterval: validatedInterval,
            restoreOnLaunch: boolValue(table["restore-on-launch"]) ?? defaults.restoreOnLaunch
        )
    }

    /// Parses the `[worktree]` section with validation.
    ///
    /// Missing keys fall back to defaults. `onClose` accepts only the
    /// known enum raw values (`keep`, `prompt`, `remove`) — unknown
    /// strings revert to the default (`keep`) so a typo in the config
    /// never silently produces destructive behaviour. `idLength` is
    /// clamped to `[WorktreeConfig.minIDLength, maxIDLength]`.
    private func parseWorktreeConfig(from parsed: [String: TOMLValue]) -> WorktreeConfig {
        let table = extractTable("worktree", from: parsed)
        let defaults = WorktreeConfig.defaults

        let onCloseRaw = stringValue(table["on-close"]) ?? defaults.onClose.rawValue
        let onClose = WorktreeOnClose(rawValue: onCloseRaw) ?? defaults.onClose

        let rawIDLength = intValue(table["id-length"]) ?? defaults.idLength
        let clampedIDLength = clamp(
            rawIDLength,
            min: WorktreeConfig.minIDLength,
            max: WorktreeConfig.maxIDLength
        )

        return WorktreeConfig(
            enabled: boolValue(table["enabled"]) ?? defaults.enabled,
            basePath: stringValue(table["base-path"]) ?? defaults.basePath,
            branchTemplate: stringValue(table["branch-template"]) ?? defaults.branchTemplate,
            baseRef: stringValue(table["base-ref"]) ?? defaults.baseRef,
            onClose: onClose,
            openInNewTab: boolValue(table["open-in-new-tab"]) ?? defaults.openInNewTab,
            idLength: clampedIDLength,
            inheritProjectConfig: boolValue(table["inherit-project-config"])
                ?? defaults.inheritProjectConfig,
            showBadge: boolValue(table["show-badge"]) ?? defaults.showBadge
        )
    }

    /// Parses the `[github]` section with validation.
    ///
    /// `autoRefreshInterval` is clamped to
    /// `[GitHubConfig.minAutoRefreshInterval, maxAutoRefreshInterval]` so
    /// a negative value never disables the timer in a way the UI
    /// cannot describe, and a very large value never starves the refresh
    /// loop. `maxItems` is clamped to `[1, 200]` to match the upstream
    /// `gh` CLI hard cap. `defaultState` falls back to the default when
    /// the user supplies a value outside the allowed set so a typo never
    /// silently picks a surprising initial view.
    private func parseGitHubConfig(from parsed: [String: TOMLValue]) -> GitHubConfig {
        let table = extractTable("github", from: parsed)
        let defaults = GitHubConfig.defaults

        let rawRefresh = intValue(table["auto-refresh-interval"]) ?? defaults.autoRefreshInterval
        let clampedRefresh = clamp(
            rawRefresh,
            min: GitHubConfig.minAutoRefreshInterval,
            max: GitHubConfig.maxAutoRefreshInterval
        )

        let rawMaxItems = intValue(table["max-items"]) ?? defaults.maxItems
        let clampedMaxItems = clamp(
            rawMaxItems,
            min: GitHubConfig.minMaxItems,
            max: GitHubConfig.maxMaxItems
        )

        let rawState = stringValue(table["default-state"])?.lowercased() ?? defaults.defaultState
        let validatedState = GitHubConfig.allowedDefaultStates.contains(rawState)
            ? rawState
            : defaults.defaultState

        return GitHubConfig(
            enabled: boolValue(table["enabled"]) ?? defaults.enabled,
            autoRefreshInterval: clampedRefresh,
            maxItems: clampedMaxItems,
            includeDrafts: boolValue(table["include-drafts"]) ?? defaults.includeDrafts,
            defaultState: validatedState,
            mergeEnabled: boolValue(table["merge-enabled"]) ?? defaults.mergeEnabled
        )
    }

    // MARK: - Value Extractors

    /// Extracts a string from a TOML value, returning `nil` for non-string values.
    private func stringValue(_ value: TOMLValue?) -> String? {
        guard case .string(let stringContent) = value else { return nil }
        return stringContent
    }

    /// Extracts a boolean from a TOML value, returning `nil` for non-boolean values.
    private func boolValue(_ value: TOMLValue?) -> Bool? {
        guard case .boolean(let boolContent) = value else { return nil }
        return boolContent
    }

    /// Extracts an integer from a TOML value, returning `nil` for non-integer values.
    private func intValue(_ value: TOMLValue?) -> Int? {
        guard case .integer(let intContent) = value else { return nil }
        return intContent
    }

    /// Extracts a double from a TOML value.
    ///
    /// Accepts both `.float` and `.integer` TOML values, converting integers
    /// to doubles transparently. This handles cases like `font-size = 14`
    /// (parsed as integer) vs `font-size = 14.0` (parsed as float).
    private func doubleValue(_ value: TOMLValue?) -> Double? {
        switch value {
        case .float(let doubleContent):
            return doubleContent
        case .integer(let intContent):
            return Double(intContent)
        default:
            return nil
        }
    }

    // MARK: - Validation Helpers

    /// Clamps a comparable value to a range.
    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }

    /// Strips surrounding double or single quotes from a TOML table key.
    ///
    /// The shared TOML parser preserves quotes around literal keys (for
    /// example `\"tab.new\"` for a dotted key). Keybindings need to match
    /// both quoted and bare forms, so this helper normalizes both.
    fileprivate static func unquoteKey(_ rawKey: String) -> String {
        if rawKey.count >= 2 {
            if rawKey.hasPrefix("\"") && rawKey.hasSuffix("\"") {
                return String(rawKey.dropFirst().dropLast())
            }
            if rawKey.hasPrefix("'") && rawKey.hasSuffix("'") {
                return String(rawKey.dropFirst().dropLast())
            }
        }
        return rawKey
    }
}
