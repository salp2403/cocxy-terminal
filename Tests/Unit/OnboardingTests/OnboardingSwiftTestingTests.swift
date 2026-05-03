// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Guided onboarding")
struct OnboardingSwiftTestingTests {

    @Test("completion persists selected settings and creates starter artifacts")
    func completionPersistsSettingsAndStarterArtifacts() throws {
        let root = try temporaryDirectory()
        let provider = InMemoryConfigFileProvider(content: ConfigService.generateDefaultToml())
        let tabStore = TabConfigStore(rootDirectory: root.appendingPathComponent("tabs"))
        let applier = GuidedOnboardingApplier(
            configFileProvider: provider,
            tabConfigStore: tabStore,
            skillDirectory: root.appendingPathComponent("skills", isDirectory: true),
            workflowDirectory: root.appendingPathComponent("workflows", isDirectory: true)
        )

        let result = try applier.complete(
            OnboardingSelection(
                theme: "catppuccin-latte",
                agentAutoMode: true,
                lspEnabled: true,
                createTabConfig: true,
                createPrimerSkill: true,
                createFirstWorkflow: true
            ),
            workingDirectory: "/tmp"
        )
        #expect(provider.writtenContent != nil)
        provider.content = provider.writtenContent

        let service = ConfigService(fileProvider: provider)
        try service.reload()

        #expect(service.current.appearance.theme == "catppuccin-latte")
        #expect(service.current.agent.autoMode == true)
        #expect(service.current.lsp.enabled == true)
        #expect(result.createdTabConfigName == "starter")
        #expect(result.createdSkillID == "cocxy-primer")
        #expect(result.createdWorkflowID == "first-check")

        let tabConfig = try tabStore.load(named: "starter")
        #expect(tabConfig.workingDirectory == "/tmp")

        let skills = try SkillRegistry(directories: [
            SkillDirectory(url: root.appendingPathComponent("skills", isDirectory: true), source: .user)
        ]).loadSkills()
        #expect(skills.map(\.id).contains("cocxy-primer"))

        let loadedWorkflow = try WorkflowRegistry(
            directory: root.appendingPathComponent("workflows", isDirectory: true)
        ).load(id: "first-check")
        let workflow = try #require(loadedWorkflow)
        #expect(workflow.steps.count == 1)
        #expect(workflow.steps[0].workingDirectory == "/tmp")
    }

    @Test("skip and completion both suppress automatic first-launch presentation")
    func stateStoreTracksSkipAndCompletion() {
        let suiteName = "dev.cocxy.tests.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = OnboardingStateStore(userDefaults: defaults, stateKey: "onboarding-state")

        #expect(store.shouldPresentAutomatically)
        store.markSkipped()
        #expect(!store.shouldPresentAutomatically)

        store.reset()
        #expect(store.shouldPresentAutomatically)
        store.markCompleted()
        #expect(!store.shouldPresentAutomatically)
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-onboarding-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return root
    }
}
