// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitMergeAftermathServiceSwiftTestingTests.swift - Coverage for the
// post-merge sync service shipped in v0.1.87.
//
// The suite combines unit tests against a `RunnerSpy` (fast, exhaust
// every outcome enum case) with a small integration suite that drives
// the real default runner against a temp git repo + bare remote so the
// end-to-end pipe drain / Process plumbing is exercised at least once.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Runner spy

/// Thread-safe stub for `GitMergeAftermathService.Runner`. Records every
/// invocation and returns the first stub whose predicate matches the
/// args. Mirrors the spy used in `GitHubServiceMergeSwiftTestingTests`
/// so the two suites can be audited side-by-side.
private final class AftermathRunnerSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations: [(directory: URL, args: [String], timeout: TimeInterval)] = []
    private var stubs: [(predicate: @Sendable ([String]) -> Bool,
                         result: Result<GitMergeAftermathService.RunResult, GitMergeAftermathError>)] = []

    func stub(
        matching predicate: @escaping @Sendable ([String]) -> Bool,
        result: GitMergeAftermathService.RunResult
    ) {
        lock.lock()
        stubs.append((predicate, .success(result)))
        lock.unlock()
    }

    func stubThrows(
        matching predicate: @escaping @Sendable ([String]) -> Bool,
        error: GitMergeAftermathError
    ) {
        lock.lock()
        stubs.append((predicate, .failure(error)))
        lock.unlock()
    }

    var runner: GitMergeAftermathService.Runner {
        return { [self] directory, args, timeout in
            self.lock.lock()
            self.invocations.append((directory, args, timeout))
            let stubs = self.stubs
            self.lock.unlock()
            for entry in stubs where entry.predicate(args) {
                switch entry.result {
                case .success(let value):
                    return value
                case .failure(let error):
                    throw error
                }
            }
            return GitMergeAftermathService.RunResult(
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

    func argsContaining(_ token: String) -> [[String]] {
        return allInvocations
            .map(\.args)
            .filter { $0.contains(token) }
    }
}

// MARK: - Convenience factories

private func ok(stdout: String = "", stderr: String = "") -> GitMergeAftermathService.RunResult {
    GitMergeAftermathService.RunResult(stdout: stdout, stderr: stderr, terminationStatus: 0)
}

private func fail(stdout: String = "", stderr: String, exit: Int32 = 1) -> GitMergeAftermathService.RunResult {
    GitMergeAftermathService.RunResult(stdout: stdout, stderr: stderr, terminationStatus: exit)
}

private let workingDirectory = URL(fileURLWithPath: "/tmp/repo")

private func service(_ spy: AftermathRunnerSpy) -> GitMergeAftermathService {
    GitMergeAftermathService(
        runner: spy.runner,
        fileExistsProvider: { _ in true }
    )
}

// MARK: - Unit suite

@Suite("GitMergeAftermathService.unit", .serialized)
struct GitMergeAftermathServiceUnitTests {

    // MARK: - Workspace gate

    @Test("workspace vanished short-circuits before any subprocess")
    func workspaceVanished() async throws {
        let spy = AftermathRunnerSpy()
        let svc = GitMergeAftermathService(
            runner: spy.runner,
            fileExistsProvider: { _ in false }
        )
        let outcome = try await svc.sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .workspaceVanished)
        #expect(spy.allInvocations.isEmpty)
    }

    @Test("empty base branch collapses to skippedNotInRepo")
    func emptyBaseBranch() async throws {
        let spy = AftermathRunnerSpy()
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "")
        #expect(outcome == .skippedNotInRepo)
        #expect(spy.allInvocations.isEmpty)
    }

    // MARK: - Repo discovery

    @Test("rev-parse failing collapses to skippedNotInRepo")
    func revParseFails() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: fail(stderr: "fatal: not a git repo", exit: 128))
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .skippedNotInRepo)
    }

    @Test("rev-parse output not 'true' collapses to skippedNotInRepo")
    func revParseSurprisingOutput() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "false\n"))
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .skippedNotInRepo)
    }

    @Test("rev-parse runner timeout propagates as typed error")
    func revParseTimeout() async throws {
        let spy = AftermathRunnerSpy()
        spy.stubThrows(
            matching: { $0.contains("rev-parse") },
            error: .timedOut(operation: "rev-parse", after: 30)
        )
        await #expect(throws: GitMergeAftermathError.self) {
            _ = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        }
    }

    @Test("rev-parse runner gitUnavailable propagates")
    func revParseGitUnavailable() async throws {
        let spy = AftermathRunnerSpy()
        spy.stubThrows(matching: { _ in true }, error: .gitUnavailable)
        await #expect(throws: GitMergeAftermathError.self) {
            _ = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        }
    }

    // MARK: - HEAD state

    @Test("symbolic-ref failing returns skippedDetachedHead")
    func detachedHeadByExitCode() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(
            matching: { $0.contains("symbolic-ref") },
            result: fail(stderr: "fatal: ref HEAD is not a symbolic ref", exit: 128)
        )
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .skippedDetachedHead)
    }

    @Test("symbolic-ref empty stdout returns skippedDetachedHead")
    func detachedHeadByEmptyStdout() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "   \n"))
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .skippedDetachedHead)
    }

    // MARK: - Dirty tree

    @Test("dirty tree with modified entries returns skippedDirtyTree counts")
    func dirtyModified() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "main\n"))
        spy.stub(
            matching: { $0.contains("status") },
            result: ok(stdout: " M src/foo.swift\nM  src/bar.swift\n")
        )
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        if case .skippedDirtyTree(let branch, let modified, let untracked) = outcome {
            #expect(branch == "main")
            #expect(modified == 2)
            #expect(untracked == 0)
        } else {
            Issue.record("expected skippedDirtyTree, got \(outcome)")
        }
    }

    @Test("dirty tree with untracked entries reports untracked count")
    func dirtyUntracked() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "main\n"))
        spy.stub(
            matching: { $0.contains("status") },
            result: ok(stdout: "?? notes.txt\n?? scratch/\n")
        )
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        if case .skippedDirtyTree(_, let modified, let untracked) = outcome {
            #expect(modified == 0)
            #expect(untracked == 2)
        } else {
            Issue.record("expected skippedDirtyTree, got \(outcome)")
        }
    }

    @Test("dirty tree with composite markers MM/AD/AM/RM counts as modified")
    func dirtyCompositeMarkers() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "main\n"))
        spy.stub(
            matching: { $0.contains("status") },
            result: ok(stdout: "MM file1.swift\nAD file2.swift\nAM file3.swift\nRM file4.swift -> file4-renamed.swift\n")
        )
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        if case .skippedDirtyTree(_, let modified, let untracked) = outcome {
            #expect(modified == 4)
            #expect(untracked == 0)
        } else {
            Issue.record("expected skippedDirtyTree, got \(outcome)")
        }
    }

    @Test("malformed porcelain line surfaces invalidPorcelainOutput error")
    func invalidPorcelain() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "main\n"))
        spy.stub(matching: { $0.contains("status") }, result: ok(stdout: "X\n"))
        await #expect(throws: GitMergeAftermathError.self) {
            _ = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        }
    }

    // MARK: - Fetch failures

    @Test("fetch failing throws fetchFailed with stderr captured")
    func fetchFails() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "main\n"))
        spy.stub(matching: { $0.contains("status") }, result: ok(stdout: ""))
        spy.stub(matching: { $0.contains("fetch") }, result: fail(stderr: "fatal: unable to access", exit: 128))
        do {
            _ = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
            Issue.record("expected throw")
        } catch let error as GitMergeAftermathError {
            if case .fetchFailed(let stderr, let exitCode) = error {
                #expect(stderr.contains("unable to access"))
                #expect(exitCode == 128)
            } else {
                Issue.record("expected fetchFailed, got \(error)")
            }
        }
    }

    // MARK: - Branch routing

    @Test("on feature branch returns fetchedOnly without pull")
    func onFeatureBranch() async throws {
        let spy = AftermathRunnerSpy()
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "feat/x\n"))
        spy.stub(matching: { $0.contains("status") }, result: ok(stdout: ""))
        spy.stub(matching: { $0.contains("fetch") }, result: ok())
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .fetchedOnly(currentBranch: "feat/x", baseBranch: "main"))
        // Crucially: no `pull` command should have been issued.
        let pullInvocations = spy.argsContaining("pull")
        #expect(pullInvocations.isEmpty)
    }

    @Test("on base branch with no delta returns synced(0,0)")
    func syncedNoDelta() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "0\t0\n"))
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .synced(branch: "main", ahead: 0, behind: 0))
        let pullInvocations = spy.argsContaining("pull")
        #expect(pullInvocations.isEmpty)
    }

    @Test("on base branch ahead-only skips pull but reports synced(N,0)")
    func aheadOnly() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "2\t0\n"))
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .synced(branch: "main", ahead: 2, behind: 0))
        let pullInvocations = spy.argsContaining("pull")
        #expect(pullInvocations.isEmpty)
    }

    @Test("on base branch diverging returns skippedNonFastForward")
    func divergingBranch() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "2\t4\n"))
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .skippedNonFastForward(branch: "main", ahead: 2, behind: 4))
        let pullInvocations = spy.argsContaining("pull")
        #expect(pullInvocations.isEmpty)
    }

    @Test("on base branch behind-only triggers pull and returns synced")
    func behindPullSucceeds() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "0\t3\n"))
        spy.stub(matching: { $0.contains("pull") }, result: ok())
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        #expect(outcome == .synced(branch: "main", ahead: 0, behind: 3))
        let pullInvocations = spy.argsContaining("pull")
        #expect(pullInvocations.count == 1)
        #expect(pullInvocations.first?.contains("--ff-only") == true)
    }

    @Test("pull failing with not-fast-forward stderr folds into outcome")
    func pullNotFFFolds() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "0\t3\n"))
        spy.stub(
            matching: { $0.contains("pull") },
            result: fail(stderr: "fatal: Not possible to fast-forward, aborting.", exit: 128)
        )
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
        if case .skippedNonFastForward(let branch, _, _) = outcome {
            #expect(branch == "main")
        } else {
            Issue.record("expected skippedNonFastForward, got \(outcome)")
        }
    }

    @Test("pull failing for other reasons throws pullFailed")
    func pullOtherFailure() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "0\t3\n"))
        spy.stub(
            matching: { $0.contains("pull") },
            result: fail(stderr: "error: Your local changes would be overwritten by merge.", exit: 1)
        )
        do {
            _ = try await service(spy).sync(at: workingDirectory, baseBranch: "main")
            Issue.record("expected throw")
        } catch let error as GitMergeAftermathError {
            if case .pullFailed = error { } else {
                Issue.record("expected pullFailed, got \(error)")
            }
        }
    }

    @Test("base branch is trimmed before use")
    func baseBranchTrimmed() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "0\t0\n"))
        let outcome = try await service(spy).sync(at: workingDirectory, baseBranch: "  main  ")
        #expect(outcome == .synced(branch: "main", ahead: 0, behind: 0))
        // The fetch should have used the trimmed name.
        let fetchInvocation = spy.argsContaining("fetch").first
        #expect(fetchInvocation?.contains("main") == true)
        #expect(fetchInvocation?.contains("  main  ") != true)
    }

    @Test("pull deadline doubles the read-only timeout")
    func pullDoubleTimeout() async throws {
        let spy = AftermathRunnerSpy()
        stubAllSetup(spy: spy, branch: "main")
        spy.stub(matching: { $0.contains("rev-list") }, result: ok(stdout: "0\t1\n"))
        spy.stub(matching: { $0.contains("pull") }, result: ok())
        _ = try await service(spy).sync(at: workingDirectory, baseBranch: "main", timeoutSeconds: 10)
        let pullCall = spy.allInvocations.first(where: { $0.args.contains("pull") })
        #expect(pullCall?.timeout == 20)
        let fetchCall = spy.allInvocations.first(where: { $0.args.contains("fetch") })
        #expect(fetchCall?.timeout == 10)
    }

    // MARK: - Helper stubbing

    /// Stubs the rev-parse / symbolic-ref / status / fetch chain with
    /// the canonical "everything OK so far" responses. Tests then layer
    /// the rev-list / pull stubs on top to exercise the decision tree.
    private func stubAllSetup(spy: AftermathRunnerSpy, branch: String) {
        spy.stub(matching: { $0.contains("rev-parse") }, result: ok(stdout: "true\n"))
        spy.stub(matching: { $0.contains("symbolic-ref") }, result: ok(stdout: "\(branch)\n"))
        spy.stub(matching: { $0.contains("status") }, result: ok(stdout: ""))
        spy.stub(matching: { $0.contains("fetch") }, result: ok())
    }
}

