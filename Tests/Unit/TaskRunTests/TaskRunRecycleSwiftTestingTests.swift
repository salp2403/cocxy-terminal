// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task run candidate recycling")
struct TaskRunRecycleSwiftTestingTests {
    @Test("discarded candidate becomes a bounded prefilled task draft")
    func discardedCandidateBecomesDraft() throws {
        var run = try makeRun()
        let discardedID = run.candidates[1].id
        try run.updateCandidate(id: run.candidates[0].id) {
            $0.worktree = entry(id: "winner", tabID: TabID())
        }
        try run.updateCandidate(id: discardedID) {
            $0.worktree = entry(id: "discarded", tabID: nil)
            $0.touchedFiles = ["Sources/A.swift", "Tests/ATests.swift"]
        }
        try run.markCompleted(candidateID: run.candidates[0].id)

        let draft = try TaskRunRecycleDraft.make(run: run, candidateID: discardedID)

        #expect(draft.sourceRunID == run.id)
        #expect(draft.sourceCandidateID == discardedID)
        #expect(draft.plannedPaths == ["Sources/A.swift", "Tests/ATests.swift"])
        #expect(draft.providers == [run.candidates[1].provider])
        #expect(draft.candidateCount == 2)
        #expect(draft.prompt.contains("Tab: `(unavailable)`"))
        #expect(draft.prompt.contains("Sources/A.swift"))
    }

    @Test("active candidate cannot be recycled")
    func activeCandidateIsRejected() throws {
        var run = try makeRun()
        let candidateID = run.candidates[0].id
        try run.updateCandidate(id: candidateID) {
            $0.worktree = entry(id: "active", tabID: TabID())
        }

        #expect(throws: TaskRunError.candidateNotRecyclable(candidateID)) {
            try TaskRunRecycleDraft.make(run: run, candidateID: candidateID)
        }
    }

    @Test("comparison uses persisted metadata after worktree cleanup")
    func comparisonSurvivesCleanup() throws {
        var run = try makeRun()
        let candidateID = run.candidates[0].id
        try run.updateCandidate(id: candidateID) {
            $0.worktree = entry(id: "removed", tabID: nil)
            $0.touchedFiles = ["Sources/Retained.swift"]
        }
        let service = TaskRunComparisonService(
            gitRunner: { _, _ in
                Issue.record("Git must not run for a removed worktree")
                return CodeReviewGitResult(stdout: "", stderr: "", terminationStatus: 1)
            },
            directoryExists: { _ in false }
        )

        let comparison = try #require(service.load(run: run).first)
        #expect(comparison.diffs.isEmpty)
        #expect(comparison.touchedFiles == ["Sources/Retained.swift"])
        #expect(comparison.changedFileCount == 1)
    }

    private func makeRun() throws -> TaskRun {
        TaskRun(
            id: "recycle",
            request: try TaskRunRequest.make(prompt: "Original task", agents: "codex,claude"),
            originRepoPath: URL(fileURLWithPath: "/tmp/repo"),
            baseCommit: "base"
        )
    }

    private func entry(id: String, tabID: TabID?) -> WorktreeManifest.WorktreeEntry {
        WorktreeManifest.WorktreeEntry(
            id: id,
            branch: "task/\(id)",
            path: URL(fileURLWithPath: "/tmp/\(id)"),
            createdAt: Date(timeIntervalSince1970: 1),
            agent: "codex",
            tabID: tabID
        )
    }
}
