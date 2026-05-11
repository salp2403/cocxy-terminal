// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DiffStager.swift - Builds and applies per-hunk staging operations.

import Foundation

enum DiffStagingAction: Sendable, Equatable {
    case stage
    case unstage
    case discard

    var arguments: [String] {
        switch self {
        case .stage:
            return ["apply", "--cached", "--recount", "-"]
        case .unstage:
            return ["apply", "--cached", "--reverse", "--recount", "-"]
        case .discard:
            return ["apply", "--reverse", "--recount", "-"]
        }
    }
}

struct DiffStagingPlan: Equatable, Sendable {
    let action: DiffStagingAction
    let arguments: [String]
    let patch: String

    var stdin: Data {
        Data(patch.utf8)
    }
}

struct DiffStager {
    typealias Runner = (URL, [String], Data) throws -> CodeReviewGitResult

    private let runner: Runner
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        runner: @escaping Runner = { workingDirectory, arguments, stdin in
            try CodeReviewGit.run(
                workingDirectory: workingDirectory,
                arguments: arguments,
                stdin: stdin
            )
        }
    ) {
        self.fileManager = fileManager
        self.runner = runner
    }

    static func plan(
        action: DiffStagingAction,
        fileDiff: FileDiff,
        hunk: DiffHunk
    ) -> DiffStagingPlan {
        DiffStagingPlan(
            action: action,
            arguments: action.arguments,
            patch: HunkActionService.buildPatch(fileDiff: fileDiff, hunk: hunk)
        )
    }

    func perform(
        action: DiffStagingAction,
        fileDiff: FileDiff,
        hunk: DiffHunk,
        workingDirectory: URL
    ) throws {
        guard fileManager.fileExists(atPath: workingDirectory.path) else {
            throw HunkActionError.invalidWorkingDirectory
        }

        let plan = Self.plan(action: action, fileDiff: fileDiff, hunk: hunk)
        let result = try runner(workingDirectory, plan.arguments, plan.stdin)
        guard result.terminationStatus == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HunkActionError.commandFailed(message.isEmpty ? "git apply failed." : message)
        }
    }
}
