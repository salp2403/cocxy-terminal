// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitMergeAftermathService.swift - Actor that drives the post-merge
// `git fetch` (+ optional `git pull --ff-only`) syncing the local
// checkout after a successful `gh pr merge` from the in-panel flow.
//
// Shape mirrors `GitHubService` and `WorktreeService` so the three
// subprocess orchestrators audit with the same mental model:
//   - dependencies arrive as `@Sendable` closures so tests stub the
//     subprocess runner without touching PATH
//   - every public method is `async` so the caller never blocks the
//     main thread on a network-bound git invocation
//   - the actor boundary serialises concurrent merges across surfaces
//     (Code Review panel + GitHub pane share the singleton)
//   - typed `GitMergeAftermathError` carries actionable copy; the
//     "user declined" results travel as `GitMergeAftermathOutcome` so
//     the view layer routes them through the **info** banner channel
//     (see `feedback_info_vs_error_banners`).
//
// The service deliberately never executes `git checkout`. Switching
// branches under a user mid-merge is too invasive for an automatic
// flow; the `fetchedOnly` and `skippedNonFastForward` outcomes leave
// the user in full control with a clear banner.

import Foundation

// MARK: - GitMergeAftermathService

actor GitMergeAftermathService {

    // MARK: Run result

    /// Subprocess result captured by the runner. Mirrors the shape of
    /// `CodeReviewGitResult` and `GitHubCLIResult` so future refactors
    /// can collapse the three runners into a shared utility without
    /// renaming associated types.
    struct RunResult: Sendable, Equatable {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32

        init(stdout: String, stderr: String, terminationStatus: Int32) {
            self.stdout = stdout
            self.stderr = stderr
            self.terminationStatus = terminationStatus
        }
    }

    // MARK: Runner

    /// Signature of the injected subprocess runner.
    ///
    /// `args` already includes the subcommand (e.g. `["fetch", "origin",
    /// "main"]`). The runner's job is to invoke the resolved `git`
    /// binary inside `directory` and capture stdout/stderr/termination.
    /// The runner may itself throw `GitMergeAftermathError.timedOut` or
    /// `.gitUnavailable`; every other case routes through the typed
    /// outcome enum.
    typealias Runner = @Sendable (URL, [String], TimeInterval) throws -> RunResult

    private let runner: Runner
    private let fileExistsProvider: @Sendable (URL) -> Bool

    // MARK: Init

    init(
        runner: @escaping Runner = GitMergeAftermathService.defaultRunner,
        fileExistsProvider: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    ) {
        self.runner = runner
        self.fileExistsProvider = fileExistsProvider
    }

    // MARK: - Public surface

    /// Performs the post-merge aftermath sync.
    ///
    /// Pipeline (every step is "best effort + safe to skip"):
    ///   1. Workspace existence sanity check (race with worktree removal).
    ///   2. `git rev-parse --is-inside-work-tree` — bail to
    ///      `.skippedNotInRepo` when the directory is not a checkout.
    ///   3. `git symbolic-ref --short HEAD` — bail to
    ///      `.skippedDetachedHead` when HEAD is detached.
    ///   4. `git status --porcelain` — count modified vs untracked
    ///      entries with composite-marker awareness
    ///      (see `feedback_porcelain_status_composite_markers`). Any
    ///      non-empty result short-circuits to `.skippedDirtyTree`.
    ///   5. `git fetch origin <baseBranch>` — typed `.fetchFailed` on
    ///      non-zero exit because a fetch failure is actionable.
    ///   6. Branch comparison — when the user is **not** on the base
    ///      branch, return `.fetchedOnly` without touching their
    ///      checkout.
    ///   7. `git rev-list --left-right --count HEAD...origin/<base>` —
    ///      derive ahead/behind to decide between `.synced` (already up
    ///      to date), `.skippedNonFastForward` (diverged), and the
    ///      pull path.
    ///   8. `git pull --ff-only origin <base>` — typed `.pullFailed`
    ///      on non-zero, with stderr inspection that folds the
    ///      "not possible to fast-forward" race into
    ///      `.skippedNonFastForward` instead of an error.
    ///
    /// - Parameters:
    ///   - directory: Working directory of the checkout. Typically the
    ///     active tab's `worktreeRoot ?? workingDirectory`.
    ///   - baseBranch: The PR's `baseRefName`. Trimmed before use; an
    ///     empty value is treated as `.skippedNotInRepo` because we
    ///     have no anchor to fetch.
    ///   - timeoutSeconds: Per-subprocess timeout. Defaults to 30s for
    ///     read-only operations; the pull step internally doubles it
    ///     because pull is the only operation that can take tens of
    ///     seconds on slow networks.
    /// - Returns: A typed outcome the view layer maps to an info banner.
    /// - Throws: `GitMergeAftermathError` for actionable errors only.
    func sync(
        at directory: URL,
        baseBranch: String,
        timeoutSeconds: TimeInterval = 30
    ) async throws -> GitMergeAftermathOutcome {
        let trimmedBase = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Workspace sanity check.
        guard fileExistsProvider(directory) else {
            return .workspaceVanished
        }

        guard !trimmedBase.isEmpty else {
            // No base ref to fetch against — treat the same as "not a
            // git repository for our purposes". The caller did not
            // give us enough information to do anything useful.
            return .skippedNotInRepo
        }

        // 2. Inside a git work tree?
        let revParse: RunResult
        do {
            revParse = try runner(directory, ["rev-parse", "--is-inside-work-tree"], timeoutSeconds)
        } catch let error as GitMergeAftermathError {
            // Re-throw timeouts and `gitUnavailable`; everything else
            // collapses to "not in repo" because the runner failed to
            // even start `git`.
            switch error {
            case .timedOut, .gitUnavailable:
                throw error
            default:
                return .skippedNotInRepo
            }
        }
        if revParse.terminationStatus != 0 ||
           revParse.stdout.trimmingCharacters(in: .whitespacesAndNewlines) != "true" {
            return .skippedNotInRepo
        }

        // 3. Current branch (detached HEAD has no symbolic-ref).
        let symbolicRef = try runner(directory, ["symbolic-ref", "--short", "HEAD"], timeoutSeconds)
        if symbolicRef.terminationStatus != 0 {
            return .skippedDetachedHead
        }
        let currentBranch = symbolicRef.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentBranch.isEmpty else {
            return .skippedDetachedHead
        }

        // 4. Working tree state — porcelain output composite markers.
        let porcelain = try runner(directory, ["status", "--porcelain"], timeoutSeconds)
        if porcelain.terminationStatus != 0 {
            // `git status` rarely fails when the rev-parse above passed;
            // collapse to "not in repo" rather than throwing because
            // the merge already succeeded — we should not block the
            // user with an error banner over a status hiccup.
            return .skippedNotInRepo
        }
        let porcelainOutput = porcelain.stdout
        if !porcelainOutput.allSatisfy(\.isWhitespace) {
            let counts = try Self.classifyPorcelain(porcelainOutput)
            if counts.modified > 0 || counts.untracked > 0 {
                return .skippedDirtyTree(
                    branch: currentBranch,
                    modifiedCount: counts.modified,
                    untrackedCount: counts.untracked
                )
            }
        }

        // 5. Fetch the base branch from origin.
        let fetch = try runner(directory, ["fetch", "origin", trimmedBase], timeoutSeconds)
        if fetch.terminationStatus != 0 {
            throw GitMergeAftermathError.fetchFailed(
                stderr: fetch.stderr,
                exitCode: fetch.terminationStatus
            )
        }

        // 6. If we're not on the base branch, stop after the fetch.
        if currentBranch != trimmedBase {
            return .fetchedOnly(currentBranch: currentBranch, baseBranch: trimmedBase)
        }

        // 7. Decide between pull / non-fast-forward / already-synced.
        let counts = try countAheadBehind(
            directory: directory,
            branch: currentBranch,
            baseBranch: trimmedBase,
            timeoutSeconds: timeoutSeconds
        )
        if counts.behind == 0 {
            return .synced(branch: currentBranch, ahead: counts.ahead, behind: 0)
        }
        if counts.ahead > 0 {
            return .skippedNonFastForward(
                branch: currentBranch,
                ahead: counts.ahead,
                behind: counts.behind
            )
        }

        // 8. Fast-forward pull. Pull gets a longer deadline because
        // it can chase a long history on slow networks; the multiplier
        // matches the gh merge timeout doubling so the user sees the
        // same patience profile across both halves of the flow.
        let pullTimeout = timeoutSeconds * 2
        let pull = try runner(
            directory,
            ["pull", "--ff-only", "origin", trimmedBase],
            pullTimeout
        )
        if pull.terminationStatus != 0 {
            let lower = pull.stderr.lowercased()
            if lower.contains("not possible to fast-forward") ||
               lower.contains("not a fast-forward") {
                return .skippedNonFastForward(
                    branch: currentBranch,
                    ahead: counts.ahead,
                    behind: counts.behind
                )
            }
            throw GitMergeAftermathError.pullFailed(
                stderr: pull.stderr,
                exitCode: pull.terminationStatus
            )
        }
        return .synced(branch: currentBranch, ahead: counts.ahead, behind: counts.behind)
    }

    // MARK: - Helpers

    /// `git rev-list --left-right --count HEAD...origin/<base>` reports
    /// `ahead<TAB>behind`. We tolerate missing remote refs by collapsing
    /// to `(0, 0)` — the caller treats that as "already synced" which
    /// is the safest default after a successful merge.
    private func countAheadBehind(
        directory: URL,
        branch: String,
        baseBranch: String,
        timeoutSeconds: TimeInterval
    ) throws -> (ahead: Int, behind: Int) {
        let result = try runner(
            directory,
            ["rev-list", "--left-right", "--count", "HEAD...origin/\(baseBranch)"],
            timeoutSeconds
        )
        guard result.terminationStatus == 0 else {
            return (0, 0)
        }
        return Self.parseAheadBehind(result.stdout)
    }

    /// Parses the `<ahead>\t<behind>` output of
    /// `git rev-list --left-right --count`. Any unexpected shape
    /// collapses to `(0, 0)` so a one-off git oddity never escalates
    /// into a thrown error during aftermath.
    static func parseAheadBehind(_ raw: String) -> (ahead: Int, behind: Int) {
        let parts = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }

    /// Classifies the lines of `git status --porcelain` into modified
    /// (`X`/`Y` not space, including composite markers like `MM`, `AD`,
    /// `RM`) vs untracked (`??`) counts. The implementation is
    /// intentionally permissive — anything that does not match the
    /// untracked prefix counts as modified so a freshly added file
    /// (`A `, `AM`, `AD`) shows up correctly.
    static func classifyPorcelain(_ raw: String) throws -> (modified: Int, untracked: Int) {
        var modified = 0
        var untracked = 0

        let lines = raw.split(omittingEmptySubsequences: true) { $0.isNewline }
        for line in lines {
            let trimmed = String(line)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("?? ") {
                untracked += 1
                continue
            }
            // Porcelain v1 always emits a 2-char marker followed by a
            // space and the path. Anything shorter is malformed —
            // prefer to surface the issue via a typed error rather
            // than miscount.
            guard trimmed.count >= 3 else {
                throw GitMergeAftermathError.invalidPorcelainOutput(raw: trimmed)
            }
            modified += 1
        }
        return (modified, untracked)
    }

    // MARK: - Default runner

    /// Production runner: spawn `git` via `Process`, drain stdout and
    /// stderr concurrently with a `DispatchGroup` (mirroring
    /// `CodeReviewGit.run` so both audits look identical), and enforce
    /// `timeoutSeconds` with a `DispatchSourceTimer` that terminates
    /// the process on expiration.
    ///
    /// Pipe cleanup on `process.run()` failure follows
    /// `feedback_dispatch_group_pipe_cleanup` so a runner that never
    /// even spawned does not leak a stuck reader.
    static let defaultRunner: Runner = { directory, args, timeoutSeconds in
        guard let gitURL = CodeReviewGit.resolveGitExecutableURL() else {
            throw GitMergeAftermathError.gitUnavailable
        }

        let process = Process()
        process.executableURL = gitURL
        process.arguments = args
        process.currentDirectoryURL = directory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBox = AftermathDataBox()
        let stderrBox = AftermathDataBox()
        let readGroup = DispatchGroup()
        let readQueue = DispatchQueue.global(qos: .userInitiated)

        readGroup.enter()
        readQueue.async {
            stdoutBox.store(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        readGroup.enter()
        readQueue.async {
            stderrBox.store(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        do {
            try process.run()
        } catch {
            // Pipe cleanup so the readers see EOF and unblock — see
            // `feedback_dispatch_group_pipe_cleanup`.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            readGroup.wait()
            throw GitMergeAftermathError.gitUnavailable
        }

        // Timeout watcher: terminate the process if `timeoutSeconds`
        // elapses before `waitUntilExit` returns. We cancel the watcher
        // explicitly when the process completes on its own to avoid a
        // late terminate() landing on a recycled pid.
        let timeoutFlag = AftermathTimeoutFlag()
        let timer = DispatchSource.makeTimerSource(queue: readQueue)
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler {
            timeoutFlag.markFired()
            // Best-effort terminate. The process may already be gone if
            // it raced us; that is fine because waitUntilExit returns
            // for both normal exits and signals.
            process.terminate()
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()
        readGroup.wait()

        if timeoutFlag.fired {
            let operation = args.first ?? "git"
            throw GitMergeAftermathError.timedOut(
                operation: operation,
                after: timeoutSeconds
            )
        }

        return RunResult(
            stdout: String(decoding: stdoutBox.data, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }
}

// MARK: - Internal sync primitives

/// Thread-safe data box used to collect stdout/stderr from the two
/// reader queues. Reuses the same shape as `CodeReviewGitDataBox` so
/// audits across the three runners can confirm the locking discipline
/// is consistent.
private final class AftermathDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// One-shot flag set by the timeout watcher and read by the runner
/// after `waitUntilExit`. NSLock is overkill for a single-bit field
/// but keeps memory ordering explicit and matches the discipline used
/// elsewhere in the codebase for cross-thread booleans.
private final class AftermathTimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var didFire: Bool = false

    func markFired() {
        lock.lock()
        didFire = true
        lock.unlock()
    }

    var fired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFire
    }
}
