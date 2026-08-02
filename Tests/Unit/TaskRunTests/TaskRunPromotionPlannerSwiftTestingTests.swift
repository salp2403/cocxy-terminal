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
