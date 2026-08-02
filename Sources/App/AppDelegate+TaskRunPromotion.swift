// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskRunPromotion.swift - Previewed, stale-safe task promotion.

import Foundation

extension AppDelegate {
    nonisolated func prepareTaskRunPromotion(
        runID rawRunID: String,
        candidateID rawCandidateID: String
    ) async throws -> TaskRunPromotionPreview {
        let runID = AgentTeamConfig.slug(rawRunID)
        let candidateID = AgentTeamConfig.slug(rawCandidateID)
        guard var run = await MainActor.run(body: { self.activeTaskRuns[runID] }) else {
            throw TaskRunError.runNotFound(runID)
        }
        guard let candidate = run.candidates.first(where: { $0.id == candidateID }),
              let selectedEntry = candidate.worktree else {
            throw TaskRunError.candidateNotFound(candidateID)
        }
        guard candidate.status != .orphaned else {
            throw TaskRunExecutionError.promotionUnavailable(
                "candidate \(candidateID) has no available worktree"
            )
        }
        guard run.status == .running else {
            throw TaskRunExecutionError.promotionUnavailable(
                "task run \(run.id) is \(run.status.rawValue)"
            )
        }
        let originalComparisons = try await loadTaskRunComparisons(run)
        var changedMetadata = false
        for comparison in originalComparisons {
            let touchedFiles = TaskCollisionDetector.normalize(
                comparison.diffs.map(\.filePath) + comparison.candidate.touchedFiles,
                projectRoot: run.originRepoPath
            ).sorted()
            guard comparison.candidate.touchedFiles != touchedFiles else { continue }
            try run.updateCandidate(id: comparison.candidate.id) {
                $0.touchedFiles = touchedFiles
            }
            changedMetadata = true
        }
        if changedMetadata {
            let fallbackTabID = run.candidates.compactMap(\.worktree?.tabID?.rawValue).first ?? UUID()
            await publishTaskRunPromotionSnapshot(run, fallbackTabID: fallbackTabID)
        }

        let comparisons = originalComparisons.compactMap { comparison in
            run.candidates.first(where: { $0.id == comparison.id }).map {
                TaskRunCandidateComparison(candidate: $0, diffs: comparison.diffs)
            }
        }
        guard let selectedComparison = comparisons.first(where: { $0.id == candidateID }) else {
            throw TaskRunError.candidateNotFound(candidateID)
        }

        let service = await worktreeServiceSnapshot()
        let store = taskRunManifestStore(for: run)
        try await service.validatePromotionOrigin(
            originRepoPath: run.originRepoPath,
            expectedBaseCommit: run.baseCommit
        )
        let manifestEntries = try await service.list(store: store)
        guard manifestEntries.contains(where: { $0.id == selectedEntry.id }) else {
            throw TaskRunExecutionError.promotionUnavailable(
                "candidate \(candidateID) is no longer managed"
            )
        }
        let runWorktreeIDs = Set(run.candidates.compactMap(\.worktree?.id))
        let mergedPlan = try await service.mergedCleanupPlan(
            originRepoPath: run.originRepoPath,
            baseRef: selectedEntry.branch,
            force: true,
            restrictingToIDs: runWorktreeIDs,
            store: store
        )
        let cleanupEntries = try TaskRunPromotionPlanner.cleanupEntries(
            run: run,
            selectedCandidateID: candidateID,
            manifestEntries: manifestEntries,
            mergedPlan: mergedPlan
        )
        let excludedRuntimeIDs = Set(run.candidates.flatMap { [$0.id, $0.teamID] })
        let dashboardSessions = await MainActor.run { self.taskCollisionSessionsSnapshot() }
        let collisionReport = TaskCollisionDetector.beforePromotion(
            candidate: selectedComparison,
            liveSessions: dashboardSessions,
            projectID: run.projectID,
            projectRoot: run.originRepoPath,
            excludingIDs: excludedRuntimeIDs
        )
        return TaskRunPromotionPreview(
            run: run,
            selectedComparison: selectedComparison,
            collisionReport: collisionReport,
            mergedCleanupPlan: mergedPlan,
            cleanupEntries: cleanupEntries
        )
    }

