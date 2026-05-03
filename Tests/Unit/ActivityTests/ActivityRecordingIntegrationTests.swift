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
        store: ActivityStoring
    ) throws -> MainWindowController {
        let provider = ActivityRecordingConfigProvider(content: """
        [activity]
        enabled = true
        cost-tracking = false
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
