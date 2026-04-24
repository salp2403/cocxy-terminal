// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubServiceSwiftTestingTests.swift - Unit tests for the `gh` actor.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitHubService")
struct GitHubServiceSwiftTestingTests {

    // MARK: - Runner spy

    /// Thread-safe stub for the `GitHubService.Runner` closure.
    ///
    /// Tests add responses keyed on the first two positional arguments
    /// (`gh <verb> <subverb>`). The spy records every invocation so tests
    /// can assert on the arguments they care about. Reference type
    /// because actor operations need a shared mutable store; marked
    /// `@unchecked Sendable` and guarded by `NSLock`.
    final class RunnerSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var invocations: [(directory: URL, args: [String], timeout: TimeInterval)] = []
        private var stubs: [(predicate: @Sendable ([String]) -> Bool, result: GitHubCLIResult)] = []
        private var errorToThrow: (@Sendable ([String]) -> Error?) = { _ in nil }

        func stub(
            matching predicate: @escaping @Sendable ([String]) -> Bool,
            result: GitHubCLIResult
        ) {
            lock.lock()
            stubs.append((predicate, result))
            lock.unlock()
        }

        func stubError(_ error: @escaping @Sendable ([String]) -> Error?) {
            lock.lock()
            errorToThrow = error
            lock.unlock()
        }

        var runner: GitHubService.Runner {
            return { [self] directory, args, timeout in
                self.lock.lock()
                self.invocations.append((directory, args, timeout))
                let errorToThrow = self.errorToThrow
                let stubs = self.stubs
                self.lock.unlock()

                if let error = errorToThrow(args) { throw error }
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

    // MARK: - authStatus

    @Test("authStatus returns parsed login when gh reports authenticated")
    func authStatus_returnsParsedLoginWhenAuthenticated() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
            stdout: "",
            stderr: """
            github.com
              ✓ Logged in to github.com account octocat (keyring)
              - Active account: true
              - Token scopes: 'repo', 'workflow', 'gist'
            """,
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let status = try await service.authStatus()

        #expect(status.isAuthenticated == true)
        #expect(status.login == "octocat")
        #expect(status.hasRepoScope)
        #expect(status.hasWorkflowScope)
    }

    @Test("authStatus returns .loggedOut when gh reports no login")
    func authStatus_returnsLoggedOutWhenNotAuthenticated() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("status") }, result: GitHubCLIResult(
            stdout: "",
            stderr: "You are not logged into any GitHub hosts. Run gh auth login to authenticate.",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        let status = try await service.authStatus()

        #expect(status.isAuthenticated == false)
        #expect(status.login == nil)
    }

    // MARK: - currentRepo

    @Test("currentRepo decodes `gh repo view` JSON output")
    func currentRepo_decodesPayload() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("view") && $0.contains("repo") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "defaultBranchRef": {"name": "main"},
              "description": "A test repo",
              "hasIssuesEnabled": true,
              "isEmpty": false,
              "isPrivate": false,
              "name": "cocxy-terminal",
              "owner": {"id": "x", "login": "salp2403"},
              "url": "https://github.com/salp2403/cocxy-terminal"
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let repo = try await service.currentRepo(at: URL(fileURLWithPath: "/tmp"))

