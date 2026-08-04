// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task run promotion planner")
struct TaskRunPromotionPlannerSwiftTestingTests {
    @Test("cleanup preview scopes every action to the task run")
    func cleanupPreviewIsScoped() throws {
        var run = try makeRun()
        let winner = entry(id: "winner")
        let loser = entry(id: "loser")
        let unrelated = entry(id: "unrelated")
        try run.updateCandidate(id: run.candidates[0].id) { $0.worktree = winner }
        try run.updateCandidate(id: run.candidates[1].id) { $0.worktree = loser }
        let plan = WorktreeBatchCleanupPlan(
            removable: [winner, unrelated],
            blocked: [],
            skipped: []
        )

        let entries = try TaskRunPromotionPlanner.cleanupEntries(
            run: run,
            selectedCandidateID: run.candidates[0].id,
            manifestEntries: [winner, loser, unrelated],
            mergedPlan: plan
        )

        #expect(entries.map(\.worktree.id) == ["winner", "loser"])
        #expect(entries.map(\.disposition) == [.removeMerged, .discardCandidate])
    }

    @Test("blocked winner remains explicit in the confirmation plan")
    func retainedWinner() throws {
        var run = try makeRun()
        let winner = entry(id: "winner")
        try run.updateCandidate(id: run.candidates[0].id) { $0.worktree = winner }
        let plan = WorktreeBatchCleanupPlan(
            removable: [],
            blocked: [WorktreeBatchCleanupBlock(
                entry: winner,
                reason: .dependentWorktrees(ids: ["dependent"])
            )],
            skipped: []
        )

        let entries = try TaskRunPromotionPlanner.cleanupEntries(
            run: run,
            selectedCandidateID: run.candidates[0].id,
            manifestEntries: [winner],
            mergedPlan: plan
        )

        #expect(entries.first?.disposition == .retainWinner)
    }

    @Test("promotion freshness ignores activity metadata but binds promotion invariants")
    func promotionFreshnessUsesExplicitInvariants() throws {
        var run = try makeRun()
        let winner = entry(id: "winner")
        let loser = entry(id: "loser")
        try run.updateCandidate(id: run.candidates[0].id) {
            $0.worktree = winner
            $0.status = .finished
        }
        try run.updateCandidate(id: run.candidates[1].id) {
            $0.worktree = loser
            $0.status = .running
        }
        run.markRunning(now: Date(timeIntervalSince1970: 10))
        let selected = TaskRunCandidateComparison(candidate: run.candidates[0], diffs: [])
        let preview = TaskRunPromotionPreview(
            run: run,
            comparisons: [
                selected,
                TaskRunCandidateComparison(candidate: run.candidates[1], diffs: []),
            ],
            selectedComparison: selected,
            collisionReport: .empty,
            mergedCleanupPlan: WorktreeBatchCleanupPlan(removable: [], blocked: [], skipped: []),
            cleanupEntries: []
        )

        var activityUpdate = run
        try activityUpdate.updateCandidate(
            id: activityUpdate.candidates[1].id,
            now: Date(timeIntervalSince1970: 20)
        ) {
            $0.status = .finished
            $0.touchedFiles = ["Sources/Background.swift"]
        }
        #expect(preview.matchesPromotionState(activityUpdate))
        #expect(preview.matches(currentComparisons: activityUpdate.candidates.map {
            TaskRunCandidateComparison(candidate: $0, diffs: [])
        }))

        var selectedStatusChanged = activityUpdate
        try selectedStatusChanged.updateCandidate(id: selectedStatusChanged.candidates[0].id) {
            $0.status = .failed
        }
        #expect(!preview.matchesPromotionState(selectedStatusChanged))

        var worktreeChanged = activityUpdate
        try worktreeChanged.updateCandidate(id: worktreeChanged.candidates[1].id) {
            $0.worktree = entry(id: "replacement")
        }
        #expect(!preview.matchesPromotionState(worktreeChanged))

        let changedDiff = FileDiff(
            filePath: "Sources/App.swift",
            status: .modified,
            hunks: []
        )
        #expect(!preview.matches(currentComparisons: [
            TaskRunCandidateComparison(candidate: activityUpdate.candidates[0], diffs: [changedDiff]),
            TaskRunCandidateComparison(candidate: activityUpdate.candidates[1], diffs: []),
        ]))
    }

    private func makeRun() throws -> TaskRun {
        let request = try TaskRunRequest.make(prompt: "Ship", agents: "codex,claude")
        return TaskRun(
            id: "promotion-plan",
            request: request,
            originRepoPath: URL(fileURLWithPath: "/tmp/repo"),
            baseCommit: "base"
        )
    }

    private func entry(id: String) -> WorktreeManifest.WorktreeEntry {
        WorktreeManifest.WorktreeEntry(
            id: id,
            branch: "task/\(id)",
            path: URL(fileURLWithPath: "/tmp/\(id)"),
            createdAt: Date(timeIntervalSince1970: 1),
            agent: "codex",
            tabID: nil
        )
    }
}
