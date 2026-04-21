// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreePreferencesSwiftTestingTests.swift - Round-trip coverage for
// the editable worktree fields exposed by PreferencesViewModel
// (v0.1.81, ajuste #2).

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel — worktree round-trip")
@MainActor
struct WorktreePreferencesSwiftTestingTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(_ content: String? = nil) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func makeViewModel(config: CocxyConfig = .defaults) -> (PreferencesViewModel, InMemoryProvider) {
        let provider = InMemoryProvider()
        let vm = PreferencesViewModel(config: config, fileProvider: provider)
        return (vm, provider)
    }

    // MARK: - Initialisation

    @Test("init populates every worktree field from the saved config")
    func initPopulatesFromConfig() {
        let custom = WorktreeConfig(
            enabled: true,
            basePath: "/custom",
            branchTemplate: "feat/{id}",
            baseRef: "develop",
            onClose: .prompt,
            openInNewTab: false,
            idLength: 8,
            inheritProjectConfig: false,
            showBadge: false
        )
        var config = CocxyConfig.defaults
        config = CocxyConfig(
            general: config.general,
            appearance: config.appearance,
            terminal: config.terminal,
            agentDetection: config.agentDetection,
            codeReview: config.codeReview,
            notifications: config.notifications,
            quickTerminal: config.quickTerminal,
            keybindings: config.keybindings,
            sessions: config.sessions,
            worktree: custom
        )
        let (vm, _) = makeViewModel(config: config)

        #expect(vm.worktreeEnabled == true)
        #expect(vm.worktreeBasePath == "/custom")
        #expect(vm.worktreeBranchTemplate == "feat/{id}")
        #expect(vm.worktreeBaseRef == "develop")
        #expect(vm.worktreeOnClose == "prompt")
        #expect(vm.worktreeOpenInNewTab == false)
        #expect(vm.worktreeIDLength == 8)
        #expect(vm.worktreeInheritProjectConfig == false)
        #expect(vm.worktreeShowBadge == false)
    }

    // MARK: - Save → reload preserves every field

    @Test("save then reload preserves every worktree field")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.worktreeEnabled = true
        vm.worktreeBasePath = "/tmp/custom-wt"
        vm.worktreeBranchTemplate = "task/{agent}-{id}"
        vm.worktreeBaseRef = "main"
        vm.worktreeOnClose = WorktreeOnClose.remove.rawValue
        vm.worktreeOpenInNewTab = false
        vm.worktreeIDLength = 10
        vm.worktreeInheritProjectConfig = false
        vm.worktreeShowBadge = false

        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()
        let reloaded = service.current.worktree

        #expect(reloaded.enabled == true)
        #expect(reloaded.basePath == "/tmp/custom-wt")
        #expect(reloaded.branchTemplate == "task/{agent}-{id}")
        #expect(reloaded.baseRef == "main")
        #expect(reloaded.onClose == .remove)
        #expect(reloaded.openInNewTab == false)
        #expect(reloaded.idLength == 10)
        #expect(reloaded.inheritProjectConfig == false)
        #expect(reloaded.showBadge == false)
    }

    // MARK: - Clamping

    @Test("id length clamped on save even when user bypasses the stepper")
    func idLengthClampedOnSave() throws {
        let (vm, provider) = makeViewModel()
        vm.worktreeIDLength = 99 // above maxIDLength
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()
        #expect(service.current.worktree.idLength == WorktreeConfig.maxIDLength)
    }

    // MARK: - Empty strings fall back to defaults

    @Test("empty string fields fall back to their defaults on save")
    func emptyStringsFallBackToDefaults() throws {
        let (vm, provider) = makeViewModel()
        vm.worktreeBasePath = "   "
        vm.worktreeBranchTemplate = ""
        vm.worktreeBaseRef = ""
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()
        let reloaded = service.current.worktree
        #expect(reloaded.basePath == WorktreeConfig.defaults.basePath)
        #expect(reloaded.branchTemplate == WorktreeConfig.defaults.branchTemplate)
        #expect(reloaded.baseRef == WorktreeConfig.defaults.baseRef)
    }

    // MARK: - Unknown on-close falls back without crashing

    @Test("unknown on-close value falls back to the default on save")
    func unknownOnCloseFallsBack() throws {
        let (vm, provider) = makeViewModel()
        vm.worktreeOnClose = "nuke"
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()
        #expect(service.current.worktree.onClose == WorktreeConfig.defaults.onClose)
    }
}
