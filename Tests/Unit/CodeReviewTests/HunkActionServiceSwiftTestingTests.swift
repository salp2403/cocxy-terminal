// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("HunkActionService")
struct HunkActionServiceSwiftTestingTests {
    @Test("buildPatch targets the current renamed path and ends with a trailing newline")
    func buildPatchTargetsCurrentRenamePath() {
        let hunk = DiffHunk(
            header: "@@ -1 +1,2 @@",
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 2,
            lines: [
                DiffLine(kind: .context, content: "one", oldLineNumber: 1, newLineNumber: 1),
                DiffLine(kind: .addition, content: "two", oldLineNumber: nil, newLineNumber: 2),
            ]
        )
        let fileDiff = FileDiff(
            filePath: "new\tname.swift",
            originalFilePath: "old\tname.swift",
            status: .renamed,
            hunks: [hunk]
        )

        let patch = HunkActionService.buildPatch(fileDiff: fileDiff, hunk: hunk)

        #expect(patch.contains(#"diff --git "a/new\tname.swift" "b/new\tname.swift""#))
        #expect(patch.contains(#"--- "a/new\tname.swift""#))
        #expect(patch.contains(#"+++ "b/new\tname.swift""#))
        #expect(!patch.contains("rename from"))
        #expect(!patch.contains("rename to"))
        #expect(patch.hasSuffix("\n"))
    }

    @Test("acceptHunk stages a modified file whose path contains spaces")
    func acceptHunkStagesSpacedFile() async throws {
        let repo = try makeHunkRepo(filePath: "dir with space/file name.swift")
        defer { try? FileManager.default.removeItem(at: repo) }

        let parsed = DiffParser.parse(try runGit(["diff", "--no-color"], in: repo))
        let fileDiff = try #require(parsed.first)
        let hunk = try #require(fileDiff.hunks.first)

        try await waitForHunkAction {
            HunkActionService.acceptHunk(
                fileDiff: fileDiff,
                hunk: hunk,
                workingDirectory: repo,
                completion: $0
            )
        }

        let cached = try runGit(["diff", "--cached", "--name-only"], in: repo)
        let workingTree = try runGit(["diff", "--name-only"], in: repo)
        #expect(cached.contains("dir with space/file name.swift"))
        #expect(workingTree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("revertHunk restores the working tree for a modified file with spaces")
    func revertHunkRestoresSpacedFile() async throws {
        let repo = try makeHunkRepo(filePath: "dir with space/file name.swift")
        defer { try? FileManager.default.removeItem(at: repo) }

        let parsed = DiffParser.parse(try runGit(["diff", "--no-color"], in: repo))
        let fileDiff = try #require(parsed.first)
        let hunk = try #require(fileDiff.hunks.first)

        try await waitForHunkAction {
            HunkActionService.revertHunk(
                fileDiff: fileDiff,
                hunk: hunk,
                workingDirectory: repo,
                completion: $0
            )
        }

        let workingTree = try runGit(["diff", "--name-only"], in: repo)
        let restored = try String(contentsOf: repo.appendingPathComponent("dir with space/file name.swift"))
        #expect(workingTree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(restored == "one\n")
    }

    @Test("acceptHunk stages modifications on a renamed file")
    func acceptHunkStagesRenamedFile() async throws {
        let repo = try makeRenamedHunkRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let parsed = DiffParser.parse(try runGit(["diff", "HEAD", "--no-color"], in: repo))
        let fileDiff = try #require(parsed.first)
        let hunk = try #require(fileDiff.hunks.first)

        #expect(fileDiff.status == .renamed)
        #expect(fileDiff.originalFilePath == "old.swift")
        #expect(fileDiff.filePath == "new name.swift")

        try await waitForHunkAction {
            HunkActionService.acceptHunk(
                fileDiff: fileDiff,
                hunk: hunk,
                workingDirectory: repo,
                completion: $0
            )
        }

        let cached = try runGit(["diff", "--cached", "HEAD", "--", "new name.swift"], in: repo)
        #expect(cached.contains("+two"))
    }

    @Test("revertHunk restores the working tree for a renamed file")
    func revertHunkRestoresRenamedFile() async throws {
        let repo = try makeRenamedHunkRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let parsed = DiffParser.parse(try runGit(["diff", "HEAD", "--no-color"], in: repo))
        let fileDiff = try #require(parsed.first)
        let hunk = try #require(fileDiff.hunks.first)

        try await waitForHunkAction {
            HunkActionService.revertHunk(
                fileDiff: fileDiff,
                hunk: hunk,
                workingDirectory: repo,
                completion: $0
            )
        }

        let workingTree = try runGit(["diff", "--name-only"], in: repo)
        let restored = try String(contentsOf: repo.appendingPathComponent("new name.swift"))
        #expect(workingTree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(restored == "one\n")
    }
}

private func makeHunkRepo(filePath: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("code-review-hunk-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try runGit(["init"], in: root)
    _ = try runGit(["config", "user.name", "Code Review Tests"], in: root)
    _ = try runGit(["config", "user.email", "tests@cocxy.dev"], in: root)

    let fileURL = root.appendingPathComponent(filePath)
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "one\n".write(to: fileURL, atomically: true, encoding: .utf8)
    _ = try runGit(["add", "."], in: root)
    _ = try runGit(["commit", "-m", "init"], in: root)
    try "one\ntwo\n".write(to: fileURL, atomically: true, encoding: .utf8)
    return root
}

private func makeRenamedHunkRepo() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("code-review-hunk-rename-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    _ = try runGit(["init"], in: root)
    _ = try runGit(["config", "user.name", "Code Review Tests"], in: root)
    _ = try runGit(["config", "user.email", "tests@cocxy.dev"], in: root)

    let oldURL = root.appendingPathComponent("old.swift")
    try "one\n".write(to: oldURL, atomically: true, encoding: .utf8)
    _ = try runGit(["add", "."], in: root)
    _ = try runGit(["commit", "-m", "init"], in: root)
    _ = try runGit(["mv", "old.swift", "new name.swift"], in: root)
    try "one\ntwo\n".write(to: root.appendingPathComponent("new name.swift"), atomically: true, encoding: .utf8)
    return root
}

private func runGit(_ arguments: [String], in directory: URL) throws -> String {
    let result = try CodeReviewGit.run(workingDirectory: directory, arguments: arguments)
    guard result.terminationStatus == 0 else {
        throw HunkActionError.commandFailed(result.stderr)
    }
    return result.stdout
}

private func waitForHunkAction(
    _ operation: (@escaping @Sendable (Result<Void, Error>) -> Void) -> Void
) async throws {
    try await withCheckedThrowingContinuation { continuation in
        operation { result in
            continuation.resume(with: result)
        }
    }
}
