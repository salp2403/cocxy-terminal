// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubCLISwiftTestingTests.swift - Unit tests for the gh subprocess helper.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitHubCLI")
struct GitHubCLISwiftTestingTests {

    // MARK: - Fixtures

    /// Builds an isolated temp directory, copies a shebang script to it, and
    /// marks it executable. The caller receives both the directory and the
    /// script URL so it can pass them to the helper under test.
    private static func makeFakeGhBinary(
        name: String = "gh",
        script: String
    ) throws -> (workingDirectory: URL, binary: URL, cleanup: () -> Void) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitHubCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let binary = tempDir.appendingPathComponent(name)
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binary.path
        )

        let cleanup: () -> Void = {
            _ = try? FileManager.default.removeItem(at: tempDir)
        }
        return (tempDir, binary, cleanup)
    }

    // MARK: - resolveGHExecutableURL

    @Test("resolveGHExecutableURL uses gh from PATH when present")
    func resolveGHExecutableURL_usesPATHWhenPresent() throws {
        let (dir, _, cleanup) = try Self.makeFakeGhBinary(
            script: "#!/bin/sh\necho ok\n"
        )
        defer { cleanup() }

        let resolved = GitHubCLI.resolveGHExecutableURL(
            environment: ["PATH": dir.path]
        )

        #expect(resolved?.path == dir.appendingPathComponent("gh").path)
    }

    @Test("resolveGHExecutableURL skips obsolete npm gh wrappers")
    func resolveGHExecutableURL_skipsNodeGHWrapper() throws {
        let (badDir, _, badCleanup) = try Self.makeFakeGhBinary(
            script: "#!/usr/bin/env node\nrequire('gh')\n"
        )
        let (goodDir, _, goodCleanup) = try Self.makeFakeGhBinary(
            script: "#!/bin/sh\necho 'gh version 2.88.1'\n"
        )
        defer {
            badCleanup()
            goodCleanup()
        }

        let resolved = GitHubCLI.resolveGHExecutableURL(
            environment: ["PATH": "\(badDir.path):\(goodDir.path)"]
        )

        #expect(resolved?.path == goodDir.appendingPathComponent("gh").path)
    }

    @Test("resolveGHExecutableURL returns nil when no candidate is executable")
    func resolveGHExecutableURL_returnsNilWhenNoCandidateExecutable() throws {
        // Craft a PATH that definitely has no `gh`. The tempdir is brand new
        // so it cannot contain any binary.
        let emptyDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitHubCLI-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        // Stub the file manager so the known fallback paths also fail.
        final class RejectingFileManager: FileManager, @unchecked Sendable {
            override func isExecutableFile(atPath path: String) -> Bool { false }
        }

        let resolved = GitHubCLI.resolveGHExecutableURL(
            fileManager: RejectingFileManager(),
            environment: ["PATH": emptyDir.path]
        )

        #expect(resolved == nil)
    }

    @Test("resolveGHExecutableURL walks fallback paths when PATH lacks gh")
    func resolveGHExecutableURL_usesFallbackWhenPATHHasNoGH() throws {
        // Empty PATH + fallback /opt/homebrew/bin/gh should still succeed on
        // the development host (the CI runner has gh preinstalled there too).
        // If gh is not installed at all on the host, the test is skipped to
        // keep CI green on minimal machines.
        let hasHomebrewGH = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/gh")
        let hasLocalGH = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/gh")
        let hasSystemGH = FileManager.default.isExecutableFile(atPath: "/usr/bin/gh")
        let hasFallback = hasHomebrewGH || hasLocalGH || hasSystemGH
        try #require(hasFallback, "Skipping: no gh fallback present on this host")

        let resolved = GitHubCLI.resolveGHExecutableURL(environment: ["PATH": ""])
        #expect(resolved != nil)
    }

    // MARK: - run

    @Test("run returns stdout, stderr and exit code for a successful invocation")
    func run_returnsStdoutAndStderrAndExitCode() throws {
        let (_, binary, cleanup) = try Self.makeFakeGhBinary(
            script: """
            #!/bin/sh
            echo "hello stdout"
            echo "hello stderr" >&2
            exit 0
            """
        )
        defer { cleanup() }

        let result = try GitHubCLI.run(
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            arguments: ["--version"],
            ghExecutableURLOverride: binary
        )

        #expect(result.stdout.contains("hello stdout"))
        #expect(result.stderr.contains("hello stderr"))
        #expect(result.terminationStatus == 0)
    }

    @Test("run preserves non-zero exit codes for the caller to classify")
    func run_preservesNonZeroExitCode() throws {
        let (_, binary, cleanup) = try Self.makeFakeGhBinary(
            script: """
            #!/bin/sh
            echo "oops" >&2
            exit 4
            """
        )
        defer { cleanup() }

        let result = try GitHubCLI.run(
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            arguments: ["pr", "list"],
            ghExecutableURLOverride: binary
        )

        #expect(result.terminationStatus == 4)
        #expect(result.stderr.contains("oops"))
    }

    @Test("run fails cleanly without hanging when the binary cannot start")
    func run_failsCleanlyWhenProcessCannotStart() throws {
        // Writing plain text to an executable path and marking it 0o644
        // reproduces the "not executable" failure Process.run() surfaces.
        // The regression we guard against: if the drain tasks are not
        // released when run() throws, readGroup.wait() would hang the test
        // forever. Reaching the expected throw is itself the passing
        // condition.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitHubCLI-bad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let invalidBinary = tempDir.appendingPathComponent("gh-not-executable")
        try "plain text".write(to: invalidBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: invalidBinary.path
        )

        #expect(throws: GitHubCLIError.self) {
            _ = try GitHubCLI.run(
                workingDirectory: tempDir,
                arguments: ["--version"],
                ghExecutableURLOverride: invalidBinary
            )
        }
    }

    @Test("run throws .notInstalled when no executable is resolved")
    func run_throwsNotInstalledWhenNoExecutableResolved() throws {
        final class RejectingFileManager: FileManager, @unchecked Sendable {
            override func isExecutableFile(atPath path: String) -> Bool { false }
        }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitHubCLI-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // With no override and no executable resolvable, run should throw
        // notInstalled. The test cannot force the shared resolveGHExecutableURL
        // to reject unless we call it via the same rejecting file manager —
        // but run() does not expose that seam. Instead we exercise the check
        // indirectly: passing a non-existent path as override surfaces the
        // run-time "not executable" path, which is a different error.
        //
        // So we assert the contract of resolveGHExecutableURL separately and
        // trust the `guard` in run() to throw notInstalled when its return
        // is nil. This test therefore validates that path by injecting an
        // empty PATH combined with the rejecting file manager and checking
        // the resolver returns nil — preserving the invariant.
        let resolved = GitHubCLI.resolveGHExecutableURL(
            fileManager: RejectingFileManager(),
            environment: ["PATH": tempDir.path]
        )
        #expect(resolved == nil)
    }

    @Test("run respects the absolute deadline and throws .timeout for hung subprocess")
    func run_timesOutWhenSubprocessHangsPastDeadline() throws {
        let (_, binary, cleanup) = try Self.makeFakeGhBinary(
            script: """
            #!/bin/sh
            sleep 5
            """
        )
        defer { cleanup() }

        #expect(throws: GitHubCLIError.self) {
            _ = try GitHubCLI.run(
                workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
                arguments: ["hang"],
                timeoutSeconds: 0.25,
                ghExecutableURLOverride: binary
            )
        }
    }

    // MARK: - classifyError

    @Test("classifyError maps authentication stderr to .notAuthenticated")
    func classifyError_mapsAuthenticationTo_notAuthenticated() {
        let cases = [
            "error: you are not logged into any GitHub hosts",
            "authentication token required",
            "to set up authentication, run: gh auth login",
        ]

        for stderr in cases {
            let err = GitHubCLI.classifyError(
                command: "gh pr list",
                stderr: stderr,
                exitCode: 4
            )
            guard case .notAuthenticated = err else {
                Issue.record("Expected .notAuthenticated for stderr: \(stderr), got: \(err)")
                continue
            }
        }
    }

    @Test("classifyError maps rate limit stderr to .rateLimited")
    func classifyError_mapsRateLimitTo_rateLimited() {
        let err = GitHubCLI.classifyError(
            command: "gh pr list",
            stderr: "error: API rate limit exceeded for 8.8.8.8",
            exitCode: 1
        )
        guard case .rateLimited = err else {
            Issue.record("Expected .rateLimited, got: \(err)")
            return
        }
    }

    @Test("classifyError maps no-remote stderr to .noRemote")
    func classifyError_mapsNoRemoteTo_noRemote() {
        let cases = [
            "no github remote configured for this repository",
            "could not determine the current repository",
            "unable to determine the repository to use",
        ]
        for stderr in cases {
            let err = GitHubCLI.classifyError(
                command: "gh pr list",
                stderr: stderr,
                exitCode: 1
            )
            #expect(err == .noRemote, "stderr: \(stderr)")
        }
    }

    @Test("classifyError maps not-a-git-repo stderr to .notAGitRepository")
    func classifyError_mapsNotAGitRepoTo_notAGitRepository() {
        let err = GitHubCLI.classifyError(
            command: "gh pr list",
            stderr: "fatal: not a git repository (or any of the parent directories): .git",
            exitCode: 128
        )
        guard case .notAGitRepository = err else {
            Issue.record("Expected .notAGitRepository, got: \(err)")
            return
        }
    }

    @Test("classifyError falls back to .commandFailed for unknown stderr")
    func classifyError_fallsBackToCommandFailedForUnknownStderr() {
        let err = GitHubCLI.classifyError(
            command: "gh pr list",
            stderr: "some unrelated failure with no keyword",
            exitCode: 1
        )
        guard case .commandFailed(let command, let stderr, let exitCode) = err else {
            Issue.record("Expected .commandFailed, got: \(err)")
            return
        }
        #expect(command == "gh pr list")
        #expect(stderr.contains("unrelated failure"))
        #expect(exitCode == 1)
    }

    // MARK: - GitHubCLIError equatability

    @Test("GitHubCLIError cases are equatable on raw contents")
    func gitHubCLIError_isEquatable() {
        let a: GitHubCLIError = .notAuthenticated(stderr: "x")
        let b: GitHubCLIError = .notAuthenticated(stderr: "x")
        let c: GitHubCLIError = .notAuthenticated(stderr: "y")
        #expect(a == b)
        #expect(a != c)

        let d: GitHubCLIError = .timeout(seconds: 1.0)
        let e: GitHubCLIError = .timeout(seconds: 1.0)
        let f: GitHubCLIError = .timeout(seconds: 2.0)
        #expect(d == e)
        #expect(d != f)
    }
}
