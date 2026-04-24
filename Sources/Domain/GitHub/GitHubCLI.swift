// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubCLI.swift - Shared `gh` CLI helpers for the GitHub pane and CLI verbs.
//
// The helper intentionally mirrors `CodeReviewGit` (same shape, same patterns)
// so the two subprocess paths can be audited side-by-side:
//   - single binary resolver with PATH + known fallbacks
//   - `run(workingDirectory:arguments:)` with Pipe + DispatchGroup drain
//     and absolute-deadline timeout (no retry cumulativo)
//   - cleanup in the catch of `process.run()` to avoid readGroup hangs
//
// The wire contract between callers and this helper is stdout+stderr+exitCode.
// Classification of failures into typed errors lives in `classifyError` so
// every caller that shells out to `gh` can render the same actionable message.

import Foundation

// MARK: - Result + Errors

/// Raw result of invoking `gh`. Mirrors `CodeReviewGitResult` so the shape is
/// identical across the two subprocess helpers in this codebase.
struct GitHubCLIResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

/// Typed failure surface for `gh` invocations.
///
/// Callers are expected to pattern-match `.notInstalled`, `.notAuthenticated`,
/// `.noRemote` and `.notAGitRepository` into informational banners (these are
/// user-recoverable, not bugs). `.unsupportedVersion`, `.commandFailed` and
/// `.invalidJSON` map to the error banner so the user can act on them.
enum GitHubCLIError: Error, Equatable, Sendable {
    /// `gh` binary could not be resolved on PATH nor in any known fallback.
    case notInstalled
    /// `gh auth status` reports the user is not signed in.
    case notAuthenticated(stderr: String)
    /// `gh` exited non-zero for a reason that does not fit any other case.
    case commandFailed(command: String, stderr: String, exitCode: Int32)
    /// `gh` output could not be decoded. Carries a short reason for the UI.
    case invalidJSON(reason: String)
    /// Installed `gh` is too old for the JSON fields Cocxy requests.
    case unsupportedVersion(stderr: String)
    /// GitHub rate-limit window reached (unauthenticated = 60/h).
    /// `resetAt` is populated when the CLI surfaces a parseable reset header.
    case rateLimited(resetAt: Date?)
    /// The subprocess did not complete before the configured deadline.
    case timeout(seconds: TimeInterval)
    /// Directory has no GitHub remote (or `gh` cannot determine the repo).
    case noRemote
    /// Directory is not inside a git repository.
    case notAGitRepository(path: String)
}

// MARK: - Thread-safe data box

/// Thread-safe holder for `Data` written from a background drain queue and
/// read from the main thread. Matches the pattern used in `CodeReviewGit`
/// so both helpers share the same concurrency story.
private final class GitHubCLIDataBox: @unchecked Sendable {
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

// MARK: - GitHubCLI

/// Namespace holding every `gh` invocation helper. Pure static methods so
/// the type itself is never instantiated. The enum-namespace shape matches
/// `CodeReviewGit` in the code review workflow module.
enum GitHubCLI {

    // MARK: Binary resolution

    /// Known `gh` install paths searched after `PATH` is exhausted. Ordered
    /// most-likely first: Homebrew on Apple Silicon, legacy Homebrew on
    /// Intel Macs, system /usr/bin.
    private static let fallbackGHPaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    /// Default absolute deadline for a single `gh` invocation.
    ///
    /// List operations (PRs, issues) normally return in <1s for small repos
    /// and <3s for large ones. 10s gives headroom for transient network
    /// slowness without hanging the UI when the user loses connectivity.
    static let defaultTimeout: TimeInterval = 10.0

    /// Resolves the absolute URL of the `gh` binary, or returns `nil` when
    /// no candidate is executable.
    ///
    /// - Parameters:
    ///   - fileManager: Injected so tests can stub executability checks.
    ///   - environment: Injected so tests can assemble a custom `PATH` without
    ///     leaking the host process environment into the test.
    static func resolveGHExecutableURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates: [String] = []

        if let path = environment["PATH"], !path.isEmpty {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/gh" })
        }
        candidates.append(contentsOf: fallbackGHPaths)

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            guard isSupportedGHExecutable(atPath: candidate, fileManager: fileManager) else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    /// Filters out obsolete npm packages named `gh`. Those packages are
    /// unrelated to GitHub CLI, can appear earlier in GUI-app PATHs, and fail
    /// with Node runtime errors such as "primordials is not defined".
    private static func isSupportedGHExecutable(
        atPath path: String,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.isExecutableFile(atPath: path) else { return false }

        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolvedPath.contains("/node_modules/gh/") {
            return false
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            return true
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 512),
              let text = String(data: data, encoding: .utf8) else {
            return true
        }

        let lower = text.lowercased()
        if lower.contains("#!/usr/bin/env node") || lower.contains("#!/usr/bin/node") {
            return false
        }
        return true
    }

    // MARK: Run

