// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonProtocol.swift - JSON lines protocol for daemon communication.

import Foundation

// MARK: - Daemon Commands

/// All commands supported by the cocxyd daemon protocol.
enum DaemonCommand: String, CaseIterable, Sendable {
    case sessionList = "session.list"
    case sessionCreate = "session.create"
    case sessionAttach = "session.attach"
    case sessionDetach = "session.detach"
    case sessionInput = "session.input"
    case sessionOutput = "session.output"
    case sessionKill = "session.kill"
    case forwardList = "forward.list"
    case forwardAdd = "forward.add"
    case forwardRemove = "forward.remove"
    case status = "status"
    case syncWatch = "sync.watch"
    case syncChanges = "sync.changes"
    case ping = "ping"
    case shutdown = "shutdown"
}

// MARK: - Daemon Request

/// A request message to the cocxyd daemon.
///
/// ## Wire Format (JSON line)
///
/// ```json
/// {"proto":1,"id":"req-1","cmd":"session.list","args":{"title":"my-session"}}
/// ```
///
/// The `proto` field enables backward compatibility. The daemon can reject
/// requests with an unsupported protocol version gracefully.
struct DaemonRequest: Codable, Sendable {

    /// Protocol version (always 1 for now).
    let proto: Int

    /// Unique request ID for response correlation.
    let id: String

    /// The command to execute.
    let cmd: String

    /// Optional arguments for the command.
    var args: [String: String]?

    init(id: String, cmd: String, args: [String: String]? = nil) {
        self.proto = 1
        self.id = id
        self.cmd = cmd
        self.args = args
    }

    /// Serializes the request to a JSON line (single line + newline).
    func jsonLine() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let line = String(data: data, encoding: .utf8) else {
            throw DaemonProtocolError.encodingFailed
        }
        return line + "\n"
    }
}

// MARK: - Daemon Response

/// A response message from the cocxyd daemon.
///
/// ## Wire Format (JSON line)
///
/// Success: `{"ok":true,"id":"req-1","data":{"sessions":[...]}}`
/// Error:   `{"ok":false,"id":"req-1","error":"not found"}`
///
/// Uses `JSONSerialization` instead of `Codable` because `data` can contain
/// arbitrary nested structures (session lists, status info, etc.).
struct DaemonResponse: @unchecked Sendable {

    /// Whether the request succeeded.
    let ok: Bool

    /// The request ID this response correlates to.
    let id: String?

    /// Arbitrary response data (varies by command).
    let data: [String: Any]?

    /// Error message when `ok` is false.
    let error: String?

    /// Parses a JSON line into a response.
    ///
    /// - Parameter line: A single line of JSON text.
    /// - Returns: The parsed response.
    static func parse(_ line: String) throws -> DaemonResponse {
        guard let jsonData = line.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            throw DaemonProtocolError.invalidResponse
        }

        return DaemonResponse(
            ok: json["ok"] as? Bool ?? false,
            id: json["id"] as? String,
            data: json["data"] as? [String: Any],
            error: json["error"] as? String
        )
    }
}

// MARK: - Protocol Errors

/// Errors in daemon protocol communication.
enum DaemonProtocolError: Error, Equatable {
    case invalidResponse
    case encodingFailed
    case connectionLost
    case timeout
    case daemonNotRunning
}

// MARK: - Daemon State

/// Represents the lifecycle state of the remote daemon.
enum DaemonState: Equatable, Sendable {
    case notDeployed
    case deploying
    case running(version: String, uptime: TimeInterval)
    case stopped
    case upgrading
    case unreachable
}

// MARK: - Remote Session Info (from daemon)

/// Session information reported by the daemon's `session.list` command.
struct DaemonSessionInfo: Identifiable, Sendable {
    let id: String
    let title: String
    let pid: Int
    let age: TimeInterval
    let status: String

    /// Parses from a dictionary in the daemon response.
    static func from(dict: [String: Any]) -> DaemonSessionInfo? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String
        else { return nil }

        return DaemonSessionInfo(
            id: id,
            title: title,
            pid: dict["pid"] as? Int ?? 0,
            age: dict["age"] as? TimeInterval ?? 0,
            status: dict["status"] as? String ?? "unknown"
        )
    }
}