    nonisolated func executeTaskRunPromotion(
        _ preview: TaskRunPromotionPreview
    ) async throws -> TaskRunPromotionOutcome {
        guard var run = await MainActor.run(body: {
            self.activeTaskRuns[preview.run.id]
        }) else {
            throw TaskRunError.runNotFound(preview.run.id)
        }
        guard run == preview.run else {
            throw stalePromotionError()
        }
        let candidateID = preview.selectedCandidateID
        guard let candidate = run.candidates.first(where: { $0.id == candidateID }),
              let selectedEntry = candidate.worktree else {
            throw TaskRunError.candidateNotFound(candidateID)
        }
        let freshComparisons = try await loadTaskRunComparisons(run)
        guard freshComparisons.first(where: { $0.id == candidateID }) == preview.selectedComparison else {
            throw stalePromotionError()
        }
        let dashboardSessions = await MainActor.run { self.taskCollisionSessionsSnapshot() }
        let excludedRuntimeIDs = Set(run.candidates.flatMap { [$0.id, $0.teamID] })
        let freshCollisionReport = TaskCollisionDetector.beforePromotion(
            candidate: preview.selectedComparison,
            liveSessions: dashboardSessions,
            projectID: run.projectID,
            projectRoot: run.originRepoPath,
            excludingIDs: excludedRuntimeIDs
        )
        guard freshCollisionReport == preview.collisionReport else {
            throw stalePromotionError()
        }

        let service = await worktreeServiceSnapshot()
        let store = taskRunManifestStore(for: run)
        try await service.validatePromotionOrigin(
            originRepoPath: run.originRepoPath,
            expectedBaseCommit: run.baseCommit
        )
        let currentManifest = try await service.list(store: store)
        let currentByID = Dictionary(
            currentManifest.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let approvedEntries = preview.cleanupEntries.map(\.worktree)
        guard approvedEntries.contains(where: { $0.id == selectedEntry.id }),
              approvedEntries.allSatisfy({ currentByID[$0.id] == $0 }) else {
            throw stalePromotionError()
        }

        try run.markPromoting(candidateID: candidateID)
        let fallbackTabID = selectedEntry.tabID?.rawValue ?? UUID()
        await publishTaskRunPromotionSnapshot(run, fallbackTabID: fallbackTabID)
        await MainActor.run {
            _ = self.removeAgentTeamRuntime(
                teamID: candidate.teamID,
                worktreeClosePolicyOverride: .keep,
                removeDashboardRow: false
            )
        }

        let gitResult: WorktreePromotionResult
        do {
            gitResult = try await service.promote(
                id: selectedEntry.id,
                originRepoPath: run.originRepoPath,
                expectedBaseCommit: run.baseCommit,
                commitMessage: "Apply task candidate \(candidateID)",
                store: store
            )
        } catch {
            try await recoverFailedTaskRunPromotion(
                error,
                run: &run,
                candidateID: candidateID,
                fallbackTabID: fallbackTabID,
                store: store
            )
            throw error
        }

        let otherCandidates = run.candidates.filter { $0.id != candidateID }
        await MainActor.run {
            for taskCandidate in otherCandidates {
                _ = self.removeAgentTeamRuntime(
                    teamID: taskCandidate.teamID,
                    worktreeClosePolicyOverride: .keep,
                    removeDashboardRow: false
                )
            }
        }
        let cleanupFailures = await executeConfirmedTaskRunCleanup(
            preview: preview,
            service: service,
            store: store
        )
        let warning = cleanupFailures.isEmpty
            ? nil
            : "Winner merged; some worktree directories still need cleanup"
        try run.markCompleted(candidateID: candidateID, warning: warning)
        let completedRunID = run.id
        await MainActor.run {
            self.taskOrchestrationSessionManager.revoke(runID: completedRunID)
        }
        await publishTaskRunPromotionSnapshot(run, fallbackTabID: fallbackTabID)
        return TaskRunPromotionOutcome(
            run: run,
            gitResult: gitResult,
            cleanupFailures: cleanupFailures
        )
    }

    nonisolated private func executeConfirmedTaskRunCleanup(
        preview: TaskRunPromotionPreview,
        service: WorktreeService,
        store: WorktreeManifestStore
    ) async -> [String] {
        var failures: [String] = []
        let merged = preview.cleanupEntries.filter { $0.disposition == .removeMerged }
        if let winner = merged.first {
            do {
                let result = try await service.cleanupMergedWorktrees(
                    originRepoPath: preview.run.originRepoPath,
                    baseRef: "HEAD",
                    force: false,
                    restrictingToIDs: [winner.worktree.id],
                    store: store
                )
                if !result.removed.contains(where: { $0.id == winner.worktree.id }) {
                    failures.append("\(winner.worktree.id): retained by cleanup plan")
                }
            } catch {
                failures.append("\(winner.worktree.id): \(error)")
            }
        } else if let winner = preview.cleanupEntries.first(where: {
            $0.disposition == .retainWinner
        }) {
            failures.append("\(winner.worktree.id): retained by cleanup plan")
        }

        for entry in preview.cleanupEntries.reversed()
            where entry.disposition == .discardCandidate {
            do {
                _ = try await service.remove(
                    id: entry.worktree.id,
                    force: true,
                    originRepoPath: preview.run.originRepoPath,
                    store: store
                )
            } catch {
                failures.append("\(entry.worktree.id): \(error)")
            }
        }
        return failures
    }

    nonisolated private func recoverFailedTaskRunPromotion(
        _ error: Error,
        run: inout TaskRun,
        candidateID: String,
        fallbackTabID: UUID,
        store: WorktreeManifestStore
    ) async throws {
        run.markPromotionFailed(candidateID: candidateID, message: String(describing: error))
        if let detachedEntry = run.candidates.first(where: { $0.id == candidateID })?.worktree {
            do {
                try await store.upsert(detachedEntry)
            } catch {
                let primary = run.failureMessage ?? "Promotion failed"
                run.failureMessage = "\(primary). Worktree metadata update failed: \(error)"
            }
        }
        let recoveryTabID = run.candidates.compactMap(\.worktree?.tabID?.rawValue).first
            ?? fallbackTabID
        await publishTaskRunPromotionSnapshot(run, fallbackTabID: recoveryTabID)
    }

    nonisolated private func loadTaskRunComparisons(
        _ run: TaskRun
    ) async throws -> [TaskRunCandidateComparison] {
        try await Task.detached { try TaskRunComparisonService().load(run: run) }.value
    }

    nonisolated private func taskRunManifestStore(for run: TaskRun) -> WorktreeManifestStore {
        WorktreeManifestStore.forRepo(
            basePath: run.worktreeBasePath,
            originRepoPath: run.originRepoPath
        )
    }

    nonisolated private func publishTaskRunPromotionSnapshot(
        _ run: TaskRun,
        fallbackTabID: UUID
    ) async {
        await MainActor.run {
            self.publishTaskRun(run, fallbackTabID: fallbackTabID)
        }
    }

    nonisolated private func stalePromotionError() -> TaskRunExecutionError {
        .promotionUnavailable("the task changed; refresh the cleanup preview")
    }

    @MainActor
    private func taskCollisionSessionsSnapshot() -> [AgentSessionInfo] {
        var sessions = agentDashboardViewModel?.sessions ?? []
        for controller in allWindowControllers {
            guard let model = controller.dashboardViewModel,
                  model !== agentDashboardViewModel else { continue }
            sessions.append(contentsOf: model.sessions)
        }
        let grouped = Dictionary(grouping: sessions) {
            "\($0.projectIdentity?.rawValue ?? ""):\($0.id):\($0.tabId.uuidString)"
        }
        return grouped.values.compactMap { values in
            values.max { ($0.lastActivityTime ?? .distantPast) < ($1.lastActivityTime ?? .distantPast) }
        }
    }
}
