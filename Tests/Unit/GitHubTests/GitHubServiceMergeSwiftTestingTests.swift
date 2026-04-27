// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubServiceMergeSwiftTestingTests.swift - Tests for the
// `pullRequestMergeability` and `mergePullRequest` actor methods
// shipped in v0.1.86.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitHubService.merge")
struct GitHubServiceMergeSwiftTestingTests {

    // MARK: - Runner spy

    /// Thread-safe stub for `GitHubService.Runner`. Records every
    /// invocation and returns the first stub whose predicate matches
    /// the args. Mirrors the spy in `GitHubServiceSwiftTestingTests`
    /// so the two suites can be audited side-by-side.
    final class RunnerSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var invocations: [(directory: URL, args: [String], timeout: TimeInterval)] = []
        private var stubs: [(predicate: @Sendable ([String]) -> Bool, result: GitHubCLIResult)] = []

        func stub(
            matching predicate: @escaping @Sendable ([String]) -> Bool,
            result: GitHubCLIResult
        ) {
            lock.lock()
            stubs.append((predicate, result))
            lock.unlock()
        }

        var runner: GitHubService.Runner {
            return { [self] directory, args, timeout in
                self.lock.lock()
                self.invocations.append((directory, args, timeout))
                let stubs = self.stubs
                self.lock.unlock()
                for stub in stubs where stub.predicate(args) {
                    return stub.result
                }
                return GitHubCLIResult(
                    stdout: "",
                    stderr: "no stub matched for args: \(args)",
                    terminationStatus: 1
                )
            }
        }

