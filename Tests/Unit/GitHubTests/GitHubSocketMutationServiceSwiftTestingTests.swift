// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("GitHub socket mutation service")
struct GitHubSocketMutationServiceSwiftTestingTests {
    final class RunnerSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var invocations: [[String]] = []
        private let repositoryJSON: String
        private let onInvocation: @Sendable ([String]) -> Void

        init(
            repositoryJSON: String = GitHubSocketMutationServiceSwiftTestingTests.repositoryJSON,
            onInvocation: @escaping @Sendable ([String]) -> Void = { _ in }
        ) {
            self.repositoryJSON = repositoryJSON
            self.onInvocation = onInvocation
        }

        var runner: GitHubService.Runner {
            { [self] _, arguments, _ in
                lock.lock()
                invocations.append(arguments)
                lock.unlock()
                onInvocation(arguments)

                if arguments.starts(with: ["repo", "view"]) {
                    return GitHubCLIResult(
                        stdout: repositoryJSON,
                        stderr: "",
                        terminationStatus: 0
                    )
                }
                if arguments.starts(with: ["pr", "review"]) {
                    return GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0)
                }
                if arguments.starts(with: ["pr", "merge"]) {
                    return GitHubCLIResult(stdout: "Merged", stderr: "", terminationStatus: 0)
                }
                if arguments.starts(with: ["pr", "view", "42"]) {
                    return GitHubCLIResult(
                        stdout: GitHubSocketMutationServiceSwiftTestingTests.mergedPullRequestJSON,
                        stderr: "",
                        terminationStatus: 0
                    )
                }
                if arguments.starts(with: ["api"]) {
                    return GitHubCLIResult(stdout: "", stderr: "", terminationStatus: 0)
                }
                return GitHubCLIResult(
                    stdout: "",
                    stderr: "No stub for \(arguments)",
                    terminationStatus: 1
                )
            }
        }

        var calls: [[String]] {
            lock.lock()
            defer { lock.unlock() }
            return invocations
        }
    }

    final class DateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Date

        init(_ value: Date) {
            storage = value
        }

        var value: Date {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func store(_ value: Date) {
            lock.lock()
            storage = value
            lock.unlock()
        }
    }

    @Test("review grant is single use and binds the exact repository and body")
    func reviewGrantIsSingleUseAndExact() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-service")
        let spy = RunnerSpy()
        let service = GitHubService(runner: spy.runner)
        let grant = try makeGrant(
            intent: .review(
                pullRequestNumber: 42,
                action: .requestChanges,
                body: "Fix the failing check."
            ),
            directory: directory
        )

        try await service.reviewPullRequest(authorizedBy: grant, at: directory)

        let review = try #require(spy.calls.first(where: { $0.starts(with: ["pr", "review"]) }))
        #expect(review == [
            "pr", "review", "42", "--request-changes",
            "--body", "Fix the failing check.",
            "--repo", "github.com/owner/repo",
        ])

        await #expect(throws: GitHubSocketMutationAuthorizationError.alreadyConsumed) {
            try await service.reviewPullRequest(authorizedBy: grant, at: directory)
        }
        #expect(spy.calls.filter { $0.starts(with: ["pr", "review"]) }.count == 1)
        #expect(spy.calls.filter { $0.starts(with: ["repo", "view"]) }.count == 1)
    }

    @Test("repository change consumes the grant without reaching a mutation")
    func repositoryChangeFailsClosed() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-service")
        let spy = RunnerSpy(repositoryJSON: Self.repositoryJSON(owner: "other"))
        let service = GitHubService(runner: spy.runner)
        let grant = try makeGrant(
            intent: .review(
                pullRequestNumber: 42,
                action: .approve,
                body: nil
            ),
            directory: directory
        )

        await #expect(throws: GitHubSocketMutationAuthorizationError.repositoryChanged) {
            try await service.reviewPullRequest(authorizedBy: grant, at: directory)
        }
        #expect(!spy.calls.contains(where: { $0.starts(with: ["pr", "review"]) }))
    }

    @Test("expired and directory-mismatched grants fail before repository discovery")
    func invalidGrantFailsBeforeRepositoryDiscovery() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-service")
        let now = Date(timeIntervalSince1970: 10_000)
        let spy = RunnerSpy()
        let service = GitHubService(runner: spy.runner)
        let grant = try makeGrant(
            intent: .review(
                pullRequestNumber: 42,
                action: .approve,
                body: nil
            ),
            directory: directory,
            createdAt: now.addingTimeInterval(-120),
            approvedAt: now.addingTimeInterval(-119)
        )

        await #expect(throws: GitHubSocketMutationAuthorizationError.invalidOrExpired) {
            try await service.reviewPullRequest(
                authorizedBy: grant,
                at: URL(fileURLWithPath: "/tmp/other"),
                now: now
            )
        }
        #expect(spy.calls.isEmpty)
    }

    @Test("grant expiring during repository discovery fails before mutation")
    func grantExpiresDuringRepositoryDiscovery() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-service")
        let startedAt = Date(timeIntervalSince1970: 20_000)
        let clock = DateBox(startedAt)
        let spy = RunnerSpy { arguments in
            if arguments.starts(with: ["repo", "view"]) {
                clock.store(startedAt.addingTimeInterval(61))
            }
        }
        let service = GitHubService(
            runner: spy.runner,
            dateProvider: { clock.value }
        )
        let grant = try makeGrant(
            intent: .review(
                pullRequestNumber: 42,
                action: .approve,
                body: nil
            ),
            directory: directory,
            createdAt: startedAt,
            approvedAt: startedAt
        )

        await #expect(throws: GitHubSocketMutationAuthorizationError.invalidOrExpired) {
            try await service.reviewPullRequest(
                authorizedBy: grant,
                at: directory,
                now: startedAt
            )
        }
        #expect(spy.calls.filter { $0.starts(with: ["repo", "view"]) }.count == 1)
        #expect(!spy.calls.contains(where: { $0.starts(with: ["pr", "review"]) }))
    }

    @Test("branch discovery enforces its subprocess deadline")
    func branchDiscoveryTimesOut() async {
        let timeout: TimeInterval = 0.05
        let startedAt = Date()

        await #expect(throws: GitHubCLIError.timeout(seconds: timeout)) {
            try await AppDelegate.currentBranchForCLIMerge(
                directory: URL(fileURLWithPath: "/tmp"),
                timeoutSeconds: timeout,
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"]
            )
        }

        #expect(Date().timeIntervalSince(startedAt) < 1.5)
    }

    @Test("merge grant binds repository and keeps branch deletion opt-in")
    func mergeGrantBindsRepository() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-service")
        let spy = RunnerSpy()
        let service = GitHubService(runner: spy.runner)
        let grant = try makeGrant(
            intent: .merge(GitHubMergeRequest(
                pullRequestNumber: 42,
                method: .squash,
                deleteBranch: false,
                subject: "Ship it",
                body: "Reviewed"
            )),
            directory: directory
        )

        _ = try await service.mergePullRequest(authorizedBy: grant, at: directory)

        let merge = try #require(spy.calls.first(where: { $0.starts(with: ["pr", "merge"]) }))
        #expect(merge.contains("--repo"))
        #expect(merge.contains("github.com/owner/repo"))
        #expect(!merge.contains("--delete-branch"))
        let view = try #require(spy.calls.first(where: { $0.starts(with: ["pr", "view", "42"]) }))
        #expect(view.suffix(2) == ["--repo", "github.com/owner/repo"])
    }

    @Test("authorized branch deletion binds the API host and repository")
    func authorizedBranchDeletionBindsHost() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-service")
        let spy = RunnerSpy()
        let service = GitHubService(runner: spy.runner)
        let grant = try makeGrant(
            intent: .merge(GitHubMergeRequest(
                pullRequestNumber: 42,
                method: .merge,
                deleteBranch: true
            )),
            directory: directory
        )

        _ = try await service.mergePullRequest(authorizedBy: grant, at: directory)

        let merge = try #require(spy.calls.first(where: { $0.starts(with: ["pr", "merge"]) }))
        #expect(merge.contains("--delete-branch"))
        #expect(merge.suffix(2) == ["--repo", "github.com/owner/repo"])
        let api = try #require(spy.calls.first(where: { $0.starts(with: ["api"]) }))
        #expect(api.prefix(3) == ["api", "--hostname", "github.com"])
        #expect(api.contains("repos/owner/repo/git/refs/heads/feature/test"))
    }

    @MainActor
    @Test("AppDelegate requires visible approval before submitting a review")
    func appDelegateRequiresVisibleApproval() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-app-delegate")
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        _ = controller.tabManager.addTab(workingDirectory: directory)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let configService = ConfigService(fileProvider: MemoryConfigProvider(content: """
        [github]
        enabled = true
        merge-enabled = true
        """))
        try configService.reload()
        delegate.installConfigServiceForTesting(configService)

        let deniedSpy = RunnerSpy()
        controller.githubSocketMutationAuthorizationPresenter = { _ in false }
        let denied = await delegate.performGitHubCLIRequest(
            kind: "review-approve",
            params: ["pr": "42", "body": "Ship it"],
            serviceOverride: GitHubService(runner: deniedSpy.runner)
        )
        #expect(!denied.0)
        #expect(!deniedSpy.calls.contains(where: { $0.starts(with: ["pr", "review"]) }))

        let approvedSpy = RunnerSpy()
        var approvedRequest: GitHubSocketMutationAuthorizationRequest?
        controller.githubSocketMutationAuthorizationPresenter = { request in
            approvedRequest = request
            return true
        }
        let approved = await delegate.performGitHubCLIRequest(
            kind: "review-request-changes",
            params: ["pr": "42", "body": "  Fix this.  "],
            serviceOverride: GitHubService(runner: approvedSpy.runner)
        )

        #expect(approved.0)
        #expect(approvedRequest?.context.repository.displayName == "owner/repo")
        #expect(approvedRequest?.intent == .review(
            pullRequestNumber: 42,
            action: .requestChanges,
            body: "Fix this."
        ))
        let review = try #require(
            approvedSpy.calls.first(where: { $0.starts(with: ["pr", "review"]) })
        )
        #expect(review.suffix(2) == ["--repo", "github.com/owner/repo"])
    }

    @MainActor
    @Test("AppDelegate binds every approved merge field and keeps deletion opt-in")
    func appDelegateBindsExactMergeIntent() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-app-merge")
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        _ = controller.tabManager.addTab(workingDirectory: directory)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        let configService = ConfigService(fileProvider: MemoryConfigProvider(content: """
        [github]
        enabled = true
        merge-enabled = true
        """))
        try configService.reload()
        delegate.installConfigServiceForTesting(configService)

        let spy = RunnerSpy()
        var approvedIntent: GitHubSocketMutationIntent?
        controller.githubSocketMutationAuthorizationPresenter = { request in
            approvedIntent = request.intent
            return true
        }

        let result = await delegate.performGitHubCLIRequest(
            kind: "pr-merge",
            params: [
                "pr": "42",
                "method": "squash",
                "subject": "  Release candidate  ",
                "body": "  Verified locally.  ",
            ],
            serviceOverride: GitHubService(runner: spy.runner)
        )

        #expect(result.0)
        #expect(approvedIntent == .merge(GitHubMergeRequest(
            pullRequestNumber: 42,
            method: .squash,
            deleteBranch: false,
            subject: "Release candidate",
            body: "Verified locally."
        )))
        let merge = try #require(spy.calls.first(where: { $0.starts(with: ["pr", "merge"]) }))
        #expect(merge.contains("--squash"))
        #expect(merge.contains("Release candidate"))
        #expect(merge.contains("Verified locally."))
        #expect(merge.suffix(2) == ["--repo", "github.com/owner/repo"])
        #expect(!merge.contains("--delete-branch"))
    }

    private static var repositoryJSON: String { repositoryJSON(owner: "owner") }

    private static func repositoryJSON(owner: String) -> String {
        """
        {
          "owner": {"login": "\(owner)"},
          "name": "repo",
          "defaultBranchRef": {"name": "main"},
          "url": "https://github.com/\(owner)/repo",
          "hasIssuesEnabled": true,
          "isPrivate": false,
          "isEmpty": false,
          "description": "Repository"
        }
        """
    }

    private static let mergedPullRequestJSON = """
    {
      "number": 42,
      "title": "Test PR",
      "state": "MERGED",
      "author": {"login": "octocat"},
      "headRefName": "feature/test",
      "headRepository": {"name": "repo"},
      "headRepositoryOwner": {"login": "owner"},
      "isCrossRepository": false,
      "baseRefName": "main",
      "labels": [],
      "isDraft": false,
      "reviewDecision": "APPROVED",
      "url": "https://github.com/owner/repo/pull/42",
      "updatedAt": "2026-04-25T12:00:00Z"
    }
    """

    private func makeGrant(
        intent: GitHubSocketMutationIntent,
        directory: URL,
        createdAt: Date = Date(),
        approvedAt: Date? = nil
    ) throws -> GitHubSocketMutationAuthorizationGrant {
        let token = NSObject()
        let authority = try #require(GitHubRepositoryAuthority(
            host: "github.com",
            ownerLogin: "owner",
            name: "repo"
        ))
        let request = GitHubSocketMutationAuthorizationRequest(
            intent: intent,
            context: GitHubSocketMutationContext(
                windowControllerIdentifier: ObjectIdentifier(token),
                tabID: TabID(),
                workingDirectory: directory,
                repository: authority
            ),
            createdAt: createdAt
        )
        return try #require(GitHubSocketMutationAuthorizationGrant(
            request: request,
            approvedAt: approvedAt ?? createdAt
        ))
    }

    private final class MemoryConfigProvider: ConfigFileProviding, @unchecked Sendable {
        private let content: String

        init(content: String) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws {}
    }
}