// MARK: - Static helper coverage

@Suite("GitMergeAftermathService.helpers")
struct GitMergeAftermathServiceHelpersSwiftTestingTests {

    @Test("parseAheadBehind reads tab-separated ahead/behind")
    func parseAheadBehindTab() {
        let result = GitMergeAftermathService.parseAheadBehind("3\t7\n")
        #expect(result.ahead == 3)
        #expect(result.behind == 7)
    }

    @Test("parseAheadBehind tolerates leading/trailing whitespace")
    func parseAheadBehindWhitespace() {
        let result = GitMergeAftermathService.parseAheadBehind("  2  5  ")
        #expect(result.ahead == 2)
        #expect(result.behind == 5)
    }

    @Test("parseAheadBehind collapses malformed input to zeros")
    func parseAheadBehindMalformed() {
        let result = GitMergeAftermathService.parseAheadBehind("garbage")
        #expect(result.ahead == 0)
        #expect(result.behind == 0)
    }

    @Test("classifyPorcelain counts modified vs untracked correctly")
    func classifyPorcelainBasic() throws {
        let counts = try GitMergeAftermathService.classifyPorcelain(
            "?? a.txt\n M b.txt\nMM c.txt\nA  d.txt\n?? e/\n"
        )
        #expect(counts.modified == 3)
        #expect(counts.untracked == 2)
    }

