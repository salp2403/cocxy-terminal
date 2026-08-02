// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskRunRecycle.swift - Restored task candidate handoff access.

import Foundation

extension AppDelegate {
    nonisolated func recycleTaskRunCandidate(
        runID rawRunID: String,
        candidateID rawCandidateID: String
    ) async throws -> TaskRunRecycleDraft {
        let runID = AgentTeamConfig.slug(rawRunID)
        let candidateID = AgentTeamConfig.slug(rawCandidateID)
        guard let run = await MainActor.run(body: { self.activeTaskRuns[runID] }) else {
            throw TaskRunError.runNotFound(runID)
        }
        return try TaskRunRecycleDraft.make(run: run, candidateID: candidateID)
    }
}
