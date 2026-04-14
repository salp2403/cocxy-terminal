// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HunkActionService.swift - Applies accept/reject hunk actions via git apply.

import Foundation

enum HunkActionError: LocalizedError {
    case gitUnavailable
    case invalidWorkingDirectory
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            return "git is not available on PATH."
        case .invalidWorkingDirectory:
            return "The working directory for the hunk action is invalid."
        case .commandFailed(let message):
            return message
        }
    }
}

enum HunkActionService {
    private static let applyQueue = DispatchQueue(
        label: "dev.cocxy.codereview.hunk-actions",
        qos: .userInitiated
    )

    static func buildPatch(fileDiff: FileDiff, hunk: DiffHunk) -> String {
        let currentPath = fileDiff.filePath
        let oldPath: String
        let newPath: String
        switch fileDiff.status {
        case .added, .untracked:
            oldPath = "/dev/null"
            newPath = gitPatchPath(currentPath, prefix: "b")
        case .deleted:
            oldPath = gitPatchPath(currentPath, prefix: "a")
            newPath = "/dev/null"
        case .renamed:
            // The rename itself is already reflected in the index/worktree state.
            // Hunk actions should only patch the current file contents, not try
            // to replay rename metadata inside `git apply`.
            fallthrough
        case .modified:
            oldPath = gitPatchPath(currentPath, prefix: "a")
            newPath = gitPatchPath(currentPath, prefix: "b")
        }

        let body = hunk.lines.map { line -> String in
            let prefix: String
            switch line.kind {
            case .context: prefix = " "
            case .addition: prefix = "+"
            case .deletion: prefix = "-"
            }
            return prefix + line.content
        }.joined(separator: "\n")

        let patchLines = [
            "diff --git \(gitPatchPath(currentPath, prefix: "a")) \(gitPatchPath(currentPath, prefix: "b"))",
            "--- \(oldPath)",
            "+++ \(newPath)",
            hunk.header,
            body,
            "",
        ]
        return patchLines.joined(separator: "\n")
    }

    static func revertHunk(
        fileDiff: FileDiff,
        hunk: DiffHunk,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        applyPatch(
            buildPatch(fileDiff: fileDiff, hunk: hunk),
            arguments: ["apply", "--reverse", "--recount", "-"],
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    static func acceptHunk(
        fileDiff: FileDiff,
        hunk: DiffHunk,
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        applyPatch(
            buildPatch(fileDiff: fileDiff, hunk: hunk),
            arguments: ["apply", "--cached", "--recount", "-"],
            workingDirectory: workingDirectory,
            completion: completion
        )
    }

    private static func applyPatch(
        _ patch: String,
        arguments: [String],
        workingDirectory: URL,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        applyQueue.async {
            guard FileManager.default.fileExists(atPath: workingDirectory.path) else {
                completion(.failure(HunkActionError.invalidWorkingDirectory))
                return
            }

            do {
                let result = try CodeReviewGit.run(
                    workingDirectory: workingDirectory,
                    arguments: arguments,
                    stdin: patch.data(using: .utf8) ?? Data()
                )

                guard result.terminationStatus == 0 else {
                    let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(HunkActionError.commandFailed(message.isEmpty ? "git apply failed." : message)))
                    return
                }

                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func gitPatchPath(_ path: String, prefix: String) -> String {
        gitQuotedPath("\(prefix)/\(path)")
    }
    private static func gitQuotedPath(_ path: String) -> String {
        guard requiresQuotedGitPath(path) else { return path }

        var escaped = ""
        for scalar in path.unicodeScalars {
            switch scalar {
            case "\"":
                escaped += "\\\""
            case "\\":
                escaped += "\\\\"
            case "\t":
                escaped += "\\t"
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped += String(format: "\\%03o", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }

        return "\"\(escaped)\""
    }

    private static func requiresQuotedGitPath(_ path: String) -> Bool {
        path.unicodeScalars.contains { scalar in
            scalar == "\"" || scalar == "\\" || scalar == "\t" || scalar == "\n" || scalar == "\r" ||
            scalar.value < 0x20 || scalar.value == 0x7F
        }
    }
}
