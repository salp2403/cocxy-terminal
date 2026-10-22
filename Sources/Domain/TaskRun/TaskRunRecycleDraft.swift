// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunRecycleDraft.swift - Bounded context for reusing a discarded candidate.

import Foundation

struct TaskRunRecycleDraft: Equatable, Sendable {
    let sourceRunID: String
    let sourceCandidateID: String
    let prompt: String
    let plannedPaths: [String]
    let providers: [AgentTeamProvider]
    let candidateCount: Int
    let baseRef: String
    let artifact: TaskHandoffArtifact

    static func make(run: TaskRun, candidateID: String) throws -> TaskRunRecycleDraft {
        guard let candidate = run.candidates.first(where: { $0.id == candidateID }),
              let worktree = candidate.worktree else {
            throw TaskRunError.candidateNotFound(candidateID)
        }
        guard candidate.status == .discarded else {
            throw TaskRunError.candidateNotRecyclable(candidateID)
        }
        let artifact = TaskHandoffArtifactBuilder.make(input: TaskHandoffArtifactInput(
            tabID: worktree.tabID?.rawValue,
            workingDirectory: worktree.path.path,
            branch: worktree.branch,
            worktreeID: worktree.id,
            taskSummary: run.prompt,
            touchedFiles: candidate.touchedFiles,
            semanticBlocks: []
        ))
        return TaskRunRecycleDraft(
            sourceRunID: run.id,
            sourceCandidateID: candidate.id,
            prompt: artifact.markdown,
            plannedPaths: candidate.touchedFiles,
            providers: [candidate.provider],
            candidateCount: TaskRunRequest.minimumCandidateCount,
            baseRef: run.baseRef,
            artifact: artifact
        )
    }
}
