// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Branch and commit providers")
struct BranchCommitProvidersSwiftTestingTests {
    @Test("BranchListProvider parses local and remote branches and filters search")
    func branchListParsesAndFilters() throws {
        let runner = GitRunnerSpy()
        runner.stub(
            matching: { $0.starts(with: ["branch"]) },
            result: CodeReviewGitResult(
                stdout: """
                *\tmain\torigin/main\tabc1234\tInitial commit
                 \tfeature/editor\torigin/feature/editor\tdef5678\tEditor polish
                 \torigin/main\t\tabc1234\tInitial commit
                 \torigin/HEAD\t\tabc1234\torigin/main
                """,
                stderr: "",
                terminationStatus: 0
            )
        )
        let provider = BranchListProvider(runner: runner.runner)

        let branches = try provider.listBranches(
            at: URL(fileURLWithPath: "/tmp/repo"),
            query: BranchListQuery(searchText: "editor")
        )

        #expect(branches.count == 1)
        #expect(branches[0].name == "feature/editor")
        #expect(branches[0].upstreamName == "origin/feature/editor")
        #expect(!branches[0].isRemote)
        #expect(!branches[0].isCurrent)
    }

    @Test("BranchListProvider can fetch before listing when requested")
    func branchListFetchesBeforeListing() throws {
        let runner = GitRunnerSpy()
        runner.stub(matching: { $0.starts(with: ["fetch"]) }, result: .success)
        runner.stub(
            matching: { $0.starts(with: ["branch"]) },
            result: CodeReviewGitResult(
                stdout: "*\tmain\torigin/main\tabc1234\tInitial commit",
                stderr: "",
                terminationStatus: 0
            )
        )
        let provider = BranchListProvider(runner: runner.runner)

        _ = try provider.listBranches(
            at: URL(fileURLWithPath: "/tmp/repo"),
            query: BranchListQuery(refreshRemotes: true)
        )

        #expect(runner.invocations.map(\.args).first == ["fetch", "--prune", "--all"])
        #expect(runner.invocations.map(\.args).last?.first == "branch")
    }

    @Test("CommitHistoryProvider parses log lines and clamps page size")
    func commitHistoryParsesAndClamps() throws {
        let runner = GitRunnerSpy()
        runner.stub(
            matching: { $0.starts(with: ["log"]) },
            result: CodeReviewGitResult(
                stdout: """
                0123456789abcdef\t0123456\tSaid Arturo Lopez\tdev@cocxy.dev\t2026-05-11T12:10:00-06:00\tHEAD -> main, origin/main\tfeat: shared diff
                abcdef0123456789\tabcdef0\tSaid Arturo Lopez\tdev@cocxy.dev\t2026-05-10T09:00:00-06:00\t\tfix: browser tabs
                """,
                stderr: "",
                terminationStatus: 0
            )
        )
        let provider = CommitHistoryProvider(runner: runner.runner)

        let commits = try provider.history(
            at: URL(fileURLWithPath: "/tmp/repo"),
            query: CommitHistoryQuery(searchText: "diff", limit: 500, skip: -20)
        )

        #expect(commits.count == 1)
        #expect(commits[0].hash == "0123456789abcdef")
        #expect(commits[0].shortHash == "0123456")
        #expect(commits[0].refs == ["HEAD -> main", "origin/main"])
        let args = try #require(runner.invocations.first?.args)
        #expect(args.contains("-n"))
        #expect(args[args.firstIndex(of: "-n")! + 1] == "200")
        #expect(args[args.firstIndex(of: "--skip")! + 1] == "0")
    }

    @Test("CommitHistoryProvider includes ref before options when provided")
    func commitHistoryIncludesRef() throws {
        let runner = GitRunnerSpy()
        runner.stub(matching: { $0.starts(with: ["log"]) }, result: .success)
        let provider = CommitHistoryProvider(runner: runner.runner)

        _ = try provider.history(
            at: URL(fileURLWithPath: "/tmp/repo"),
            query: CommitHistoryQuery(ref: "feature/editor", limit: 25, skip: 10)
        )

        let args = try #require(runner.invocations.first?.args)
        #expect(args.prefix(2) == ["log", "feature/editor"])
    }

    @Test("BranchCreator validates names and supports checkout from a start point")
    func branchCreatorValidatesAndBuildsCommand() throws {
        let runner = GitRunnerSpy()
        runner.stub(matching: { $0.starts(with: ["switch"]) }, result: .success)
        let creator = BranchCreator(runner: runner.runner)

        let branch = try creator.createBranch(
            named: "feature/source-control",
            at: URL(fileURLWithPath: "/tmp/repo"),
            startPoint: "origin/main",
            checkout: true
        )

        #expect(branch.name == "feature/source-control")
        #expect(branch.isCurrent)
        #expect(runner.invocations.first?.args == ["switch", "-c", "feature/source-control", "origin/main"])
        #expect(throws: HunkActionError.self) {
            _ = try creator.createBranch(named: "bad branch", at: URL(fileURLWithPath: "/tmp/repo"))
        }
    }
}

private final class GitRunnerSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [(predicate: @Sendable ([String]) -> Bool, result: CodeReviewGitResult)] = []
    private(set) var invocations: [(directory: URL, args: [String])] = []

    func stub(
        matching predicate: @escaping @Sendable ([String]) -> Bool,
        result: CodeReviewGitResult
    ) {
        lock.lock()
        stubs.append((predicate, result))
        lock.unlock()
    }

    var runner: GitCommandRunner {
        { [self] directory, args in
            lock.lock()
            invocations.append((directory, args))
            let stubs = self.stubs
            lock.unlock()

            for stub in stubs where stub.predicate(args) {
                return stub.result
            }
            return CodeReviewGitResult(stdout: "", stderr: "no stub for \(args)", terminationStatus: 1)
        }
    }
}

private extension CodeReviewGitResult {
    static let success = CodeReviewGitResult(stdout: "", stderr: "", terminationStatus: 0)
}

private extension Array where Element == String {
    func starts(with prefix: [String]) -> Bool {
        guard count >= prefix.count else { return false }
        return Array(self[0..<prefix.count]) == prefix
    }
}
