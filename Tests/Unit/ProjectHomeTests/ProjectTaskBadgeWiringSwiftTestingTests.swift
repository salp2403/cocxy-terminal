// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTaskBadgeWiringSwiftTestingTests.swift - Project task badge snapshot coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project task badge wiring")
struct ProjectTaskBadgeWiringSwiftTestingTests {
    @Test("badge text hides non-positive counts and caps visual overflow")
    func badgeTextVisibilityAndCap() {
        #expect(Design.AuroraProjectRegistrySection.taskBadgeText(for: -1) == nil)
        #expect(Design.AuroraProjectRegistrySection.taskBadgeText(for: 0) == nil)
        #expect(Design.AuroraProjectRegistrySection.taskBadgeText(for: 1) == "1")
        #expect(Design.AuroraProjectRegistrySection.taskBadgeText(for: 99) == "99")
        #expect(Design.AuroraProjectRegistrySection.taskBadgeText(for: 100) == "99+")
        #expect(Design.AuroraProjectRegistrySection.taskBadgeText(for: 10_000) == "99+")
        #expect(Design.AuroraProjectRegistrySection.taskBadgeMinimumWidth == 18)
        #expect(Design.AuroraProjectRegistrySection.taskBadgeHeight == 16)
    }

    @Test("accessibility announces the real count instead of the visual cap")
    func accessibilityUsesRealCount() throws {
        let localizer = AppLocalizer(
            languagePreference: .english,
            bundle: try #require(localizationBundle())
        )

        #expect(
            Design.AuroraProjectRegistrySection.localizedProjectAccessibilityLabel(
                "Terminal",
                taskCount: 0,
                using: localizer
            ) == "Terminal"
        )
        #expect(
            Design.AuroraProjectRegistrySection.localizedProjectAccessibilityLabel(
                "Terminal",
                taskCount: 1,
                using: localizer
            ) == "Terminal, 1 task"
        )
        #expect(
            Design.AuroraProjectRegistrySection.localizedProjectAccessibilityLabel(
                "Terminal",
                taskCount: 120,
                using: localizer
            ) == "Terminal, 120 tasks"
        )
    }

    @Test("controller replaces the independent project task count snapshot")
    func controllerReplacesTaskCountSnapshot() {
        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let controller = AuroraChromeController(tabManager: tabManager, store: store)

        #expect(controller.projectTaskCounts.isEmpty)

        controller.applyProjectTaskCountsSnapshot(["/tmp/alpha": 3, "/tmp/beta": 0])
        #expect(controller.projectTaskCounts == ["/tmp/alpha": 3, "/tmp/beta": 0])

        controller.applyProjectTaskCountsSnapshot(["/tmp/beta": 7])
        #expect(controller.projectTaskCounts == ["/tmp/beta": 7])
        #expect(controller.projects.isEmpty)
    }

    @Test("sidebar and project section retain the separate count map")
    func sidebarAndSectionRetainSeparateCountMap() {
        let snapshot = ["/tmp/alpha": 4]
        let sidebar = Design.AuroraSidebarView(
            workspaces: [],
            projects: [],
            projectTaskCounts: snapshot,
            projectRegistryAvailable: true,
            activeSessionID: nil,
            onTogglePalette: {},
            onCreateTab: {},
            onActivateSession: { _ in }
        )
        let section = Design.AuroraProjectRegistrySection(
            projects: [],
            projectTaskCounts: snapshot,
            registryAvailable: true,
            recoveryMessage: nil,
            onActivate: nil,
            onSetPinned: nil,
            localizer: AppLocalizer(languagePreference: .english)
        )

        #expect(sidebar.projectTaskCounts == snapshot)
        #expect(section.projectTaskCounts == snapshot)
    }

    private func localizationBundle() -> Bundle? {
        Bundle(url: repositoryRoot().appendingPathComponent("Resources/Localization", isDirectory: true))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
