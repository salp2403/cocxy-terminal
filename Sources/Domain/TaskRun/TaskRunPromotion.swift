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

struct TaskCollisionFreshnessToken: Equatable, Sendable {
    private struct Entry: Hashable, Sendable {
        let path: String
        let collisionKind: String
        let participantID: String
        let participantKind: String
    }

    private let entries: Set<Entry>

    init(report: TaskCollisionReport) {
        entries = Set(report.collisions.flatMap { collision in
            collision.participants.map { participant in
                Entry(
                    path: collision.path,
                    collisionKind: collision.kind.rawValue,
                    participantID: participant.id,
                    participantKind: participant.kind.rawValue
                )
            }
        })
    }

    func allows(_ current: TaskCollisionFreshnessToken) -> Bool {
        current.entries.isSubset(of: entries)
    }
}

struct TaskRunPromotionPreview: Equatable, Sendable {
    let run: TaskRun
    let comparisons: [TaskRunCandidateComparison]
    let selectedComparison: TaskRunCandidateComparison
    let collisionReport: TaskCollisionReport
    let collisionFreshnessToken: TaskCollisionFreshnessToken
    let mergedCleanupPlan: WorktreeBatchCleanupPlan
    let cleanupEntries: [TaskRunCleanupPreviewEntry]

    var selectedCandidateID: String { selectedComparison.candidate.id }

    init(
        run: TaskRun,
        comparisons: [TaskRunCandidateComparison],
        selectedComparison: TaskRunCandidateComparison,
        collisionReport: TaskCollisionReport,
        mergedCleanupPlan: WorktreeBatchCleanupPlan,
        cleanupEntries: [TaskRunCleanupPreviewEntry]
    ) {
        self.run = run
        self.comparisons = comparisons
        self.selectedComparison = selectedComparison
        self.collisionReport = collisionReport
        self.collisionFreshnessToken = TaskCollisionFreshnessToken(report: collisionReport)
        self.mergedCleanupPlan = mergedCleanupPlan
        self.cleanupEntries = cleanupEntries
    }

    func matchesPromotionState(_ currentRun: TaskRun) -> Bool {
        TaskRunPromotionState(
            run: currentRun,
            selectedCandidateID: selectedCandidateID
        ) == TaskRunPromotionState(
            run: run,
            selectedCandidateID: selectedCandidateID
        )
    }

    func matches(currentComparisons: [TaskRunCandidateComparison]) -> Bool {
        let expected = Dictionary(
            comparisons.map { ($0.id, $0.diffs) },
            uniquingKeysWith: { first, _ in first }
        )
        let current = Dictionary(
            currentComparisons.map { ($0.id, $0.diffs) },
            uniquingKeysWith: { first, _ in first }
        )
        return expected == current
    }
}

private struct TaskRunPromotionState: Equatable {
    struct Candidate: Equatable {
        let id: String
        let provider: AgentTeamProvider
        let teamID: String
        let worktree: WorktreeManifest.WorktreeEntry?
    }

    let runID: String
    let projectID: ProjectID
    let originRepoPath: URL
    let worktreeBasePath: String
    let baseCommit: String
    let runStatus: TaskRunStatus
    let selectedCandidateID: String
    let selectedCandidateStatus: TaskRunCandidateStatus?
    let candidates: [Candidate]

    init(run: TaskRun, selectedCandidateID: String) {
        runID = run.id
        projectID = run.projectID
        originRepoPath = run.originRepoPath.resolvingSymlinksInPath().standardizedFileURL
        worktreeBasePath = run.worktreeBasePath
        baseCommit = run.baseCommit
        runStatus = run.status
        self.selectedCandidateID = selectedCandidateID
        selectedCandidateStatus = run.candidates
            .first(where: { $0.id == selectedCandidateID })?.status
        candidates = run.candidates.map {
            Candidate(
                id: $0.id,
                provider: $0.provider,
                teamID: $0.teamID,
                worktree: $0.worktree
            )
        }.sorted { $0.id < $1.id }
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
