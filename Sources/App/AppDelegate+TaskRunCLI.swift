// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskRunCLI.swift - Parallel task orchestration and promotion.

import Foundation

struct TaskRunLaunchContext: Sendable, Equatable {
    let worktreeConfig: WorktreeConfig
    let originRepoPath: URL
    let windowID: WindowID
    let sourceTabID: TabID
    let approvedWorkingDirectory: String
}

struct TaskRunPromotionOutcome: Sendable, Equatable {
    let run: TaskRun
    let gitResult: WorktreePromotionResult
    let cleanupFailures: [String]
}

enum TaskRunExecutionError: Error, Sendable, Equatable, CustomStringConvertible {
    case targetUnavailable
    case featureDisabled
    case duplicateRun(String)
    case launchFailed(reason: String, rollbackFailures: [String])
    case promotionUnavailable(String)
    case cancelled(String)

    var description: String {
        switch self {
        case .targetUnavailable:
            return "The approved task target is no longer available"
        case .featureDisabled:
            return AppDelegate.worktreeEnablementErrorMessage
        case .duplicateRun(let runID):
            return "Task run is already registered: \(runID)"
        case .launchFailed(let reason, let rollbackFailures):
            guard !rollbackFailures.isEmpty else {
                return "Task run launch failed and was rolled back: \(reason)"
            }
            return "Task run launch failed: \(reason). Rollback needs attention: \(rollbackFailures.joined(separator: "; "))"
        case .promotionUnavailable(let reason):
            return "Task candidate cannot be promoted: \(reason)"
        case .cancelled(let runID):
            return "Task run was cancelled: \(runID)"
        }
    }
}

extension AppDelegate {
    nonisolated func performTaskRunLaunch(
        request: TaskRunRequest,
        context: TaskRunLaunchContext
    ) async throws -> TaskRun {
        guard context.worktreeConfig.enabled else {
            throw TaskRunExecutionError.featureDisabled
        }
        guard await MainActor.run(body: { self.taskRunController(for: context) != nil }) else {
            throw TaskRunExecutionError.targetUnavailable
        }

        let originRepoPath = Self.resolveOriginRepoRoot(from: context.originRepoPath)
        let service = await worktreeServiceSnapshot()
        let baseCommit = try await service.revision(request.baseRef, at: originRepoPath)
        var run = TaskRun(
            id: "task-\(UUID().uuidString.lowercased())",
            request: request,
            originRepoPath: originRepoPath,
            baseCommit: baseCommit,
            worktreeBasePath: context.worktreeConfig.basePath
        )

        // Resolve every provider executable before creating the first worktree.
        let launchPlans = try await TaskRunAgentLaunchPlan.make(
            run: run,
            preflightWorkingDirectory: originRepoPath
        )
        do {
            try await persistTaskRunImmediately(run)
        } catch {
            throw TaskRunExecutionError.launchFailed(
                reason: "Task run could not be saved before worktree creation: \(error)",
                rollbackFailures: []
            )
        }
        let registered = await registerTaskRunSnapshot(
            run,
            fallbackTabID: context.sourceTabID.rawValue,
            persist: false
        )
        guard registered else {
            throw TaskRunExecutionError.duplicateRun(run.id)
        }

        let taskConfig = WorktreeConfig(
            enabled: true,
            basePath: context.worktreeConfig.basePath,
            branchTemplate: context.worktreeConfig.branchTemplate,
            baseRef: baseCommit,
            onClose: .keep,
            openInNewTab: true,
            idLength: context.worktreeConfig.idLength,
            inheritProjectConfig: context.worktreeConfig.inheritProjectConfig,
            showBadge: context.worktreeConfig.showBadge
        )
        let store = WorktreeManifestStore.forRepo(
            basePath: taskConfig.basePath,
            originRepoPath: originRepoPath
        )

        do {
            for index in run.candidates.indices {
                try await requireTaskRunLaunchActive(run.id)
                let candidate = run.candidates[index]
                let entry = try await service.add(
                    originRepoPath: originRepoPath,
                    agent: candidate.provider.rawValue,
                    tabID: nil,
                    config: taskConfig,
                    store: store
                )
                try run.updateCandidate(id: candidate.id) {
                    $0.worktree = entry
                }
                run = await publishTaskRunSnapshot(
                    run,
                    fallbackTabID: context.sourceTabID.rawValue
                )
                try requireTaskRunLaunchActive(run)
            }

            for plan in launchPlans {
                try await requireTaskRunLaunchActive(run.id)
                guard let candidate = run.candidates.first(where: { $0.id == plan.candidateID }),
                      var entry = candidate.worktree else {
                    throw TaskRunError.candidateNotFound(plan.candidateID)
                }
                let entrySnapshot = entry
                let runID = run.id
                let tabID = try await MainActor.run { () throws -> TabID in
                    try self.performTaskRunLaunchEffect(runID: runID) { _ in
                        guard let controller = self.taskRunController(for: context) else {
                            throw TaskRunExecutionError.targetUnavailable
                        }
                        let launch = try self.launchAgentTeamConfig(
                            plan.config,
                            controller: controller,
                            targetTabID: context.sourceTabID.rawValue,
                            workingDirectory: entrySnapshot.path.path,
                            persistSnapshot: false,
                            syncDashboard: false
                        )
                        guard launch.tabIDs.count == 1, let tabID = launch.tabIDs.first else {
                            throw AgentTeamError.paneLaunchFailed(plan.config.id)
                        }
                        controller.attachWorktree(
                            entrySnapshot,
                            originRepo: originRepoPath,
                            to: tabID
                        )
                        self.taskRunIDByTeamID[plan.config.id] = runID
                        return tabID
                    }
                }
                try await requireTaskRunLaunchActive(run.id)

                entry.tabID = tabID
                try await store.upsert(entry)
                try run.updateCandidate(id: candidate.id) {
                    $0.worktree = entry
                    $0.status = .running
                    $0.failureMessage = nil
                }
                run = await publishTaskRunSnapshot(
                    run,
                    fallbackTabID: context.sourceTabID.rawValue
                )
                try requireTaskRunLaunchActive(run)
            }

            run.markRunning()
            run = await publishTaskRunSnapshot(
                run,
                fallbackTabID: context.sourceTabID.rawValue
            )
            try requireTaskRunLaunchActive(run)
            let runID = run.id
            let registeredRun = try await MainActor.run {
                try self.performTaskRunLaunchEffect(runID: runID) { activeRun in
                    _ = try self.registerTaskOrchestrationSession(for: activeRun)
                    return activeRun
                }
            }
            return registeredRun
        } catch {
            if let executionError = error as? TaskRunExecutionError,
               case .cancelled = executionError {
                await stopCancelledTaskRunRuntimes(run)
                throw executionError
            }
            let rollback = await rollbackTaskRunLaunch(
                run: run,
                reason: String(describing: error),
                context: context,
                store: store,
                service: service
            )
            throw TaskRunExecutionError.launchFailed(
                reason: String(describing: error),
                rollbackFailures: rollback.failures
            )
        }
    }

