// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TmuxSessionManager.swift - Manages persistent tmux sessions on remote hosts.

import Foundation

// MARK: - Tmux Session Info

/// Represents a tmux session running on a remote host.
///
/// Parsed from `tmux list-sessions -F` output, which provides structured
/// session metadata without ambiguous formatting.
struct TmuxSessionInfo: Identifiable, Codable, Equatable, Sendable {

    /// Unique identifier derived from profile ID + session name.
    var id: String { "\(profileID.uuidString):\(name)" }

    /// The remote profile this session belongs to.
    let profileID: UUID

    /// The tmux session name on the remote host.
    let name: String

    /// Number of windows in the session.
    let windowCount: Int

    /// Whether a client is currently attached to this session.
    let isAttached: Bool

    /// When the session was created (Unix timestamp from tmux).
    let createdAt: Date?

    /// Display string: "session-name (3 windows)" or "session-name (attached)".
    var displayTitle: String {
        if isAttached {
            return "\(name) (attached)"
        }
        let windowLabel = windowCount == 1 ? "1 window" : "\(windowCount) windows"
        return "\(name) (\(windowLabel))"
    }
}

// MARK: - Tmux Errors

/// Errors that can occur during tmux operations.
enum TmuxError: Error, Equatable {
    case notInstalled
    case sessionNotFound(String)
    case sessionAlreadyExists(String)
    case commandFailed(String)
    case parseError(String)
}

// MARK: - Remote Shell Support

/// Describes which session multiplexer is available on the remote host.
enum RemoteShellSupport: Equatable, Sendable {
    case tmux(version: String)
    case screen
    case none
}

// MARK: - Tmux Session Managing Protocol

/// Abstract interface for tmux session management over SSH.
///
/// Enables dependency injection in orchestrators that manage remote
/// persistent sessions. All operations execute through the SSH
/// ControlMaster, so no additional TCP connections are opened.
protocol TmuxSessionManaging: Sendable {

