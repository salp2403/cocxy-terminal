// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubConfigRoundTripSwiftTestingTests.swift - End-to-end pipeline tests
// for the [github] config section.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitHubConfig pipeline")
struct GitHubConfigRoundTripSwiftTestingTests {

    // MARK: - Helpers

    /// In-memory `ConfigFileProviding` stub used by the pipeline tests
    /// so we never touch the real `~/.config/cocxy/config.toml`.
    private final class MemoryFileProvider: ConfigFileProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var content: String?

        init(initialContent: String? = nil) {
            self.content = initialContent
        }

        func readConfigFile() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return content
        }

        func writeConfigFile(_ content: String) throws {
            lock.lock()
            self.content = content
            lock.unlock()
        }

        var snapshot: String? {
            lock.lock()
            defer { lock.unlock() }
            return content
        }
    }

    // MARK: - Defaults and decoding

    @Test("GitHubConfig.defaults matches the published contract")
    func githubConfig_defaultsMatchContract() {
        let defaults = GitHubConfig.defaults
        #expect(defaults.enabled == true)
        #expect(defaults.autoRefreshInterval == 60)
        #expect(defaults.maxItems == 30)
        #expect(defaults.includeDrafts == true)
        #expect(defaults.defaultState == "open")
        #expect(defaults.mergeEnabled == true)
    }

    @Test("GitHubConfig falls back on missing keys")
    func githubConfig_fallsBackOnMissingKeys() throws {
        // JSON with some keys missing should still decode cleanly.
        let json = #"{"enabled": false}"#
        let decoded = try JSONDecoder().decode(GitHubConfig.self, from: Data(json.utf8))
        #expect(decoded.enabled == false)
        #expect(decoded.autoRefreshInterval == 60) // default
        #expect(decoded.maxItems == 30) // default
        #expect(decoded.defaultState == "open") // default
        #expect(decoded.mergeEnabled == true) // default — feature on by default
    }

    @Test("GitHubConfig decodes explicit mergeEnabled = false from JSON")
    func githubConfig_decodesExplicitMergeEnabledFalse() throws {
        let json = #"{"mergeEnabled": false}"#
        let decoded = try JSONDecoder().decode(GitHubConfig.self, from: Data(json.utf8))
        #expect(decoded.mergeEnabled == false)
    }

    // MARK: - generateDefaultToml

    @Test("generateDefaultToml emits the [github] block with every key")
    func generateDefaultToml_emitsGithubSection() {
        let toml = ConfigService.generateDefaultToml()
        #expect(toml.contains("[github]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("auto-refresh-interval = 60"))
        #expect(toml.contains("max-items = 30"))
        #expect(toml.contains("include-drafts = true"))
        #expect(toml.contains("default-state = \"open\""))
        #expect(toml.contains("merge-enabled = true"))
    }

    // MARK: - ConfigService parsing

    @Test("ConfigService parses valid [github] values")
    func configService_parsesValidGithubValues() throws {
        let toml = """
        [github]
        enabled = false
        auto-refresh-interval = 120
        max-items = 50
        include-drafts = false
        default-state = "closed"
        merge-enabled = false
        """
        let provider = MemoryFileProvider(initialContent: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let gh = service.current.github
        #expect(gh.enabled == false)
        #expect(gh.autoRefreshInterval == 120)
        #expect(gh.maxItems == 50)
        #expect(gh.includeDrafts == false)
        #expect(gh.defaultState == "closed")
        #expect(gh.mergeEnabled == false)
    }

    @Test("ConfigService keeps mergeEnabled default when key is absent")
    func configService_mergeEnabledDefaultsToTrueWhenAbsent() throws {
        let toml = """
        [github]
        enabled = true
        """
        let provider = MemoryFileProvider(initialContent: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        #expect(service.current.github.mergeEnabled == true)
    }

    @Test("ConfigService clamps out-of-range values")
    func configService_clampsOutOfRangeValues() throws {
        let toml = """
        [github]
        auto-refresh-interval = 99999
        max-items = 9999
        default-state = "invented"
        """
        let provider = MemoryFileProvider(initialContent: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let gh = service.current.github
        #expect(gh.autoRefreshInterval == GitHubConfig.maxAutoRefreshInterval)
        #expect(gh.maxItems == GitHubConfig.maxMaxItems)
        #expect(gh.defaultState == "open")  // unknown value falls back
    }

    @Test("ConfigService preserves defaults when [github] section is missing")
    func configService_preservesDefaultsWhenSectionMissing() throws {
        // TOML with a single unrelated field so parseAndValidate has
        // something to parse but no [github] at all.
        let toml = """
        [general]
        shell = "/bin/zsh"
        """
        let provider = MemoryFileProvider(initialContent: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let gh = service.current.github
        #expect(gh == GitHubConfig.defaults)
    }

    // MARK: - ProjectConfig overrides

    @Test("ProjectConfig parses [github] overrides when present")
    func projectConfig_parsesGithubOverrides() {
        let toml = """
        [github]
        enabled = false
        include-drafts = false
        default-state = "closed"
        merge-enabled = false
        """
        let config = ProjectConfigService().parse(toml)
        try? #require(config != nil)
        guard let config else { return }
        #expect(config.githubEnabled == false)
        #expect(config.githubIncludeDrafts == false)
        #expect(config.githubDefaultState == "closed")
        #expect(config.githubMergeEnabled == false)
    }

    @Test("ProjectConfig surfaces merge-enabled override on its own")
    func projectConfig_surfacesMergeEnabledOverrideAlone() {
        let toml = """
        [github]
        merge-enabled = false
        """
        let config = ProjectConfigService().parse(toml)
        #expect(config?.githubMergeEnabled == false)
        #expect(config?.githubEnabled == nil)
        #expect(config?.githubIncludeDrafts == nil)
    }

    @Test("ProjectConfig rejects invalid default-state values silently")
    func projectConfig_rejectsInvalidDefaultState() {
        let toml = """
        [github]
        default-state = "invented"
        """
        let config = ProjectConfigService().parse(toml)
        // With only an invalid field, isEmpty returns true so parse
        // returns nil rather than a ProjectConfig with a bogus value.
        #expect(config == nil)
    }

    // MARK: - CocxyConfig.applying merge

    @Test("CocxyConfig.applying merges GitHub overrides correctly")
    func cocxyConfig_applyingMergesGithubOverrides() {
        let global = CocxyConfig.defaults
        let overrides = ProjectConfig(
            githubEnabled: false,
            githubIncludeDrafts: false,
            githubDefaultState: "all",
            githubMergeEnabled: false
        )
        let merged = global.applying(projectOverrides: overrides)

        #expect(merged.github.enabled == false)
        #expect(merged.github.includeDrafts == false)
        #expect(merged.github.defaultState == "all")
        #expect(merged.github.mergeEnabled == false)
        // Global-only fields stay global.
        #expect(merged.github.autoRefreshInterval == global.github.autoRefreshInterval)
        #expect(merged.github.maxItems == global.github.maxItems)
    }

    @Test("CocxyConfig.applying preserves global mergeEnabled when override is nil")
    func cocxyConfig_applyingPreservesMergeEnabledWhenOverrideIsNil() {
        let global = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            github: GitHubConfig(mergeEnabled: false)
        )
        let overrides = ProjectConfig(githubEnabled: true)
        let merged = global.applying(projectOverrides: overrides)
        // Global mergeEnabled wins because the project did not override it.
        #expect(merged.github.mergeEnabled == false)
        // Project enabled override took effect.
        #expect(merged.github.enabled == true)
    }

    @Test("CocxyConfig.applying leaves GitHub untouched when no overrides")
    func cocxyConfig_applyingLeavesGithubUntouchedWithoutOverrides() {
        let global = CocxyConfig.defaults
        let overrides = ProjectConfig(fontSize: 16) // unrelated field
        let merged = global.applying(projectOverrides: overrides)

        #expect(merged.github == global.github)
    }

    @Test("Pane and CLI effective config use project GitHub overrides")
    func effectiveGithubConfig_appliesProjectOverrides() {
        let global = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            github: GitHubConfig(
                enabled: true,
                autoRefreshInterval: 120,
                maxItems: 80,
                includeDrafts: true,
                defaultState: "open"
            )
        )
        let project = ProjectConfig(
            githubEnabled: false,
            githubIncludeDrafts: false,
            githubDefaultState: "merged"
        )
        let tab = Tab(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
            projectConfig: project
        )

        let paneConfig = MainWindowController.effectiveGitHubConfig(
            for: tab,
            globalConfig: global
        )
        let cliConfig = AppDelegate.effectiveGitHubCLIConfig(
            globalConfig: global,
            projectConfig: project
        ).github

        for effective in [paneConfig, cliConfig] {
            #expect(effective.enabled == false)
            #expect(effective.includeDrafts == false)
            #expect(effective.defaultState == "merged")
            #expect(effective.autoRefreshInterval == global.github.autoRefreshInterval)
            #expect(effective.maxItems == global.github.maxItems)
        }
    }

    @Test("CLI GitHub list options prefer flags over config defaults")
    func githubListOptions_prefersParamsOverConfigDefaults() {
        let config = GitHubConfig(
            enabled: true,
            autoRefreshInterval: 60,
            maxItems: 80,
            includeDrafts: false,
            defaultState: "merged"
        )

        let defaults = AppDelegate.githubListOptions(
            params: [:],
            config: config,
            allowedStates: ["open", "closed", "merged", "all"]
        )
        #expect(defaults.state == "merged")
        #expect(defaults.limit == 80)

        let explicit = AppDelegate.githubListOptions(
            params: ["state": "closed", "limit": "12"],
            config: config,
            allowedStates: ["open", "closed", "merged", "all"]
        )
        #expect(explicit.state == "closed")
        #expect(explicit.limit == 12)

        let issueDefaults = AppDelegate.githubListOptions(
            params: [:],
            config: config,
            allowedStates: ["open", "closed", "all"]
        )
        #expect(issueDefaults.state == "open")
        #expect(issueDefaults.limit == 80)
    }

    // MARK: - Preferences roundtrip

    @Test("PreferencesViewModel persists GitHub fields via save -> reload")
    @MainActor
    func preferencesViewModel_persistsGithubFields() throws {
        let provider = MemoryFileProvider()

        // Seed with defaults so the view model has a full config to read.
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let viewModel = PreferencesViewModel(
            config: service.current,
            fileProvider: provider
        )
        viewModel.githubEnabled = false
        viewModel.githubAutoRefreshInterval = 180
        viewModel.githubMaxItems = 75
        viewModel.githubIncludeDrafts = false
        viewModel.githubDefaultState = "merged"
        viewModel.githubMergeEnabled = false

        try viewModel.save()

        // Reload from disk through a fresh ConfigService pointing at the
        // same in-memory provider to prove the written TOML is valid.
        let reloaded = ConfigService(fileProvider: provider)
        try reloaded.reload()
        let gh = reloaded.current.github

        #expect(gh.enabled == false)
        #expect(gh.autoRefreshInterval == 180)
        #expect(gh.maxItems == 75)
        #expect(gh.includeDrafts == false)
        #expect(gh.defaultState == "merged")
        #expect(gh.mergeEnabled == false)
    }

    @Test("PreferencesViewModel hasUnsavedChanges flips when mergeEnabled changes")
    @MainActor
    func preferencesViewModel_hasUnsavedChangesTracksMergeEnabled() throws {
        let provider = MemoryFileProvider()
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let viewModel = PreferencesViewModel(
            config: service.current,
            fileProvider: provider
        )
        #expect(viewModel.hasUnsavedChanges == false)

        viewModel.githubMergeEnabled = false
        #expect(viewModel.hasUnsavedChanges == true)

        viewModel.discardChanges()
        #expect(viewModel.hasUnsavedChanges == false)
        #expect(viewModel.githubMergeEnabled == true)
    }

    @Test("PreferencesViewModel clamps out-of-range values on save")
    @MainActor
    func preferencesViewModel_clampsValuesOnSave() throws {
        let provider = MemoryFileProvider()
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let viewModel = PreferencesViewModel(
            config: service.current,
            fileProvider: provider
        )
        viewModel.githubAutoRefreshInterval = 99999
        viewModel.githubMaxItems = 9999
        viewModel.githubDefaultState = "invented"

        try viewModel.save()

        let reloaded = ConfigService(fileProvider: provider)
        try reloaded.reload()
        let gh = reloaded.current.github

        #expect(gh.autoRefreshInterval == GitHubConfig.maxAutoRefreshInterval)
        #expect(gh.maxItems == GitHubConfig.maxMaxItems)
        #expect(gh.defaultState == "open")
    }

    @Test("PreferencesViewModel hasUnsavedChanges tracks GitHub edits")
    @MainActor
    func preferencesViewModel_hasUnsavedChangesTracksGithubEdits() throws {
        let provider = MemoryFileProvider()
        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let viewModel = PreferencesViewModel(
            config: service.current,
            fileProvider: provider
        )
        #expect(viewModel.hasUnsavedChanges == false)

        viewModel.githubEnabled = false
        #expect(viewModel.hasUnsavedChanges == true)

        viewModel.discardChanges()
        #expect(viewModel.hasUnsavedChanges == false)
    }
}
