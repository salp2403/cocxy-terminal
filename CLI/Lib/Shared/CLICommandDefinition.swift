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

    // MARK: - Browser (v2)

    case browserNavigate = "browser-navigate"
    case browserBack = "browser-back"
    case browserForward = "browser-forward"
    case browserReload = "browser-reload"
    case browserGetState = "browser-get-state"
    case browserEval = "browser-eval"
    case browserGetText = "browser-get-text"
    case browserListTabs = "browser-list-tabs"

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
        case .search: return "cocxy search <query> [--regex] [--case-sensitive]"

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
        }
    }
}
