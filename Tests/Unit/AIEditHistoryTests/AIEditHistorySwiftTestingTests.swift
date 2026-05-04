// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditHistorySwiftTestingTests.swift - Local agent edit history coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AI edit history")
struct AIEditHistorySwiftTestingTests {
    @Test("store appends JSONL and loads chronological timeline")
    func storeAppendsJSONLAndLoadsChronologicalTimeline() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIEditStore(rootDirectory: root)
        let later = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: Date(timeIntervalSince1970: 20),
            filePath: "Sources/App.swift"
        )
        let earlier = record(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 10),
            filePath: "README.md"
        )

        try store.append(later, repoID: "repo")
        try store.append(earlier, repoID: "repo")
        let loaded = try store.load(repoID: "repo", sessionID: "session")
        let timeline = try store.timeline(repoID: "repo", sessionID: "session")

        #expect(loaded.map(\.id) == [later.id, earlier.id])
        #expect(timeline.records.map(\.id) == [earlier.id, later.id])
        let fileURL = try store.historyFileURL(repoID: "repo", sessionID: "session")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("timeline filters by file and session")
    func timelineFiltersByFileAndSession() {
        let first = record(sessionID: "s1", createdAt: Date(timeIntervalSince1970: 1), filePath: "a.swift")
        let second = record(sessionID: "s1", createdAt: Date(timeIntervalSince1970: 2), filePath: "b.swift")
        let third = record(sessionID: "s2", createdAt: Date(timeIntervalSince1970: 3), filePath: "a.swift")
        let timeline = AIEditTimeline(records: [second, third, first])

        #expect(timeline.records(touching: "a.swift").map(\.id) == [first.id, third.id])
        #expect(timeline.records(for: "s1").map(\.id) == [first.id, second.id])
    }

    @Test("differ reports touched files additions and deletions")
    func differReportsTouchedFilesAdditionsAndDeletions() {
        let record = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            createdAt: Date(timeIntervalSince1970: 1),
            summary: "Update files",
            changes: [
                AIEditChange(filePath: "a.swift", beforeContent: "one\ntwo\n", afterContent: "one\nthree\n"),
                AIEditChange(filePath: "b.swift", beforeContent: nil, afterContent: "new\n"),
            ]
        )
        let differ = AIEditDiffer()

        #expect(differ.touchedFiles(for: [record]) == ["a.swift", "b.swift"])
        #expect(differ.fileSummaries(for: record) == [
            AIEditFileSummary(filePath: "a.swift", additions: 1, deletions: 1),
            AIEditFileSummary(filePath: "b.swift", additions: 1, deletions: 0),
        ])
    }

    @Test("differ counts duplicate line removals without collapsing values")
    func differCountsDuplicateLineRemovals() {
        let record = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            createdAt: Date(timeIntervalSince1970: 1),
            summary: "Remove duplicate",
            changes: [
                AIEditChange(filePath: "README.md", beforeContent: "same\nsame\n", afterContent: "same\n"),
            ]
        )

        #expect(AIEditDiffer().fileSummaries(for: record) == [
            AIEditFileSummary(filePath: "README.md", additions: 0, deletions: 1),
        ])
    }

    @Test("reverter restores modified files only when current content matches agent output")
    func reverterRestoresModifiedFilesOnlyWhenCurrentContentMatchesAgentOutput() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "after\n".write(to: file, atomically: true, encoding: .utf8)
        let edit = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            summary: "Modify App",
            changes: [
                AIEditChange(filePath: "Sources/App.swift", beforeContent: "before\n", afterContent: "after\n"),
            ]
        )

        let result = try AIEditReverter().revert(edit, in: root)

        #expect(result.revertedFiles == ["Sources/App.swift"])
        #expect(try String(contentsOf: file, encoding: .utf8) == "before\n")
    }

    @Test("reverter removes files created by the agent")
    func reverterRemovesFilesCreatedByTheAgent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("generated.txt")
        try "created\n".write(to: file, atomically: true, encoding: .utf8)
        let edit = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            summary: "Create file",
            changes: [
                AIEditChange(filePath: "generated.txt", beforeContent: nil, afterContent: "created\n"),
            ]
        )

        _ = try AIEditReverter().revert(edit, in: root)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("reverter restores files deleted by the agent")
    func reverterRestoresFilesDeletedByTheAgent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let edit = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            summary: "Delete file",
            changes: [
                AIEditChange(filePath: "deleted.txt", beforeContent: "old\n", afterContent: nil),
            ]
        )

        _ = try AIEditReverter().revert(edit, in: root)

        #expect(try String(contentsOf: root.appendingPathComponent("deleted.txt"), encoding: .utf8) == "old\n")
    }

    @Test("reverter refuses when user changed file after agent edit")
    func reverterRefusesWhenUserChangedFileAfterAgentEdit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("README.md")
        try "user change\n".write(to: file, atomically: true, encoding: .utf8)
        let edit = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            summary: "Modify readme",
            changes: [
                AIEditChange(filePath: "README.md", beforeContent: "before\n", afterContent: "agent\n"),
            ]
        )

        #expect(throws: AIEditRevertError.currentContentChanged("README.md")) {
            _ = try AIEditReverter().revert(edit, in: root)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "user change\n")
    }

    @Test("reverter validates all files before changing any file")
    func reverterValidatesAllFilesBeforeChangingAnyFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        try "after first\n".write(to: first, atomically: true, encoding: .utf8)
        try "user changed second\n".write(to: second, atomically: true, encoding: .utf8)
        let edit = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            summary: "Two files",
            changes: [
                AIEditChange(filePath: "first.txt", beforeContent: "before first\n", afterContent: "after first\n"),
                AIEditChange(filePath: "second.txt", beforeContent: "before second\n", afterContent: "after second\n"),
            ]
        )

        #expect(throws: AIEditRevertError.currentContentChanged("second.txt")) {
            _ = try AIEditReverter().revert(edit, in: root)
        }
        #expect(try String(contentsOf: first, encoding: .utf8) == "after first\n")
        #expect(try String(contentsOf: second, encoding: .utf8) == "user changed second\n")
    }

    @Test("reverter rejects symlink paths that escape the working directory")
    func reverterRejectsSymlinkEscapes() throws {
        let root = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("linked").path,
            withDestinationPath: outside.path
        )
        let edit = AIEditRecord(
            sessionID: "session",
            agentID: "local-agent",
            summary: "Symlink escape",
            changes: [
                AIEditChange(filePath: "linked/outside.txt", beforeContent: nil, afterContent: nil),
            ]
        )

        #expect(throws: AIEditRevertError.unsafePath("linked/outside.txt")) {
            _ = try AIEditReverter().revert(edit, in: root)
        }
    }

    @Test("store and reverter reject unsafe identifiers and paths")
    func storeAndReverterRejectUnsafeIdentifiersAndPaths() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIEditStore(rootDirectory: root)

        #expect(throws: AIEditStoreError.invalidIdentifier("../repo")) {
            try store.append(record(filePath: "a.swift"), repoID: "../repo")
        }
        #expect(throws: AIEditRevertError.unsafePath("../escape.swift")) {
            _ = try AIEditReverter().revert(
                AIEditRecord(
                    sessionID: "session",
                    agentID: "local-agent",
                    summary: "Unsafe",
                    changes: [
                        AIEditChange(filePath: "../escape.swift", beforeContent: nil, afterContent: "x"),
                    ]
                ),
                in: root
            )
        }
    }

    @Test("store delete removes only requested session history")
    func storeDeleteRemovesOnlyRequestedSessionHistory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AIEditStore(rootDirectory: root)
        try store.append(record(sessionID: "one", filePath: "a.swift"), repoID: "repo")
        try store.append(record(sessionID: "two", filePath: "b.swift"), repoID: "repo")

        try store.delete(repoID: "repo", sessionID: "one")

        #expect(try store.load(repoID: "repo", sessionID: "one").isEmpty)
        #expect(try store.load(repoID: "repo", sessionID: "two").count == 1)
    }

    private func record(
        id: UUID = UUID(),
        sessionID: String = "session",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        filePath: String
    ) -> AIEditRecord {
        AIEditRecord(
            id: id,
            sessionID: sessionID,
            agentID: "local-agent",
            createdAt: createdAt,
            summary: "Edit \(filePath)",
            changes: [
                AIEditChange(filePath: filePath, beforeContent: "before\n", afterContent: "after\n"),
            ]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-ai-edit-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
