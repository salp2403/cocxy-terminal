// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLICommandDefinition.swift - Known commands and their metadata.

import Foundation

// MARK: - CLI Command Definition

/// The set of commands supported by the `cocxy` CLI companion.
///
/// Each command knows how to describe itself for --help output.
/// Organized by category: tab, split, dashboard, timeline, search,
/// config, theme, and system commands.
public enum CLICommand: String, CaseIterable {

    // MARK: - Original commands (v1)

    case notify
    case newTab = "new-tab"
    case listTabs = "list-tabs"
    case focusTab = "focus-tab"
    case closeTab = "close-tab"
    case split
    case status
    case hookEvent = "hook-event"
    case hooks
    case hookHandler = "hook-handler"

    // MARK: - Tab extended (v2)

    case tabRename = "tab-rename"
    case tabMove = "tab-move"

    // MARK: - Split extended (v2)

    case splitList = "split-list"
    case splitFocus = "split-focus"
    case splitClose = "split-close"
    case splitResize = "split-resize"

    // MARK: - Dashboard (v2)

    case dashboardShow = "dashboard-show"
    case dashboardHide = "dashboard-hide"
    case dashboardToggle = "dashboard-toggle"
    case dashboardStatus = "dashboard-status"

    // MARK: - Timeline (v2)

    case timelineShow = "timeline-show"
    case timelineExport = "timeline-export"

    // MARK: - Search (v2)

    case search

    // MARK: - Config (v2)

    case configGet = "config-get"
    case configSet = "config-set"
    case configPath = "config-path"
    case configProject = "config-project"

    // MARK: - Theme (v2)

    case themeList = "theme-list"
    case themeSet = "theme-set"

    // MARK: - System (v2)

    case send
    case sendKey = "send-key"

    // MARK: - Remote Workspace (v2)

    case remoteList = "remote-list"
    case remoteConnect = "remote-connect"
    case remoteDisconnect = "remote-disconnect"
    case remoteStatus = "remote-status"
    case remoteTunnels = "remote-tunnels"

    // MARK: - Plugins (v2)

    case pluginList = "plugin-list"
    case pluginEnable = "plugin-enable"
    case pluginDisable = "plugin-disable"

    // MARK: - Browser (v2)

    case browserNavigate = "browser-navigate"
    case browserBack = "browser-back"
    case browserForward = "browser-forward"
    case browserReload = "browser-reload"
    case browserGetState = "browser-get-state"
    case browserEval = "browser-eval"
    case browserGetText = "browser-get-text"
    case browserListTabs = "browser-list-tabs"

    // MARK: - Window Management (v3)

    case windowNew = "window-new"
    case windowList = "window-list"
    case windowFocus = "window-focus"
    case windowClose = "window-close"
    case windowFullscreen = "window-fullscreen"

    // MARK: - Session Management (v3)

    case sessionSave = "session-save"
    case sessionRestore = "session-restore"
    case sessionList = "session-list"
    case sessionDelete = "session-delete"

    // MARK: - Tab extended (v3)

    case tabDuplicate = "tab-duplicate"
    case tabPin = "tab-pin"

    // MARK: - Config extended (v3)

    case configList = "config-list"
    case configReload = "config-reload"

    // MARK: - Split extended (v3)

    case splitSwap = "split-swap"
    case splitZoom = "split-zoom"

    // MARK: - Output (v3)

    case capturePane = "capture-pane"

    // MARK: - Notification CLI (v3)

    case notificationList = "notification-list"
    case notificationClear = "notification-clear"

    // MARK: - SSH (v4)

    case ssh

    // MARK: - Web Terminal (v5)

    case webStart = "web-start"
    case webStop = "web-stop"
    case webStatus = "web-status"
    case streamList = "stream-list"
    case streamCurrent = "stream-current"
    case protocolCapabilities = "protocol-capabilities"
    case protocolViewport = "protocol-viewport"
    case protocolSend = "protocol-send"
    case imageList = "image-list"
    case imageDelete = "image-delete"
    case imageClear = "image-clear"

    /// Whether this command is internal (hidden from --help).
    public var isInternal: Bool {
        switch self {
        case .hookEvent: return true
        default: return false
        }
    }

