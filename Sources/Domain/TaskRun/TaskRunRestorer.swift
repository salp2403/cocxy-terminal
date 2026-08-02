// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunRestorer.swift - Safe reconciliation of persisted runs and worktrees.

import Foundation

struct TaskRunRestorationReport: Sendable, Equatable {
    let runs: [TaskRun]
    let rejectedFiles: [TaskRunStoreRejectedFile]
    let orphanedCandidateCount: Int
}

struct TaskRunRestorer: Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func restore(from store: TaskRunStore) async throws -> TaskRunRestorationReport {
        let loadReport = try store.loadAll()
        var restoredRuns: [TaskRun] = []
        var orphanedCandidateCount = 0
        for run in loadReport.runs {
            let result = await reconcile(run)
            restoredRuns.append(result.run)
            orphanedCandidateCount += result.orphanedCandidateCount
        }
        return TaskRunRestorationReport(
            runs: restoredRuns,
            rejectedFiles: loadReport.rejectedFiles,
            orphanedCandidateCount: orphanedCandidateCount
        )
    }

    func reconcile(_ persistedRun: TaskRun) async -> (
        run: TaskRun,
        orphanedCandidateCount: Int
    ) {
        var run = persistedRun
        let manifest: WorktreeManifest
        do {
            manifest = try await WorktreeManifestStore.forRepo(
                basePath: run.worktreeBasePath,
                originRepoPath: run.originRepoPath
            ).load()
        } catch {
            return orphanAllWorktreeCandidates(in: run)
        }

        var orphanedCount = 0
        for index in run.candidates.indices {
            guard let persistedEntry = run.candidates[index].worktree else { continue }
            guard let manifestEntry = manifest.entry(withID: persistedEntry.id),
                  manifestEntry.path.standardizedFileURL == persistedEntry.path.standardizedFileURL,
                  isUsableWorktree(manifestEntry.path) else {
                markOrphaned(&run.candidates[index])
                orphanedCount += 1
                continue
            }
            run.candidates[index].worktree = manifestEntry
        }
        return (run, orphanedCount)
    }

    private func orphanAllWorktreeCandidates(
        in persistedRun: TaskRun
    ) -> (run: TaskRun, orphanedCandidateCount: Int) {
        var run = persistedRun
        var orphanedCount = 0
        for index in run.candidates.indices where run.candidates[index].worktree != nil {
            markOrphaned(&run.candidates[index])
            orphanedCount += 1
        }
        return (run, orphanedCount)
    }

    private func markOrphaned(_ candidate: inout TaskRunCandidate) {
        candidate.status = .orphaned
        candidate.failureMessage = "Worktree is no longer available"
        candidate.worktree?.tabID = nil
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
