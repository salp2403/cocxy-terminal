// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Update channel config")
struct ChannelConfigRoundTripSwiftTestingTests {

    @Test("updates channel defaults to stable")
    func updatesChannelDefaultsToStable() throws {
        let service = ConfigService(fileProvider: InMemoryConfigFileProvider(content: ""))

        try service.reload()

        #expect(service.current.updates.channel == .stable)
    }

    @Test("missing updates channel can default from bundle channel")
    func missingUpdatesChannelCanDefaultFromBundleChannel() throws {
        let service = ConfigService(
            fileProvider: InMemoryConfigFileProvider(content: """
            [general]
            shell = "/bin/zsh"
            """),
            fallbackUpdatesChannel: .preview
        )

        try service.reload()

        #expect(service.current.updates.channel == .preview)
    }

    @Test("updates channel parses preview and nightly")
    func updatesChannelParsesPreviewAndNightly() throws {
        let preview = ConfigService(fileProvider: InMemoryConfigFileProvider(content: """
        [updates]
        channel = "preview"
        """))
        try preview.reload()

        let nightly = ConfigService(fileProvider: InMemoryConfigFileProvider(content: """
        [updates]
        channel = "nightly"
        """))
        try nightly.reload()

        #expect(preview.current.updates.channel == .preview)
        #expect(nightly.current.updates.channel == .nightly)
    }

    @Test("invalid updates channel falls back to stable")
    func invalidUpdatesChannelFallsBackToStable() throws {
        let service = ConfigService(fileProvider: InMemoryConfigFileProvider(content: """
        [updates]
        channel = "beta"
        """))

        try service.reload()

        #expect(service.current.updates.channel == .stable)
    }

    @Test("default TOML can be generated for a non-stable app channel")
    func defaultTomlCanBeGeneratedForNonStableAppChannel() throws {
        let toml = ConfigService.generateDefaultToml(updateChannel: .preview)
        let service = ConfigService(
            fileProvider: InMemoryConfigFileProvider(content: toml),
            fallbackUpdatesChannel: .preview
        )

        try service.reload()

        #expect(toml.contains("channel = \"preview\""))
        #expect(service.current.updates.channel == .preview)
    }

    @Test("project config merge preserves update channel")
    func projectConfigMergePreservesUpdateChannel() {
        let config = CocxyConfig.defaults(updateChannel: .nightly)
        let merged = config.applying(projectOverrides: ProjectConfig())

        #expect(merged.updates.channel == .nightly)
    }

    @Test("default TOML includes updates section and round trips")
    func defaultTomlIncludesUpdatesSectionAndRoundTrips() throws {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[updates]"))
        #expect(toml.contains("channel = \"stable\""))

        let service = ConfigService(fileProvider: InMemoryConfigFileProvider(content: toml))
        try service.reload()

        #expect(service.current.updates == .defaults)
    }

    @Test("preferences view model writes update channel")
    @MainActor
    func preferencesViewModelWritesUpdateChannel() {
        let viewModel = PreferencesViewModel(config: .defaults)

        viewModel.updateChannel = .nightly
        let toml = viewModel.generateToml()

        #expect(toml.contains("[updates]"))
        #expect(toml.contains("channel = \"nightly\""))
    }
}
