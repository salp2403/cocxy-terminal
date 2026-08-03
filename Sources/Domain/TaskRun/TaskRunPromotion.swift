// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunPromotion.swift - Immutable promotion and cleanup confirmation contract.

import Foundation

enum TaskRunCleanupDisposition: String, Equatable, Sendable {
    case removeMerged
    case discardCandidate
    case retainWinner
}

struct TaskRunCleanupPreviewEntry: Identifiable, Equatable, Sendable {
    let candidateID: String
    let worktree: WorktreeManifest.WorktreeEntry
    let disposition: TaskRunCleanupDisposition

    var id: String { worktree.id }
}

struct TaskRunPromotionPreview: Equatable, Sendable {
    let run: TaskRun
    let comparisons: [TaskRunCandidateComparison]
    let selectedComparison: TaskRunCandidateComparison
    let collisionReport: TaskCollisionReport
    let mergedCleanupPlan: WorktreeBatchCleanupPlan
    let cleanupEntries: [TaskRunCleanupPreviewEntry]

    var selectedCandidateID: String { selectedComparison.candidate.id }

    func matches(currentComparisons: [TaskRunCandidateComparison]) -> Bool {
        currentComparisons == comparisons
    }
}

enum TaskRunPromotionPlanner {
    static func cleanupEntries(
        run: TaskRun,
        selectedCandidateID: String,
        manifestEntries: [WorktreeManifest.WorktreeEntry],
        mergedPlan: WorktreeBatchCleanupPlan
    ) throws -> [TaskRunCleanupPreviewEntry] {
        guard run.candidates.contains(where: { $0.id == selectedCandidateID }) else {
            throw TaskRunError.candidateNotFound(selectedCandidateID)
        }
        let manifestByID = Dictionary(
            manifestEntries.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let removable = Set(mergedPlan.removable.map(\.id))
        return run.candidates.compactMap { candidate in
            guard let recorded = candidate.worktree,
                  let current = manifestByID[recorded.id] else { return nil }
            let disposition: TaskRunCleanupDisposition
            if candidate.id != selectedCandidateID {
                disposition = .discardCandidate
            } else if removable.contains(current.id) {
                disposition = .removeMerged
            } else {
                disposition = .retainWinner
            }
            return TaskRunCleanupPreviewEntry(
                candidateID: candidate.id,
                worktree: current,
                disposition: disposition
            )
        }
    }
}
