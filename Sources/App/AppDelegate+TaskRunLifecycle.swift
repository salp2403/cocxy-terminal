// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskRunLifecycle.swift - Durable cancellation and removal of task runs.

import Foundation

enum TaskRunLifecycleError: Error, Sendable, Equatable, CustomStringConvertible {
    case cancellationUnavailable(status: TaskRunStatus)
    case removalUnavailable(status: TaskRunStatus)
    case persistenceFailed(action: String, reason: String)

    var description: String {
        switch self {
        case .cancellationUnavailable(let status):
            return "Task run cannot be cancelled while it is \(status.rawValue)"
        case .removalUnavailable(let status):
            return "Task run cannot be removed while it is \(status.rawValue)"
        case .persistenceFailed(let action, let reason):
            return "Task run \(action) changed the in-memory state but could not be saved: \(reason)"
        }
    }
}

@MainActor
extension AppDelegate {
    func cancelTaskRun(runID rawRunID: String) async throws -> TaskRun {
        let runID = AgentTeamConfig.slug(rawRunID)
        guard var run = activeTaskRuns[runID] else {
            throw TaskRunError.runNotFound(runID)
        }
        guard !run.status.isFinished else {
            throw TaskRunError.runAlreadyFinished(runID)
        }
        guard run.status == .launching || run.status == .running else {
            throw TaskRunLifecycleError.cancellationUnavailable(status: run.status)
        }

        try run.markCancelled()
        taskOrchestrationSessionManager.revoke(runID: run.id)
        for candidate in run.candidates {
            _ = removeAgentTeamRuntime(
                teamID: candidate.teamID,
                worktreeClosePolicyOverride: .keep,
                removeDashboardRow: false
            )
        }
        run = publishTaskRun(
            run,
            fallbackTabID: run.candidates.compactMap(\.worktree?.tabID?.rawValue).first ?? UUID(),
            persist: false
        )

        do {
            try await persistTaskRunImmediately(run)
            return activeTaskRuns[run.id] ?? run
        } catch {
            throw TaskRunLifecycleError.persistenceFailed(
                action: "cancellation",
                reason: String(describing: error)
            )
        }
    }

    func forgetTaskRun(runID rawRunID: String) async throws {
        let runID = AgentTeamConfig.slug(rawRunID)
        guard let run = activeTaskRuns[runID] else {
            throw TaskRunError.runNotFound(runID)
        }
        guard run.status.isFinished else {
            throw TaskRunLifecycleError.removalUnavailable(status: run.status)
        }

        do {
            try await deletePersistedTaskRun(run)
        } catch {
            throw TaskRunLifecycleError.persistenceFailed(
                action: "removal",
                reason: String(describing: error)
            )
        }

        guard activeTaskRuns[runID]?.status.isFinished == true else {
            taskRunPersistenceCoordinator?.resume(
                runID: runID,
                replaying: activeTaskRuns[runID]
            )
            throw TaskRunLifecycleError.removalUnavailable(
                status: activeTaskRuns[runID]?.status ?? run.status
            )
        }
        activeTaskRuns.removeValue(forKey: runID)
        taskRunPersistenceCoordinator?.discard(runID: runID)
        taskOrchestrationSessionManager.revoke(runID: runID)
        for candidate in run.candidates {
            _ = removeAgentTeamRuntime(
                teamID: candidate.teamID,
                worktreeClosePolicyOverride: .keep,
                removeDashboardRow: false
            )
        }
        taskInboxStore.updateTaskRuns(Array(activeTaskRuns.values))
        agentDashboardViewModel?.removeTaskRun(runID: runID)
        for controller in allWindowControllers {
            guard controller.dashboardViewModel !== agentDashboardViewModel else { continue }
            controller.dashboardViewModel?.removeTaskRun(runID: runID)
        }
        clearTaskRunPersistenceIssue(for: runID)
    }
}
