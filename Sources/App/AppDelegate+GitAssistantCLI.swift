// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+GitAssistantCLI.swift - Socket bridge for `cocxy git-assistant`.

import AppKit
import Foundation

extension AppDelegate {
    // MARK: - Sync bridge called from the socket queue

    nonisolated func handleGitAssistantCLIRequest(
        kind: String,
        params: [String: String]
    ) -> (success: Bool, data: [String: String]) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "Git Assistant dispatch did not complete"]
        ))

        Task.detached { [self] in
            let result = await performGitAssistantCLIRequest(kind: kind, params: params)
            box.withValue { $0 = result }
            semaphore.signal()
        }

        semaphore.wait()
        return box.withValue { $0 }
    }

    // MARK: - Async implementation

    nonisolated func performGitAssistantCLIRequest(
        kind: String,
        params: [String: String]
    ) async -> (Bool, [String: String]) {
        let context = await MainActor.run { () -> GitAssistantCLIContext? in
            guard let directory = self.currentGitHubCLIWorkingDirectory() else { return nil }
            return GitAssistantCLIContext(
                workingDirectory: directory,
                settings: self.configService?.current.gitAssistant ?? .defaults
            )
        }

        guard let context else {
            return (false, ["error": "Open a git repository before using Git Assistant."])
        }
        guard context.settings.enabled else {
            return (
                false,
                ["error": "Git Assistant is disabled. Enable [git-assistant].enabled in config.toml or Preferences > GitHub."]
            )
        }

        do {
            switch kind {
            case "commit-message":
                let diff = try Self.gitOutput(
                    at: context.workingDirectory,
                    arguments: ["diff", "--cached", "--no-color", "--no-ext-diff"]
                )
                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return (false, ["error": "No staged changes found. Stage files before generating a commit message."])
                }
                let client = try makeGitAssistantLLMClient(settings: context.settings)
                let service = DefaultGitAssistantService(client: client)
                let draft = try await service.generateCommitMessage(
                    diff: diff,
                    settings: context.settings
                )
                return (true, ["subject": draft.subject, "body": draft.body])

            case "pr-draft":
                let rawBase = try Self.nonEmptyParam(params["base"])
                    ?? Self.defaultBaseBranch(at: context.workingDirectory)
                let rawHead = try Self.nonEmptyParam(params["head"])
                    ?? Self.currentBranch(at: context.workingDirectory)
                let revisions = try GitAssistantRevisionSelection(
                    base: rawBase,
                    head: rawHead
                )
                let diff = try Self.gitOutput(
                    at: context.workingDirectory,
                    arguments: revisions.diffArguments
                )
                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return (false, ["error": "No branch diff found between \(revisions.base) and \(revisions.head)."])
                }
                let client = try makeGitAssistantLLMClient(settings: context.settings)
                let service = DefaultGitAssistantService(client: client)
                let draft = try await service.generatePullRequestDraft(
                    baseBranch: revisions.base,
                    headBranch: revisions.head,
                    diff: diff,
                    settings: context.settings
                )
                return (true, ["title": draft.title, "body": draft.body])

            case "release-notes":
                let rawBase = try Self.nonEmptyParam(params["base"])
                    ?? Self.defaultBaseBranch(at: context.workingDirectory)
                let rawHead = try Self.nonEmptyParam(params["head"])
                    ?? Self.currentBranch(at: context.workingDirectory)
                let revisions = try GitAssistantRevisionSelection(
                    base: rawBase,
                    head: rawHead
                )
                let commits = try Self.gitLogCommits(
                    at: context.workingDirectory,
                    base: revisions.base,
                    head: revisions.head
                )
                guard !commits.isEmpty else {
                    return (false, ["error": "No commits found between \(revisions.base) and \(revisions.head)."])
                }
                let client = try makeGitAssistantLLMClient(settings: context.settings)
                let service = DefaultGitAssistantService(client: client)
                let draft = try await service.generateReleaseNotes(
                    commits: commits,
                    settings: context.settings
                )
                return (true, ["markdown": draft.markdown])

            default:
                return (false, ["error": "Unknown Git Assistant subcommand: \(kind)"])
            }
        } catch {
            return (false, ["error": gitAssistantErrorMessage(error)])
        }
    }

    // MARK: - Provider construction

    nonisolated private func makeGitAssistantLLMClient(
        settings: GitAssistantSettings
    ) throws -> any AgentLLMClient {
        let config = AgentModeConfig(
            enabled: true,
            preferredProvider: settings.defaultProvider,
            foundationModelsFallback: .requireExplicitChoice,
            autoMode: false,
            computerUseConfirm: true,
            maxIterations: 1
        )
        return try AgentProviderClientFactory().makeClient(configuration: config)
    }

    nonisolated private func gitAssistantErrorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    private struct GitAssistantCLIContext: Sendable {
        let workingDirectory: URL
        let settings: GitAssistantSettings
    }

    // MARK: - Git helpers

    nonisolated static func currentBranch(at directory: URL) throws -> String {
        let raw = try gitOutput(
            at: directory,
            arguments: ["rev-parse", "--abbrev-ref", "HEAD"]
        )
        let branch = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, branch != "HEAD" else {
            throw GitAssistantGitError.detachedHead
        }
        return branch
    }

    nonisolated private static func nonEmptyParam(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    nonisolated static func defaultBaseBranch(at directory: URL) throws -> String {
        if let originHead = try? gitOutput(
            at: directory,
            arguments: ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]
        ) {
            let value = originHead.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return "main"
    }

    nonisolated static func gitLogCommits(
        at directory: URL,
        base: String,
        head: String
    ) throws -> [GitAssistantCommit] {
        let revisions = try GitAssistantRevisionSelection(base: base, head: head)
        let output = try gitOutput(
            at: directory,
            arguments: revisions.logArguments
        )
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> GitAssistantCommit? in
                let parts = line.split(separator: "\u{0}", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                let hash = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !hash.isEmpty, !subject.isEmpty else { return nil }
                return GitAssistantCommit(hash: hash, subject: subject)
            }
    }

    nonisolated static func gitOutput(at directory: URL, arguments: [String]) throws -> String {
        let result = try CodeReviewGit.run(
            workingDirectory: directory,
            arguments: arguments,
            gitExecutableURLOverride: URL(fileURLWithPath: "/usr/bin/git")
        )

        guard result.terminationStatus == 0 else {
            throw GitAssistantGitError.commandFailed(
                command: "git " + arguments.joined(separator: " "),
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                exitCode: result.terminationStatus
            )
        }
        return result.stdout
    }
}

