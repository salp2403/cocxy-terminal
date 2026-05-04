// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateCrashRecoverySwiftTestingTests.swift - App lifecycle crash recovery wiring.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AppDelegate crash recovery wiring")
@MainActor
struct AppDelegateCrashRecoverySwiftTestingTests {
    @Test("initializeCrashRecovery records pending snapshot after unclean previous launch")
    func initializeCrashRecoveryRecordsPendingSnapshotAfterUncleanPreviousLaunch() throws {
        let fixture = try AppCrashRecoveryFixture()
        defer { fixture.cleanup() }
        _ = try fixture.manager(now: fixture.date("2026-05-03T12:00:00Z")).beginLaunch()
        _ = try fixture.manager(now: fixture.date("2026-05-03T12:01:00Z"))
            .saveSnapshot(fixture.session(title: "Recovered"))

        let delegate = AppDelegate()
        delegate.initializeCrashRecovery(manager: fixture.manager(now: fixture.date("2026-05-03T12:05:00Z")))

        #expect(delegate.pendingCrashRecoverySnapshot?.session.windows.first?.tabs.first?.title == "Recovered")
        #expect(delegate.crashRecoveryManager != nil)
    }

    @Test("periodic snapshots write an immediate local snapshot")
    func periodicSnapshotsWriteImmediateLocalSnapshot() throws {
        let fixture = try AppCrashRecoveryFixture()
        defer { fixture.cleanup() }
        let delegate = AppDelegate()
        delegate.crashRecoveryManager = fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))

        delegate.startCrashRecoverySnapshotsIfNeeded()
        delegate.stopCrashRecoverySnapshots()

        let snapshots = try FileManager.default.contentsOfDirectory(atPath: fixture.snapshotDirectory.path)
        #expect(snapshots.count == 1)
    }

    @Test("clean shutdown marker suppresses next recovery prompt")
    func cleanShutdownMarkerSuppressesNextRecoveryPrompt() throws {
        let fixture = try AppCrashRecoveryFixture()
        defer { fixture.cleanup() }
        let delegate = AppDelegate()
        delegate.crashRecoveryManager = fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))
        _ = try delegate.crashRecoveryManager?.beginLaunch()

        delegate.markCrashRecoveryCleanShutdown()
        let next = try fixture.manager(now: fixture.date("2026-05-03T12:05:00Z")).beginLaunch()

        #expect(next.suspectedCrash == false)
    }

    @Test("restore offer keeps pending snapshot when no window is available")
    func restoreOfferKeepsPendingSnapshotWhenNoWindowIsAvailable() throws {
        let fixture = try AppCrashRecoveryFixture()
        defer { fixture.cleanup() }
        let delegate = AppDelegate()
        delegate.pendingCrashRecoverySnapshot = CrashRecoverySnapshot(
            savedAt: fixture.date("2026-05-03T12:00:00Z"),
            session: fixture.session(title: "Pending")
        )

        delegate.presentCrashRecoveryOfferIfNeeded()

        #expect(delegate.pendingCrashRecoverySnapshot?.session.windows.first?.tabs.first?.title == "Pending")
    }
}

private struct AppCrashRecoveryFixture {
    let root: URL
    let snapshotDirectory: URL
    let stateURL: URL
    let crashLogDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-app-crash-recovery-tests-\(UUID().uuidString)", isDirectory: true)
        snapshotDirectory = root.appendingPathComponent("snapshots", isDirectory: true)
        stateURL = root.appendingPathComponent("state.json", isDirectory: false)
        crashLogDirectory = root.appendingPathComponent("crashes", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func manager(now: Date) -> CrashRecoveryManager {
        CrashRecoveryManager(
            snapshotDirectory: snapshotDirectory,
            stateURL: stateURL,
            crashLogDirectory: crashLogDirectory,
            now: { now }
        )
    }

    func session(title: String) -> Session {
        Session(
            savedAt: date("2026-05-03T12:00:00Z"),
            windows: [
                WindowState(
                    frame: CodableRect(x: 10, y: 20, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: title,
                            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
                            splitTree: .leaf(
                                workingDirectory: URL(fileURLWithPath: "/tmp/project"),
                                command: nil
                            )
                        ),
                    ],
                    activeTabIndex: 0
                ),
            ]
        )
    }

    func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }
}
