// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunComparisonService.swift - Read-only N-way task candidate diffs.

import Foundation

struct TaskRunComparisonService: Sendable {
    typealias GitRunner = @Sendable (URL, [String]) throws -> CodeReviewGitResult

    private let gitRunner: GitRunner
    private static let gitSafetyOverrides = [
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.fsmonitor=false",
    ]

    init(gitRunner: @escaping GitRunner = { directory, arguments in
        try CodeReviewGit.run(workingDirectory: directory, arguments: arguments)
    }) {
        self.gitRunner = gitRunner
    }

    func load(run: TaskRun) throws -> [TaskRunCandidateComparison] {
        try run.candidates.compactMap { candidate in
            guard candidate.status != .orphaned,
                  let worktree = candidate.worktree else { return nil }
            return TaskRunCandidateComparison(
                candidate: candidate,
                diffs: try loadDiffs(
                    workingDirectory: worktree.path,
                    baseCommit: run.baseCommit
                )
            )
        }
    }

    func loadDiffs(
        workingDirectory: URL,
        baseCommit: String
    ) throws -> [FileDiff] {
        let diffResult = try gitRunner(workingDirectory, Self.gitSafetyOverrides + [
            "diff", "--no-color", "--no-ext-diff",
            "--no-textconv",
            "--end-of-options", baseCommit, "--", ".",
        ])
        guard diffResult.terminationStatus == 0 else {
            throw WorktreeServiceError.gitCommandFailed(
                command: "git diff \(baseCommit) -- .",
                stderr: diffResult.stderr,
                exitCode: diffResult.terminationStatus
            )
        }

        let statusResult = try gitRunner(
            workingDirectory,
            Self.gitSafetyOverrides + ["status", "--porcelain"]
        )
        guard statusResult.terminationStatus == 0 else {
            throw WorktreeServiceError.gitCommandFailed(
                command: "git status --porcelain",
                stderr: statusResult.stderr,
                exitCode: statusResult.terminationStatus
            )
        }

        var statusByPath: [String: FileStatus] = [:]
        for entry in DiffParser.parseStatus(statusResult.stdout) {
            statusByPath[entry.path] = mergeStatus(
                statusByPath[entry.path],
                entry.status
            )
        }

        var diffs = DiffParser.parse(diffResult.stdout).map { diff in
            FileDiff(
                filePath: diff.filePath,
                originalFilePath: diff.originalFilePath,
                status: statusByPath[diff.filePath] ?? diff.status,
                hunks: diff.hunks,
                agentName: diff.agentName,
                reviewNote: diff.reviewNote
            )
        }

        let existingPaths = Set(diffs.map(\.filePath))
        let fileAccess = try CodeReviewWorkspaceFileAccess(rootURL: workingDirectory)
        for (path, status) in statusByPath where !existingPaths.contains(path) {
            guard status == .untracked || status == .added,
                  let snapshot = try? fileAccess.read(relativePath: path) else {
                continue
            }
            let synthetic = DiffParser.makeSyntheticAddedFileDiff(
                filePath: path,
                fileContent: snapshot.content
            )
            diffs.append(FileDiff(
                filePath: synthetic.filePath,
                status: status,
                hunks: synthetic.hunks
            ))
        }

        return diffs.sorted { lhs, rhs in
            if lhs.status.sortRank != rhs.status.sortRank {
                return lhs.status.sortRank < rhs.status.sortRank
            }
            return lhs.filePath.localizedStandardCompare(rhs.filePath) == .orderedAscending
        }
    }

    private func mergeStatus(_ existing: FileStatus?, _ incoming: FileStatus) -> FileStatus {
        guard let existing else { return incoming }
        return statusPriority(incoming) >= statusPriority(existing) ? incoming : existing
    }

    private func statusPriority(_ status: FileStatus) -> Int {
        switch status {
        case .modified: return 0
        case .added: return 1
        case .untracked: return 2
        case .deleted: return 3
        case .renamed: return 4
        }
    }
}