    /// Detects which session multiplexer is available on the remote host.
    func detectSupport(
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async -> RemoteShellSupport

    /// Lists all tmux sessions on the remote host.
    func listSessions(
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws -> [TmuxSessionInfo]

    /// Creates a new detached tmux session on the remote host.
    func createSession(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws

    /// Returns the SSH command string to attach to an existing tmux session.
    func attachCommand(
        sessionName: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing
    ) -> String

    /// Detaches all clients from a tmux session without killing it.
    func detachSession(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws

    /// Kills a tmux session on the remote host.
    func killSession(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws

    /// Checks whether a specific tmux session exists on the remote host.
    func sessionExists(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async -> Bool
}

// MARK: - Tmux Session Manager

/// Manages persistent tmux sessions on remote hosts via SSH.
///
/// All operations execute commands through the existing SSH ControlMaster
/// session, avoiding the overhead of opening new TCP connections.
///
/// ## Session Naming Convention
///
/// Sessions created by Cocxy use the prefix `cocxy-` to distinguish them
/// from user-created tmux sessions. For example: `cocxy-dev`, `cocxy-deploy`.
///
/// ## Workflow
///
/// 1. `detectSupport()` checks if tmux (preferred) or screen is installed.
/// 2. `createSession()` starts a new detached tmux session.
/// 3. `attachCommand()` returns the SSH command to attach (for the terminal PTY).
/// 4. On SSH disconnect, the tmux session persists on the server.
/// 5. On reconnect, `listSessions()` discovers surviving sessions.
/// 6. `attachCommand()` re-attaches without losing state.
struct TmuxSessionManager: TmuxSessionManaging, Sendable {

    /// Prefix for sessions created by Cocxy (to distinguish from user sessions).
    static let sessionPrefix = "cocxy-"

    // MARK: - Support Detection

    func detectSupport(
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async -> RemoteShellSupport {
        // Check tmux first (preferred).
        if let result = try? await multiplexer.executeRemoteCommand(
            "tmux -V 2>/dev/null",
            on: profile,
            executor: executor
        ), result.exitCode == 0 {
            let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return .tmux(version: version)
        }

        // Fallback: check screen.
        if let result = try? await multiplexer.executeRemoteCommand(
            "screen -v 2>/dev/null",
            on: profile,
            executor: executor
        ), result.exitCode == 0 {
            return .screen
        }

        return .none
    }

    // MARK: - List Sessions

    func listSessions(
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws -> [TmuxSessionInfo] {
        let format = "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_created}"
        let result = try await multiplexer.executeRemoteCommand(
            "tmux list-sessions -F '\(format)' 2>/dev/null",
            on: profile,
            executor: executor
        )

        // Exit code 1 with "no server running" means no sessions exist.
        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("no server running") || stderr.contains("no sessions") {
                return []
            }
            throw TmuxError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return parseSessions(from: result.stdout, profileID: profile.id)
    }

    // MARK: - Create Session

    func createSession(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws {
        let sanitized = sanitizeSessionName(name)

        // Check if session already exists.
        let exists = await sessionExists(
            named: sanitized,
            on: profile,
            multiplexer: multiplexer,
            executor: executor
        )
        if exists {
            throw TmuxError.sessionAlreadyExists(sanitized)
        }

        let result = try await multiplexer.executeRemoteCommand(
            "tmux new-session -d -s '\(sanitized)'",
            on: profile,
            executor: executor
        )

        if result.exitCode != 0 {
            throw TmuxError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    // MARK: - Attach Command

    func attachCommand(
        sessionName: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing
    ) -> String {
        let controlPath = multiplexer.controlPath(for: profile)
        let sanitized = sanitizeSessionName(sessionName)

        var parts: [String] = ["ssh"]
        parts.append("-o ControlMaster=no")
        parts.append("-o ControlPath=\(controlPath)")

        if let port = profile.port {
            parts.append("-p \(port)")
        }

        if let user = profile.user {
            parts.append("\(user)@\(profile.host)")
        } else {
            parts.append(profile.host)
        }

        parts.append("-t")
        parts.append("tmux attach-session -t '\(sanitized)'")

        return parts.joined(separator: " ")
    }

    // MARK: - Detach Session

    func detachSession(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws {
        let sanitized = sanitizeSessionName(name)
        let result = try await multiplexer.executeRemoteCommand(
            "tmux detach-client -s '\(sanitized)' 2>/dev/null; true",
            on: profile,
            executor: executor
        )

        // Detach is best-effort: if no clients attached, it's still fine.
        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if !stderr.contains("no clients") && !stderr.isEmpty {
                throw TmuxError.commandFailed(
                    result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
    }

    // MARK: - Kill Session

    func killSession(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async throws {
        let sanitized = sanitizeSessionName(name)
        let result = try await multiplexer.executeRemoteCommand(
            "tmux kill-session -t '\(sanitized)'",
            on: profile,
            executor: executor
        )

        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.lowercased().contains("session not found") {
                throw TmuxError.sessionNotFound(sanitized)
            }
            throw TmuxError.commandFailed(stderr)
        }
    }

    // MARK: - Session Exists

    func sessionExists(
        named name: String,
        on profile: RemoteConnectionProfile,
        multiplexer: any SSHMultiplexing,
        executor: any ProcessExecutor
    ) async -> Bool {
        let sanitized = sanitizeSessionName(name)
        guard let result = try? await multiplexer.executeRemoteCommand(
            "tmux has-session -t '\(sanitized)' 2>/dev/null",
            on: profile,
            executor: executor
        ) else {
            return false
        }
        return result.exitCode == 0
    }

    // MARK: - Parsing

    /// Parses `tmux list-sessions -F` output into structured session info.
    ///
    /// Expected format per line (tab-separated):
    /// `session-name\twindow-count\tattached-count\tcreated-timestamp`
    func parseSessions(
        from output: String,
        profileID: UUID
    ) -> [TmuxSessionInfo] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> TmuxSessionInfo? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 3 else { return nil }

                let name = String(fields[0])
                let windowCount = Int(fields[1]) ?? 1
                let attachedCount = Int(fields[2]) ?? 0
                let createdAt: Date? = fields.count >= 4
                    ? Date(timeIntervalSince1970: TimeInterval(String(fields[3])) ?? 0)
                    : nil

                return TmuxSessionInfo(
                    profileID: profileID,
                    name: name,
                    windowCount: windowCount,
                    isAttached: attachedCount > 0,
                    createdAt: createdAt
                )
            }
    }

    // MARK: - Sanitization

    /// Sanitizes a session name for safe use in tmux commands.
    ///
    /// tmux session names cannot contain periods or colons.
    /// Replaces unsafe characters with hyphens and limits length.
    func sanitizeSessionName(_ name: String) -> String {
        let sanitized = name
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: " ", with: "-")

        // Limit to 64 characters (tmux practical limit).
        if sanitized.count > 64 {
            return String(sanitized.prefix(64))
        }
        return sanitized
    }
}