    /// Human-readable description for --help output.
    public var helpDescription: String {
        switch self {
        // Original commands
        case .notify: return "Send a notification to Cocxy Terminal"
        case .newTab: return "Open a new tab"
        case .listTabs: return "List all open tabs as JSON"
        case .focusTab: return "Focus a tab by UUID"
        case .closeTab: return "Close a tab by UUID"
        case .split: return "Split the focused pane"
        case .status: return "Show application status"
        case .hookEvent: return "Receive a Claude Code hook event (internal)"
        case .hooks: return "Manage Claude Code hooks (install/uninstall/status)"
        case .hookHandler: return "Handle incoming Claude Code hook event from stdin"

        // Tab extended
        case .tabRename: return "Rename a tab by UUID"
        case .tabMove: return "Move a tab to a new position"

        // Split extended
        case .splitList: return "List all split panes as JSON"
        case .splitFocus: return "Focus a pane by direction (left/right/up/down)"
        case .splitClose: return "Close the active split pane"
        case .splitResize: return "Resize a pane in a direction by pixels"

        // Dashboard
        case .dashboardShow: return "Show the agent dashboard"
        case .dashboardHide: return "Hide the agent dashboard"
        case .dashboardToggle: return "Toggle the agent dashboard"
        case .dashboardStatus: return "Show dashboard status as JSON"

        // Timeline
        case .timelineShow: return "Show timeline for a tab"
        case .timelineExport: return "Export timeline for a tab"

        // Search
        case .search: return "Search in scrollback buffer"

        // Config
        case .configGet: return "Get a configuration value"
        case .configSet: return "Set a configuration value"
        case .configPath: return "Show configuration file path"
        case .configProject: return "Show active tab's project config overrides"

        // Theme
        case .themeList: return "List available themes"
        case .themeSet: return "Set the active theme"

        // System
        case .send: return "Send text to the active terminal"
        case .sendKey: return "Send a keystroke to the active terminal"

        // Plugins
        case .pluginList: return "List all installed plugins"
        case .pluginEnable: return "Enable a plugin by ID"
        case .pluginDisable: return "Disable a plugin by ID"

        // Remote Workspace
        case .remoteList: return "List all saved remote connection profiles"
        case .remoteConnect: return "Connect to a remote profile by name or UUID"
        case .remoteDisconnect: return "Disconnect from a remote profile"
        case .remoteStatus: return "Show connection status for all or a specific profile"
        case .remoteTunnels: return "List active SSH tunnels"

        // Browser
        case .browserNavigate: return "Navigate the embedded browser to a URL"
        case .browserBack: return "Go back in browser history"
        case .browserForward: return "Go forward in browser history"
        case .browserReload: return "Reload the current browser page"
        case .browserGetState: return "Get current browser state as JSON"
        case .browserEval: return "Evaluate JavaScript in the active browser tab"
        case .browserGetText: return "Get the text content of the current page"
        case .browserListTabs: return "List all open browser tabs"

        // Window Management
        case .windowNew: return "Create a new window"
        case .windowList: return "List all open windows as JSON"
        case .windowFocus: return "Focus a window by index"
        case .windowClose: return "Close a window by index"
        case .windowFullscreen: return "Toggle fullscreen for the focused window"

        // Session Management
        case .sessionSave: return "Save the current session to disk"
        case .sessionRestore: return "Restore a saved session"
        case .sessionList: return "List all saved sessions as JSON"
        case .sessionDelete: return "Delete a saved session by name"

        // Tab extended v3
        case .tabDuplicate: return "Duplicate the active tab"
        case .tabPin: return "Pin or unpin a tab"

        // Config extended v3
        case .configList: return "List all configuration keys and values"
        case .configReload: return "Reload configuration from disk"

        // Split extended v3
        case .splitSwap: return "Swap two pane positions"
        case .splitZoom: return "Toggle zoom on the active pane"

        // Output
        case .capturePane: return "Capture the active pane's visible content as text"

        // Notification CLI
        case .notificationList: return "List recent notifications as JSON"
        case .notificationClear: return "Clear notification badge and unread count"
        case .ssh: return "Open SSH session in a new tab"
        case .webStart: return "Start the CocxyCore web terminal for the focused surface"
        case .webStop: return "Stop the CocxyCore web terminal for the focused surface"
        case .webStatus: return "Show CocxyCore web terminal status for the focused surface"
        case .streamList: return "List CocxyCore process streams for the focused surface"
        case .streamCurrent: return "Select the active CocxyCore stream for the focused surface"
        case .protocolCapabilities: return "Request a Protocol v2 capabilities exchange from the focused surface"
        case .protocolViewport: return "Send a Protocol v2 viewport update from the focused surface"
        case .protocolSend: return "Send an explicit Protocol v2 JSON message from the focused surface"
        case .imageList: return "List inline images stored for the focused surface"
        case .imageDelete: return "Delete a specific inline image from the focused surface"
        case .imageClear: return "Clear inline images from the focused surface"
        }
    }

