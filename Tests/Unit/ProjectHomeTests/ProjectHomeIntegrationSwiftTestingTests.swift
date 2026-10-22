// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomeIntegrationSwiftTestingTests.swift - Project home app and panel integration coverage.

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("Project home integration")
@MainActor
struct ProjectHomeIntegrationSwiftTestingTests {
    @Test("project tasks CLI serializes the exact visible inbox snapshot")
    func projectTasksCLIMatchesVisibleSnapshot() async throws {
        let delegate = AppDelegate()
        let projectRoot = URL(
            fileURLWithPath: "/tmp/project-home-cli-(UUID().uuidString)",
            isDirectory: true
        )
        let request = try TaskRunRequest.make(
            prompt: "Compare project changes",
            agents: "codex,gemini"
        )
        var run = TaskRun(
            id: "cli-visible-run",
            request: request,
            originRepoPath: projectRoot,
            baseCommit: "abc123",
            now: Date(timeIntervalSince1970: 100)
        )
        run.markRunning(now: Date(timeIntervalSince1970: 101))

        delegate.taskInboxStore.updateTaskRuns([run])
        delegate.taskInboxStore.updateQueueItems([])
        delegate.taskInboxStore.updateSessions([])
        delegate.taskInboxStore.updateDashboardSessions([])
        let visibleEntries = delegate.taskInboxStore.snapshot.entries

        let result = try await delegate.projectTasksForCLI(projectReference: nil)
        #expect(result.0)
        #expect(result.1["count"] == String(visibleEntries.count))
        #expect(result.1["warning"] == nil)
        let json = try #require(result.1["tasks"])
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cliEntries = try decoder.decode([TaskInboxEntry].self, from: data)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let visibleContract = try decoder.decode(
            [TaskInboxEntry].self,
            from: encoder.encode(visibleEntries)
        )
        #expect(cliEntries == visibleContract)
        #expect(visibleEntries.first?.navigation?.sessionID == run.id)
    }

    @Test("project tasks CLI publishes safe localized availability copy")
    func projectTasksCLIPublishesLocalizedAvailabilityWarning() async throws {
        let delegate = AppDelegate()
        delegate.taskInboxStore.markFailed(.queue, message: "/Users/private/queue")

        let result = try await delegate.projectTasksForCLI(projectReference: nil)

        #expect(result.0)
        #expect(
            result.1["warning"]
                == "Some project activity is temporarily unavailable."
        )
        #expect(result.1["warning"]?.contains("/Users/private") == false)

        let bundle = try #require(Bundle(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Localization", isDirectory: true)))
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        #expect(
            AppDelegate.projectTasksAvailabilityWarning(.partial([]), localizer: spanish)
                == "Parte de la actividad del proyecto no está disponible temporalmente."
        )
        #expect(AppDelegate.projectTasksAvailabilityWarning(.ready, localizer: spanish) == nil)
    }

    @Test("restored factory is non-nil and duplicate opens reuse one panel")
    func restoredFactoryAndDuplicateOpenContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-project-home-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolver = CachedProjectResolver()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            projectResolver: resolver
        )
        controller.injectedTaskInboxStore = TaskInboxStore(projectResolver: resolver)
        controller.injectedProjectFanOutCoordinator = ProjectFanOutCoordinator()

        let restored = controller.makeProjectHomePanelView(
            panel: .projectHome(projectRoot: root),
            tabID: controller.tabManager.activeTabID
        )
        #expect(restored is NSHostingView<ProjectHomePanelView>)
        #expect(controller.openProjectHome(projectRoot: root))
        #expect(controller.openProjectHome(projectRoot: root))

        let tabID = try #require(controller.tabManager.activeTabID)
        let splitManager = controller.tabSplitCoordinator.splitManager(for: tabID)
        let homes = splitManager.panelTypes.values.filter { $0.type == .projectHome }
        #expect(homes.count == 1)
        #expect(homes.first?.filePath?.standardizedFileURL == root.standardizedFileURL)
    }

    @Test("cross-tab open targets the requested project tab synchronously")
    func crossTabOpenUsesRequestedTab() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-project-home-tabs-\(UUID().uuidString)", isDirectory: true)
        let firstRoot = base.appendingPathComponent("first", isDirectory: true)
        let secondRoot = base.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let resolver = CachedProjectResolver()
        let controller = MainWindowController(bridge: MockTerminalEngine(), projectResolver: resolver)
        controller.injectedTaskInboxStore = TaskInboxStore(projectResolver: resolver)
        controller.injectedProjectFanOutCoordinator = ProjectFanOutCoordinator()
        let firstTabID = try #require(controller.tabManager.activeTabID)
        controller.tabManager.updateTab(id: firstTabID) { $0.workingDirectory = firstRoot }
        let secondTabID = controller.createTab(workingDirectory: secondRoot)

        #expect(controller.visibleTabID == secondTabID)
        #expect(controller.openProjectHome(projectRoot: firstRoot, in: firstTabID))
        #expect(controller.visibleTabID == firstTabID)
        let firstPanels = controller.tabSplitCoordinator.splitManager(for: firstTabID).panelTypes.values
        let secondPanels = controller.tabSplitCoordinator.splitManager(for: secondTabID).panelTypes.values
        #expect(firstPanels.filter { $0.type == .projectHome }.count == 1)
        #expect(secondPanels.allSatisfy { $0.type != .projectHome })
    }

    @Test("restored factory degrades to a real unavailable view")
    func restoredFactoryUnavailableState() {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let view = controller.makeProjectHomePanelView(
            panel: .projectHome(projectRoot: URL(fileURLWithPath: "/missing/project")),
            tabID: nil
        )
        #expect(view is NSHostingView<ProjectHomeUnavailablePanelView>)
    }
}