    nonisolated func taskRunComparisons(
        runID rawRunID: String
    ) async throws -> [TaskRunCandidateComparison] {
        let runID = AgentTeamConfig.slug(rawRunID)
        guard let run = await MainActor.run(body: { self.activeTaskRuns[runID] }) else {
            throw TaskRunError.runNotFound(runID)
        }
        return try await Task.detached {
            try TaskRunComparisonService().load(run: run)
        }.value
    }

    nonisolated func promoteTaskRun(
        runID rawRunID: String,
        candidateID rawCandidateID: String
    ) async throws -> TaskRunPromotionOutcome {
        let preview = try await prepareTaskRunPromotion(
            runID: rawRunID,
            candidateID: rawCandidateID
        )
        return try await executeTaskRunPromotion(preview)
    }

    @MainActor
    func updateTaskRunCandidate(
        taskRunID: String,
        teamID: String,
        from teamRun: AgentTeamRunState
    ) {
        guard var run = activeTaskRuns[taskRunID], run.status == .running else {
            return
        }
        let teammateStatuses = teamRun.coordinator.teammateStates.map(\.status)
        let candidateStatus: TaskRunCandidateStatus
        if teammateStatuses.contains(.error) {
            candidateStatus = .failed
        } else if !teammateStatuses.isEmpty,
                  teammateStatuses.allSatisfy({ $0 == .finished }) {
            candidateStatus = .finished
        } else {
            candidateStatus = .running
        }
        guard let candidateID = run.candidates.first(where: { $0.teamID == teamID })?.id else {
            return
        }
        let changed = (try? run.updateCandidate(id: candidateID) {
            $0.status = candidateStatus
            $0.failureMessage = candidateStatus == .failed ? "Provider reported an error" : nil
        }) ?? false
        guard changed else { return }
        publishTaskRun(
            run,
            fallbackTabID: run.candidates.compactMap(\.worktree?.tabID?.rawValue).first ?? UUID()
        )
    }

