// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLISocketServing.swift - Contract for the CLI companion socket server.

import Foundation

// MARK: - CLI Socket Serving Protocol

/// Server that listens on a Unix Domain Socket for commands from `cocxy-cli`.
///
/// Security measures (addressing cmux vulnerabilities #385-#390):
/// 1. Socket file permissions are `0600` (owner-only read/write).
/// 2. Every connection is verified via `getpeereid()` — the peer's UID must
///    match the server's UID.
/// 3. Commands are a closed enum — no arbitrary code execution.
///    `browser-eval` allows JS evaluation only in the embedded browser
///    (max 10,000 chars), scoped to UID-authenticated local socket.
/// 4. The socket path is `~/.config/cocxy/cocxy.sock`.
///
/// Protocol: Length-prefixed JSON messages.
/// ```
/// [4 bytes: payload length, big-endian][N bytes: JSON payload]
/// ```
///
/// - SeeAlso: ADR-006 (CLI communication)
/// - SeeAlso: ARCHITECTURE.md Section 7.8
@MainActor protocol CLISocketServing: AnyObject, Sendable {

    /// Starts listening on the Unix Domain Socket.
    ///
    /// Creates the socket file at `~/.config/cocxy/cocxy.sock` with
    /// permissions `0600`. If a stale socket file exists from a previous
    /// crash, it is removed first.
    ///
    /// - Throws: `CLISocketError.bindFailed` if the socket cannot be created.
    func start() throws

    /// Stops the server and removes the socket file.
    ///
    /// All active connections are closed gracefully.
    func stop()

    /// Whether the server is currently listening.
    var isRunning: Bool { get }

    /// Registers a handler for a specific CLI command type.
    ///
    /// - Parameters:
    ///   - commandName: The command name string (e.g., "notify", "new-tab").
    ///   - handler: Closure that processes the command and returns a response.
    ///     The handler receives the raw JSON arguments as `Data`.
    func registerHandler(
        for commandName: String,
        handler: @escaping @Sendable (Data) -> CLIResponse
    )
}

// MARK: - CLI Command Names

/// Closed set of commands accepted by the socket server.
///
/// Any command name not in this enum is rejected with an error response.
/// This prevents arbitrary command execution (unlike cmux's `browser.eval`).
enum CLICommandName: String, CaseIterable, Sendable {

    // MARK: - Original commands (v1)

    /// Send a notification to the user.
    case notify
    /// Create a new tab.
    case newTab = "new-tab"
    /// List all open tabs.
    case listTabs = "list-tabs"
    /// Focus a specific tab.
    case focusTab = "focus-tab"
    /// Close a specific tab.
    case closeTab = "close-tab"
    /// Create a split pane.
    case split
    /// Query the application status.
    case status
    /// Receive a hook event from Claude Code (Layer 0, ADR-008).
    case hookEvent = "hook-event"
    /// Manage Claude Code hooks (install/uninstall/status). CLI-only, handled locally.
    case hooks
    /// Handle incoming Claude Code hook event from stdin. CLI-only, forwards via hook-event.
    case hookHandler = "hook-handler"

    // MARK: - Tab extended (v2)

    /// Rename a tab by UUID.
    case tabRename = "tab-rename"
    /// Move a tab to a new position.
    case tabMove = "tab-move"

    // MARK: - Split extended (v2)

    /// List all split panes.
    case splitList = "split-list"
    /// Focus a pane by direction.
    case splitFocus = "split-focus"
    /// Close the active split pane.
    case splitClose = "split-close"
    /// Resize a pane in a direction by pixels.
    case splitResize = "split-resize"

    // MARK: - Dashboard (v2)

    /// Show the agent dashboard.
    case dashboardShow = "dashboard-show"
    /// Hide the agent dashboard.
    case dashboardHide = "dashboard-hide"
    /// Toggle the agent dashboard.
    case dashboardToggle = "dashboard-toggle"
    /// Show dashboard status.
    case dashboardStatus = "dashboard-status"

    // MARK: - Timeline (v2)

    /// Show timeline for a tab.
    case timelineShow = "timeline-show"
    /// Export timeline for a tab.
    case timelineExport = "timeline-export"

    // MARK: - Search (v2)

    /// Search in scrollback buffer.
    case search

    // MARK: - Config (v2)

    /// Get a configuration value.
    case configGet = "config-get"
    /// Set a configuration value.
    case configSet = "config-set"
    /// Show configuration file path.
    case configPath = "config-path"
    /// Show the active tab's project config (.cocxy.toml overrides).
    case configProject = "config-project"

    // MARK: - Theme (v2)

    /// List available themes.
    case themeList = "theme-list"
    /// Set the active theme.
    case themeSet = "theme-set"

    // MARK: - System (v2)

    /// Send text to the active terminal.
    case send
    /// Send a keystroke to the active terminal.
    case sendKey = "send-key"

    // MARK: - Remote Workspace (v2)

    /// List all saved remote connection profiles.
    case remoteList = "remote-list"
    /// Connect to a remote profile by name or UUID.
    case remoteConnect = "remote-connect"
    /// Disconnect from a remote profile.
    case remoteDisconnect = "remote-disconnect"
    /// Show connection status for all or a specific profile.
    case remoteStatus = "remote-status"
    /// List active SSH tunnels.
    case remoteTunnels = "remote-tunnels"

    // MARK: - Plugins (v2)

    /// List all installed plugins.
    case pluginList = "plugin-list"
    /// Enable a plugin by ID.
    case pluginEnable = "plugin-enable"
    /// Disable a plugin by ID.
    case pluginDisable = "plugin-disable"

    // MARK: - Browser (v2)

    /// Navigate the embedded browser to a URL.
    case browserNavigate = "browser-navigate"
    /// Go back in browser history.
    case browserBack = "browser-back"
    /// Go forward in browser history.
    case browserForward = "browser-forward"
    /// Reload the current browser page.
    case browserReload = "browser-reload"
    /// Get current browser state (URL, title, loading, tabs).
    case browserGetState = "browser-get-state"
    /// Evaluate JavaScript in the active browser tab (max 10,000 chars).
    case browserEval = "browser-eval"
    /// Get the text content of the current page via `document.body.innerText`.
    case browserGetText = "browser-get-text"
    /// List all open browser tabs.
    case browserListTabs = "browser-list-tabs"
}

// MARK: - CLI Response

/// Response sent back to the CLI client.
struct CLIResponse: Codable, Sendable {
    /// Whether the command was executed successfully.
    let success: Bool
    /// Optional data payload (command-specific).
    let data: Data?
    /// Error message if `success` is `false`.
    let error: String?

    /// Convenience factory for a successful response with data.
    static func ok(data: Data? = nil) -> CLIResponse {
        CLIResponse(success: true, data: data, error: nil)
    }

    /// Convenience factory for a failed response.
    static func failure(error: String) -> CLIResponse {
        CLIResponse(success: false, data: nil, error: error)
    }
}

// MARK: - CLI Socket Errors

/// Errors that can occur during socket server operations.
enum CLISocketError: Error, Sendable {
    /// The socket could not be created or bound.
    case bindFailed(path: String, reason: String)
    /// A connection was rejected because the peer's UID does not match.
    case authenticationFailed(expectedUID: uid_t, actualUID: uid_t)
    /// The received command name is not recognized.
    case unknownCommand(String)
    /// The received message could not be parsed as valid JSON.
    case malformedMessage(reason: String)
}
