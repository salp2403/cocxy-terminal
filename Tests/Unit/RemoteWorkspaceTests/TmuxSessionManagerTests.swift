// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TmuxSessionManagerTests.swift - Tests for tmux session management via SSH.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Scriptable Mock Multiplexer

/// Multiplexer mock that returns configurable results for remote commands.
final class ScriptableSSHMultiplexer: SSHMultiplexing, @unchecked Sendable {
    var commandResults: [String: ProcessResult] = [:]
    var executedCommands: [String] = []

    func connect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool { true }
    func controlPath(for profile: RemoteConnectionProfile) -> String { profile.controlPath }
    func newSession(profile: RemoteConnectionProfile) -> String { "ssh mock" }
    func forwardPort(_ forward: RemoteConnectionProfile.PortForward, on profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}
    func cancelForward(_ forward: RemoteConnectionProfile.PortForward, on profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {}

    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        executedCommands.append(command)
        // Match by prefix for flexibility.
        for (key, result) in commandResults {
            if command.contains(key) {
                return result
            }
        }
        return ProcessResult(exitCode: 1, stdout: "", stderr: "command not found")
    }
}

// MARK: - Tmux Session Manager Tests

@Suite("TmuxSessionManager")
struct TmuxSessionManagerTests {

    private let manager = TmuxSessionManager()
    private let profile = RemoteConnectionProfile(name: "dev", host: "server.com", user: "root")
    private let executor = MockProcessExecutor()

    // MARK: - Support Detection

    @Test func detectTmuxSupport() async {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["tmux -V"] = ProcessResult(
            exitCode: 0, stdout: "tmux 3.4\n", stderr: ""
        )

        let support = await manager.detectSupport(
            on: profile, multiplexer: multiplexer, executor: executor
        )

        #expect(support == .tmux(version: "tmux 3.4"))
    }

    @Test func detectScreenFallback() async {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["screen -v"] = ProcessResult(
            exitCode: 0, stdout: "Screen version 4.09.01\n", stderr: ""
        )

        let support = await manager.detectSupport(
            on: profile, multiplexer: multiplexer, executor: executor
        )

        #expect(support == .screen)
    }

    @Test func detectNoSupport() async {
        let multiplexer = ScriptableSSHMultiplexer()

        let support = await manager.detectSupport(
            on: profile, multiplexer: multiplexer, executor: executor
        )

        #expect(support == .none)
    }

    // MARK: - List Sessions

    @Test func listSessionsParsesTmuxOutput() async throws {
        let multiplexer = ScriptableSSHMultiplexer()
        let output = "dev\t3\t1\t1711700000\nstaging\t1\t0\t1711600000\n"
        multiplexer.commandResults["list-sessions"] = ProcessResult(
            exitCode: 0, stdout: output, stderr: ""
        )

        let sessions = try await manager.listSessions(
            on: profile, multiplexer: multiplexer, executor: executor
        )

        #expect(sessions.count == 2)
        #expect(sessions[0].name == "dev")
        #expect(sessions[0].windowCount == 3)
        #expect(sessions[0].isAttached == true)
        #expect(sessions[1].name == "staging")
        #expect(sessions[1].windowCount == 1)
        #expect(sessions[1].isAttached == false)
    }

    @Test func listSessionsReturnsEmptyWhenNoServer() async throws {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["list-sessions"] = ProcessResult(
            exitCode: 1, stdout: "", stderr: "no server running on /tmp/tmux-1000/default"
        )

        let sessions = try await manager.listSessions(
            on: profile, multiplexer: multiplexer, executor: executor
        )

        #expect(sessions.isEmpty)
    }

    @Test func listSessionsThrowsOnRealError() async {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["list-sessions"] = ProcessResult(
            exitCode: 1, stdout: "", stderr: "permission denied"
        )

        do {
            _ = try await manager.listSessions(
                on: profile, multiplexer: multiplexer, executor: executor
            )
            Issue.record("Expected TmuxError.commandFailed")
        } catch {
            #expect(error is TmuxError)
        }
    }

    // MARK: - Create Session

    @Test func createSessionSucceeds() async throws {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["has-session"] = ProcessResult(
            exitCode: 1, stdout: "", stderr: "session not found"
        )
        multiplexer.commandResults["new-session"] = ProcessResult(
            exitCode: 0, stdout: "", stderr: ""
        )

        try await manager.createSession(
            named: "work",
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )

        #expect(multiplexer.executedCommands.contains { $0.contains("new-session") })
    }