    @Test("classifyPorcelain returns zeros for empty input")
    func classifyPorcelainEmpty() throws {
        let counts = try GitMergeAftermathService.classifyPorcelain("")
        #expect(counts.modified == 0)
        #expect(counts.untracked == 0)
    }

    @Test("classifyPorcelain throws on truncated marker")
    func classifyPorcelainTruncated() {
        #expect(throws: GitMergeAftermathError.self) {
            _ = try GitMergeAftermathService.classifyPorcelain("X\n")
        }
    }
}

// MARK: - Integration with real git

/// Hermetic temp git repo helper. Each test owns its own pair of
/// directories (origin + worktree) and tears them down via `defer`.
/// The real `git` binary is required; if it is missing the suite
/// skips itself rather than failing.
private struct GitHarness {
    let workingDirectory: URL
    let originBare: URL
    private let cleanup: () -> Void

    func runGit(_ args: [String], in dir: URL? = nil) throws -> (stdout: String, exit: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = dir ?? workingDirectory
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (stdout, process.terminationStatus)
    }

    func writeFile(named name: String, contents: String) throws {
        try contents.write(
            to: workingDirectory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    func teardown() {
        cleanup()
    }

    /// Creates a fresh bare origin and a working clone with one commit
    /// on `main`. Returns nil if `git` is missing on the runner.
    static func make() throws -> GitHarness? {
        guard CodeReviewGit.resolveGitExecutableURL() != nil else { return nil }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aftermath-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let origin = root.appendingPathComponent("origin.git", isDirectory: true)
        let working = root.appendingPathComponent("working", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Bare origin.
        try runRaw(["init", "--bare", "--initial-branch=main", origin.path])

        // Working tree clone with an initial commit.
        try runRaw(["clone", origin.path, working.path])
        try "hello\n".write(
            to: working.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runRaw(["-C", working.path, "-c", "user.email=test@example.com", "-c", "user.name=Test", "add", "."])
        try runRaw(["-C", working.path, "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "init"])
        try runRaw(["-C", working.path, "branch", "-M", "main"])
        try runRaw(["-C", working.path, "push", "origin", "main"])

        let cleanup: () -> Void = {
            _ = try? FileManager.default.removeItem(at: root)
        }
        return GitHarness(
            workingDirectory: working,
            originBare: origin,
            cleanup: cleanup
        )
    }

    private static func runRaw(_ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "GitHarness",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) exited \(process.terminationStatus)"]
            )
        }
    }
}

@Suite("GitMergeAftermathService.integration", .serialized)
struct GitMergeAftermathServiceIntegrationTests {

    @Test("clean tree on base branch with no remote delta returns synced(0,0)")
    func cleanTreeNoDelta() async throws {
        guard let harness = try GitHarness.make() else { return }
        defer { harness.teardown() }

        let svc = GitMergeAftermathService()
        let outcome = try await svc.sync(
            at: harness.workingDirectory,
            baseBranch: "main",
            timeoutSeconds: 30
        )
        #expect(outcome == .synced(branch: "main", ahead: 0, behind: 0))
    }

    @Test("dirty working tree returns skippedDirtyTree")
    func dirtyTreeIntegration() async throws {
        guard let harness = try GitHarness.make() else { return }
        defer { harness.teardown() }

        try harness.writeFile(named: "scratch.txt", contents: "draft\n")
        let svc = GitMergeAftermathService()
        let outcome = try await svc.sync(
            at: harness.workingDirectory,
            baseBranch: "main",
            timeoutSeconds: 30
        )
        if case .skippedDirtyTree(let branch, _, let untracked) = outcome {
            #expect(branch == "main")
            #expect(untracked >= 1)
        } else {
            Issue.record("expected skippedDirtyTree, got \(outcome)")
        }
    }

    @Test("non-git directory returns skippedNotInRepo")
    func notARepoIntegration() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aftermath-norepo-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let svc = GitMergeAftermathService()
        let outcome = try await svc.sync(at: scratch, baseBranch: "main", timeoutSeconds: 15)
        #expect(outcome == .skippedNotInRepo)
    }
}