    @MainActor
    func markTaskRunCandidateStopped(
        taskRunID: String,
        teamID: String,
        reason: String
    ) {
        guard var run = activeTaskRuns[taskRunID],
              run.status == .launching || run.status == .running,
              let candidateID = run.candidates.first(where: { $0.teamID == teamID })?.id else {
            return
        }
        _ = try? run.updateCandidate(id: candidateID) {
            $0.status = .failed
            $0.failureMessage = reason
        }
        if run.candidates.allSatisfy({ $0.status == .failed }) {
            run.markFailed(reason)
            taskOrchestrationSessionManager.revoke(runID: run.id)
        }
        publishTaskRun(
            run,
            fallbackTabID: run.candidates.compactMap(\.worktree?.tabID?.rawValue).first ?? UUID()
        )
    }

    @MainActor
    func handleTaskRunTabClosed(_ tabID: TabID) {
        for (runID, storedRun) in activeTaskRuns {
            guard storedRun.status == .launching || storedRun.status == .running else {
                continue
            }
            let candidate = storedRun.candidates.first(where: { candidate in
                let isActive = candidate.status == TaskRunCandidateStatus.preparing
                    || candidate.status == TaskRunCandidateStatus.running
                return isActive && candidate.worktree?.tabID == tabID
            })
            guard let candidate else {
                continue
            }
            activeAgentTeamCoordinators.removeValue(forKey: candidate.teamID)
            activeAgentTeamRuns.removeValue(forKey: candidate.teamID)
            taskRunIDByTeamID.removeValue(forKey: candidate.teamID)
            markTaskRunCandidateStopped(
                taskRunID: runID,
                teamID: candidate.teamID,
                reason: "Terminal tab closed"
            )
            return
        }
    }

