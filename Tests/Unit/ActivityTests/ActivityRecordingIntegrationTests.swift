// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityRecordingIntegrationTests.swift - Opt-in window event recording coverage.

import Foundation
import XCTest
@testable import CocxyTerminal

@MainActor
final class ActivityRecordingIntegrationTests: XCTestCase {

    func testDefaultDisabledConfigDoesNotRecordNewTabs() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.injectedActivityStore = store
        controller.showWindow(nil)
        try store.deleteAll()

        controller.newTabAction(nil)

        XCTAssertTrue(
            try store.events().isEmpty,
            "Activity recording must stay off unless the user explicitly enables it"
        )
    }

    func testEnabledConfigRecordsNewTabsLocally() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = try makeActivityEnabledController(store: store)
        controller.showWindow(nil)
        try store.deleteAll()

        controller.newTabAction(nil)

        let events = try store.events()
        XCTAssertEqual(events.map(\.kind), [.tabOpened])
        XCTAssertEqual(events.first?.summary, "New tab")
        XCTAssertNotNil(events.first?.project)
    }

    func testEnabledConfigRecordsTerminalSplitsLocally() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = try makeActivityEnabledController(store: store)
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }
        try store.deleteAll()

        controller.performVisualSplit(isVertical: true)

        let events = try store.events()
        XCTAssertEqual(events.map(\.kind), [.splitCreated])
        XCTAssertEqual(events.first?.summary, "Split side by side")
    }

    func testEnabledConfigRecordsCommandBlocksLocally() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = try makeActivityEnabledController(store: store)
        controller.showWindow(nil)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        try store.deleteAll()

        controller.recordCommandBlockActivity(
            makeCommandBlock(command: "swift test", pwd: "/tmp/cocxy-test", exitCode: 0),
            tabID: tabID,
            surfaceID: SurfaceID()
        )

        let events = try store.events()
        XCTAssertEqual(events.map(\.kind), [.commandExecuted, .blockFinished])
        let commandEvent = try XCTUnwrap(events.first)
        XCTAssertEqual(commandEvent.summary, "swift test")
        XCTAssertEqual(commandEvent.project?.name, "cocxy-test")
        XCTAssertEqual(commandEvent.metadata["exit_code"], "0")
        XCTAssertEqual(commandEvent.metadata["duration_ms"], "1500")
        XCTAssertEqual(commandEvent.metadata["block_id"], "42")
        XCTAssertEqual(events.last?.summary, "Block finished: swift test")
    }

    func testFailedCommandBlockRecordsErrorEventLocally() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = try makeActivityEnabledController(store: store)
        controller.showWindow(nil)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        try store.deleteAll()

        controller.recordCommandBlockActivity(
            makeCommandBlock(command: "swift test", pwd: "/tmp/cocxy-test", exitCode: 127),
            tabID: tabID,
            surfaceID: nil
        )

        let events = try store.events()
        XCTAssertEqual(events.map(\.kind), [.commandExecuted, .blockFinished, .errorEncountered])
        XCTAssertEqual(events.last?.summary, "Command failed: swift test")
        XCTAssertEqual(events.last?.metadata["exit_code"], "127")
    }

    func testEnabledConfigRecordsAgentInvokedLocally() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = try makeActivityEnabledController(store: store)
        controller.showWindow(nil)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        try store.deleteAll()

        controller.recordAgentInvokedActivity(
            agentName: "codex",
            displayName: "Codex CLI",
            launchCommand: "codex",
            tabID: tabID,
            surfaceID: SurfaceID()
        )

        let event = try XCTUnwrap(try store.events().first)
        XCTAssertEqual(event.kind, .agentInvoked)
        XCTAssertEqual(event.summary, "Codex CLI")
        XCTAssertEqual(event.metadata["agent_name"], "codex")
        XCTAssertEqual(event.metadata["launch_command"], "codex")
        XCTAssertNotNil(event.metadata["surface_id"])
    }

    func testEnabledCostTrackingRecordsAgentTokenUsageLocally() throws {
        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = try makeActivityEnabledController(store: store, costTracking: true)
        controller.showWindow(nil)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        try store.deleteAll()

        controller.recordAgentTokenUsage(
            AgentLLMUsage(
                provider: "openai",
                model: "local-model",
                inputTokens: 123,
                outputTokens: 45
            ),
            tabID: tabID,
            surfaceID: nil
        )

        let usage = try XCTUnwrap(try store.tokenUsage().first)
        XCTAssertEqual(usage.provider, "openai")
        XCTAssertEqual(usage.model, "local-model")
        XCTAssertEqual(usage.inputTokens, 123)
        XCTAssertEqual(usage.outputTokens, 45)
        XCTAssertEqual(usage.estimatedCostMicros, 0)
        XCTAssertNotNil(usage.sessionID)
        XCTAssertNotNil(usage.project)
    }

    func testEnabledConfigRecordsProjectSwitchesOnlyWhenDirectoryChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-project-switch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let store = try SQLiteActivityStore(databasePath: ":memory:")
        let controller = try makeActivityEnabledController(store: store)
        controller.showWindow(nil)
        let tabID = try XCTUnwrap(controller.tabManager.activeTabID)
        try store.deleteAll()

        controller.handleOSCNotification(.currentDirectory(root), fromTabID: tabID)
        controller.handleOSCNotification(.currentDirectory(root), fromTabID: tabID)

        let events = try store.events()
        XCTAssertEqual(events.map(\.kind), [.projectSwitched])
        XCTAssertEqual(events.first?.summary, root.lastPathComponent)
        XCTAssertEqual(events.first?.project?.name, root.lastPathComponent)
    }

    func testStorageDirectoryChangeUsesNewLocalDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-activity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
        let provider = ActivityRecordingConfigProvider(
            content: Self.activityConfigContent(storageDirectory: firstDirectory.path)
        )
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )

        controller.recordLocalActivity(kind: .tabOpened, summary: "First")
        provider.content = Self.activityConfigContent(storageDirectory: secondDirectory.path)
        try service.reload()
        controller.recordLocalActivity(kind: .splitCreated, summary: "Second")

        let firstStore = try SQLiteActivityStore(
            databasePath: firstDirectory.appendingPathComponent("activity.sqlite").path
        )
        let secondStore = try SQLiteActivityStore(
            databasePath: secondDirectory.appendingPathComponent("activity.sqlite").path
        )
        XCTAssertEqual(try firstStore.events().map(\.summary), ["First"])
        XCTAssertEqual(try secondStore.events().map(\.summary), ["Second"])
    }

    func testVisibleDashboardFollowsStorageDirectoryChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-activity-dashboard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
        let provider = ActivityRecordingConfigProvider(
            content: Self.activityConfigContent(storageDirectory: firstDirectory.path)
        )
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )
        controller.showWindow(nil)
        controller.toggleActivityDashboard()

        controller.recordLocalActivity(kind: .tabOpened, summary: "First")
        provider.content = Self.activityConfigContent(storageDirectory: secondDirectory.path)
        try service.reload()
        controller.recordLocalActivity(kind: .splitCreated, summary: "Second")

        let viewModel = try XCTUnwrap(controller.activityDashboardViewModel)
        let export = try viewModel.exportData(format: .json)
        let exportedText = try XCTUnwrap(String(data: export, encoding: .utf8))
        XCTAssertTrue(exportedText.contains("Second"))
        XCTAssertFalse(exportedText.contains("First"))
    }

    private func makeActivityEnabledController(
        store: ActivityStoring,
        costTracking: Bool = false
    ) throws -> MainWindowController {
        let provider = ActivityRecordingConfigProvider(content: """
        [activity]
        enabled = true
        cost-tracking = \(costTracking ? "true" : "false")
        storage-directory = "~/.config/cocxy/activity-test"
        """)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )
        controller.injectedActivityStore = store
        return controller
    }

    private static func activityConfigContent(storageDirectory: String) -> String {
        """
        [activity]
        enabled = true
        cost-tracking = false
        storage-directory = "\(storageDirectory)"
        """
    }

    private func makeCommandBlock(
        command: String,
        pwd: String?,
        exitCode: Int32?
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: 42,
            command: command,
            output: "ok",
            exitCode: exitCode,
            pwd: pwd,
            startTimeNs: 1_000_000_000,
            endTimeNs: 2_500_000_000,
            durationNs: 1_500_000_000,
            startRow: 1,
            endRow: 2,
            streamID: 0,
            blockType: 2
        )
    }
}

private final class ActivityRecordingConfigProvider: ConfigFileProviding, @unchecked Sendable {
    var content: String?

    init(content: String?) {
        self.content = content
    }

    func readConfigFile() -> String? {
        content
    }

    func writeConfigFile(_ content: String) throws {
        self.content = content
    }
}
