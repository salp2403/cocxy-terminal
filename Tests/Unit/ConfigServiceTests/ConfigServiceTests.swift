// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ConfigServiceTests.swift - Tests for the configuration service.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Config Service Tests

/// Tests for `ConfigService` covering TOML parsing, defaults and validation.
///
/// Covers:
/// - Default config creation when no file exists.
/// - Parsing valid TOML with all sections.
/// - Partial TOML (missing sections use defaults).
/// - Invalid values (out-of-range font size, etc.).
/// - Hot-reload notification via Combine.
/// - Config-to-TOML mapping for every section.
/// - Validation of ranges and constraints.
///
/// Uses `InMemoryConfigFileProvider` to avoid filesystem dependency in tests.
///
/// - SeeAlso: ADR-005 (TOML config format)

// MARK: - Default Config Tests

final class ConfigServiceDefaultTests: XCTestCase {

    func testDefaultConfigHasExpectedValues() {
        let config = CocxyConfig.defaults

        XCTAssertEqual(config.general.shell, "/bin/zsh")
        XCTAssertEqual(config.general.workingDirectory, "~")
        XCTAssertTrue(config.general.confirmCloseProcess)
        XCTAssertEqual(config.appearance.theme, "catppuccin-mocha")
        XCTAssertEqual(config.appearance.fontFamily, "JetBrainsMono Nerd Font")
        XCTAssertEqual(config.appearance.fontSize, 14)
        XCTAssertEqual(config.appearance.tabPosition, .left)
        XCTAssertEqual(config.appearance.windowPadding, 8)
        XCTAssertTrue(config.agentDetection.enabled)
        XCTAssertTrue(config.agentDetection.oscNotifications)
        XCTAssertEqual(config.agentDetection.idleTimeoutSeconds, 5)
        XCTAssertTrue(config.notifications.macosNotifications)
        XCTAssertTrue(config.notifications.sound)
        XCTAssertTrue(config.notifications.badgeOnTab)
        XCTAssertTrue(config.notifications.flashTab)
        XCTAssertEqual(config.quickTerminal.hotkey, "cmd+grave")
        XCTAssertEqual(config.quickTerminal.position, .top)
        XCTAssertEqual(config.quickTerminal.heightPercentage, 40)
        XCTAssertEqual(config.keybindings.newTab, "cmd+t")
        XCTAssertEqual(config.keybindings.closeTab, "cmd+w")
        XCTAssertTrue(config.sessions.autoSave)
        XCTAssertEqual(config.sessions.autoSaveInterval, 30)
        XCTAssertTrue(config.sessions.restoreOnLaunch)
    }
}

// MARK: - ConfigService with Missing File

final class ConfigServiceMissingFileTests: XCTestCase {

    func testMissingFileReturnsDefaults() throws {
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let service = ConfigService(fileProvider: fileProvider)
        service.ghosttyConfigPath = nil  // Disable Ghostty fallback for test isolation.
        try service.reload()

        let config = service.current
        XCTAssertEqual(config, CocxyConfig.defaults)
    }

    func testMissingFileCreatesDefaultFileViaProvider() throws {
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let service = ConfigService(fileProvider: fileProvider)
        service.ghosttyConfigPath = nil  // Disable Ghostty fallback for test isolation.
        try service.reload()

        XCTAssertNotNil(
            fileProvider.writtenContent,
            "ConfigService must write a default config file when none exists"
        )
    }
}

// MARK: - Full TOML Parsing Tests

final class ConfigServiceFullParsingTests: XCTestCase {