    @MainActor
    func taskRunsSnapshot() -> [TaskRun] {
        activeTaskRuns.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    @MainActor
    private func registerTaskOrchestrationSession(
        for run: TaskRun
    ) throws -> TaskOrchestrationSessionCredential {
        let tabIDs = Set(run.candidates.compactMap(\.worktree?.tabID?.rawValue))
        return try taskOrchestrationSessionManager.issue(
            runID: run.id,
            tabIDs: tabIDs
        )
    }

    @MainActor
    func makeTaskRunLaunchContext(
        controller: MainWindowController,
        tab: Tab
    ) -> TaskRunLaunchContext? {
        guard let config = configService?.current else { return nil }
        let effectiveConfig = Self.effectiveWorktreeCLIConfig(
            globalConfig: config,
            projectConfig: tab.projectConfig
        )
        return TaskRunLaunchContext(
            worktreeConfig: effectiveConfig.worktree,
            originRepoPath: tab.worktreeOriginRepo ?? tab.workingDirectory,
            windowID: controller.windowID,
            sourceTabID: tab.id,
            approvedWorkingDirectory: canonicalTaskRunWorkingDirectory(for: tab)
        )
    }

    @MainActor
    func taskRunController(
        for context: TaskRunLaunchContext
    ) -> MainWindowController? {
        guard let controller = allWindowControllers.first(where: { $0.windowID == context.windowID }),
              let tab = controller.tabManager.tab(for: context.sourceTabID),
              canonicalTaskRunWorkingDirectory(for: tab) == context.approvedWorkingDirectory else {
            return nil
        }
        return controller
    }

    @MainActor
    func canonicalTaskRunWorkingDirectory(for tab: Tab) -> String {
        (tab.worktreeRoot ?? tab.workingDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
    }

    @MainActor
    @discardableResult
    func publishTaskRun(
        _ proposedRun: TaskRun,
        fallbackTabID: UUID,
        persist: Bool = true
    ) -> TaskRun {
        let run = taskRunSnapshotForPublication(proposedRun)
        activeTaskRuns[run.id] = run
        taskInboxStore.updateTaskRuns(Array(activeTaskRuns.values))
        if persist {
            taskRunPersistenceCoordinator?.enqueue(run)
        }
        agentDashboardViewModel?.syncTaskRun(run, fallbackTabId: fallbackTabID)
        for controller in allWindowControllers {
            guard controller.dashboardViewModel !== agentDashboardViewModel else { continue }
            controller.dashboardViewModel?.syncTaskRun(run, fallbackTabId: fallbackTabID)
        }
        return run
    }

    @MainActor
    private func taskRunSnapshotForPublication(_ proposedRun: TaskRun) -> TaskRun {
        guard var current = activeTaskRuns[proposedRun.id],
              current.status == .cancelled,
              proposedRun.status != .cancelled else {
            return proposedRun
        }
        for proposedCandidate in proposedRun.candidates {
            guard let index = current.candidates.firstIndex(where: {
                $0.id == proposedCandidate.id
            }) else { continue }
            if current.candidates[index].worktree == nil {
                current.candidates[index].worktree = proposedCandidate.worktree
                current.candidates[index].worktree?.tabID = nil
            }
            current.candidates[index].touchedFiles = Array(Set(
                current.candidates[index].touchedFiles + proposedCandidate.touchedFiles
            )).sorted()
        }
        return current
    }

    nonisolated private func requireTaskRunLaunchActive(_ runID: String) async throws {
        let run = await MainActor.run { self.activeTaskRuns[runID] }
        guard let run else { throw TaskRunError.runNotFound(runID) }
        try requireTaskRunLaunchActive(run)
    }

    nonisolated private func requireTaskRunLaunchActive(_ run: TaskRun) throws {
        if run.status == .cancelled {
            throw TaskRunExecutionError.cancelled(run.id)
        }
        guard run.status == .launching || run.status == .running else {
            throw TaskRunExecutionError.launchFailed(
                reason: "Task run changed to \(run.status.rawValue) during launch",
                rollbackFailures: []
            )
        }
    }

    @MainActor
    func performTaskRunLaunchEffect<T>(
        runID: String,
        _ effect: (TaskRun) throws -> T
    ) throws -> T {
        guard let current = activeTaskRuns[runID] else {
            throw TaskRunError.runNotFound(runID)
        }
        try requireTaskRunLaunchActive(current)
        return try effect(current)
    }

    nonisolated private func stopCancelledTaskRunRuntimes(_ run: TaskRun) async {
        await MainActor.run {
            self.taskOrchestrationSessionManager.revoke(runID: run.id)
            for candidate in run.candidates {
                _ = self.removeAgentTeamRuntime(
                    teamID: candidate.teamID,
                    worktreeClosePolicyOverride: .keep,
                    removeDashboardRow: false
                )
            }
        }
    }

    nonisolated private func rollbackTaskRunLaunch(
        run originalRun: TaskRun,
        reason: String,
        context: TaskRunLaunchContext,
        store: WorktreeManifestStore,
        service: WorktreeService
    ) async -> (run: TaskRun, failures: [String]) {
        var run = originalRun
        for candidate in run.candidates {
            _ = try? run.updateCandidate(id: candidate.id) {
                $0.status = .failed
                $0.failureMessage = reason
            }
        }
        run.markFailed(reason)
        await publishTaskRunSnapshot(
            run,
            fallbackTabID: context.sourceTabID.rawValue
        )
        let candidatesToStop = run.candidates
        await MainActor.run {
            for candidate in candidatesToStop {
                _ = self.removeAgentTeamRuntime(
                    teamID: candidate.teamID,
                    worktreeClosePolicyOverride: .keep,
                    removeDashboardRow: false
                )
            }
        }

        var failures: [String] = []
        for candidate in run.candidates.reversed() {
            guard let entry = candidate.worktree else { continue }
            do {
                _ = try await service.remove(
                    id: entry.id,
                    force: true,
                    originRepoPath: run.originRepoPath,
                    store: store
                )
                _ = try? run.updateCandidate(id: candidate.id) { $0.worktree = nil }
            } catch {
                failures.append("\(entry.id): \(error)")
            }
        }
        if !failures.isEmpty {
            run.failureMessage = "\(reason). Rollback needs attention: \(failures.joined(separator: "; "))"
        }
        await publishTaskRunSnapshot(
            run,
            fallbackTabID: context.sourceTabID.rawValue
        )
        return (run, failures)
    }

    nonisolated private func registerTaskRunSnapshot(
        _ run: TaskRun,
        fallbackTabID: UUID,
        persist: Bool = true
    ) async -> Bool {
        await MainActor.run {
            guard self.activeTaskRuns[run.id] == nil else { return false }
            self.publishTaskRun(run, fallbackTabID: fallbackTabID, persist: persist)
            return true
        }
    }

    @discardableResult
    nonisolated private func publishTaskRunSnapshot(
        _ run: TaskRun,
        fallbackTabID: UUID
    ) async -> TaskRun {
        await MainActor.run {
            self.publishTaskRun(run, fallbackTabID: fallbackTabID)
        }
    }
}
