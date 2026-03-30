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
    init(fileProvider: ConfigFileProviding = DiskConfigFileProvider()) {
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
    /// Path to the Ghostty config used as fallback. Nil disables the fallback.
    /// Exposed for testing so the fallback can be disabled or pointed at a fixture.
    var ghosttyConfigPath: String? = GhosttyConfigFallback.defaultConfigPath

    func reload() throws {
        guard let rawContent = fileProvider.readConfigFile() else {
            // No cocxy config exists. Try Ghostty config as fallback
            // so users who already have Ghostty configured see a familiar
            // terminal on first launch.
            if let path = ghosttyConfigPath,
               let ghosttyValues = GhosttyConfigFallback.read(from: path) {
                let config = GhosttyConfigFallback.applyToDefaults(ghosttyValues)
                configSubject.send(config)
                NSLog("[ConfigService] Loaded appearance from Ghostty config fallback")
            } else {
                configSubject.send(.defaults)
            }
            try createDefaultConfigFile()
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
        font-family = "\(defaults.appearance.fontFamily)"
        font-size = \(defaults.appearance.fontSize)
        tab-position = "\(defaults.appearance.tabPosition.rawValue)"
        window-padding = \(defaults.appearance.windowPadding)

        [terminal]
        scrollback-lines = \(defaults.terminal.scrollbackLines)

        [agent-detection]
        enabled = \(defaults.agentDetection.enabled)
        osc-notifications = \(defaults.agentDetection.oscNotifications)
        pattern-matching = \(defaults.agentDetection.patternMatching)
        timing-heuristics = \(defaults.agentDetection.timingHeuristics)
        idle-timeout-seconds = \(defaults.agentDetection.idleTimeoutSeconds)

        [notifications]
        macos-notifications = \(defaults.notifications.macosNotifications)
        sound = \(defaults.notifications.sound)
        badge-on-tab = \(defaults.notifications.badgeOnTab)
        flash-tab = \(defaults.notifications.flashTab)
        sound-finished = "\(defaults.notifications.soundFinished)"
        sound-attention = "\(defaults.notifications.soundAttention)"
        sound-error = "\(defaults.notifications.soundError)"

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
        let notifications = parseNotificationConfig(from: parsed)
        let quickTerminal = parseQuickTerminalConfig(from: parsed)
        let keybindings = parseKeybindingsConfig(from: parsed)
        let sessions = parseSessionsConfig(from: parsed)

        return CocxyConfig(
            general: general,
            appearance: appearance,
            terminal: terminal,
            agentDetection: agentDetection,
            notifications: notifications,
            quickTerminal: quickTerminal,
            keybindings: keybindings,
            sessions: sessions
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

        return AppearanceConfig(
            theme: stringValue(table["theme"]) ?? defaults.theme,
            fontFamily: stringValue(table["font-family"]) ?? defaults.fontFamily,
            fontSize: validatedFontSize,
            tabPosition: tabPosition,
            windowPadding: validatedWindowPadding,
            windowPaddingX: doubleValue(table["window-padding-x"]),
            windowPaddingY: doubleValue(table["window-padding-y"]),
            backgroundOpacity: clamp(rawOpacity, min: 0.1, max: 1.0),
            backgroundBlurRadius: clamp(rawBlur, min: 0, max: 100)
        )
    }

    /// Parses the `[terminal]` section with validation.
    private func parseTerminalConfig(from parsed: [String: TOMLValue]) -> TerminalConfig {
        let table = extractTable("terminal", from: parsed)
        let defaults = TerminalConfig.defaults

        let rawScrollback = intValue(table["scrollback-lines"]) ?? defaults.scrollbackLines
        let validatedScrollback = max(0, rawScrollback)

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
            clipboardPasteProtection: boolValue(table["clipboard-paste-protection"]) ?? defaults.clipboardPasteProtection
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
    private func parseKeybindingsConfig(from parsed: [String: TOMLValue]) -> KeybindingsConfig {
        let table = extractTable("keybindings", from: parsed)
        let defaults = KeybindingsConfig.defaults

        return KeybindingsConfig(
            newTab: stringValue(table["new-tab"]) ?? defaults.newTab,
            closeTab: stringValue(table["close-tab"]) ?? defaults.closeTab,
            nextTab: stringValue(table["next-tab"]) ?? defaults.nextTab,
            prevTab: stringValue(table["prev-tab"]) ?? defaults.prevTab,
            splitVertical: stringValue(table["split-vertical"]) ?? defaults.splitVertical,
            splitHorizontal: stringValue(table["split-horizontal"]) ?? defaults.splitHorizontal,
            gotoAttention: stringValue(table["goto-attention"]) ?? defaults.gotoAttention,
            toggleQuickTerminal: stringValue(table["toggle-quick-terminal"]) ?? defaults.toggleQuickTerminal
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
}
