// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectConfigTests.swift - Tests for ProjectConfig and merge logic.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ProjectConfig")
struct ProjectConfigTests {

    @Test("Empty project config changes nothing when merged")
    func emptyOverrideIsIdentity() {
        let global = CocxyConfig.defaults
        let empty = ProjectConfig()
        let result = global.applying(projectOverrides: empty)
        #expect(result == global)
    }

    @Test("Font size override replaces global value")
    func fontSizeOverride() {
        let global = CocxyConfig.defaults
        let project = ProjectConfig(fontSize: 18.0)
        let result = global.applying(projectOverrides: project)
        #expect(result.appearance.fontSize == 18.0)
        #expect(result.appearance.theme == global.appearance.theme)
        #expect(result.appearance.fontFamily == global.appearance.fontFamily)
    }

    @Test("Multiple appearance overrides apply together")
    func multipleOverrides() {
        let global = CocxyConfig.defaults
        let project = ProjectConfig(
            fontSize: 12.0,
            windowPadding: 16.0,
            backgroundOpacity: 0.7
        )
        let result = global.applying(projectOverrides: project)
        #expect(result.appearance.fontSize == 12.0)
        #expect(result.appearance.backgroundOpacity == 0.7)
        #expect(result.appearance.windowPadding == 16.0)
    }

    @Test("Padding X/Y overrides apply independently")
    func paddingXYOverrides() {
        let global = CocxyConfig.defaults
        let project = ProjectConfig(windowPaddingX: 20.0, windowPaddingY: 10.0)
        let result = global.applying(projectOverrides: project)
        #expect(result.appearance.windowPaddingX == 20.0)
        #expect(result.appearance.windowPaddingY == 10.0)
        #expect(result.appearance.windowPadding == global.appearance.windowPadding)
    }

    @Test("Blur radius override applies")
    func blurRadiusOverride() {
        let global = CocxyConfig.defaults
        let project = ProjectConfig(backgroundBlurRadius: 50.0)
        let result = global.applying(projectOverrides: project)
        #expect(result.appearance.backgroundBlurRadius == 50.0)
    }

    @Test("Keybinding override replaces only specified keys")
    func keybindingPartialOverride() {
        let global = CocxyConfig.defaults
        let project = ProjectConfig(
            keybindingOverrides: ["new-tab": "cmd+shift+t"]
        )
        let result = global.applying(projectOverrides: project)
        #expect(result.keybindings.newTab == "cmd+shift+t")
        #expect(result.keybindings.closeTab == global.keybindings.closeTab)
        #expect(result.keybindings.nextTab == global.keybindings.nextTab)
    }

    @Test("Multiple keybinding overrides apply together")
    func keybindingMultipleOverrides() {
        let global = CocxyConfig.defaults
        let project = ProjectConfig(
            keybindingOverrides: [
                "new-tab": "cmd+n",
                "close-tab": "cmd+shift+w",
                "split-vertical": "cmd+\\"
            ]
        )
        let result = global.applying(projectOverrides: project)
        #expect(result.keybindings.newTab == "cmd+n")
        #expect(result.keybindings.closeTab == "cmd+shift+w")
        #expect(result.keybindings.splitVertical == "cmd+\\")
        #expect(result.keybindings.splitHorizontal == global.keybindings.splitHorizontal)
    }

    @Test("Non-appearance fields remain unchanged")
    func nonAppearanceFieldsUnchanged() {
        let global = CocxyConfig.defaults
        let project = ProjectConfig(fontSize: 20.0)
        let result = global.applying(projectOverrides: project)
        #expect(result.general == global.general)
        #expect(result.terminal == global.terminal)
        #expect(result.agentDetection == global.agentDetection)
        #expect(result.notifications == global.notifications)
        #expect(result.quickTerminal == global.quickTerminal)
        #expect(result.sessions == global.sessions)
    }

    @Test("Agent detection extra patterns are stored on ProjectConfig")
    func agentDetectionPatterns() {
        let project = ProjectConfig(
            agentDetectionExtraPatterns: ["^python manage.py", "^rails server"]
        )
        #expect(project.agentDetectionExtraPatterns?.count == 2)
        #expect(project.agentDetectionExtraPatterns?[0] == "^python manage.py")
    }
}

