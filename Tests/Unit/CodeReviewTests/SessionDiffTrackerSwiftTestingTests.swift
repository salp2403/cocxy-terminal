// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("SessionDiffTracker", .serialized)
struct SessionDiffTrackerSwiftTestingTests {
    @Test("snapshotRef stores git HEAD for session")
    func snapshot() {
        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(
            sessionId: "s1",
            ref: "abc123",
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        #expect(tracker.snapshotRef(for: "s1") == "abc123")
    }

    @Test("removeSnapshot cleans up")
    func removeSnapshot() {
        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(
            sessionId: "s1",
            ref: "abc123",
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        tracker.removeSnapshot(sessionId: "s1")
        #expect(tracker.snapshotRef(for: "s1") == nil)
    }

    @Test("trackedFiles accumulates per session")
    func trackedFiles() {
        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(
            sessionId: "s1",
            ref: "abc123",
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        tracker.trackFile(sessionId: "s1", filePath: "foo.swift", agentName: "Claude Code")
        tracker.trackFile(sessionId: "s1", filePath: "bar.swift", agentName: "Claude Code")
        let files = tracker.trackedFiles(for: "s1")
        #expect(files.count == 2)
        #expect(files.contains("foo.swift"))
    }

    @Test("SessionStart event records pending snapshot directory")
    func sessionStartTriggersPendingSnapshot() {
        let tracker = SessionDiffTrackerImpl(gitRunner: { _, _ in "abc123\n" })
        let event = HookEvent(
            type: .sessionStart,
            sessionId: "test-session",
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                model: "claude-3",
                agentType: "Claude Code",
                workingDirectory: "/tmp"
            )),
            cwd: "/tmp"
        )

        tracker.handleHookEvent(event)
        #expect(tracker.pendingSnapshot(for: "test-session")?.path == "/tmp")
    }

    @Test("duplicate SessionStart events for the same session do not launch redundant head snapshots")
    func duplicateSessionStartDeduplicatesSnapshotLookup() async throws {
        let gate = DispatchSemaphore(value: 0)
        let headCalls = CounterBox()
        let tracker = SessionDiffTrackerImpl(gitRunner: { _, arguments in
            if arguments == ["rev-parse", "--show-toplevel"] {
                return "/tmp\n"
            }
            if arguments == ["rev-parse", "HEAD"] {
                headCalls.increment()
                gate.wait()
                return "abc123\n"
            }
            return ""
        })

        let event = HookEvent(
            type: .sessionStart,
            sessionId: "dup-session",
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                model: "claude-3",
                agentType: "Claude Code",
                workingDirectory: "/tmp"
            )),
            cwd: "/tmp"
        )

        tracker.handleHookEvent(event)
        tracker.handleHookEvent(event)

        try await waitForTrackerCondition {
            headCalls.value == 1
        }