    func testParseValidTomlWithAllSections() throws {
        let toml = """
        [general]
        shell = "/bin/bash"
        working-directory = "/tmp"
        confirm-close-process = false

        [appearance]
        theme = "dracula"
        font-family = "Fira Code"
        font-size = 16.0
        tab-position = "top"
        window-padding = 12.0

        [agent-detection]
        enabled = false
        osc-notifications = false
        pattern-matching = false
        timing-heuristics = false
        idle-timeout-seconds = 10

        [notifications]
        macos-notifications = false
        sound = false
        badge-on-tab = false
        flash-tab = false

        [quick-terminal]
        hotkey = "ctrl+grave"
        position = "bottom"
        height-percentage = 60

        [keybindings]
        new-tab = "ctrl+t"
        close-tab = "ctrl+w"
        next-tab = "ctrl+tab"
        prev-tab = "ctrl+shift+tab"
        split-vertical = "ctrl+d"
        split-horizontal = "ctrl+shift+d"
        goto-attention = "ctrl+shift+u"
        toggle-quick-terminal = "ctrl+grave"

        [sessions]
        auto-save = false
        auto-save-interval = 60
        restore-on-launch = false
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let config = service.current
        XCTAssertEqual(config.general.shell, "/bin/bash")
        XCTAssertEqual(config.general.workingDirectory, "/tmp")
        XCTAssertFalse(config.general.confirmCloseProcess)

        XCTAssertEqual(config.appearance.theme, "dracula")
        XCTAssertEqual(config.appearance.fontFamily, "Fira Code")
        XCTAssertEqual(config.appearance.fontSize, 16.0)
        XCTAssertEqual(config.appearance.tabPosition, .top)
        XCTAssertEqual(config.appearance.windowPadding, 12.0)

        XCTAssertFalse(config.agentDetection.enabled)
        XCTAssertFalse(config.agentDetection.oscNotifications)
        XCTAssertEqual(config.agentDetection.idleTimeoutSeconds, 10)

        XCTAssertFalse(config.notifications.macosNotifications)
        XCTAssertFalse(config.notifications.sound)

        XCTAssertEqual(config.quickTerminal.hotkey, "ctrl+grave")
        XCTAssertEqual(config.quickTerminal.position, .bottom)
        XCTAssertEqual(config.quickTerminal.heightPercentage, 60)

        XCTAssertEqual(config.keybindings.newTab, "ctrl+t")
        XCTAssertEqual(config.keybindings.closeTab, "ctrl+w")

        XCTAssertFalse(config.sessions.autoSave)
        XCTAssertEqual(config.sessions.autoSaveInterval, 60)
        XCTAssertFalse(config.sessions.restoreOnLaunch)
    }
}

// MARK: - Partial TOML Tests

final class ConfigServicePartialTomlTests: XCTestCase {

    func testPartialTomlUsesDefaultsForMissingSections() throws {
        let toml = """
        [appearance]
        theme = "nord"
        font-size = 18.0
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let config = service.current

        // Overridden values
        XCTAssertEqual(config.appearance.theme, "nord")
        XCTAssertEqual(config.appearance.fontSize, 18.0)

        // Missing appearance keys use defaults
        XCTAssertEqual(
            config.appearance.fontFamily,
            AppearanceConfig.defaults.fontFamily
        )
        XCTAssertEqual(config.appearance.tabPosition, .left)

        // Missing sections use defaults entirely
        XCTAssertEqual(config.general, GeneralConfig.defaults)
        XCTAssertEqual(config.agentDetection, AgentDetectionConfig.defaults)
        XCTAssertEqual(config.notifications, NotificationConfig.defaults)
        XCTAssertEqual(config.quickTerminal, QuickTerminalConfig.defaults)
        XCTAssertEqual(config.keybindings, KeybindingsConfig.defaults)
        XCTAssertEqual(config.sessions, SessionsConfig.defaults)
    }

    func testPartialSectionKeysUsesDefaultsForMissingKeys() throws {
        let toml = """
        [general]
        shell = "/bin/fish"
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let config = service.current
        XCTAssertEqual(config.general.shell, "/bin/fish")
        XCTAssertEqual(config.general.workingDirectory, "~")
        XCTAssertTrue(config.general.confirmCloseProcess)
    }

    func testEmptyTomlReturnsDefaults() throws {
        let toml = ""

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(service.current, CocxyConfig.defaults)
    }
}

// MARK: - Validation Tests

final class ConfigServiceValidationTests: XCTestCase {

    func testFontSizeBelowMinimumClampsToMinimum() throws {
        let toml = """
        [appearance]
        font-size = 2.0
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.appearance.fontSize,
            6.0,
            "Font size below 6 must be clamped to 6"
        )
    }

    func testFontSizeAboveMaximumClampsToMaximum() throws {
        let toml = """
        [appearance]
        font-size = 200.0
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.appearance.fontSize,
            72.0,
            "Font size above 72 must be clamped to 72"
        )
    }

    func testIdleTimeoutBelowMinimumClampsToMinimum() throws {
        let toml = """
        [agent-detection]
        idle-timeout-seconds = 0
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.agentDetection.idleTimeoutSeconds,
            1,
            "Idle timeout must be at least 1 second"
        )
    }

    func testAutoSaveIntervalBelowMinimumClampsToMinimum() throws {
        let toml = """
        [sessions]
        auto-save-interval = 0
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.sessions.autoSaveInterval,
            5,
            "Auto-save interval must be at least 5 seconds"
        )
    }

    func testHeightPercentageBelowMinimumClampsToMinimum() throws {
        let toml = """
        [quick-terminal]
        height-percentage = -5
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.quickTerminal.heightPercentage,
            10,
            "Height percentage must be at least 10"
        )
    }

    func testHeightPercentageAboveMaximumClampsToMaximum() throws {
        let toml = """
        [quick-terminal]
        height-percentage = 150
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.quickTerminal.heightPercentage,
            100,
            "Height percentage must be at most 100"
        )
    }

    func testWindowPaddingBelowZeroClampsToZero() throws {
        let toml = """
        [appearance]
        window-padding = -5.0
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.appearance.windowPadding,
            0.0,
            "Window padding must be at least 0"
        )
    }

    func testInvalidTabPositionUsesDefault() throws {
        let toml = """
        [appearance]
        tab-position = "nonexistent"
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.appearance.tabPosition,
            AppearanceConfig.defaults.tabPosition,
            "Invalid tab-position must fall back to default"
        )
    }

    func testInvalidQuickTerminalPositionUsesDefault() throws {
        let toml = """
        [quick-terminal]
        position = "middle"
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current.quickTerminal.position,
            QuickTerminalConfig.defaults.position,
            "Invalid quick-terminal position must fall back to default"
        )
    }
}

