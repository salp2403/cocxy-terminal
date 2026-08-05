// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardViewModel+TaskRun.swift - Parallel task dashboard projection.

import Foundation

extension AgentDashboardViewModel {
    /// Mirrors all candidates in one parallel task as subagents of a single
    /// dashboard row. Provider hook rows stay folded into this aggregate.
    func syncTaskRun(_ run: TaskRun, fallbackTabId: UUID) {
        updateTaskRunSession(run, fallbackTabId: fallbackTabId)
        rebuildSessions()
    }

    func syncTaskRuns(_ snapshots: [(run: TaskRun, fallbackTabId: UUID)]) {
        guard !snapshots.isEmpty else { return }
        for snapshot in snapshots {
            updateTaskRunSession(snapshot.run, fallbackTabId: snapshot.fallbackTabId)
        }
        rebuildSessions()
    }

    func removeTaskRun(runID: String) {
        sessionDataStore.removeValue(forKey: AgentTeamConfig.slug(runID))
        rebuildSessions()
    }

    private func updateTaskRunSession(_ run: TaskRun, fallbackTabId: UUID) {
        let subagents = run.candidates.map { candidate in
            let branch = candidate.worktree?.branch ?? "Preparing worktree"
            let cost = candidate.estimatedCostMicros > 0
                ? String(format: "$%.4f estimated", Double(candidate.estimatedCostMicros) / 1_000_000)
                : "Cost unavailable"
            return SubagentInfo(
                id: candidate.id,
                type: candidate.provider.displayName,
                state: mapTaskRunCandidateStatus(candidate.status),
                startTime: run.createdAt,
                lastActivity: "\(branch) - \(cost)",
                lastActivityTime: run.updatedAt
            )
        }
        let tabId = run.candidates
            .compactMap(\.worktree?.tabID?.rawValue)
            .first ?? fallbackTabId
        let activity: String
        switch run.status {
        case .launching:
            activity = "Preparing \(run.candidates.count) candidates"
        case .running:
            activity = "Comparing \(run.candidates.count) parallel candidates"
        case .promoting:
            activity = "Promoting selected candidate"
        case .completed:
            activity = run.completionWarning ?? "Winner promoted"
        case .failed:
            activity = run.failureMessage ?? "Task run failed"
        case .cancelled:
            activity = "Task run cancelled"
        }

        let project = resolveProject(from: run.originRepoPath.path)
        sessionDataStore[run.id] = MutableSessionData(
            id: run.id,
            projectName: project.name,
            projectIdentity: project.identity,
            tabId: tabId,
            state: mapTaskRunStatus(run),
            agentName: "Parallel Task",
            gitBranch: run.baseRef,
            lastActivity: activity,
            lastActivityTime: run.updatedAt,
            subagents: subagents
        )
    }

    private func mapTaskRunCandidateStatus(
        _ status: TaskRunCandidateStatus
    ) -> AgentDashboardState {
        switch status {
        case .preparing:
            return .launching
        case .running:
            return .working
        case .finished, .promoted:
            return .finished
        case .failed, .orphaned:
            return .error
        case .discarded:
            return .idle
        }
    }

    private func mapTaskRunStatus(_ run: TaskRun) -> AgentDashboardState {
        switch run.status {
        case .launching:
            return .launching
        case .promoting:
            return .working
        case .completed, .cancelled:
            return .finished
        case .failed:
            return .error
        case .running:
            return aggregateAgentTeamState(
                run.candidates.map { mapTaskRunCandidateStatus($0.status) }
            )
        }
    }
}
