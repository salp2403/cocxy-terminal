// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskRunPersistence.swift - App-scoped TaskRun restore wiring.

import Foundation
import os.log

private struct TaskRunRestorationOutcome: Sendable {
    let report: TaskRunRestorationReport?
    let failure: String?
}

extension AppDelegate {
    nonisolated private static let taskRunPersistenceLogger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "TaskRunPersistence"
    )
    private static let taskRunRestoreIssueKey = "$restore"

    func setupTaskRunDurability() {
        guard taskRunPersistenceCoordinator == nil else { return }
        let store = taskRunStore
        taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(
            store: store,
            eventHandler: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleTaskRunPersistenceEvent(event)
                }
            }
        )

        taskRunRestorationTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                do {
                    return TaskRunRestorationOutcome(
                        report: try await TaskRunRestorer().restore(from: store),
                        failure: nil
                    )
                } catch {
                    return TaskRunRestorationOutcome(
                        report: nil,
                        failure: String(describing: error)
                    )
                }
            }.value
            guard !Task.isCancelled, let self else { return }
            if let failure = outcome.failure {
                let issue =
                    "Task run restoration failed: \(Self.singleLinePersistenceMessage(failure))"
                taskRunPersistenceIssues[Self.taskRunRestoreIssueKey] = issue
                taskInboxStore.markFailed(.taskRuns, message: issue)
                Self.taskRunPersistenceLogger.error(
                    "Task run restore failed: \(failure, privacy: .private)"
                )
                return
            }
            guard let report = outcome.report else { return }
            self.installRestoredTaskRuns(report)
        }
    }

    nonisolated func persistTaskRunImmediately(_ run: TaskRun) async throws {
        let (store, coordinator) = await MainActor.run {
            (self.taskRunStore, self.taskRunPersistenceCoordinator)
        }
        coordinator?.suppress(runID: run.id)
        do {
            try await Task.detached(priority: .utility) {
                if let coordinator {
                    try coordinator.performExclusiveSave(run)
                } else {
                    try store.save(run)
                }
            }.value
            let replayRun = await MainActor.run { () -> TaskRun? in
                self.handleTaskRunPersistenceEvent(.saved(runID: run.id))
                if let latest = self.activeTaskRuns[run.id], latest != run {
                    return latest
                }
                return nil
            }
            coordinator?.resume(runID: run.id, replaying: replayRun)
        } catch {
            let message = String(describing: error)
            let replayRun = await MainActor.run { () -> TaskRun? in
                self.handleTaskRunPersistenceEvent(.failed(runID: run.id, message: message))
                return self.activeTaskRuns[run.id]
            }
            coordinator?.resume(runID: run.id, replaying: replayRun)
            throw error
        }
    }

    nonisolated func deletePersistedTaskRun(_ run: TaskRun) async throws {
        let (store, coordinator) = await MainActor.run {
            (self.taskRunStore, self.taskRunPersistenceCoordinator)
        }
        coordinator?.suppress(runID: run.id)
        do {
            try await Task.detached(priority: .utility) {
                if let coordinator {
                    try coordinator.performExclusive { try store.remove(run) }
                } else {
                    try store.remove(run)
                }
            }.value
        } catch {
            coordinator?.resume(runID: run.id)
            let message = String(describing: error)
            await MainActor.run {
                self.handleTaskRunPersistenceEvent(.failed(runID: run.id, message: message))
            }
            throw error
        }
    }

    func shutdownTaskRuntimesForTermination() {
        taskQueueTimer?.invalidate()
        taskQueueTimer = nil
        taskRunPersistenceCoordinator?.flush()
        taskRunPersistenceCoordinator = nil
        taskRunRestorationTask?.cancel()
        taskRunRestorationTask = nil
        let terminatingTaskQueue = taskQueue
        taskQueue = nil
        taskQueueIsReady = false
        Task { [agentPipelineCompletionBroker] in
            await terminatingTaskQueue?.shutdown()
            await agentPipelineCompletionBroker.cancelAll()
        }
    }

    private func installRestoredTaskRuns(_ report: TaskRunRestorationReport) {
        var installedRunIDs: Set<String> = []
        for run in report.runs where activeTaskRuns[run.id] == nil {
            activeTaskRuns[run.id] = run
            installedRunIDs.insert(run.id)
            let fallbackTabID = run.candidates.compactMap(\.worktree?.tabID?.rawValue).first
                ?? UUID()
            agentDashboardViewModel?.syncTaskRun(run, fallbackTabId: fallbackTabID)
            for controller in allWindowControllers {
                guard controller.dashboardViewModel !== agentDashboardViewModel else { continue }
                controller.dashboardViewModel?.syncTaskRun(run, fallbackTabId: fallbackTabID)
            }
        }
        taskInboxStore.updateTaskRuns(Array(activeTaskRuns.values))
        for run in report.runs where installedRunIDs.contains(run.id)
            && report.reconciledRunIDs.contains(run.id) {
            taskRunPersistenceCoordinator?.enqueue(run)
        }

        var restorationIssues: [String] = []
        if !report.rejectedFiles.isEmpty {
            restorationIssues.append(
                "Ignored \(report.rejectedFiles.count) invalid task run snapshot(s)"
            )
            Self.taskRunPersistenceLogger.warning(
                "Task run restore ignored \(report.rejectedFiles.count, privacy: .public) invalid snapshot(s)"
            )
        }
        if !report.maintenanceFailures.isEmpty {
            restorationIssues.append(
                "Could not prune \(report.maintenanceFailures.count) older task run snapshot(s)"
            )
            Self.taskRunPersistenceLogger.error(
                "Task run retention failed for \(report.maintenanceFailures.count, privacy: .public) snapshot(s)"
            )
        }
        if report.orphanedCandidateCount > 0 {
            Self.taskRunPersistenceLogger.notice(
                "Task run restore found \(report.orphanedCandidateCount, privacy: .public) unavailable candidate worktree(s)"
            )
        }
        if report.prunedSnapshotCount > 0 {
            Self.taskRunPersistenceLogger.notice(
                "Task run retention pruned \(report.prunedSnapshotCount, privacy: .public) finished snapshot(s)"
            )
        }
        if restorationIssues.isEmpty {
            taskRunPersistenceIssues.removeValue(forKey: Self.taskRunRestoreIssueKey)
        } else {
            taskRunPersistenceIssues[Self.taskRunRestoreIssueKey] = restorationIssues.joined(
                separator: ". "
            )
        }
        refreshTaskRunPersistenceAvailability()
    }

    func taskRunPersistenceIssue(for runID: String) -> String? {
        taskRunPersistenceIssues[AgentTeamConfig.slug(runID)]
    }

    func clearTaskRunPersistenceIssue(for runID: String) {
        taskRunPersistenceIssues.removeValue(forKey: AgentTeamConfig.slug(runID))
        refreshTaskRunPersistenceAvailability()
    }

    func handleTaskRunPersistenceEvent(_ event: TaskRunPersistenceEvent) {
        switch event {
        case .saved(let runID):
            taskRunPersistenceIssues.removeValue(forKey: runID)
        case .failed(let runID, let message):
            let safeMessage = Self.singleLinePersistenceMessage(message)
            taskRunPersistenceIssues[runID] =
                "Task \(runID) could not be saved. Changes remain in memory. \(safeMessage)"
            Self.taskRunPersistenceLogger.error(
                "Task run \(runID, privacy: .public) save failed: \(message, privacy: .private)"
            )
        }
        refreshTaskRunPersistenceAvailability()
    }

    private func refreshTaskRunPersistenceAvailability() {
        guard !taskRunPersistenceIssues.isEmpty else {
            taskInboxStore.markReady(.taskRuns)
            return
        }
        let message = taskRunPersistenceIssues.values.sorted().joined(separator: "\n")
        taskInboxStore.markDegraded(.taskRuns, message: message)
    }

    nonisolated private static func singleLinePersistenceMessage(_ message: String) -> String {
        String(
            message.components(separatedBy: .newlines)
                .joined(separator: " ")
                .prefix(512)
        )
    }
}