    /// Runs `gh <arguments>` inside `workingDirectory` and returns the raw
    /// stdout/stderr/exit code.
    ///
    /// The implementation mirrors `CodeReviewGit.run` to preserve the
    /// audited concurrency pattern:
    ///   - stdout and stderr are drained on a background queue in parallel
    ///     via `DispatchGroup`
    ///   - if `process.run()` throws, all pipe writing ends are closed so
    ///     the drain tasks receive EOF and `readGroup` unblocks
    ///   - timeout uses an absolute deadline against `DispatchSemaphore`,
    ///     not cumulative retries, so slow subprocesses fail fast with
    ///     useful diagnostic output
    ///
    /// The method is `throws` rather than `Result` so callers can bridge to
    /// `async`/`await` cleanly via `try await`.
    ///
    /// - Parameters:
    ///   - workingDirectory: Directory `gh` runs inside. Normally the tab's
    ///     worktree root or working directory.
    ///   - arguments: Arguments passed to `gh` verbatim (no shell quoting).
    ///   - timeoutSeconds: Absolute deadline enforced after `run()` succeeds.
    ///   - ghExecutableURLOverride: Escape hatch for tests that want to
    ///     point at a fake binary without mutating `PATH`.
    /// - Throws: `GitHubCLIError.notInstalled` when the binary cannot be
    ///   resolved, `GitHubCLIError.timeout` when the deadline fires, and
    ///   `GitHubCLIError.commandFailed` when the subprocess itself fails to
    ///   start.
    static func run(
        workingDirectory: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval = defaultTimeout,
        ghExecutableURLOverride: URL? = nil
    ) throws -> GitHubCLIResult {
        guard let ghURL = ghExecutableURLOverride ?? resolveGHExecutableURL() else {
            throw GitHubCLIError.notInstalled
        }

        let process = Process()
        process.executableURL = ghURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBox = GitHubCLIDataBox()
        let stderrBox = GitHubCLIDataBox()
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
            // Critical: close the write ends ourselves so the drain tasks
            // above see EOF and leave their group. Without this they would
            // block forever on `readDataToEndOfFile` and `readGroup.wait()`
            // at the caller would hang the thread permanently.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            readGroup.wait()
            throw GitHubCLIError.commandFailed(
                command: "gh " + arguments.joined(separator: " "),
                stderr: "\(error.localizedDescription)",
                exitCode: -1
            )
        }

        // Absolute deadline: fail fast instead of retry cumulativo.
        let completed = DispatchSemaphore(value: 0)
        readQueue.async {
            process.waitUntilExit()
            completed.signal()
        }

        let deadline = DispatchTime.now() + .milliseconds(Int(timeoutSeconds * 1000))
        let waitResult = completed.wait(timeout: deadline)

        if waitResult == .timedOut {
            process.terminate()
            // Give SIGTERM up to 500 ms to exit before we give up on a
            // clean shutdown; the reader group still gets drained in the
            // final `readGroup.wait()` once pipes close.
            _ = completed.wait(timeout: .now() + .milliseconds(500))
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = completed.wait(timeout: .now() + .milliseconds(200))
            }
            readGroup.wait()
            throw GitHubCLIError.timeout(seconds: timeoutSeconds)
        }

        readGroup.wait()

        return GitHubCLIResult(
            stdout: String(decoding: stdoutBox.data, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }

    // MARK: Error classification

    /// Maps a failed `gh` invocation into the typed error surface.
    ///
    /// The mapping is deliberately conservative: a stderr containing an
    /// unexpected phrase ends up as `.commandFailed` with the full stderr
    /// preserved, so the error banner can still render something useful.
    /// Classification checks are lowercased so we survive case flips in
    /// future `gh` releases without breaking the banner copy.
    ///
    /// - Parameters:
    ///   - command: The full `gh` command line, used for error messages.
    ///   - stderr: Raw stderr captured from the subprocess.
    ///   - exitCode: Subprocess termination status.
    static func classifyError(
        command: String,
        stderr: String,
        exitCode: Int32
    ) -> GitHubCLIError {
        let lower = stderr.lowercased()

        // Authentication issues. `gh` surfaces several forms; we match the
        // most common ones rather than rely on a single exit code, because
        // older `gh` versions and `gh auth refresh` paths print different
        // preambles.
        if lower.contains("authentication") ||
           lower.contains("not logged into") ||
           lower.contains("gh auth login") ||
           lower.contains("authentication token") {
            return .notAuthenticated(stderr: stderr)
        }

        // Rate limiting. `gh` prints "api rate limit exceeded" and sometimes
        // "x-ratelimit-remaining: 0"; both end up here.
        if lower.contains("rate limit") {
            return .rateLimited(resetAt: nil)
        }

        // Remote discovery failures. `gh repo view` without a remote produces
        // messages around "could not determine the current repository" on
        // newer `gh` and "no github remote" on older.
        if lower.contains("no github remote") ||
           lower.contains("no such remote") ||
           lower.contains("unable to determine the repository") ||
           lower.contains("could not determine the current repository") ||
           lower.contains("no remote configured") {
            return .noRemote
        }

        // Directory is not a git repo. Checked after remote lookup so an
        // unrelated repo with no remote maps to `.noRemote`, not
        // `.notAGitRepository`.
        if lower.contains("not a git repository") {
            return .notAGitRepository(path: "")
        }

        // Older `gh` builds may not support the JSON fields Cocxy requests
        // from newer commands such as `gh pr checks --json state,bucket`.
        // Keep the raw stderr for diagnostics but surface an actionable
        // update prompt instead of a confusing field-list dump.
        if (lower.contains("unknown json field") || lower.contains("invalid field")) &&
           lower.contains("available fields") {
            return .unsupportedVersion(stderr: stderr)
        }

        return .commandFailed(command: command, stderr: stderr, exitCode: exitCode)
    }
}