struct GitAssistantRevisionSelection: Equatable, Sendable {
    let base: String
    let head: String
    private let diffRange: String
    private let logRange: String

    init(base: String, head: String) throws {
        let validatedBase = try GitRevisionArgument(base)
        let validatedHead = try GitRevisionArgument(head)
        self.base = validatedBase.value
        self.head = validatedHead.value
        self.diffRange = GitRevisionArgument.range(
            base: validatedBase,
            head: validatedHead,
            kind: .threeDot
        )
        self.logRange = GitRevisionArgument.range(
            base: validatedBase,
            head: validatedHead,
            kind: .twoDot
        )
    }

    var diffArguments: [String] {
        [
            "diff", "--no-color", "--no-ext-diff", "--end-of-options",
            diffRange, "--",
        ]
    }

    var logArguments: [String] {
        [
            "log", "--format=%H%x00%s", "--end-of-options",
            logRange, "--",
        ]
    }
}

enum GitAssistantGitError: Error, Equatable, Sendable {
    case detachedHead
    case commandFailed(command: String, stderr: String, exitCode: Int32)
}

extension GitAssistantGitError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .detachedHead:
            return "Git Assistant cannot infer a head branch while HEAD is detached. Pass --head explicitly."
        case .commandFailed(let command, let stderr, let exitCode):
            let detail = stderr.isEmpty ? "exit \(exitCode)" : stderr
            return "\(command) failed: \(detail)"
        }
    }
}
