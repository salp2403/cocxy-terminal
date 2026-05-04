// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AutomaticBackupControllerSwiftTestingTests.swift - Launch backup gating coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Automatic backup controller")
struct AutomaticBackupControllerSwiftTestingTests {
    @Test("runs at most once per local day and prunes after successful backup")
    func runsAtMostOncePerLocalDayAndPrunesAfterSuccessfulBackup() throws {
        let fixture = try BackupFixture()
        defer { fixture.cleanup() }
        try fixture.writeFixtureFiles()

        let config = BackupConfig(
            enabled: true,
            storageDirectory: fixture.backupRoot.path,
            dailyRetentionCount: 30,
            monthlyRetentionCount: 12,
            artifactKinds: [.settings]
        )
        let controller = AutomaticBackupController(
            roots: fixture.roots,
            stateURL: fixture.root.appendingPathComponent("backup-state.json"),
            now: { fixture.date("2026-05-03T12:00:00Z") }
        )

        let first = try controller.runIfDue(config: config)
        let second = try controller.runIfDue(config: config)

        #expect(first.createdBackupURL?.lastPathComponent == "2026-05-03_12-00-00")
        #expect(second.createdBackupURL == nil)
        #expect(second.reason == .alreadyRanToday)
    }
}