// MARK: - ProjectConfigService Parsing Tests

@Suite("ProjectConfigService Parsing")
struct ProjectConfigServiceParsingTests {

    @Test("Parses valid TOML with font-size override")
    func parsesValidToml() {
        let toml = """
        font-size = 18
        background-opacity = 0.9
        """
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config != nil)
        #expect(config?.fontSize == 18.0)
        #expect(config?.backgroundOpacity == 0.9)
    }

    @Test("Returns nil for empty string")
    func emptyStringReturnsNil() {
        let service = ProjectConfigService()
        let config = service.parse("")
        #expect(config == nil)
    }

    @Test("Returns nil for whitespace-only string")
    func whitespaceOnlyReturnsNil() {
        let service = ProjectConfigService()
        let config = service.parse("   \n  \n  ")
        #expect(config == nil)
    }

    @Test("Parses agent-detection extra patterns")
    func parsesAgentPatterns() {
        let toml = """
        [agent-detection]
        extra-launch-patterns = ["^python manage.py", "^rails server"]
        """
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config != nil)
        #expect(config?.agentDetectionExtraPatterns?.count == 2)
        #expect(config?.agentDetectionExtraPatterns?[0] == "^python manage.py")
    }

    @Test("Parses keybinding overrides")
    func parsesKeybindings() {
        let toml = """
        [keybindings]
        new-tab = "cmd+shift+t"
        close-tab = "cmd+shift+w"
        """
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config != nil)
        #expect(config?.keybindingOverrides?["new-tab"] == "cmd+shift+t")
        #expect(config?.keybindingOverrides?["close-tab"] == "cmd+shift+w")
    }

    @Test("Invalid TOML returns nil")
    func invalidTomlReturnsNil() {
        let service = ProjectConfigService()
        let config = service.parse("[invalid\nbroken = ")
        #expect(config == nil)
    }

    @Test("Validates font-size range — clamps to max")
    func validatesMaxFontSize() {
        let toml = "font-size = 200"
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config?.fontSize == 72.0)
    }

    @Test("Validates font-size range — clamps to min")
    func validatesMinFontSize() {
        let toml = "font-size = 2"
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config?.fontSize == 6.0)
    }

    @Test("Validates background-opacity range")
    func validatesOpacityRange() {
        let toml = "background-opacity = 0.05"
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config?.backgroundOpacity == 0.1)
    }

    @Test("Validates window-padding non-negative")
    func validatesPaddingNonNegative() {
        let toml = "window-padding = -5"
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config?.windowPadding == 0.0)
    }

    @Test("Parses all supported fields together")
    func parsesAllFields() {
        let toml = """
        font-size = 16
        window-padding = 12
        window-padding-x = 20
        window-padding-y = 10
        background-opacity = 0.85
        background-blur-radius = 30

        [agent-detection]
        extra-launch-patterns = ["^custom-agent"]

        [keybindings]
        new-tab = "cmd+n"
        """
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config != nil)
        #expect(config?.fontSize == 16.0)
        #expect(config?.windowPadding == 12.0)
        #expect(config?.windowPaddingX == 20.0)
        #expect(config?.windowPaddingY == 10.0)
        #expect(config?.backgroundOpacity == 0.85)
        #expect(config?.backgroundBlurRadius == 30.0)
        #expect(config?.agentDetectionExtraPatterns == ["^custom-agent"])
        #expect(config?.keybindingOverrides?["new-tab"] == "cmd+n")
    }

    @Test("Comments in TOML are ignored")
    func commentsIgnored() {
        let toml = """
        # This is a comment
        font-size = 15
        """
        let service = ProjectConfigService()
        let config = service.parse(toml)
        #expect(config?.fontSize == 15.0)
    }
}

// MARK: - Directory Traversal Tests

@Suite("ProjectConfigService Directory Traversal")
struct ProjectConfigDirectoryTests {

    @Test("Finds .cocxy.toml in same directory")
    func findsInSameDir() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configFile = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 20".write(to: configFile, atomically: true, encoding: .utf8)

