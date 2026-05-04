// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditHistoryGitRecorderSwiftTestingTests.swift - Git-backed local edit capture.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AI edit history Git recorder", .serialized)
struct AIEditHistoryGitRecorderSwiftTestingTests {
    @Test("recorder captures modified created and deleted files relative to base ref")
    func recorderCapturesTrackedFileChanges() throws {
        let repo = try makeGitRepository()
        let storeRoot = try makeTemporaryDirectory(named: "ai-edit-history-git-store")
        defer {
            try? FileManager.default.removeItem(at: repo.url)
            try? FileManager.default.removeItem(at: storeRoot)
        }

        try "old\nchanged\n".write(
            to: repo.url.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "new\n".write(
            to: repo.url.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.removeItem(at: repo.url.appendingPathComponent("deleted.txt"))

        let store = AIEditStore(rootDirectory: storeRoot)
        let recorder = AIEditHistoryGitRecorder(store: store)

        let record = try #require(try recorder.recordSession(
            sessionID: "session",
            agentID: "local-agent",
            workingDirectory: repo.url,
            baseRef: repo.head,
            trackedFiles: ["tracked.txt", "new.txt", "deleted.txt"]
        ))

        #expect(record.sessionID == "session")
        #expect(record.agentID == "local-agent")
        #expect(record.summary == "Recorded 3 file changes")
        #expect(record.changes.map(\.filePath) == ["deleted.txt", "new.txt", "tracked.txt"])

        let changes = Dictionary(uniqueKeysWithValues: record.changes.map { ($0.filePath, $0) })
        #expect(changes["tracked.txt"]?.beforeContent == "old\n")
        #expect(changes["tracked.txt"]?.afterContent == "old\nchanged\n")
        #expect(changes["new.txt"]?.beforeContent == nil)
        #expect(changes["new.txt"]?.afterContent == "new\n")
        #expect(changes["deleted.txt"]?.beforeContent == "remove me\n")
        #expect(changes["deleted.txt"]?.afterContent == nil)

        let repoID = try AIEditRepositoryIdentifier.id(for: repo.url)
        #expect(repoID.count == AIEditRepositoryIdentifier.idLength)
        #expect(repoID.range(of: #"^[a-f0-9]+$"#, options: .regularExpression) != nil)
        #expect(!repoID.contains(repo.url.lastPathComponent))
        let persisted = try store.load(repoID: repoID, sessionID: "session")
        #expect(persisted.map(\.id) == [record.id])
        #expect(persisted.first?.changes == record.changes)
    }

    private func makeGitRepository() throws -> (url: URL, head: String) {
        let root = try makeTemporaryDirectory(named: "ai-edit-history-git-repo")
        _ = try runGit(["init"], in: root)
        _ = try runGit(["config", "user.name", "Local Tests"], in: root)
        _ = try runGit(["config", "user.email", "tests@cocxy.dev"], in: root)

        try "old\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "remove me\n".write(to: root.appendingPathComponent("deleted.txt"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "."], in: root)
        _ = try runGit(["commit", "-m", "Initial fixture"], in: root)
        let head = try runGit(["rev-parse", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
        return (root, head)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let result = try CodeReviewGit.run(workingDirectory: directory, arguments: arguments)
        guard result.terminationStatus == 0 else {
            throw NSError(
                domain: "AIEditHistoryGitRecorderSwiftTestingTests",
                code: Int(result.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: result.stderr]
            )
        }
        return result.stdout
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
