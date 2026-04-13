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
        case .setupHooks(let agent, let remove):
            return SetupHooksCommand.execute(target: agent, remove: remove)
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
                params = ["dir": directory]
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
                params = ["direction": direction == .horizontal ? "horizontal" : "vertical"]
            }
            return CLISocketRequest(id: requestID, command: "split", params: params)

        case .status:
            return CLISocketRequest(id: requestID, command: "status", params: nil)

        case .hooksInstall, .hooksUninstall, .hooksStatus, .hookHandler, .setupHooks:
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
            let normalizedFormat = format.lowercased() == "md" ? "markdown" : format.lowercased()
            return CLISocketRequest(
                id: requestID,
                command: "timeline-export",
                params: ["tabId": tabID, "format": normalizedFormat]
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

        // MARK: Window Management (v3)

        case .windowNew:
            return CLISocketRequest(id: requestID, command: "window-new", params: nil)

        case .windowList:
            return CLISocketRequest(id: requestID, command: "window-list", params: nil)

        case .windowFocus(let index):
            return CLISocketRequest(
                id: requestID, command: "window-focus", params: ["index": index]
            )

        case .windowClose(let index):
            var params: [String: String]?
            if let index { params = ["index": index] }
            return CLISocketRequest(id: requestID, command: "window-close", params: params)

        case .windowFullscreen:
            return CLISocketRequest(id: requestID, command: "window-fullscreen", params: nil)

        // MARK: Session Management (v3)

        case .sessionSave(let name):
            var params: [String: String]?
            if let name { params = ["name": name] }
            return CLISocketRequest(id: requestID, command: "session-save", params: params)

        case .sessionRestore(let name):
            return CLISocketRequest(
                id: requestID, command: "session-restore", params: ["name": name]
            )

        case .sessionList:
            return CLISocketRequest(id: requestID, command: "session-list", params: nil)

        case .sessionDelete(let name):
            return CLISocketRequest(
                id: requestID, command: "session-delete", params: ["name": name]
            )

        // MARK: Tab extended (v3)

        case .tabDuplicate(let id):
            var params: [String: String]?
            if let id { params = ["id": id] }
            return CLISocketRequest(id: requestID, command: "tab-duplicate", params: params)

        case .tabPin(let id):
            var params: [String: String]?
            if let id { params = ["id": id] }
            return CLISocketRequest(id: requestID, command: "tab-pin", params: params)

        // MARK: Config extended (v3)

        case .configList(let filter):
            var params: [String: String]?
            if let filter { params = ["filter": filter] }
            return CLISocketRequest(id: requestID, command: "config-list", params: params)

        case .configReload:
            return CLISocketRequest(id: requestID, command: "config-reload", params: nil)

        case .configProject:
            return CLISocketRequest(id: requestID, command: "config-project", params: nil)

        // MARK: Split extended (v3)

        case .splitSwap(let direction):
            return CLISocketRequest(
                id: requestID, command: "split-swap", params: ["direction": direction]
            )

        case .splitZoom:
            return CLISocketRequest(id: requestID, command: "split-zoom", params: nil)

        // MARK: Output (v3)

        case .capturePane(let start, let end):
            var params: [String: String] = [:]
            if let start { params["start"] = String(start) }
            if let end { params["end"] = String(end) }
            return CLISocketRequest(
                id: requestID,
                command: "capture-pane",
                params: params.isEmpty ? nil : params
            )

        // MARK: Notification CLI (v3)

        case .notificationList(let limit):
            var params: [String: String]?
            if let limit { params = ["limit": String(limit)] }
            return CLISocketRequest(id: requestID, command: "notification-list", params: params)

        case .notificationClear:
            return CLISocketRequest(id: requestID, command: "notification-clear", params: nil)

        // MARK: Remote Workspace (exposed v3)

        case .remoteList:
            return CLISocketRequest(id: requestID, command: "remote-list", params: nil)

        case .remoteConnect(let name):
            return CLISocketRequest(
                id: requestID, command: "remote-connect", params: ["name": name]
            )

        case .remoteDisconnect(let name):
            return CLISocketRequest(
                id: requestID, command: "remote-disconnect", params: ["name": name]
            )

        case .remoteStatus(let name):
            var params: [String: String]?
            if let name { params = ["name": name] }
            return CLISocketRequest(id: requestID, command: "remote-status", params: params)

        case .remoteTunnels(let profile):
            var params: [String: String]?
            if let profile { params = ["profile": profile] }
            return CLISocketRequest(id: requestID, command: "remote-tunnels", params: params)

        // MARK: Plugin Management (exposed v3)

        case .pluginList:
            return CLISocketRequest(id: requestID, command: "plugin-list", params: nil)

        case .pluginEnable(let id):
            return CLISocketRequest(
                id: requestID, command: "plugin-enable", params: ["id": id]
            )

        case .pluginDisable(let id):
            return CLISocketRequest(
                id: requestID, command: "plugin-disable", params: ["id": id]
            )

        // MARK: Browser (exposed v3)

        case .browserNavigate(let url):
            return CLISocketRequest(
                id: requestID, command: "browser-navigate", params: ["url": url]
            )

        case .browserBack:
            return CLISocketRequest(id: requestID, command: "browser-back", params: nil)

        case .browserForward:
            return CLISocketRequest(id: requestID, command: "browser-forward", params: nil)

        case .browserReload:
            return CLISocketRequest(id: requestID, command: "browser-reload", params: nil)

        case .browserGetState:
            return CLISocketRequest(id: requestID, command: "browser-get-state", params: nil)

        case .browserEval(let script):
            return CLISocketRequest(
                id: requestID, command: "browser-eval", params: ["script": script]
            )

        case .browserGetText:
            return CLISocketRequest(id: requestID, command: "browser-get-text", params: nil)

        case .browserListTabs:
            return CLISocketRequest(id: requestID, command: "browser-list-tabs", params: nil)

        // MARK: SSH (v4)

        case .ssh(let destination, let port, let identityFile):
            var params: [String: String] = ["destination": destination]
            if let port { params["port"] = "\(port)" }
            if let identityFile { params["identity"] = identityFile }
            return CLISocketRequest(id: requestID, command: "ssh", params: params)

        // MARK: Web Terminal (v5)

        case .webStart(let bindAddress, let port, let token, let fps):
            var params: [String: String] = [:]
            if let bindAddress { params["bind"] = bindAddress }
            if let port { params["port"] = "\(port)" }
            if let token { params["token"] = token }
            if let fps { params["fps"] = "\(fps)" }
            return CLISocketRequest(id: requestID, command: "web-start", params: params.isEmpty ? nil : params)

        case .webStop:
            return CLISocketRequest(id: requestID, command: "web-stop", params: nil)

        case .webStatus:
            return CLISocketRequest(id: requestID, command: "web-status", params: nil)

        case .streamList:
            return CLISocketRequest(id: requestID, command: "stream-list", params: nil)

        case .streamCurrent(let id):
            return CLISocketRequest(id: requestID, command: "stream-current", params: ["id": "\(id)"])

        case .protocolCapabilities:
            return CLISocketRequest(id: requestID, command: "protocol-capabilities", params: nil)

        case .protocolViewport(let requestIDValue):
            let params = requestIDValue.map { ["request_id": $0] }
            return CLISocketRequest(id: requestID, command: "protocol-viewport", params: params)

        case .protocolSend(let type, let json):
            return CLISocketRequest(
                id: requestID,
                command: "protocol-send",
                params: ["type": type, "json": json]
            )

        case .coreReset:
            return CLISocketRequest(id: requestID, command: "core-reset", params: nil)

        case .coreSignal(let signal):
            return CLISocketRequest(
                id: requestID,
                command: "core-signal",
                params: ["signal": signal]
            )

        case .coreProcess:
            return CLISocketRequest(id: requestID, command: "core-process", params: nil)

        case .coreModes:
            return CLISocketRequest(id: requestID, command: "core-modes", params: nil)

        case .coreSearch:
            return CLISocketRequest(id: requestID, command: "core-search", params: nil)

        case .coreLigatures:
            return CLISocketRequest(id: requestID, command: "core-ligatures", params: nil)

        case .coreProtocol:
            return CLISocketRequest(id: requestID, command: "core-protocol", params: nil)

        case .coreSelection:
            return CLISocketRequest(id: requestID, command: "core-selection", params: nil)

        case .coreFontMetrics:
            return CLISocketRequest(id: requestID, command: "core-font-metrics", params: nil)

        case .corePreedit:
            return CLISocketRequest(id: requestID, command: "core-preedit", params: nil)

        case .coreSemantic(let limit):
            let params = limit.map { ["limit": "\($0)"] }
            return CLISocketRequest(id: requestID, command: "core-semantic", params: params)

        case .imageList:
            return CLISocketRequest(id: requestID, command: "image-list", params: nil)

        case .imageDelete(let id):
            return CLISocketRequest(id: requestID, command: "image-delete", params: ["id": "\(id)"])

        case .imageClear:
            return CLISocketRequest(id: requestID, command: "image-clear", params: nil)
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
