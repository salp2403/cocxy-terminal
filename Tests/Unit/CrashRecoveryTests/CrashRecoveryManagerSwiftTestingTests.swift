// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CrashRecoveryManagerSwiftTestingTests.swift - Local-only crash recovery coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Crash recovery manager")
struct CrashRecoveryManagerSwiftTestingTests {
    @Test("begin launch marks running and clean shutdown suppresses recovery")
    func beginLaunchMarksRunningAndCleanShutdownSuppressesRecovery() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))

        let first = try manager.beginLaunch()
        try manager.markCleanShutdown()
        let second = try manager.beginLaunch()

        #expect(first.suspectedCrash == false)
        #expect(first.latestSnapshot == nil)
        #expect(second.suspectedCrash == false)
        #expect(second.latestSnapshot == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.stateURL.path))
    }

    @Test("unclean previous launch exposes latest snapshot and writes local crash log")
    func uncleanPreviousLaunchExposesLatestSnapshotAndWritesLocalCrashLog() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        let firstManager = fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))
        _ = try firstManager.beginLaunch()
        let snapshot = try firstManager.saveSnapshot(fixture.session(title: "Recovered"))

        let secondManager = fixture.manager(now: fixture.date("2026-05-03T12:05:00Z"))
        let result = try secondManager.beginLaunch()

        #expect(result.suspectedCrash == true)
        #expect(result.latestSnapshot?.session.windows.first?.tabs.first?.title == "Recovered")
        #expect(result.latestSnapshot?.url?.lastPathComponent == snapshot.url?.lastPathComponent)
        let crashLogs = try FileManager.default.contentsOfDirectory(atPath: fixture.crashLogDirectory.path)
        #expect(crashLogs.count == 1)
        #expect(crashLogs.first?.hasSuffix(".json") == true)
    }

    @Test("snapshots are local files with owner-only permissions")
    func snapshotsAreLocalFilesWithOwnerOnlyPermissions() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))

        let snapshot = try manager.saveSnapshot(fixture.session(title: "Permissions"))

        let url = try #require(snapshot.url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[FileAttributeKey.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(url.path.hasPrefix(fixture.snapshotDirectory.path))
    }

    @Test("latest snapshot is selected by saved date")
    func latestSnapshotIsSelectedBySavedDate() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        _ = try fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))
            .saveSnapshot(fixture.session(title: "Old"))
        _ = try fixture.manager(now: fixture.date("2026-05-03T12:05:00Z"))
            .saveSnapshot(fixture.session(title: "New"))

        let latest = try fixture.manager(now: fixture.date("2026-05-03T12:10:00Z"))
            .loadLatestSnapshot()

        #expect(latest?.session.windows.first?.tabs.first?.title == "New")
    }

    @Test("snapshot preserves granular pane metadata")
    func snapshotPreservesGranularPaneMetadata() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        let notebook = URL(fileURLWithPath: "/tmp/notebook.cocxynb")
        let session = fixture.session(
            title: "Workspace",
            paneStates: [
                SplitPaneState(scrollPosition: TerminalScrollPosition(visibleStartRow: 12)),
                SplitPaneState(panelInfo: .notebook(path: notebook), title: "Notebook")
            ]
        )

        _ = try fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))
            .saveSnapshot(session)
        let loaded = try fixture.manager(now: fixture.date("2026-05-03T12:05:00Z"))
            .loadLatestSnapshot()

        let panes = try #require(loaded?.session.windows.first?.tabs.first?.paneStates)
        #expect(panes.count == 2)
        #expect(panes[0].scrollPosition?.visibleStartRow == 12)
        #expect(panes[1].panelInfo.type == .notebook)
        #expect(panes[1].panelInfo.filePath == notebook)
    }

    @Test("prune keeps newest snapshots")
    func pruneKeepsNewestSnapshots() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        for offset in 0..<5 {
            _ = try fixture.manager(now: fixture.dateByAdding(minutes: offset, to: fixture.date("2026-05-03T12:00:00Z")))
                .saveSnapshot(fixture.session(title: "Snapshot \(offset)"))
        }

        let pruned = try fixture.manager(now: fixture.date("2026-05-03T12:10:00Z"))
            .pruneSnapshots(keepNewest: 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.snapshotDirectory.path)

        #expect(pruned == 3)
        #expect(names.count == 2)
    }

    @Test("corrupt snapshot files are ignored during latest lookup and pruning")
    func corruptSnapshotFilesAreIgnoredDuringLatestLookupAndPruning() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        _ = try fixture.manager(now: fixture.date("2026-05-03T12:00:00Z"))
            .saveSnapshot(fixture.session(title: "Valid"))
        try FileManager.default.createDirectory(at: fixture.snapshotDirectory, withIntermediateDirectories: true)
        try "{ broken".write(
            to: fixture.snapshotDirectory.appendingPathComponent("2026-05-03_12-01-00-broken.json"),
            atomically: true,
            encoding: .utf8
        )

        let manager = fixture.manager(now: fixture.date("2026-05-03T12:10:00Z"))
        let latest = try manager.loadLatestSnapshot()
        let pruned = try manager.pruneSnapshots(keepNewest: 1)

        #expect(latest?.session.windows.first?.tabs.first?.title == "Valid")
        #expect(pruned == 0)
    }

    @Test("corrupt launch state is replaced by a fresh running marker")
    func corruptLaunchStateIsReplacedByFreshRunningMarker() throws {
        let fixture = try CrashRecoveryFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{ broken".write(to: fixture.stateURL, atomically: true, encoding: .utf8)

        let first = try fixture.manager(now: fixture.date("2026-05-03T12:00:00Z")).beginLaunch()
        let second = try fixture.manager(now: fixture.date("2026-05-03T12:05:00Z")).beginLaunch()

        #expect(first.suspectedCrash == false)
        #expect(second.suspectedCrash == true)
    }
}

private struct CrashRecoveryFixture {
    let root: URL
    let snapshotDirectory: URL
    let stateURL: URL
    let crashLogDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-crash-recovery-tests-\(UUID().uuidString)", isDirectory: true)
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

    func session(title: String, paneStates: [SplitPaneState] = []) -> Session {
        let workingDirectory = URL(fileURLWithPath: "/tmp/project")
        let splitTree: SplitNodeState = paneStates.count > 1
            ? .split(
                direction: .horizontal,
                first: .leaf(workingDirectory: workingDirectory, command: nil),
                second: .leaf(workingDirectory: workingDirectory, command: nil),
                ratio: 0.65
            )
            : .leaf(workingDirectory: workingDirectory, command: nil)

        return Session(
            savedAt: date("2026-05-03T12:00:00Z"),
            windows: [
                WindowState(
                    frame: CodableRect(x: 10, y: 20, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: title,
                            workingDirectory: workingDirectory,
                            splitTree: splitTree,
                            paneStates: paneStates
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

    func dateByAdding(minutes: Int, to date: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .minute, value: minutes, to: date)!
    }
}
