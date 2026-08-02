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

    func setupTaskRunDurability() {
        guard taskRunPersistenceCoordinator == nil else { return }
        let store = taskRunStore
        taskRunPersistenceCoordinator = TaskRunPersistenceCoordinator(
            store: store,
            failureHandler: { message in
                Self.taskRunPersistenceLogger.error(
                    "Task run save failed: \(message, privacy: .private)"
                )
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
                Self.taskRunPersistenceLogger.error(
                    "Task run restore failed: \(failure, privacy: .private)"
                )
                return
            }
            guard let report = outcome.report else { return }
            self.installRestoredTaskRuns(report)
        }
    }

    private func installRestoredTaskRuns(_ report: TaskRunRestorationReport) {
        for run in report.runs where activeTaskRuns[run.id] == nil {
            publishTaskRun(
                run,
                fallbackTabID: run.candidates.compactMap(\.worktree?.tabID?.rawValue).first
                    ?? UUID()
            )
        }
        if !report.rejectedFiles.isEmpty {
            Self.taskRunPersistenceLogger.warning(
                "Task run restore ignored \(report.rejectedFiles.count, privacy: .public) invalid snapshot(s)"
            )
        }
        if report.orphanedCandidateCount > 0 {
            Self.taskRunPersistenceLogger.notice(
                "Task run restore found \(report.orphanedCandidateCount, privacy: .public) unavailable candidate worktree(s)"
            )
        }
    }
}
