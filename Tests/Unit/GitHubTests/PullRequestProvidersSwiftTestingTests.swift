// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Pull request providers")
struct PullRequestProvidersSwiftTestingTests {
    @Test("PullRequestListProvider applies state, draft, author and text filters")
    func listProviderFiltersPullRequests() async throws {
        let provider = PullRequestListProvider { directory, state, limit, includeDrafts, timeout in
            #expect(directory.path == "/tmp/repo")
            #expect(state == "all")
            #expect(limit == 200)
            #expect(includeDrafts)
            #expect(timeout == 10)
            return [
                samplePullRequest(number: 1, title: "Add source control", author: "said", isDraft: false),
                samplePullRequest(number: 2, title: "WIP terminal", author: "said", isDraft: true),
                samplePullRequest(number: 3, title: "Docs", author: "other", isDraft: false),
            ]
        }

        let result = try await provider.listPullRequests(
            at: URL(fileURLWithPath: "/tmp/repo"),
            query: PullRequestListQuery(
                state: .all,
                searchText: "source",
                authorLogin: "said",
                includeDrafts: false,
                limit: 500
            )
        )

        #expect(result.map(\.number) == [1])
    }

    @Test("PullRequestCreator builds a gh create plan with base draft and reviewers")
    func creatorBuildsPlan() throws {
        let request = PullRequestCreateRequest(
            title: "Add source control",
            body: "Implementation notes",
            baseBranch: "main",
            reviewers: ["alice", "bob", "alice"],
            draft: true
        )

        let plan = try PullRequestCreator.plan(for: request)

        #expect(plan.arguments == [
            "pr", "create",
            "--title", "Add source control",
            "--body", "Implementation notes",
            "--base", "main",
            "--draft",
            "--reviewer", "alice",
            "--reviewer", "bob",
        ])
        #expect(throws: GitHubCLIError.self) {
            _ = try PullRequestCreator.plan(for: PullRequestCreateRequest(title: "  "))
        }
    }

    @Test("PullRequestCreator creates then hydrates the pull request")
    func creatorCreatesThenHydrates() async throws {
        let spy = GHRunnerSpy()
        spy.stub(
            matching: { $0.starts(with: ["pr", "create"]) },
            result: GitHubCLIResult(
                stdout: "https://github.com/owner/repo/pull/42\n",
                stderr: "",
                terminationStatus: 0
            )
        )
        spy.stub(
            matching: { $0.starts(with: ["pr", "view", "42"]) },
            result: GitHubCLIResult(stdout: samplePullRequestJSON(number: 42), stderr: "", terminationStatus: 0)
        )
        let creator = PullRequestCreator(runner: spy.runner)

        let pr = try await creator.create(
            PullRequestCreateRequest(title: "Add source control", baseBranch: "main", draft: false),
            at: URL(fileURLWithPath: "/tmp/repo")
        )

        #expect(pr.number == 42)
        #expect(spy.invocations.map(\.args).count == 2)
        #expect(spy.invocations.map(\.args)[0].contains("--base"))
        #expect(spy.invocations.map(\.args)[1].contains("view"))
    }

    @Test("PullRequestCreator maps gh failures through GitHubCLI classifier")
    func creatorMapsFailures() async throws {
        let creator = PullRequestCreator { _, _, _ in
            GitHubCLIResult(
                stdout: "",
                stderr: "You are not logged into any GitHub hosts. Run gh auth login.",
                terminationStatus: 1
            )
        }

        await #expect(throws: GitHubCLIError.self) {
            _ = try await creator.create(
                PullRequestCreateRequest(title: "Add source control"),
                at: URL(fileURLWithPath: "/tmp/repo")
            )
        }
    }
}

private final class GHRunnerSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [(predicate: @Sendable ([String]) -> Bool, result: GitHubCLIResult)] = []
    private(set) var invocations: [(directory: URL, args: [String], timeout: TimeInterval)] = []

    func stub(
        matching predicate: @escaping @Sendable ([String]) -> Bool,
        result: GitHubCLIResult
    ) {
        lock.lock()
        stubs.append((predicate, result))
        lock.unlock()
    }

    var runner: GitHubService.Runner {
        { [self] directory, args, timeout in
            lock.lock()
            invocations.append((directory, args, timeout))
            let stubs = self.stubs
            lock.unlock()

            for stub in stubs where stub.predicate(args) {
                return stub.result
            }
            return GitHubCLIResult(stdout: "", stderr: "no stub for \(args)", terminationStatus: 1)
        }
    }
}

private func samplePullRequest(
    number: Int,
    title: String,
    author: String,
    isDraft: Bool
) -> GitHubPullRequest {
    GitHubPullRequest(
        number: number,
        title: title,
        state: .open,
        author: GitHubUser(login: author),
        headRefName: "feature/\(number)",
        baseRefName: "main",
        isDraft: isDraft,
        url: URL(string: "https://github.com/owner/repo/pull/\(number)")!,
        updatedAt: Date(timeIntervalSince1970: TimeInterval(number))
    )
}

private func samplePullRequestJSON(number: Int) -> String {
    """
    {
      "number": \(number),
      "title": "Add source control",
      "state": "OPEN",
      "author": {"login": "said"},
      "headRefName": "feature/source-control",
      "baseRefName": "main",
      "labels": [],
      "isDraft": false,
      "reviewDecision": null,
      "url": "https://github.com/owner/repo/pull/\(number)",
      "updatedAt": "2026-05-11T12:10:00Z"
    }
    """
}
