// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunRestorer.swift - Safe reconciliation of persisted runs and worktrees.

import Foundation

struct TaskRunRestorationReport: Sendable, Equatable {
    let runs: [TaskRun]
    let rejectedFiles: [TaskRunStoreRejectedFile]
    let maintenanceFailures: [TaskRunStoreRejectedFile]
    let orphanedCandidateCount: Int
    let interruptedRunCount: Int
    let prunedSnapshotCount: Int
    let reconciledRunIDs: Set<String>
}

struct TaskRunRestorer: Sendable {
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.now = now
    }

    func restore(from store: TaskRunStore) async throws -> TaskRunRestorationReport {
        let loadReport = try store.loadAll()
        var restoredRuns: [TaskRun] = []
        var orphanedCandidateCount = 0
        var interruptedRunCount = 0
        var reconciledRunIDs: Set<String> = []
        for run in loadReport.runs {
            let result = await reconcile(run)
            restoredRuns.append(result.run)
            orphanedCandidateCount += result.orphanedCandidateCount
            interruptedRunCount += result.interruptedRunCount
            if result.run != run {
                reconciledRunIDs.insert(run.id)
            }
        }
        return TaskRunRestorationReport(
            runs: restoredRuns,
            rejectedFiles: loadReport.rejectedFiles,
            maintenanceFailures: loadReport.maintenanceFailures,
            orphanedCandidateCount: orphanedCandidateCount,
            interruptedRunCount: interruptedRunCount,
            prunedSnapshotCount: loadReport.prunedSnapshotCount,
            reconciledRunIDs: reconciledRunIDs
        )
    }

    func reconcile(_ persistedRun: TaskRun) async -> (
        run: TaskRun,
        orphanedCandidateCount: Int,
        interruptedRunCount: Int
    ) {
        var run = persistedRun
        var orphanedCount = 0

        for index in run.candidates.indices where run.candidates[index].worktree == nil {
            guard isTransient(run.candidates[index].status) else { continue }
            markOrphaned(
                &run.candidates[index],
                message: "Worktree was not created before the task was interrupted"
            )
            orphanedCount += 1
        }

        let worktreeIndices = run.candidates.indices.filter {
            run.candidates[$0].worktree != nil
        }
        if !worktreeIndices.isEmpty {
            do {
                let manifest = try await WorktreeManifestStore.forRepo(
                    basePath: run.worktreeBasePath,
                    originRepoPath: run.originRepoPath
                ).load()
                for index in worktreeIndices {
                    guard let persistedEntry = run.candidates[index].worktree else { continue }
                    guard let manifestEntry = manifest.entry(withID: persistedEntry.id),
                          manifestEntry.path.standardizedFileURL
                            == persistedEntry.path.standardizedFileURL,
                          isUsableWorktree(manifestEntry.path) else {
                        markOrphaned(&run.candidates[index])
                        orphanedCount += 1
                        continue
                    }
                    run.candidates[index].worktree = manifestEntry
                    if isTransient(run.candidates[index].status) {
                        run.candidates[index].status = .failed
                        run.candidates[index].failureMessage =
                            "Agent execution was interrupted; the worktree is available for review"
                        run.candidates[index].worktree?.tabID = nil
                    }
                }
            } catch {
                for index in worktreeIndices where run.candidates[index].status != .orphaned {
                    markOrphaned(&run.candidates[index])
                    orphanedCount += 1
                }
            }
        }

        let wasInterrupted = reconcileRunStatus(&run)
        if wasInterrupted {
            run.updatedAt = max(run.updatedAt, now())
        }
        return (run, orphanedCount, wasInterrupted ? 1 : 0)
    }

    private func reconcileRunStatus(_ run: inout TaskRun) -> Bool {
        let reviewableCandidates = run.candidates.filter {
            $0.worktree != nil && $0.status != .orphaned
        }
        switch run.status {
        case .launching:
            run.promotedCandidateID = nil
            run.recoveredFromInterruption = true
            if reviewableCandidates.isEmpty {
                run.status = .failed
                run.failureMessage = "Task launch was interrupted before a candidate became reviewable"
            } else {
                run.status = .running
                run.failureMessage =
                    "Task launch was interrupted; preserved worktrees are available for review"
            }
            run.completionWarning = nil
            return true
        case .running:
            guard !reviewableCandidates.isEmpty else {
                run.status = .failed
                run.recoveredFromInterruption = true
                run.failureMessage = "Task execution was interrupted and no candidate worktree is available"
                run.completionWarning = nil
                return true
            }
            guard !run.recoveredFromInterruption else { return false }
            run.recoveredFromInterruption = true
            run.failureMessage =
                "Task execution was interrupted; preserved worktrees are available for review"
            run.completionWarning = nil
            return true
        case .promoting:
            run.status = .failed
            run.promotedCandidateID = nil
            run.recoveredFromInterruption = true
            run.failureMessage =
                "Task promotion was interrupted; verify the repository state before retrying"
            run.completionWarning = nil
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    private func markOrphaned(
        _ candidate: inout TaskRunCandidate,
        message: String = "Worktree is no longer available"
    ) {
        candidate.status = .orphaned
        candidate.failureMessage = message
        candidate.worktree?.tabID = nil
    }

    private func isTransient(_ status: TaskRunCandidateStatus) -> Bool {
        status == .preparing || status == .running
    }

    private func isUsableWorktree(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                return false
            }
            return fileManager.fileExists(
                atPath: url.appendingPathComponent(".git", isDirectory: false).path
            )
        } catch {
            return false
        }
    }
}