        #expect(repo.fullName == "salp2403/cocxy-terminal")
        #expect(repo.defaultBranch == "main")
    }

    @Test("currentRepo maps stderr to typed error on non-zero exit")
    func currentRepo_throwsTypedErrorOnFailure() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { _ in true }, result: GitHubCLIResult(
            stdout: "",
            stderr: "unable to determine the repository to use",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubCLIError.self) {
            _ = try await service.currentRepo(at: URL(fileURLWithPath: "/tmp"))
        }
    }

    // MARK: - listPullRequests

    @Test("listPullRequests decodes empty array without crashing")
    func listPullRequests_decodesEmptyArray() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
            stdout: "[]",
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let prs = try await service.listPullRequests(at: URL(fileURLWithPath: "/tmp"))
        #expect(prs.isEmpty)
    }

    @Test("listPullRequests decodes a multi-entry payload")
    func listPullRequests_decodesMultiEntryPayload() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
            stdout: #"""
            [
              {
                "number": 1,
                "title": "first",
                "state": "OPEN",
                "author": {"login": "a"},
                "headRefName": "feat/a",
                "baseRefName": "main",
                "labels": [],
                "isDraft": false,
                "reviewDecision": null,
                "url": "https://github.com/u/r/pull/1",
                "updatedAt": "2026-04-23T15:47:21Z"
              },
              {
                "number": 2,
                "title": "second",
                "state": "OPEN",
                "author": {"login": "b"},
                "headRefName": "feat/b",
                "baseRefName": "main",
                "labels": [],
                "isDraft": true,
                "reviewDecision": null,
                "url": "https://github.com/u/r/pull/2",
                "updatedAt": "2026-04-23T15:47:21Z"
              }
            ]
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let all = try await service.listPullRequests(at: URL(fileURLWithPath: "/tmp"))

        #expect(all.count == 2)
        #expect(all.map(\.number) == [1, 2])
    }

    @Test("listPullRequests filters drafts when includeDrafts is false")
    func listPullRequests_filtersDraftsWhenIncludeDraftsFalse() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
            stdout: #"""
            [
              {"number": 1, "title": "a", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "b", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"},
              {"number": 2, "title": "b", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "b", "labels": [], "isDraft": true, "reviewDecision": null, "url": "https://github.com/u/r/pull/2", "updatedAt": "2026-04-23T15:47:21Z"}
            ]
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let filtered = try await service.listPullRequests(
            at: URL(fileURLWithPath: "/tmp"),
            includeDrafts: false
        )

        #expect(filtered.count == 1)
        #expect(filtered.first?.number == 1)
    }

    @Test("listPullRequests clamps limit into the [1, 200] range")
    func listPullRequests_clampsLimit() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { _ in true }, result: GitHubCLIResult(
            stdout: "[]",
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.listPullRequests(at: URL(fileURLWithPath: "/tmp"), limit: 9999)

        // Confirm the --limit value actually passed to gh is the clamped one.
        let invocation = spy.allInvocations.first
        try #require(invocation != nil)
        let args = invocation!.args
        guard let limitIndex = args.firstIndex(of: "--limit") else {
            Issue.record("Expected --limit arg in \(args)")
            return
        }
        #expect(args[limitIndex + 1] == "200")
    }

    @Test("listPullRequests normalises unknown state to the fallback")
    func listPullRequests_normalisesUnknownState() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { _ in true }, result: GitHubCLIResult(
            stdout: "[]",
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.listPullRequests(
            at: URL(fileURLWithPath: "/tmp"),
            state: "WEIRD"
        )

        let args = spy.allInvocations.first?.args ?? []
        guard let stateIndex = args.firstIndex(of: "--state") else {
            Issue.record("Expected --state arg in \(args)")
            return
        }
        #expect(args[stateIndex + 1] == "open")
    }

    // MARK: - listIssues

    @Test("listIssues decodes payload and handles integer comments")
    func listIssues_decodesPayload() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
            stdout: #"""
            [
              {"number": 1, "title": "bug", "state": "OPEN", "author": {"login": "u"}, "labels": [], "comments": 3, "url": "https://github.com/u/r/issues/1", "updatedAt": "2026-04-23T15:47:21Z"}
            ]
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let issues = try await service.listIssues(at: URL(fileURLWithPath: "/tmp"))

        #expect(issues.count == 1)
        #expect(issues.first?.commentCount == 3)
    }

    // MARK: - checksForPullRequest

    @Test("checksForPullRequest returns [] when gh reports 'no checks'")
    func checksForPullRequest_returnsEmptyForNoChecks() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("checks") }, result: GitHubCLIResult(
            stdout: "",
            stderr: "no checks reported on the 'feat/github-pane' branch",
            terminationStatus: 8
        ))

        let service = GitHubService(runner: spy.runner)
        let checks = try await service.checksForPullRequest(
            number: 1,
            at: URL(fileURLWithPath: "/tmp")
        )
        #expect(checks.isEmpty)
    }

    @Test("checksForPullRequest decodes status/conclusion payload")
    func checksForPullRequest_decodesPayload() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("checks") }, result: GitHubCLIResult(
            stdout: #"""
            [
              {"name": "build", "status": "COMPLETED", "conclusion": "SUCCESS", "detailsUrl": "https://github.com/u/r/runs/1"},
              {"name": "tests", "status": "IN_PROGRESS"}
            ]
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let checks = try await service.checksForPullRequest(
            number: 1,
            at: URL(fileURLWithPath: "/tmp")
        )

        #expect(checks.count == 2)
        #expect(checks[0].conclusion == .success)
        #expect(checks[1].status == .inProgress)
    }

    // MARK: - createPullRequest

    @Test("createPullRequest rejects empty title before shelling out")
    func createPullRequest_rejectsEmptyTitle() async throws {
        let spy = RunnerSpy()
        let service = GitHubService(runner: spy.runner)

        await #expect(throws: GitHubCLIError.self) {
            _ = try await service.createPullRequest(
                title: "   ",
                at: URL(fileURLWithPath: "/tmp")
            )
        }
        #expect(spy.allInvocations.isEmpty, "Runner should not be called when title is empty")
    }

    @Test("createPullRequest chains `gh pr create` with a follow-up `pr view`")
    func createPullRequest_chainsCreateAndView() async throws {
        let spy = RunnerSpy()

        // First invocation: gh pr create -> print URL
        spy.stub(matching: { $0.contains("create") }, result: GitHubCLIResult(
            stdout: "https://github.com/salp2403/cocxy-terminal/pull/42\n",
            stderr: "",
            terminationStatus: 0
        ))
        // Second invocation: gh pr view 42 --json ... -> PR payload
        spy.stub(matching: { $0.contains("view") && $0.contains("42") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "number": 42,
              "title": "t",
              "state": "OPEN",
              "author": {"login": "u"},
              "headRefName": "feat/x",
              "baseRefName": "main",
              "labels": [],
              "isDraft": false,
              "reviewDecision": null,
              "url": "https://github.com/salp2403/cocxy-terminal/pull/42",
              "updatedAt": "2026-04-23T15:47:21Z"
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let pr = try await service.createPullRequest(
            title: "t",
            body: "b",
            at: URL(fileURLWithPath: "/tmp")
        )

        #expect(pr.number == 42)

        // At least two invocations happened: create then view.
        #expect(spy.allInvocations.count >= 2)
        let firstArgs = spy.allInvocations.first?.args ?? []
        #expect(firstArgs.contains("create"))
    }

    @Test("createPullRequest forwards --draft and --base when provided")
    func createPullRequest_forwardsDraftAndBaseFlags() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("create") }, result: GitHubCLIResult(
            stdout: "https://github.com/u/r/pull/7",
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("view") && $0.contains("7") }, result: GitHubCLIResult(
            stdout: #"""
            {"number": 7, "title": "x", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": true, "reviewDecision": null, "url": "https://github.com/u/r/pull/7", "updatedAt": "2026-04-23T15:47:21Z"}
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        _ = try await service.createPullRequest(
            title: "t",
            body: nil,
            baseBranch: "main",
            draft: true,
            at: URL(fileURLWithPath: "/tmp")
        )

        let createArgs = spy.allInvocations.first?.args ?? []
        #expect(createArgs.contains("--draft"))
        guard let baseIndex = createArgs.firstIndex(of: "--base") else {
            Issue.record("Expected --base arg in \(createArgs)")
            return
        }
        #expect(createArgs[baseIndex + 1] == "main")
    }

    // MARK: - PR number extraction

    @Test("extractPullRequestNumber parses the canonical gh URL")
    func extractPullRequestNumber_parsesCanonicalURL() {
        let url = "https://github.com/salp2403/cocxy-terminal/pull/42"
        #expect(GitHubService.extractPullRequestNumber(from: url) == 42)
    }

    @Test("extractPullRequestNumber parses URLs surrounded by extra output")
    func extractPullRequestNumber_parsesURLsInNoisyOutput() {
        let noisy = """
        Creating pull request…
        https://github.com/salp2403/cocxy-terminal/pull/123
        Thanks for using gh!
        """
        #expect(GitHubService.extractPullRequestNumber(from: noisy) == 123)
    }

    @Test("extractPullRequestNumber returns nil for garbage input")
    func extractPullRequestNumber_returnsNilForGarbage() {
        #expect(GitHubService.extractPullRequestNumber(from: "no url") == nil)
        #expect(GitHubService.extractPullRequestNumber(from: "") == nil)
        #expect(GitHubService.extractPullRequestNumber(
            from: "https://github.com/u/r/tree/main"
        ) == nil)
    }
}
