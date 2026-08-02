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