        let service = ProjectConfigService()
        let config = service.loadConfig(for: tmpDir)
        #expect(config?.fontSize == 20.0)
    }

    @Test("Finds .cocxy.toml in parent directory")
    func findsInParent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let childDir = tmpDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configFile = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 16".write(to: configFile, atomically: true, encoding: .utf8)

        let service = ProjectConfigService()
        let config = service.loadConfig(for: childDir)
        #expect(config?.fontSize == 16.0)
    }

    @Test("Finds .cocxy.toml two levels up")
    func findsInGrandparent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let deepDir = tmpDir.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configFile = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 13".write(to: configFile, atomically: true, encoding: .utf8)

        let service = ProjectConfigService()
        let config = service.loadConfig(for: deepDir)
        #expect(config?.fontSize == 13.0)
    }

    @Test("Returns nil when no .cocxy.toml exists")
    func returnsNilWhenMissing() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let service = ProjectConfigService()
        let config = service.loadConfig(for: tmpDir)
        #expect(config == nil)
    }

    @Test("Stops traversal at home directory")
    func stopsAtHome() {
        let service = ProjectConfigService()
        let homeChild = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let config = service.loadConfig(for: homeChild)
        #expect(config == nil)
    }

    @Test("Nearest .cocxy.toml wins over parent")
    func nearestWins() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let childDir = tmpDir.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try "font-size = 10".write(
            to: tmpDir.appendingPathComponent(".cocxy.toml"),
            atomically: true, encoding: .utf8
        )
        try "font-size = 22".write(
            to: childDir.appendingPathComponent(".cocxy.toml"),
            atomically: true, encoding: .utf8
        )

        let service = ProjectConfigService()
        let config = service.loadConfig(for: childDir)
        #expect(config?.fontSize == 22.0)
    }
}

// MARK: - ProjectConfigWatcher Tests

@Suite("ProjectConfigWatcher")
struct ProjectConfigWatcherTests {

    @Test("Watcher reports correct watched path")
    func watchedPath() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configPath = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 14".write(to: configPath, atomically: true, encoding: .utf8)

        let watcher = ProjectConfigWatcher(configFilePath: configPath.path)
        #expect(watcher.watchedPath == configPath.path)
        #expect(watcher.isWatching == false)
    }

    @Test("Start watching sets isWatching to true")
    func startSetsWatching() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configPath = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 14".write(to: configPath, atomically: true, encoding: .utf8)

        let watcher = ProjectConfigWatcher(configFilePath: configPath.path)
        watcher.startWatching { }
        #expect(watcher.isWatching == true)
        watcher.stopWatching()
        #expect(watcher.isWatching == false)
    }

    @Test("Start watching on non-existent file does not mark as watching")
    func nonExistentFileNotWatching() {
        let watcher = ProjectConfigWatcher(configFilePath: "/tmp/nonexistent-\(UUID().uuidString)")
        watcher.startWatching { }
        #expect(watcher.isWatching == false)
    }

    @Test("Double start is idempotent")
    func doubleStartIdempotent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configPath = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 14".write(to: configPath, atomically: true, encoding: .utf8)

        let watcher = ProjectConfigWatcher(configFilePath: configPath.path)
        watcher.startWatching { }
        watcher.startWatching { } // should be no-op
        #expect(watcher.isWatching == true)
        watcher.stopWatching()
    }
}

// MARK: - findConfigPath Tests

@Suite("ProjectConfigService findConfigPath")
struct ProjectConfigFindPathTests {

    @Test("findConfigPath returns path when file exists")
    func findsExistingFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configFile = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 14".write(to: configFile, atomically: true, encoding: .utf8)

        let service = ProjectConfigService()
        let path = service.findConfigPath(for: tmpDir)
        #expect(path == configFile.path)
    }

    @Test("findConfigPath returns nil when no file exists")
    func returnsNilWhenMissing() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let service = ProjectConfigService()
        let path = service.findConfigPath(for: tmpDir)
        #expect(path == nil)
    }

    @Test("findConfigPath finds in parent directory")
    func findsInParent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let childDir = tmpDir.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configFile = tmpDir.appendingPathComponent(".cocxy.toml")
        try "font-size = 14".write(to: configFile, atomically: true, encoding: .utf8)

        let service = ProjectConfigService()
        let path = service.findConfigPath(for: childDir)
        #expect(path == configFile.path)
    }
}

// MARK: - End-to-End Integration Tests