    /// Example usage for --help output.
    public var usageExample: String {
        switch self {
        // Original commands
        case .notify: return "cocxy notify <message>"
        case .newTab: return "cocxy new-tab [--dir <path>]"
        case .listTabs: return "cocxy list-tabs"
        case .focusTab: return "cocxy focus-tab <id>"
        case .closeTab: return "cocxy close-tab <id>"
        case .split: return "cocxy split [--dir h|v]"
        case .status: return "cocxy status"
        case .hookEvent: return "cocxy hook-event '{\"type\":\"Stop\",...}'"
        case .hooks: return "cocxy hooks install|uninstall|status"
        case .hookHandler: return "cocxy hook-handler (reads JSON from stdin)"

        // Tab extended
        case .tabRename: return "cocxy tab rename <id> <name>"
        case .tabMove: return "cocxy tab move <id> <position>"

        // Split extended
        case .splitList: return "cocxy split list [--json]"
        case .splitFocus: return "cocxy split focus <direction>"
        case .splitClose: return "cocxy split close"
        case .splitResize: return "cocxy split resize <direction> <px>"

        // Dashboard
        case .dashboardShow: return "cocxy dashboard show"
        case .dashboardHide: return "cocxy dashboard hide"
        case .dashboardToggle: return "cocxy dashboard toggle"
        case .dashboardStatus: return "cocxy dashboard status [--json]"

        // Timeline
        case .timelineShow: return "cocxy timeline show <tab-id>"
        case .timelineExport: return "cocxy timeline export <tab-id> [--format json|md]"

        // Search
        case .search: return "cocxy search <query> [--regex] [--case-sensitive] [--tab <id>]"

        // Config
        case .configGet: return "cocxy config get <key>"
        case .configSet: return "cocxy config set <key> <value>"
        case .configPath: return "cocxy config path"
        case .configProject: return "cocxy config-project"

        // Theme
        case .themeList: return "cocxy theme list"
        case .themeSet: return "cocxy theme set <name>"

        // System
        case .send: return "cocxy send <text>"
        case .sendKey: return "cocxy send-key <key>"

        // Plugins
        case .pluginList: return "cocxy plugin-list"
        case .pluginEnable: return "cocxy plugin-enable <id>"
        case .pluginDisable: return "cocxy plugin-disable <id>"

        // Remote Workspace
        case .remoteList: return "cocxy remote-list [--group <group>]"
        case .remoteConnect: return "cocxy remote-connect <name-or-uuid>"
        case .remoteDisconnect: return "cocxy remote-disconnect <name-or-uuid>"
        case .remoteStatus: return "cocxy remote-status [<name-or-uuid>]"
        case .remoteTunnels: return "cocxy remote-tunnels [--profile <name>]"

        // Browser
        case .browserNavigate: return "cocxy browser-navigate <url>"
        case .browserBack: return "cocxy browser-back"
        case .browserForward: return "cocxy browser-forward"
        case .browserReload: return "cocxy browser-reload"
        case .browserGetState: return "cocxy browser-get-state"
        case .browserEval: return "cocxy browser-eval <script>"
        case .browserGetText: return "cocxy browser-get-text"
        case .browserListTabs: return "cocxy browser-list-tabs"

        // Window Management
        case .windowNew: return "cocxy window new"
        case .windowList: return "cocxy window list"
        case .windowFocus: return "cocxy window focus <index>"
        case .windowClose: return "cocxy window close [<index>]"
        case .windowFullscreen: return "cocxy window fullscreen"

        // Session Management
        case .sessionSave: return "cocxy session save [<name>]"
        case .sessionRestore: return "cocxy session restore <name>"
        case .sessionList: return "cocxy session list"
        case .sessionDelete: return "cocxy session delete <name>"

        // Tab extended v3
        case .tabDuplicate: return "cocxy tab duplicate [<id>]"
        case .tabPin: return "cocxy tab pin [<id>]"

        // Config extended v3
        case .configList: return "cocxy config list [--filter <prefix>]"
        case .configReload: return "cocxy config reload"

        // Split extended v3
        case .splitSwap: return "cocxy split swap <direction>"
        case .splitZoom: return "cocxy split zoom"

        // Output
        case .capturePane: return "cocxy capture-pane [--start <line>] [--end <line>]"

        // Notification CLI
        case .notificationList: return "cocxy notification list [--limit <n>]"
        case .notificationClear: return "cocxy notification clear"
        case .ssh: return "cocxy ssh user@host [-p port] [-i key]"
        case .webStart: return "cocxy web start [--bind <address>] [--port <port>] [--token <token>] [--fps <n>]"
        case .webStop: return "cocxy web stop"
        case .webStatus: return "cocxy web status"
        case .streamList: return "cocxy stream list"
        case .streamCurrent: return "cocxy stream current <id>"
        case .protocolCapabilities: return "cocxy protocol capabilities"
        case .protocolViewport: return "cocxy protocol viewport [--request-id <id>]"
        case .protocolSend: return "cocxy protocol send --type <type> --json <json>"
        case .imageList: return "cocxy image list"
        case .imageDelete: return "cocxy image delete <id>"
        case .imageClear: return "cocxy image clear"
        }
    }
}