        var allInvocations: [(directory: URL, args: [String], timeout: TimeInterval)] {
            lock.lock()
            defer { lock.unlock() }
            return invocations
        }
    }

    // MARK: - Fixtures

    private static let workingDirectory = URL(fileURLWithPath: "/tmp/repo")

    /// Successful `gh pr merge` stdout for a synchronous merge. The
    /// real CLI prints a one-liner like this; we keep the fixture small
    /// because the service does not parse it — the follow-up `gh pr
    /// view` is the source of truth.
    private static let mergeSuccessStdout = """
    ✓ Merged pull request #42 (Squash and merge)
    """

    /// JSON returned by `gh pr view <n> --json …` after a successful
    /// merge. Reused across tests so the structure stays consistent.
    private static let mergedPRJSON = """
    {
      "number": 42,
      "title": "Test PR",
      "state": "MERGED",
      "author": {"login": "octocat"},
      "headRefName": "feature/test",
      "baseRefName": "main",
      "labels": [],
      "isDraft": false,
      "reviewDecision": "APPROVED",
      "url": "https://github.com/owner/repo/pull/42",
      "updatedAt": "2026-04-25T12:00:00Z"
    }
    """

    private static let repoIdentityJSON = """
    {
      "owner": {"login": "owner"},
      "name": "repo"
    }
    """

    private static let cleanMergeabilityJSON = """
    {
      "number": 42,
      "state": "OPEN",
      "mergeable": "MERGEABLE",
      "mergeStateStatus": "CLEAN",
      "reviewDecision": "APPROVED",
      "statusCheckRollup": [
        {"state": "SUCCESS", "conclusion": "SUCCESS"}
      ]
    }
    """

    // MARK: - mergePullRequest argument shape

    @Test("squash method invokes gh pr merge with --squash flag")
    func squashMethodInvokesGhWithSquashFlag() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: Self.mergeSuccessStdout, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash, deleteBranch: false),
            at: Self.workingDirectory
        )

        let mergeArgs = try #require(Self.firstMergeInvocation(spy: spy))
        #expect(mergeArgs.contains("--squash"))
        #expect(!mergeArgs.contains("--merge"))
        #expect(!mergeArgs.contains("--rebase"))
        #expect(!mergeArgs.contains("--delete-branch"))
    }

    @Test("merge method invokes gh pr merge with --merge flag")
    func mergeMethodInvokesGhWithMergeFlag() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .merge, deleteBranch: false),
            at: Self.workingDirectory
        )
        let args = try #require(Self.firstMergeInvocation(spy: spy))
        #expect(args.contains("--merge"))
        #expect(!args.contains("--squash"))
        #expect(!args.contains("--rebase"))
    }

    @Test("rebase method invokes gh pr merge with --rebase flag")
    func rebaseMethodInvokesGhWithRebaseFlag() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .rebase, deleteBranch: false),
            at: Self.workingDirectory
        )
        let args = try #require(Self.firstMergeInvocation(spy: spy))
        #expect(args.contains("--rebase"))
    }

    @Test("deleteBranch=true appends --delete-branch")
    func deleteBranchTrueAppendsDeleteBranch() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash, deleteBranch: true),
            at: Self.workingDirectory
        )
        let args = try #require(Self.firstMergeInvocation(spy: spy))
        #expect(args.contains("--delete-branch"))
    }

    @Test("custom subject and body pass --subject and --body flags")
    func customSubjectAndBodyPassFlags() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(
                pullRequestNumber: 42,
                method: .squash,
                deleteBranch: false,
                subject: "Custom subject",
                body: "Custom body"
            ),
            at: Self.workingDirectory
        )
        let args = try #require(Self.firstMergeInvocation(spy: spy))
        #expect(args.contains("--subject"))
        #expect(args.contains("Custom subject"))
        #expect(args.contains("--body"))
        #expect(args.contains("Custom body"))
    }

    @Test("blank subject (whitespace only) does not pass --subject")
    func blankSubjectDoesNotPassFlag() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(
                pullRequestNumber: 42,
                method: .squash,
                deleteBranch: false,
                subject: "   ",
                body: nil
            ),
            at: Self.workingDirectory
        )
        let args = try #require(Self.firstMergeInvocation(spy: spy))
        #expect(!args.contains("--subject"))
    }

    // MARK: - mergePullRequest success path

    @Test("successful merge returns the hydrated PR via follow-up view")
    func successfulMergeReturnsHydratedPullRequest() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: Self.mergeSuccessStdout, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        let pr = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash, deleteBranch: false),
            at: Self.workingDirectory
        )
        #expect(pr.number == 42)
        #expect(pr.state == .merged)

        // Two invocations: first the merge, then the view.
        #expect(spy.allInvocations.count == 2)
        #expect(spy.allInvocations[0].args.first == "pr")
        #expect(spy.allInvocations[0].args.dropFirst().first == "merge")
        #expect(spy.allInvocations[1].args.first == "pr")
        #expect(spy.allInvocations[1].args.dropFirst().first == "view")
    }

    @Test("deleteBranch=true explicitly deletes the same-repo head ref after merge")
    func deleteBranchTrueDeletesHeadRefAfterMerge() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: Self.mergeSuccessStdout, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesRepoIdentity,
                 result: GitHubCLIResult(stdout: Self.repoIdentityJSON, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesAPI,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash, deleteBranch: true),
            at: Self.workingDirectory
        )

        let apiArgs = try #require(spy.allInvocations.first(where: { $0.args.first == "api" })?.args)
        #expect(apiArgs == [
            "api", "-X", "DELETE",
            "repos/owner/repo/git/refs/heads/feature/test",
        ])
    }

    @Test("deleteBranch=true treats an already-deleted head ref as success")
    func deleteBranchAlreadyDeletedHeadRefIsSuccess() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: Self.mergeSuccessStdout, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesRepoIdentity,
                 result: GitHubCLIResult(stdout: Self.repoIdentityJSON, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesAPI,
                 result: GitHubCLIResult(
                    stdout: "",
                    stderr: "HTTP 422: Reference does not exist",
                    terminationStatus: 1
                 ))

        let service = GitHubService(runner: spy.runner)
        let pr = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash, deleteBranch: true),
            at: Self.workingDirectory
        )

        #expect(pr.state == .merged)
    }

    @Test("non-zero gh exit after remote merge is treated as merged")
    func nonZeroGhExitAfterRemoteMergeIsTreatedAsMerged() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(
                    stdout: "✓ Merged pull request #42 (Squash and merge)",
                    stderr: "fatal: 'main' is already used by worktree at '/tmp/repo'",
                    terminationStatus: 1
                 ))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesRepoIdentity,
                 result: GitHubCLIResult(stdout: Self.repoIdentityJSON, stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesAPI,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        let pr = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash, deleteBranch: true),
            at: Self.workingDirectory
        )

        #expect(pr.state == .merged)
        #expect(spy.allInvocations.contains(where: { $0.args.first == "api" }))
    }

    // MARK: - mergePullRequest error classification

    @Test("merge conflict in stderr maps to GitHubMergeError.mergeConflict")
    func mergeConflictInStderrMapsToTypedError() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge, result: GitHubCLIResult(
            stdout: "",
            stderr: "Pull request is not mergeable: dirty",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubMergeError.mergeConflict) {
            _ = try await service.mergePullRequest(
                request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash),
                at: Self.workingDirectory
            )
        }
    }

    @Test("review-required stderr maps to GitHubMergeError.reviewRequired")
    func reviewRequiredStderrMapsToTypedError() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge, result: GitHubCLIResult(
            stdout: "",
            stderr: "At least 1 approving review is required",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubMergeError.reviewRequired) {
            _ = try await service.mergePullRequest(
                request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash),
                at: Self.workingDirectory
            )
        }
    }

    @Test("behind-base stderr maps to GitHubMergeError.behindBaseBranch")
    func behindBaseStderrMapsToTypedError() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge, result: GitHubCLIResult(
            stdout: "",
            stderr: "Pull request branch is behind the base branch",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubMergeError.behindBaseBranch) {
            _ = try await service.mergePullRequest(
                request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash),
                at: Self.workingDirectory
            )
        }
    }

    @Test("auto-merge enabled stdout (exit 0) maps to GitHubMergeError.autoMergeEnabled")
    func autoMergeEnabledStdoutMapsToTypedError() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge, result: GitHubCLIResult(
            stdout: "Pull request #42 will be automatically merged once requirements are met",
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubMergeError.autoMergeEnabled) {
            _ = try await service.mergePullRequest(
                request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash),
                at: Self.workingDirectory
            )
        }
    }

    @Test("merge invocation passes a generous default timeout (60s)")
    func mergeInvocationPassesGenerousDefaultTimeout() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesMerge,
                 result: GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0))
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.mergedPRJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.mergePullRequest(
            request: GitHubMergeRequest(pullRequestNumber: 42, method: .squash),
            at: Self.workingDirectory
        )
        let mergeInvocation = try #require(spy.allInvocations.first)
        #expect(mergeInvocation.timeout == 60.0)
    }

    // MARK: - pullRequestMergeability

    @Test("pullRequestMergeability decodes a clean PR successfully")
    func pullRequestMergeabilityDecodesCleanPullRequest() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.cleanMergeabilityJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        let mergeability = try await service.pullRequestMergeability(
            number: 42,
            at: Self.workingDirectory
        )
        #expect(mergeability.pullRequestNumber == 42)
        #expect(mergeability.canMerge)
        #expect(mergeability.checksPassed)
        #expect(mergeability.reviewDecision == .approved)
    }

    @Test("pullRequestMergeability invokes gh pr view with the right --json fields")
    func pullRequestMergeabilityInvokesGhWithRightJsonFields() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesView,
                 result: GitHubCLIResult(stdout: Self.cleanMergeabilityJSON, stderr: "", terminationStatus: 0))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.pullRequestMergeability(
            number: 42,
            at: Self.workingDirectory
        )
        let invocation = try #require(spy.allInvocations.first)
        let argsString = invocation.args.joined(separator: " ")
        #expect(argsString.contains("pr view"))
        #expect(argsString.contains("42"))
        #expect(argsString.contains("mergeable"))
        #expect(argsString.contains("mergeStateStatus"))
        #expect(argsString.contains("reviewDecision"))
        #expect(argsString.contains("statusCheckRollup"))
    }

    // MARK: - pullRequestNumber(forBranch:)

    @Test("pullRequestNumber(forBranch:) returns the PR number for a branch with an open PR")
    func pullRequestNumberForBranchReturnsTheNumber() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesView, result: GitHubCLIResult(
            stdout: "{\"number\": 42}",
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let number = try await service.pullRequestNumber(
            forBranch: "feature/test",
            at: Self.workingDirectory
        )
        #expect(number == 42)
        let invocation = try #require(spy.allInvocations.first)
        #expect(invocation.args.contains("feature/test"))
        #expect(invocation.args.contains("number"))
    }

    @Test("pullRequestNumber(forBranch:) returns nil when no PR matches the branch")
    func pullRequestNumberForBranchReturnsNilWhenNoPR() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesView, result: GitHubCLIResult(
            stdout: "",
            stderr: "no pull requests found for branch feature/orphan",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        let number = try await service.pullRequestNumber(
            forBranch: "feature/orphan",
            at: Self.workingDirectory
        )
        #expect(number == nil)
    }

    @Test("pullRequestNumber(forBranch:) returns nil for empty branch input")
    func pullRequestNumberForBranchReturnsNilForEmptyInput() async throws {
        let spy = RunnerSpy()
        let service = GitHubService(runner: spy.runner)
        let number = try await service.pullRequestNumber(
            forBranch: "   ",
            at: Self.workingDirectory
        )
        #expect(number == nil)
        // Empty input must short-circuit before invoking gh.
        #expect(spy.allInvocations.isEmpty)
    }

    @Test("pullRequestNumber(forBranch:) propagates non-not-found gh errors")
    func pullRequestNumberForBranchPropagatesOtherErrors() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesView, result: GitHubCLIResult(
            stdout: "",
            stderr: "no GitHub remote",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubCLIError.noRemote) {
            _ = try await service.pullRequestNumber(
                forBranch: "feature/test",
                at: Self.workingDirectory
            )
        }
    }

    @Test("pullRequestMergeability surfaces gh failures via classifyError")
    func pullRequestMergeabilitySurfacesGhFailures() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: Self.matchesView, result: GitHubCLIResult(
            stdout: "",
            stderr: "could not determine the current repository",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubCLIError.noRemote) {
            _ = try await service.pullRequestMergeability(
                number: 42,
                at: Self.workingDirectory
            )
        }
    }

    // MARK: - Helpers

    /// Predicate matching the `gh pr merge <n> ...` invocation.
    private static let matchesMerge: @Sendable ([String]) -> Bool = { args in
        args.first == "pr" && args.dropFirst().first == "merge"
    }

    /// Predicate matching the `gh pr view <n> ...` follow-up call.
    private static let matchesView: @Sendable ([String]) -> Bool = { args in
        args.first == "pr" && args.dropFirst().first == "view"
    }

    private static let matchesRepoIdentity: @Sendable ([String]) -> Bool = { args in
        args == ["repo", "view", "--json", "owner,name"]
    }

    private static let matchesAPI: @Sendable ([String]) -> Bool = { args in
        args.first == "api"
    }

    /// Returns the args of the first merge invocation (or nil).
    private static func firstMergeInvocation(spy: RunnerSpy) -> [String]? {
        spy.allInvocations.first(where: { $0.args.first == "pr" && $0.args.dropFirst().first == "merge" })?.args
    }
}
