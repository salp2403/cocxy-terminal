// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Git Assistant Git safety")
struct GitAssistantGitSafetySwiftTestingTests {
    @Test("revision selection rejects option and nested range operands")
    func revisionSelectionRejectsUnsafeOperands() {
        #expect(throws: GitRevisionArgumentError.self) {
            _ = try GitAssistantRevisionSelection(
                base: "--output=/tmp/probe",
                head: "HEAD"
            )
        }
        #expect(throws: GitRevisionArgumentError.self) {
            _ = try GitAssistantRevisionSelection(
                base: "main..attacker",
                head: "HEAD"
            )
        }
        #expect(throws: GitRevisionArgumentError.self) {
            _ = try GitAssistantRevisionSelection(
                base: "main",
                head: "feature branch"
            )
        }
        #expect(throws: GitRevisionArgumentError.self) {
            _ = try GitAssistantRevisionSelection(
                base: " main",
                head: "HEAD"
            )
        }
        #expect(throws: GitRevisionArgumentError.self) {
            _ = try GitAssistantRevisionSelection(
                base: "main",
                head: "HEAD "
            )
        }
    }

    @Test("revision selection builds bounded diff and log argument vectors")
    func revisionSelectionBuildsBoundedArguments() throws {
        let revisions = try GitAssistantRevisionSelection(
            base: "origin/main",
            head: "feature/review-panel"
        )

        #expect(revisions.diffArguments == [
            "diff", "--no-color", "--no-ext-diff", "--end-of-options",
            "origin/main...feature/review-panel", "--",
        ])
        #expect(revisions.logArguments == [
            "log", "--format=%H%x00%s", "--end-of-options",
            "origin/main..feature/review-panel", "--",
        ])
    }

    @Test("real Git rejects unsafe selection before file creation and accepts valid ranges")
    func realGitRespectsValidatedRevisionBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitAssistantSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try AppDelegate.gitOutput(at: root, arguments: ["init", "-q"])
        _ = try AppDelegate.gitOutput(
            at: root,
            arguments: ["config", "user.name", "Git Assistant Safety Tests"]
        )
        _ = try AppDelegate.gitOutput(
            at: root,
            arguments: ["config", "user.email", "tests@cocxy.dev"]
        )

        let tracked = root.appendingPathComponent("tracked.txt")
        try "before\n".write(to: tracked, atomically: true, encoding: .utf8)
        _ = try AppDelegate.gitOutput(at: root, arguments: ["add", "--", "tracked.txt"])
        _ = try AppDelegate.gitOutput(at: root, arguments: ["commit", "-q", "-m", "Initial"])
        try "after\n".write(to: tracked, atomically: true, encoding: .utf8)
        _ = try AppDelegate.gitOutput(at: root, arguments: ["commit", "-qam", "Update"])

        let target = root.appendingPathComponent("must-not-exist.txt")
        #expect(throws: GitRevisionArgumentError.self) {
            _ = try GitAssistantRevisionSelection(
                base: "--output=\(target.path)",
                head: "HEAD"
            )
        }
        #expect(FileManager.default.fileExists(atPath: target.path) == false)

        let revisions = try GitAssistantRevisionSelection(base: "HEAD~1", head: "HEAD")
        let diff = try AppDelegate.gitOutput(at: root, arguments: revisions.diffArguments)
        let commits = try AppDelegate.gitLogCommits(at: root, base: "HEAD~1", head: "HEAD")

        #expect(diff.contains("+after"))
        #expect(commits.count == 1)
        #expect(commits.first?.subject == "Update")
    }
}
