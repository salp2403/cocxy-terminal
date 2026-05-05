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

    @Test("pullRequestReviewThreads decodes unresolved and resolved GraphQL threads")
    func pullRequestReviewThreads_decodesGraphQLThreads() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "defaultBranchRef": {"name": "main"},
              "description": "",
              "hasIssuesEnabled": true,
              "isEmpty": false,
              "isPrivate": false,
              "name": "r",
              "owner": {"login": "u"},
              "url": "https://github.com/u/r"
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("api") && $0.contains("graphql") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "data": {
                "repository": {
                  "pullRequest": {
                    "reviewThreads": {
                      "nodes": [
                        {
                          "id": "PRRT_1",
                          "isResolved": false,
                          "isOutdated": false,
                          "viewerCanResolve": true,
                          "viewerCanUnresolve": false,
                          "path": "Sources/App.swift",
                          "line": 12,
                          "startLine": 10,
                          "comments": {
                            "nodes": [
                              {
                                "id": "PRRC_1",
                                "body": "Please tighten this guard.",
                                "author": {"login": "reviewer"},
                                "createdAt": "2026-05-05T10:00:00Z",
                                "url": "https://github.com/u/r/pull/42#discussion_r1"
                              }
                            ]
                          }
                        },
                        {
                          "id": "PRRT_2",
                          "isResolved": true,
                          "isOutdated": true,
                          "viewerCanResolve": false,
                          "viewerCanUnresolve": true,
                          "path": "Sources/Done.swift",
                          "line": 4,
                          "startLine": null,
                          "comments": {"nodes": []}
                        }
                      ],
                      "pageInfo": {"hasNextPage": false, "endCursor": null}
                    }
                  }
                }
              }
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let threads = try await service.pullRequestReviewThreads(
            number: 42,
            at: URL(fileURLWithPath: "/tmp")
        )

        #expect(threads.map(\.id) == ["PRRT_1", "PRRT_2"])
        #expect(threads[0].state == .unresolved)
        #expect(threads[0].lineRange == 10...12)
        #expect(threads[0].comments.count == 1)
        #expect(threads[0].comments.first?.authorLogin == "reviewer")
        #expect(threads[1].state == .resolved)
        #expect(threads[1].lineRange == 4...4)
        #expect(threads[1].isOutdated)
        #expect(threads[1].viewerCanUnresolve)
    }

    @Test("resolveReviewThread sends a GraphQL mutation and decodes the updated thread")
    func resolveReviewThread_sendsMutationAndDecodesThread() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("api") && $0.contains("graphql") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "data": {
                "resolveReviewThread": {
                  "thread": {
                    "id": "PRRT_1",
                    "isResolved": true,
                    "isOutdated": false,
                    "viewerCanResolve": false,
                    "viewerCanUnresolve": true,
                    "path": "Sources/App.swift",
                    "line": 12,
                    "startLine": null,
                    "comments": {"nodes": []}
                  }
                }
              }
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let thread = try await service.resolveReviewThread(
            threadID: "PRRT_1",
            at: URL(fileURLWithPath: "/tmp")
        )

        #expect(thread.id == "PRRT_1")
        #expect(thread.state == .resolved)
        #expect(thread.viewerCanUnresolve)

        let args = try #require(spy.allInvocations.first?.args)
        #expect(args.contains("api"))
        #expect(args.contains("graphql"))
        #expect(args.contains("-F"))
        #expect(args.contains("threadId=PRRT_1"))
        #expect(args.contains { $0.contains("resolveReviewThread") })
    }

    @Test("unresolveReviewThread maps non-zero gh exit to a typed error")
    func unresolveReviewThread_mapsNonZeroExitToTypedError() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("api") && $0.contains("graphql") }, result: GitHubCLIResult(
            stdout: "",
            stderr: "GraphQL: Could not resolve to a node with the global id",
            terminationStatus: 1
        ))

        let service = GitHubService(runner: spy.runner)
        await #expect(throws: GitHubCLIError.self) {
            _ = try await service.unresolveReviewThread(
                threadID: "PRRT_missing",
                at: URL(fileURLWithPath: "/tmp")
            )
        }
    }

    @Test("unresolveReviewThread sends a GraphQL mutation and decodes the updated thread")
    func unresolveReviewThread_sendsMutationAndDecodesThread() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("api") && $0.contains("graphql") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "data": {
                "unresolveReviewThread": {
                  "thread": {
                    "id": "PRRT_1",
                    "isResolved": false,
                    "isOutdated": false,
                    "viewerCanResolve": true,
                    "viewerCanUnresolve": false,
                    "path": "Sources/App.swift",
                    "line": 12,
                    "startLine": null,
                    "comments": {"nodes": []}
                  }
                }
              }
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let thread = try await service.unresolveReviewThread(
            threadID: "PRRT_1",
            at: URL(fileURLWithPath: "/tmp")
        )

        #expect(thread.id == "PRRT_1")
        #expect(thread.state == .unresolved)
        #expect(thread.viewerCanResolve)

        let args = try #require(spy.allInvocations.first?.args)
        #expect(args.contains("threadId=PRRT_1"))
        #expect(args.contains { $0.contains("unresolveReviewThread") })
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

    @Test("checksForPullRequest decodes current gh state/bucket payload")
    func checksForPullRequest_decodesPayload() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("checks") }, result: GitHubCLIResult(
            stdout: #"""
            [
              {"name": "build", "state": "SUCCESS", "bucket": "pass", "link": "https://github.com/u/r/runs/1"},
              {"name": "tests", "state": "PENDING", "bucket": "pending"}
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
        #expect(checks[0].detailsUrl?.absoluteString == "https://github.com/u/r/runs/1")
        #expect(checks[1].status == .pending)

        let args = spy.allInvocations.first?.args ?? []
        guard let jsonIndex = args.firstIndex(of: "--json") else {
            Issue.record("Expected --json arg in \(args)")
            return
        }
        #expect(args[jsonIndex + 1] == "name,state,bucket,link,startedAt,completedAt")
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

    @Test("createPullRequest fills empty body from repository template and commits")
    func createPullRequest_fillsBodyFromTemplateAndCommits() async throws {
        let root = try makeGitHubPRTemplateFillTemporaryDirectory(named: "github-pr-template-fill")
        defer { try? FileManager.default.removeItem(at: root) }
        let templateDirectory = root.appendingPathComponent(".github", isDirectory: true)
        try FileManager.default.createDirectory(at: templateDirectory, withIntermediateDirectories: true)
        try """
        ## Summary

        -
        """.write(
            to: templateDirectory.appendingPathComponent("pull_request_template.md"),
            atomically: true,
            encoding: .utf8
        )

        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("create") }, result: GitHubCLIResult(
            stdout: "https://github.com/u/r/pull/8",
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("view") && $0.contains("8") }, result: GitHubCLIResult(
            stdout: #"""
            {"number": 8, "title": "x", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/8", "updatedAt": "2026-04-23T15:47:21Z"}
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let filler = PRTemplateFiller(commitSummaryProvider: { receivedRoot, receivedBase in
            #expect(receivedRoot == root)
            #expect(receivedBase == "main")
            return ["Add review body defaults", "Keep explicit user input"]
        })
        let service = GitHubService(runner: spy.runner, pullRequestTemplateFiller: filler)

        _ = try await service.createPullRequest(
            title: "x",
            body: nil,
            baseBranch: "main",
            at: root
        )

        let createArgs = spy.allInvocations.first?.args ?? []
        guard let bodyIndex = createArgs.firstIndex(of: "--body") else {
            Issue.record("Expected --body arg in \(createArgs)")
            return
        }
        #expect(createArgs[bodyIndex + 1] == """
        ## Summary

        -

        ## Commits

        - Add review body defaults
        - Keep explicit user input
        """)
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

    // MARK: - reviewPullRequest

    @Test("reviewPullRequest approves an explicit PR with an optional body")
    func reviewPullRequest_approvesExplicitPRWithBody() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("review") }, result: GitHubCLIResult(
            stdout: "",
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        try await service.reviewPullRequest(
            number: 42,
            action: .approve,
            body: "Ship it",
            at: URL(fileURLWithPath: "/tmp")
        )

        let args = try #require(spy.allInvocations.first?.args)
        #expect(args == ["pr", "review", "42", "--approve", "--body", "Ship it"])
    }

    @Test("reviewPullRequest request-changes preserves gh current-branch default")
    func reviewPullRequest_requestChangesWithoutExplicitPR() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.contains("review") }, result: GitHubCLIResult(
            stdout: "",
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        try await service.reviewPullRequest(
            number: nil,
            action: .requestChanges,
            body: nil,
            at: URL(fileURLWithPath: "/tmp")
        )

        let args = try #require(spy.allInvocations.first?.args)
        #expect(args == ["pr", "review", "--request-changes"])
    }
}

private func makeGitHubPRTemplateFillTemporaryDirectory(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
