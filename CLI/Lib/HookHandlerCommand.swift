// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookHandlerCommand.swift - Bridge between Claude Code hooks and Cocxy socket.

import Foundation

// MARK: - Hook Handler Command

/// Handles the `cocxy hook-handler` command.
///
/// This command is invoked by Claude Code as a hook handler.
/// It reads JSON from stdin, wraps it into a socket request,
/// and sends it to the running Cocxy Terminal via the Unix Domain Socket.
///
/// Performance target: < 100ms total to avoid blocking Claude Code.
/// On socket errors: fails silently (never blocks Claude Code).
public enum HookHandlerCommand {

    /// Environment flag set only for shells spawned inside Cocxy.
    ///
    /// Agent hooks are installed globally, so this marker prevents
    /// sessions running in other terminals from polluting Cocxy
    /// with unrelated lifecycle events.
    static let cocxyHookEnvironmentKey = "COCXY_CLAUDE_HOOKS"

    /// Returns true when the current process environment indicates the hook
    /// event originated from a shell session launched by Cocxy.
    static func shouldForwardHook(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment[cocxyHookEnvironmentKey] == "1" {
            return true
        }

        // Backward-compatible fallback for shells started before the explicit
        // marker existed. Cocxy shell sessions already carry these variables.
        if environment["COCXY_RESOURCES_DIR"] != nil || environment["COCXY_SHELL_INTEGRATION_DIR"] != nil {
            return true
        }

        return false
    }

    /// Builds a socket request from raw hook JSON data.
    ///
    /// The JSON from Claude Code is forwarded as-is inside the
    /// `payload` parameter of a `hook-event` socket request.
    ///
    /// - Parameter data: Raw JSON bytes from stdin.
    /// - Returns: A `CLISocketRequest` ready to send to the socket server.
    /// - Throws: `HooksError.emptyInput` if data is empty.
    /// - Throws: `HooksError.invalidHookJSON` if data is not valid JSON.
    public static func buildRequest(from data: Data) throws -> CLISocketRequest {
        guard !data.isEmpty else {
            throw HooksError.emptyInput
        }

        // Validate that it's parseable JSON before forwarding
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw HooksError.invalidHookJSON(
                reason: "Input is not valid JSON"
            )
        }

        // Forward the raw JSON as a string payload
        guard let payloadString = String(data: data, encoding: .utf8) else {
            throw HooksError.invalidHookJSON(
                reason: "Input is not valid UTF-8"
            )
        }

        return CLISocketRequest(
            id: UUID().uuidString,
            command: "hook-event",
            params: ["payload": payloadString]
        )
    }

    /// Executes the hook-handler: reads stdin, sends to socket, returns result.
    ///
    /// On socket errors, returns exit code 0 to avoid blocking Claude Code.
    /// The hook-handler is a best-effort bridge -- if Cocxy is not running,
    /// the event is silently dropped.
    ///
    /// - Parameter socketClient: The socket client to use.
    /// - Returns: A `CLIResult` with exit code 0 on success or silent failure.
    public static func execute(
        socketClient: SocketClient,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CLIResult {
        // Ignore globally-installed hooks outside Cocxy shells.
        guard shouldForwardHook(environment: environment) else {
            return CLIResult(exitCode: 0, stdout: "", stderr: "")
        }

        // Read all of stdin
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()

        let request: CLISocketRequest
        do {
            request = try buildRequest(from: stdinData)
        } catch {
            // Fail silently -- don't block Claude Code
            return CLIResult(exitCode: 0, stdout: "", stderr: "")
        }

        // Send to socket -- fail silently on connection errors
        do {
            _ = try socketClient.send(request)
        } catch {
            // Silently drop -- Cocxy might not be running
        }

        return CLIResult(exitCode: 0, stdout: "", stderr: "")
    }
}