    @Test func createSessionThrowsWhenAlreadyExists() async {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["has-session"] = ProcessResult(
            exitCode: 0, stdout: "", stderr: ""
        )

        do {
            try await manager.createSession(
                named: "work",
                on: profile,
                multiplexer: multiplexer,
                executor: executor
            )
            Issue.record("Expected TmuxError.sessionAlreadyExists")
        } catch let error as TmuxError {
            if case .sessionAlreadyExists = error {
                // Expected.
            } else {
                Issue.record("Expected sessionAlreadyExists, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Attach Command

    @Test func attachCommandFormatsCorrectly() {
        let multiplexer = ScriptableSSHMultiplexer()

        let command = manager.attachCommand(
            sessionName: "dev",
            on: profile,
            multiplexer: multiplexer
        )

        #expect(command.contains("tmux attach-session -t 'dev'"))
        #expect(command.contains("ControlMaster=no"))
        #expect(command.contains("root@server.com"))
        #expect(command.contains("-t"))
    }

    @Test func attachCommandIncludesPort() {
        let portProfile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root", port: 2222
        )
        let multiplexer = ScriptableSSHMultiplexer()

        let command = manager.attachCommand(
            sessionName: "work",
            on: portProfile,
            multiplexer: multiplexer
        )

        #expect(command.contains("-p 2222"))
    }

    // MARK: - Kill Session

    @Test func killSessionSucceeds() async throws {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["kill-session"] = ProcessResult(
            exitCode: 0, stdout: "", stderr: ""
        )

        try await manager.killSession(
            named: "old-session",
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )

        #expect(multiplexer.executedCommands.contains { $0.contains("kill-session") })
    }

    @Test func killSessionThrowsWhenNotFound() async {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["kill-session"] = ProcessResult(
            exitCode: 1, stdout: "", stderr: "session not found: ghost"
        )

        do {
            try await manager.killSession(
                named: "ghost",
                on: profile,
                multiplexer: multiplexer,
                executor: executor
            )
            Issue.record("Expected TmuxError.sessionNotFound")
        } catch let error as TmuxError {
            if case .sessionNotFound = error {
                // Expected.
            } else {
                Issue.record("Expected sessionNotFound, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Session Exists

    @Test func sessionExistsReturnsTrue() async {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["has-session"] = ProcessResult(
            exitCode: 0, stdout: "", stderr: ""
        )

        let exists = await manager.sessionExists(
            named: "dev",
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )

        #expect(exists == true)
    }

    @Test func sessionExistsReturnsFalse() async {
        let multiplexer = ScriptableSSHMultiplexer()
        multiplexer.commandResults["has-session"] = ProcessResult(
            exitCode: 1, stdout: "", stderr: "session not found"
        )

        let exists = await manager.sessionExists(
            named: "ghost",
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )

        #expect(exists == false)
    }

    // MARK: - Parsing

    @Test func parseSessionsHandlesEmptyOutput() {
        let sessions = manager.parseSessions(from: "", profileID: UUID())
        #expect(sessions.isEmpty)
    }

    @Test func parseSessionsHandlesMalformedLines() {
        let sessions = manager.parseSessions(from: "broken-line\n", profileID: UUID())
        #expect(sessions.isEmpty)
    }

    @Test func parseSessionsHandlesMinimalFields() {
        let output = "simple\t2\t0\n"
        let profileID = UUID()
        let sessions = manager.parseSessions(from: output, profileID: profileID)

        #expect(sessions.count == 1)
        #expect(sessions[0].name == "simple")
        #expect(sessions[0].windowCount == 2)
        #expect(sessions[0].isAttached == false)
        #expect(sessions[0].profileID == profileID)
    }

    // MARK: - Sanitization

    @Test func sanitizeSessionNameReplacesUnsafeCharacters() {
        #expect(manager.sanitizeSessionName("my.session") == "my-session")
        #expect(manager.sanitizeSessionName("host:port") == "host-port")
        #expect(manager.sanitizeSessionName("it's mine") == "its-mine")
        #expect(manager.sanitizeSessionName("with spaces") == "with-spaces")
    }

    @Test func sanitizeSessionNameTruncatesLongNames() {
        let longName = String(repeating: "a", count: 100)
        let sanitized = manager.sanitizeSessionName(longName)
        #expect(sanitized.count == 64)
    }

    @Test func sanitizeSessionNamePreservesValidNames() {
        #expect(manager.sanitizeSessionName("cocxy-dev") == "cocxy-dev")
        #expect(manager.sanitizeSessionName("my_session_123") == "my_session_123")
    }

    // MARK: - Display Title

    @Test func sessionDisplayTitleShowsAttached() {
        let session = TmuxSessionInfo(
            profileID: UUID(), name: "dev", windowCount: 2,
            isAttached: true, createdAt: nil
        )
        #expect(session.displayTitle == "dev (attached)")
    }

    @Test func sessionDisplayTitleShowsWindowCount() {
        let session = TmuxSessionInfo(
            profileID: UUID(), name: "dev", windowCount: 3,
            isAttached: false, createdAt: nil
        )
        #expect(session.displayTitle == "dev (3 windows)")
    }

    @Test func sessionDisplayTitleSingularWindow() {
        let session = TmuxSessionInfo(
            profileID: UUID(), name: "dev", windowCount: 1,
            isAttached: false, createdAt: nil
        )
        #expect(session.displayTitle == "dev (1 window)")
    }
}