// MARK: - Unknown Fields Tests

final class ConfigServiceUnknownFieldsTests: XCTestCase {

    func testUnknownSectionsAreIgnored() throws {
        let toml = """
        [unknown-section]
        key = "value"

        [appearance]
        theme = "solarized"
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(service.current.appearance.theme, "solarized")
    }

    func testUnknownKeysInKnownSectionAreIgnored() throws {
        let toml = """
        [appearance]
        theme = "solarized"
        unknown-key = "ignored"
        another-unknown = 42
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(service.current.appearance.theme, "solarized")
    }
}

// MARK: - Malformed TOML Tests

final class ConfigServiceMalformedTomlTests: XCTestCase {

    func testMalformedTomlUsesDefaults() throws {
        let toml = """
        this is not valid toml at all
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)

        // Should not crash, should use defaults
        try service.reload()
        XCTAssertEqual(service.current, CocxyConfig.defaults)
    }
}

// MARK: - Combine Publisher Tests

final class ConfigServicePublisherTests: XCTestCase {

    func testReloadPublishesNewConfigViaCombine() throws {
        let initialToml = """
        [appearance]
        theme = "dracula"
        """

        let fileProvider = InMemoryConfigFileProvider(content: initialToml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let expectation = expectation(description: "Config change published")
        var receivedConfig: CocxyConfig?
        var cancellables = Set<AnyCancellable>()

        service.configChangedPublisher
            .dropFirst() // Skip the current value
            .sink { config in
                receivedConfig = config
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Change the file content and reload
        let updatedToml = """
        [appearance]
        theme = "nord"
        """
        fileProvider.content = updatedToml
        try service.reload()

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedConfig?.appearance.theme, "nord")
    }

    func testConfigChangedPublisherEmitsCurrentValueOnSubscription() throws {
        let toml = """
        [appearance]
        theme = "monokai"
        """

        let fileProvider = InMemoryConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let expectation = expectation(description: "Initial value emitted")
        var cancellables = Set<AnyCancellable>()

        service.configChangedPublisher
            .first()
            .sink { config in
                XCTAssertEqual(config.appearance.theme, "monokai")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Config-to-TOML Generation Tests

final class ConfigServiceTomlGenerationTests: XCTestCase {

    func testDefaultConfigGeneratesValidToml() throws {
        let defaultToml = ConfigService.generateDefaultToml()

        // Verify it can be parsed back
        let parser = TOMLParser()
        let parsed = try parser.parse(defaultToml)

        // Should have all 7 sections
        XCTAssertNotNil(parsed["general"])
        XCTAssertNotNil(parsed["appearance"])
        XCTAssertNotNil(parsed["agent-detection"])
        XCTAssertNotNil(parsed["notifications"])
        XCTAssertNotNil(parsed["quick-terminal"])
        XCTAssertNotNil(parsed["keybindings"])
        XCTAssertNotNil(parsed["sessions"])
    }

    func testGeneratedTomlRoundTripsToDefaults() throws {
        let defaultToml = ConfigService.generateDefaultToml()

        let fileProvider = InMemoryConfigFileProvider(content: defaultToml)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(
            service.current,
            CocxyConfig.defaults,
            "Generated default TOML must round-trip to CocxyConfig.defaults"
        )
    }
}

// MARK: - InMemoryConfigFileProvider

/// A test double for `ConfigFileProviding` that holds config content in memory.
///
/// Avoids filesystem access in unit tests, making them fast and deterministic.
final class InMemoryConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
    var content: String?
    private(set) var writtenContent: String?

    init(content: String?) {
        self.content = content
    }

    func readConfigFile() -> String? {
        content
    }

    func writeConfigFile(_ content: String) throws {
        writtenContent = content
    }
}
