// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskCollision.swift - App-scoped collision radar snapshots.

import Foundation

private struct TaskCollisionIntent: Sendable {
    let participant: TaskCollisionParticipant
    let prompts: [String]
    let seedPaths: [String]
}

private struct TaskCollisionAppSnapshot: Sendable {
    let liveWork: [TaskCollisionLiveSession]
    let intents: [TaskCollisionIntent]
}

extension AppDelegate {
    nonisolated func taskLaunchCollisionAnalysis(
        prompt: String,
        seedPaths: [String],
        projectID: ProjectID,
        projectRoot: URL
    ) async -> TaskLaunchCollisionAnalysis {
        let catalogService = await MainActor.run { self.taskFileCatalogService }
        async let projectFiles = catalogService.paths(for: projectRoot)
        async let snapshot = taskCollisionAppSnapshot(
            projectID: projectID,
            excludingRunID: nil
        )
        let (files, appSnapshot) = await (projectFiles, snapshot)
        let inferred = TaskFileInference.infer(
            prompt: prompt,
            projectFiles: files,
            projectRoot: projectRoot,
            seedPaths: seedPaths
        )
        let otherWork = collisionWorkloads(
            appSnapshot.intents,
            projectFiles: files,
            projectRoot: projectRoot
        )
        return TaskLaunchCollisionAnalysis(
            inferredPaths: inferred,
            report: TaskCollisionDetector.beforeLaunch(
                plannedPaths: inferred,
                liveWork: appSnapshot.liveWork,
                otherWork: otherWork,
                projectID: projectID,
                projectRoot: projectRoot
            )
        )
    }

    nonisolated func taskPromotionCollisionInputs(
        projectID: ProjectID,
        projectRoot: URL,
        excludingRunID: String
    ) async -> (
        liveWork: [TaskCollisionLiveSession],
        otherWork: [TaskCollisionWorkload]
    ) {
        let catalogService = await MainActor.run { self.taskFileCatalogService }
        async let projectFiles = catalogService.paths(for: projectRoot, maximumAge: 0)
        async let snapshot = taskCollisionAppSnapshot(
            projectID: projectID,
            excludingRunID: excludingRunID
        )
        let (files, appSnapshot) = await (projectFiles, snapshot)
        return (
            appSnapshot.liveWork,
            collisionWorkloads(
                appSnapshot.intents,
                projectFiles: files,
                projectRoot: projectRoot
            )
        )
    }

    nonisolated private func taskCollisionAppSnapshot(
        projectID: ProjectID,
        excludingRunID: String?
    ) async -> TaskCollisionAppSnapshot {
        let queue = await MainActor.run { self.taskQueue }
        let queueItems = await queue?.list() ?? []
        return await MainActor.run {
            TaskCollisionAppSnapshot(
                liveWork: self.taskRunLiveCollisionSessionsSnapshot(),
                intents: self.taskCollisionIntents(
                    queueItems: queueItems,
                    projectID: projectID,
                    excludingRunID: excludingRunID
                )
            )
        }
    }

    nonisolated private func collisionWorkloads(
        _ intents: [TaskCollisionIntent],
        projectFiles: [String],
        projectRoot: URL
    ) -> [TaskCollisionWorkload] {
        intents.map { intent in
            let inferred = intent.prompts.reduce(into: Set(intent.seedPaths)) { paths, prompt in
                paths.formUnion(TaskFileInference.infer(
                    prompt: prompt,
                    projectFiles: projectFiles,
                    projectRoot: projectRoot
                ))
            }
            return TaskCollisionWorkload(
                participant: intent.participant,
                paths: Array(inferred).sorted()
            )
        }
    }

    @MainActor
    private func taskCollisionIntents(
        queueItems: [TaskQueueItem],
        projectID: ProjectID,
        excludingRunID: String?
    ) -> [TaskCollisionIntent] {
        let queueIntents = queueItems.compactMap { item -> TaskCollisionIntent? in
            guard !item.status.isFinished else { return nil }
            let prompts = item.pipeline.steps.compactMap { step -> String? in
                let locations = [step.project, item.project, step.worktree].compactMap { $0 }
                guard locations.contains(where: {
                    projectIdentity(for: $0) == projectID
                }) else {
                    return nil
                }
                return step.prompt
            }
            guard !prompts.isEmpty else { return nil }
            return TaskCollisionIntent(
                participant: TaskCollisionParticipant(
                    id: "queue:\(item.id)",
                    label: "Queued: \(item.displayName)",
                    kind: .queuedTask
                ),
                prompts: prompts,
                seedPaths: []
            )
        }
        let runIntents = activeTaskRuns.values.compactMap { run -> TaskCollisionIntent? in
            guard run.id != excludingRunID,
                  run.projectID == projectID,
                  !run.status.isFinished else {
                return nil
            }
            return TaskCollisionIntent(
                participant: TaskCollisionParticipant(
                    id: "task-run:\(run.id)",
                    label: "Parallel task \(run.id)",
                    kind: .taskRun
                ),
                prompts: [run.prompt],
                seedPaths: run.candidates.flatMap(\.touchedFiles)
            )
        }
        return queueIntents + runIntents
    }

    @MainActor
    private func projectIdentity(for path: String) -> ProjectID? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NSString(string: trimmed).isAbsolutePath,
              !trimmed.contains("\0") else {
            return nil
        }
        return projectResolver.resolveProject(
            for: URL(fileURLWithPath: trimmed, isDirectory: true)
        ).groupingID
    }

    @MainActor
    private func taskRunLiveCollisionSessionsSnapshot() -> [TaskCollisionLiveSession] {
        taskRunLiveSessionsSnapshot().map { session in
            let tab = allWindowControllers.lazy.compactMap {
                $0.tabManager.tab(for: TabID(rawValue: session.tabId))
            }.first
            return TaskCollisionLiveSession(
                session: session,
                effectiveRoot: tab.map {
                    $0.worktreeRoot ?? projectResolver.resolveProject(
                        for: $0.workingDirectory
                    ).rootURL
                }
                    ?? URL(fileURLWithPath: session.projectIdentity?.rawValue ?? "/", isDirectory: true),
                worktreeID: tab?.worktreeID
            )
        }
    }
}