@Suite("ProjectConfig End-to-End")
struct ProjectConfigEndToEndTests {

    @Test("Full flow: parse TOML, merge with global, verify all overrides")
    func endToEndFlow() {
        let toml = """
        font-size = 20
        background-opacity = 0.8
        window-padding = 12
        window-padding-x = 15
        window-padding-y = 8
        background-blur-radius = 25

        [agent-detection]
        extra-launch-patterns = ["^python manage.py"]

        [keybindings]
        new-tab = "cmd+shift+n"
        close-tab = "cmd+shift+w"
        """

        let service = ProjectConfigService()
        let projectConfig = service.parse(toml)
        #expect(projectConfig != nil)

        let global = CocxyConfig.defaults
        let effective = global.applying(projectOverrides: projectConfig!)

        // Appearance overrides applied
        #expect(effective.appearance.fontSize == 20.0)
        #expect(effective.appearance.backgroundOpacity == 0.8)
        #expect(effective.appearance.windowPadding == 12.0)
        #expect(effective.appearance.windowPaddingX == 15.0)
        #expect(effective.appearance.windowPaddingY == 8.0)
        #expect(effective.appearance.backgroundBlurRadius == 25.0)

        // Keybinding overrides applied
        #expect(effective.keybindings.newTab == "cmd+shift+n")
        #expect(effective.keybindings.closeTab == "cmd+shift+w")

        // Non-overridden keybindings unchanged
        #expect(effective.keybindings.nextTab == global.keybindings.nextTab)
        #expect(effective.keybindings.splitVertical == global.keybindings.splitVertical)

        // Agent patterns stored on ProjectConfig (not merged into CocxyConfig)
        #expect(projectConfig!.agentDetectionExtraPatterns == ["^python manage.py"])

        // Non-overridden sections completely unchanged
        #expect(effective.general == global.general)
        #expect(effective.terminal == global.terminal)
        #expect(effective.agentDetection == global.agentDetection)
        #expect(effective.notifications == global.notifications)
        #expect(effective.quickTerminal == global.quickTerminal)
        #expect(effective.sessions == global.sessions)
        #expect(effective.appearance.theme == global.appearance.theme)
        #expect(effective.appearance.fontFamily == global.appearance.fontFamily)
    }

    @Test("Tab with project config round-trips through Codable")
    func tabCodableRoundTrip() throws {
        var tab = Tab(title: "Test")
        tab.projectConfig = ProjectConfig(fontSize: 18.0, backgroundOpacity: 0.9)

        let encoder = JSONEncoder()
        let data = try encoder.encode(tab)

        let decoder = JSONDecoder()
        let restored = try decoder.decode(Tab.self, from: data)

        #expect(restored.projectConfig?.fontSize == 18.0)
        #expect(restored.projectConfig?.backgroundOpacity == 0.9)
    }

    @Test("Tab without project config decodes correctly (backward compat)")
    func tabBackwardCompat() throws {
        // Simulate old session data without projectConfig field
        let tab = Tab(title: "Old Tab")
        let encoder = JSONEncoder()
        let data = try encoder.encode(tab)

        // Verify nil projectConfig
        let decoder = JSONDecoder()
        let restored = try decoder.decode(Tab.self, from: data)
        #expect(restored.projectConfig == nil)
        #expect(restored.title == "Old Tab")
    }

    @Test("Directory traversal + parse + merge works together")
    func directoryTraversalIntegration() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projectDir = tmpDir.appendingPathComponent("my-project/src")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create .cocxy.toml in project root (not src/)
        let configFile = tmpDir.appendingPathComponent("my-project/.cocxy.toml")
        try """
        font-size = 16
        background-opacity = 0.85
        """.write(to: configFile, atomically: true, encoding: .utf8)

        // Load from the src/ subdirectory -- should find parent's config
        let service = ProjectConfigService()
        let projectConfig = service.loadConfig(for: projectDir)
        #expect(projectConfig != nil)

        let global = CocxyConfig.defaults
        let effective = global.applying(projectOverrides: projectConfig!)
        #expect(effective.appearance.fontSize == 16.0)
        #expect(effective.appearance.backgroundOpacity == 0.85)
        // Theme unchanged (not overridable in v1)
        #expect(effective.appearance.theme == global.appearance.theme)
    }
}
