// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandRunner.swift - Orchestrates parsing, socket communication, and output.

import Foundation

// MARK: - Command Runner

/// Orchestrates the full CLI lifecycle: parse arguments, send to server, format output.
///
/// This is the top-level coordination layer. It delegates:
/// - Argument parsing to `CLIArgumentParser`.
/// - Socket communication to `SocketClient`.
/// - Output formatting to `OutputFormatter`.
public struct CommandRunner {

    /// The socket client to use for communication.
    public let socketClient: SocketClient

    /// Creates a command runner with a socket client.
    ///
    /// - Parameter socketClient: The socket client. Defaults to a new instance
    ///   with the default socket path.
    public init(socketClient: SocketClient = SocketClient()) {
        self.socketClient = socketClient
    }

    /// Runs the CLI with the given arguments.
    ///
    /// - Parameter arguments: The arguments array (excluding the program name).
    /// - Returns: A `CLIResult` with the exit code and output.
    public func run(arguments: [String]) -> CLIResult {
        let parsedCommand: ParsedCommand
        do {
            parsedCommand = try CLIArgumentParser.parse(arguments)
        } catch let error as CLIError {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: OutputFormatter.formatError(error)
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: \(error.localizedDescription)"
            )
        }

        // Handle commands that don't need the server.
        switch parsedCommand {
        case .help:
            return CLIResult(
                exitCode: 0,
                stdout: CLIArgumentParser.helpText(),
                stderr: ""
            )
        case .version:
            return CLIResult(
                exitCode: 0,
                stdout: CLIArgumentParser.versionText(),
                stderr: ""
            )
        case .hooksInstall:
            return executeHooksInstall()
        case .hooksUninstall:
            return executeHooksUninstall()
        case .hooksStatus:
            return executeHooksStatus()
        case .hookHandler:
            return HookHandlerCommand.execute(socketClient: socketClient)
        default:
            break
        }

        // Build the socket request.
        let request = buildRequest(from: parsedCommand)

