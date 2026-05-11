// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BranchCreator.swift - Safe git branch creation wrapper.

import Foundation

struct BranchCreator {
    private let runner: GitCommandRunner

    init(runner: @escaping GitCommandRunner = BranchCreator.defaultRunner) {
        self.runner = runner
    }

    @discardableResult
    func createBranch(
        named rawName: String,
        at workingDirectory: URL,
        startPoint: String? = nil,
        checkout: Bool = true
    ) throws -> GitBranch {
        let branchName = try CodeReviewGitWorkflowService.sanitizedBranchName(rawName)
        let trimmedStartPoint = startPoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = checkout ? ["switch", "-c", branchName] : ["branch", branchName]
        if let trimmedStartPoint, !trimmedStartPoint.isEmpty {
            args.append(trimmedStartPoint)
        }

        let result = try runner(workingDirectory, args)
        guard result.terminationStatus == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HunkActionError.commandFailed(stderr.isEmpty ? "git branch creation failed." : stderr)
        }

        return GitBranch(name: branchName, isCurrent: checkout, isRemote: false)
    }

    private static let defaultRunner: GitCommandRunner = { workingDirectory, args in
        try CodeReviewGit.run(workingDirectory: workingDirectory, arguments: args)
    }
}