        gate.signal()
        try await waitForTrackerCondition {
            tracker.pendingSnapshot(for: "dup-session") == nil
        }
        #expect(headCalls.value == 1)
    }

    @Test("PostToolUse with Write tracks file")
    func postToolUseTracksFile() {
        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(
            sessionId: "s1",
            ref: "abc",
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let event = HookEvent(
            type: .postToolUse,
            sessionId: "s1",
            timestamp: Date(),
            data: .toolUse(ToolUseData(
                toolName: "Write",
                toolInput: ["file_path": "/tmp/foo.swift"],
                result: nil,
                error: nil
            )),
            cwd: "/tmp"
        )
        tracker.handleHookEvent(event)
        #expect(tracker.trackedFiles(for: "s1").contains("foo.swift"))
    }

    @Test("computeDiff returns session scoped diff and attribution")
    func computeDiff() async throws {
        let repo = try makeGitFixtureRepo()
        defer { cleanup(repo) }

        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(sessionId: "s1", ref: repo.head, workingDirectory: repo.url)
        tracker.trackFile(sessionId: "s1", filePath: "tracked.txt", agentName: "Claude Code")

        let diffs = try await diffResult(from: tracker, sessionId: "s1", mode: .sinceSessionStart, reference: nil)
        #expect(diffs.count == 1)
        #expect(diffs[0].filePath == "tracked.txt")
        #expect(diffs[0].agentName == "Claude Code")
        #expect(diffs[0].additions == 1)
    }

    @Test("computeDiff synthesizes untracked files")
    func computeDiffIncludesUntrackedFile() async throws {
        let repo = try makeGitFixtureRepo()
        defer { cleanup(repo) }

        let newFile = repo.url.appendingPathComponent("new.swift")
        try "print(\"hello\")\n".write(to: newFile, atomically: true, encoding: .utf8)

        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(sessionId: "s1", ref: repo.head, workingDirectory: repo.url)
        tracker.trackFile(sessionId: "s1", filePath: "new.swift", agentName: "Codex CLI")

        let diffs = try await diffResult(from: tracker, sessionId: "s1", mode: .sinceSessionStart, reference: nil)
        #expect(diffs.count == 1)
        #expect(diffs[0].filePath == "new.swift")
        #expect(diffs[0].status == .untracked)
        #expect(diffs[0].agentName == "Codex CLI")
        #expect(diffs[0].additions == 1)
    }

    @Test("review rounds append per session")
    func reviewRoundsAppend() {
        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(
            sessionId: "s1",
            ref: "abc123",
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )
        let round = ReviewRound(id: 1, timestamp: Date(), baseRef: "abc123", diffs: [], comments: [])
        tracker.appendReviewRound(sessionId: "s1", round: round)
        #expect(tracker.reviewRounds(for: "s1").count == 1)
    }

    @Test("sinceSessionStart falls back to working tree when the repo has no commits yet")
    func sinceSessionStartWithoutCommitsFallsBack() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-review-empty-head-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try runGit(["init"], in: root)
        _ = try runGit(["config", "user.name", "Code Review Tests"], in: root)
        _ = try runGit(["config", "user.email", "tests@cocxy.dev"], in: root)

        let tracker = SessionDiffTrackerImpl()
        let sessionStart = HookEvent(
            type: .sessionStart,
            sessionId: "no-commit",
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                model: "claude-3",
                agentType: "Claude Code",
                workingDirectory: root.path
            )),
            cwd: root.path
        )
        tracker.handleHookEvent(sessionStart)
        try await waitForTrackerCondition {
            tracker.pendingSnapshot(for: "no-commit") == nil
        }

        let fileURL = root.appendingPathComponent("new.swift")
        try "print(\"hi\")\n".write(to: fileURL, atomically: true, encoding: .utf8)
        tracker.trackFile(sessionId: "no-commit", filePath: fileURL.path, agentName: "Claude Code")

        let diffs = try await diffResult(from: tracker, sessionId: "no-commit", mode: .sinceSessionStart, reference: nil)
        #expect(diffs.count == 1)
        #expect(diffs[0].filePath == "new.swift")
        #expect(diffs[0].status == .untracked)
        #expect(tracker.snapshotNotice(for: "no-commit")?.contains("working tree") == true)
    }

    @Test("repo root normalization keeps tracked files outside the tab cwd")
    func sinceSessionStartUsesRepoRootForTrackedFilesOutsideCwd() async throws {
        let repo = try makeGitFixtureRepo(includeSiblingDirectory: true)
        defer { cleanup(repo) }

        let workingSubdirectory = repo.url.appendingPathComponent("subdir", isDirectory: true)
        let tracker = SessionDiffTrackerImpl()
        let sessionStart = HookEvent(
            type: .sessionStart,
            sessionId: "repo-root",
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                model: "claude-3",
                agentType: "Claude Code",
                workingDirectory: workingSubdirectory.path
            )),
            cwd: workingSubdirectory.path
        )
        tracker.handleHookEvent(sessionStart)
        try await waitForTrackerCondition {
            tracker.pendingSnapshot(for: "repo-root") == nil
        }

        let siblingFile = repo.url.appendingPathComponent("other/tracked.txt")
        try "baseline\nchanged outside cwd\n".write(to: siblingFile, atomically: true, encoding: .utf8)
        tracker.trackFile(sessionId: "repo-root", filePath: siblingFile.path, agentName: "Claude Code")

        let diffs = try await diffResult(from: tracker, sessionId: "repo-root", mode: .sinceSessionStart, reference: nil)
        #expect(diffs.count == 1)
        #expect(diffs[0].filePath == "other/tracked.txt")
        #expect(diffs[0].agentName == "Claude Code")
    }

    @Test("removeSnapshot does not get resurrected by an in-flight head capture")
    func removeSnapshotWinsOverInFlightHeadCapture() async throws {
        let gate = DispatchSemaphore(value: 0)
        let callCount = CounterBox()
        let tracker = SessionDiffTrackerImpl(gitRunner: { _, arguments in
            callCount.increment()
            gate.wait()
            if arguments.contains("--show-toplevel") {
                return "/tmp\n"
            }
            return "abc123\n"
        })

        let event = HookEvent(
            type: .sessionStart,
            sessionId: "race",
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                model: "claude-3",
                agentType: "Claude Code",
                workingDirectory: "/tmp"
            )),
            cwd: "/tmp"
        )
        tracker.handleHookEvent(event)
        tracker.removeSnapshot(sessionId: "race")

        gate.signal()
        gate.signal()
        try await waitForTrackerCondition {
            callCount.value >= 1
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(tracker.snapshotRef(for: "race") == nil)
        #expect(tracker.workingDirectory(for: "race") == nil)
    }

    @Test("snapshot storage evicts the oldest sessions to cap memory growth")
    func snapshotEviction() {
        let tracker = SessionDiffTrackerImpl()

        for index in 0..<70 {
            tracker.recordSnapshot(
                sessionId: "s\(index)",
                ref: "ref-\(index)",
                workingDirectory: URL(fileURLWithPath: "/tmp/\(index)", isDirectory: true)
            )
        }

        #expect(tracker.snapshotRef(for: "s0") == nil)
        #expect(tracker.snapshotRef(for: "s69") == "ref-69")
    }

    @Test("git executable resolution honors PATH fallbacks instead of hardcoding /usr/bin/git")
    func gitResolutionUsesSearchPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-review-git-resolution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fakeGit = root.appendingPathComponent("git")
        try "#!/bin/sh\nexit 0\n".write(to: fakeGit, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGit.path)

        let resolved = CodeReviewGit.resolveGitExecutableURL(environment: ["PATH": root.path])
        #expect(resolved?.path == fakeGit.path)
    }

    @Test("git runner throws promptly when the executable cannot be launched")
    func gitRunFailsCleanlyWhenProcessCannotStart() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-review-git-run-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let invalidExecutable = root.appendingPathComponent("not-a-real-executable")
        try "plain text".write(to: invalidExecutable, atomically: true, encoding: .utf8)

        #expect(throws: Error.self) {
            _ = try CodeReviewGit.run(
                workingDirectory: root,
                arguments: ["status"],
                gitExecutableURLOverride: invalidExecutable
            )
        }
    }

    private func diffResult(
        from tracker: SessionDiffTrackerImpl,
        sessionId: String,
        mode: DiffMode,
        reference: String?
    ) async throws -> [FileDiff] {
        try await withCheckedThrowingContinuation { continuation in
            tracker.computeDiff(sessionId: sessionId, mode: mode, reference: reference) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func makeGitFixtureRepo(includeSiblingDirectory: Bool = false) throws -> (url: URL, head: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-review-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if includeSiblingDirectory {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("subdir", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("other", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        _ = try runGit(["init"], in: root)
        _ = try runGit(["config", "user.name", "Code Review Tests"], in: root)
        _ = try runGit(["config", "user.email", "tests@cocxy.dev"], in: root)

        let trackedFile = includeSiblingDirectory
            ? root.appendingPathComponent("other/tracked.txt")
            : root.appendingPathComponent("tracked.txt")
        try "baseline\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "."], in: root)
        _ = try runGit(["commit", "-m", "Initial fixture"], in: root)
        let head = try runGit(["rev-parse", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)

        try "baseline\nchanged\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        return (root, head)
    }

    private func cleanup(_ repo: (url: URL, head: String)) {
        try? FileManager.default.removeItem(at: repo.url)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let result = try CodeReviewGit.run(workingDirectory: directory, arguments: arguments)

        guard result.terminationStatus == 0 else {
            let error = result.stderr
            throw NSError(domain: "SessionDiffTrackerSwiftTestingTests", code: Int(result.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: error.isEmpty ? "git \(arguments.joined(separator: " ")) failed" : error
            ])
        }

        return result.stdout
    }

    private func waitForTrackerCondition(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while condition() == false {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                Issue.record("Timed out waiting for tracker condition")
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }
}