        // Send to server.
        let response: CLISocketResponse
        do {
            response = try socketClient.send(request)
        } catch let error as CLIError {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: OutputFormatter.formatError(error)
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: \(error.localizedDescription)"
            )
        }

        // Format the response.
        if response.success {
            let output = OutputFormatter.formatSuccess(
                command: parsedCommand,
                response: response
            )
            return CLIResult(exitCode: 0, stdout: output, stderr: "")
        } else {
            let errorMessage = response.error ?? "Unknown error"
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: CLIError.serverError(errorMessage).userMessage
            )
        }
    }

    // MARK: - Local Commands: Hooks

    /// Executes `hooks install` locally (no socket needed).
    private func executeHooksInstall() -> CLIResult {
        let manager = ClaudeSettingsManager()
        do {
            let result = try manager.installHooks()
            if result.alreadyInstalled {
                return CLIResult(
                    exitCode: 0,
                    stdout: "Hooks already installed.",
                    stderr: ""
                )
            }
            let events = result.hookEvents.joined(separator: ", ")
            return CLIResult(
                exitCode: 0,
                stdout: "Hooks installed for events: \(events)",
                stderr: ""
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to install hooks: \(error.localizedDescription)"
            )
        }
    }

    /// Executes `hooks uninstall` locally (no socket needed).
    private func executeHooksUninstall() -> CLIResult {
        let manager = ClaudeSettingsManager()
        do {
            let result = try manager.uninstallHooks()
            if result.nothingToRemove {
                return CLIResult(
                    exitCode: 0,
                    stdout: "No Cocxy hooks found to remove.",
                    stderr: ""
                )
            }
            let events = result.removedEvents.joined(separator: ", ")
            return CLIResult(
                exitCode: 0,
                stdout: "Hooks removed for events: \(events)",
                stderr: ""
            )
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to uninstall hooks: \(error.localizedDescription)"
            )
        }
    }

    /// Executes `hooks status` locally (no socket needed).
    private func executeHooksStatus() -> CLIResult {
        let manager = ClaudeSettingsManager()
        do {
            let status = try manager.hooksStatus()
            if status.installed {
                let events = status.installedEvents.joined(separator: ", ")
                return CLIResult(
                    exitCode: 0,
                    stdout: "Cocxy hooks installed for: \(events)",
                    stderr: ""
                )
            } else {
                return CLIResult(
                    exitCode: 0,
                    stdout: "Cocxy hooks not installed. Run 'cocxy hooks install' to set up.",
                    stderr: ""
                )
            }
        } catch {
            return CLIResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Failed to check hooks status: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Request Building

    /// Builds a `CLISocketRequest` from a parsed command.
    ///
    /// - Parameter command: The parsed command.
    /// - Returns: A socket request ready to send.
    public func buildRequest(from command: ParsedCommand) -> CLISocketRequest {
        let requestID = UUID().uuidString

        switch command {

        // MARK: Original commands (v1)

        case .notify(let message):
            return CLISocketRequest(
                id: requestID,
                command: "notify",
                params: ["message": message]
            )
        case .newTab(let directory):
            var params: [String: String]? = nil
            if let directory {
                params = ["directory": directory]
            }
            return CLISocketRequest(id: requestID, command: "new-tab", params: params)

        case .listTabs:
            return CLISocketRequest(id: requestID, command: "list-tabs", params: nil)

        case .focusTab(let id):
            return CLISocketRequest(id: requestID, command: "focus-tab", params: ["id": id])

        case .closeTab(let id):
            return CLISocketRequest(id: requestID, command: "close-tab", params: ["id": id])

        case .split(let direction):
            var params: [String: String]? = nil
            if let direction {
                params = ["direction": direction.rawValue]
            }
            return CLISocketRequest(id: requestID, command: "split", params: params)

        case .status:
            return CLISocketRequest(id: requestID, command: "status", params: nil)

        case .hooksInstall, .hooksUninstall, .hooksStatus, .hookHandler:
            // These are handled locally; should never reach socket request building.
            return CLISocketRequest(id: requestID, command: "status", params: nil)

        case .help, .version:
            return CLISocketRequest(id: requestID, command: "status", params: nil)

        // MARK: Tab extended (v2)

        case .tabRename(let id, let name):
            return CLISocketRequest(
                id: requestID,
                command: "tab-rename",
                params: ["id": id, "name": name]
            )

        case .tabMove(let id, let position):
            return CLISocketRequest(
                id: requestID,
                command: "tab-move",
                params: ["id": id, "position": position]
            )

        // MARK: Split extended (v2)

        case .splitList:
            return CLISocketRequest(id: requestID, command: "split-list", params: nil)

        case .splitFocus(let direction):
            return CLISocketRequest(
                id: requestID,
                command: "split-focus",
                params: ["direction": direction]
            )

        case .splitClose:
            return CLISocketRequest(id: requestID, command: "split-close", params: nil)

        case .splitResize(let direction, let pixels):
            return CLISocketRequest(
                id: requestID,
                command: "split-resize",
                params: ["direction": direction, "pixels": pixels]
            )

        // MARK: Dashboard (v2)

        case .dashboardShow:
            return CLISocketRequest(id: requestID, command: "dashboard-show", params: nil)

        case .dashboardHide:
            return CLISocketRequest(id: requestID, command: "dashboard-hide", params: nil)

        case .dashboardToggle:
            return CLISocketRequest(id: requestID, command: "dashboard-toggle", params: nil)

        case .dashboardStatus:
            return CLISocketRequest(id: requestID, command: "dashboard-status", params: nil)

        // MARK: Timeline (v2)

        case .timelineShow(let tabID):
            return CLISocketRequest(
                id: requestID,
                command: "timeline-show",
                params: ["tabId": tabID]
            )

        case .timelineExport(let tabID, let format):
            return CLISocketRequest(
                id: requestID,
                command: "timeline-export",
                params: ["tabId": tabID, "format": format]
            )

        // MARK: Search (v2)

        case .search(let query, let regex, let caseSensitive, let tabID):
            var params: [String: String] = [
                "query": query,
                "regex": String(regex),
                "caseSensitive": String(caseSensitive)
            ]
            if let tabID {
                params["tabId"] = tabID
            }
            return CLISocketRequest(id: requestID, command: "search", params: params)

        // MARK: Config (v2)

        case .configGet(let key):
            return CLISocketRequest(
                id: requestID,
                command: "config-get",
                params: ["key": key]
            )

        case .configSet(let key, let value):
            return CLISocketRequest(
                id: requestID,
                command: "config-set",
                params: ["key": key, "value": value]
            )

        case .configPath:
            return CLISocketRequest(id: requestID, command: "config-path", params: nil)

        // MARK: Theme (v2)

        case .themeList:
            return CLISocketRequest(id: requestID, command: "theme-list", params: nil)

        case .themeSet(let name):
            return CLISocketRequest(
                id: requestID,
                command: "theme-set",
                params: ["name": name]
            )

        // MARK: System (v2)

        case .send(let text):
            return CLISocketRequest(
                id: requestID,
                command: "send",
                params: ["text": text]
            )

        case .sendKey(let key):
            return CLISocketRequest(
                id: requestID,
                command: "send-key",
                params: ["key": key]
            )
        }
    }
}

// MARK: - CLI Result

/// The result of a CLI command execution.
///
/// Contains the exit code and output for stdout and stderr.
public struct CLIResult: Equatable {
    /// Process exit code. 0 for success, 1 for error.
    public let exitCode: Int32

    /// Output for stdout.
    public let stdout: String

    /// Output for stderr.
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
