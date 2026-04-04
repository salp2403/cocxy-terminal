// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OutputFormatter.swift - Formats CLI responses for terminal output.

import Foundation

// MARK: - Output Formatter

/// Formats `CLISocketResponse` data for human-readable terminal output.
///
/// Different commands produce different output formats:
/// - `list-tabs`, `split-list`: Pretty-printed JSON array.
/// - `status`, `dashboard-status`: Human-readable summary.
/// - `notify`, `new-tab`, etc.: Simple confirmation message.
/// - `config-path`, `config-get`: Data-driven output.
public enum OutputFormatter {

    /// Formats a successful response for terminal output.
    ///
    /// - Parameters:
    ///   - command: The command that was executed.
    ///   - response: The server's successful response.
    /// - Returns: A formatted string ready for stdout.
    public static func formatSuccess(command: ParsedCommand, response: CLISocketResponse) -> String {
        switch command {

        // MARK: Original commands (v1)

        case .listTabs:
            return formatListTabs(response: response)
        case .status:
            return formatStatus(response: response)
        case .notify:
            return "Notification sent."
        case .newTab:
            return "Tab opened."
        case .focusTab:
            return "Tab focused."
        case .closeTab:
            return "Tab closed."
        case .split:
            return "Pane split."
        case .hooksInstall, .hooksUninstall, .hooksStatus, .hookHandler:
            // These commands are handled locally, not via socket.
            return response.data?.values.joined(separator: "\n") ?? ""
        case .help, .version:
            return ""

        // MARK: Tab extended (v2)

        case .tabRename:
            return "Tab renamed."
        case .tabMove:
            return "Tab moved."

        // MARK: Split extended (v2)

        case .splitList:
            return formatJSONData(response: response, key: "splits")
        case .splitFocus:
            return "Pane focused."
        case .splitClose:
            return "Pane closed."
        case .splitResize:
            return "Pane resized."

        // MARK: Dashboard (v2)

        case .dashboardShow:
            return "Dashboard shown."
        case .dashboardHide:
            return "Dashboard hidden."
        case .dashboardToggle:
            return "Dashboard toggled."
        case .dashboardStatus:
            return formatDataOrJSON(response: response)

        // MARK: Timeline (v2)

        case .timelineShow:
            return formatDataOrJSON(response: response)
        case .timelineExport:
            return formatDataOrJSON(response: response)

        // MARK: Search (v2)

        case .search:
            return formatDataOrJSON(response: response)

        // MARK: Config (v2)

        case .configGet:
            return response.data?["value"] ?? ""
        case .configSet:
            return "Configuration updated."
        case .configPath:
            return response.data?["path"] ?? "~/.config/cocxy/config.toml"

        // MARK: Theme (v2)

        case .themeList:
            return formatDataOrJSON(response: response)
        case .themeSet:
            return "Theme applied."

        // MARK: System (v2)

        case .send:
            return "Text sent."
        case .sendKey:
            return "Key sent."

        // MARK: Window Management (v3)

        case .windowNew:
            return "Window created."
        case .windowList:
            return formatDataOrJSON(response: response)
        case .windowFocus:
            return "Window focused."
        case .windowClose:
            return "Window closed."
        case .windowFullscreen:
            return "Fullscreen toggled."

        // MARK: Session Management (v3)

        case .sessionSave:
            return "Session saved."
        case .sessionRestore:
            return "Session restored."
        case .sessionList:
            return formatDataOrJSON(response: response)
        case .sessionDelete:
            return "Session deleted."

        // MARK: Tab extended (v3)

        case .tabDuplicate:
            return "Tab duplicated."
        case .tabPin:
            return "Tab pin toggled."

        // MARK: Config extended (v3)

        case .configList:
            return formatDataOrJSON(response: response)
        case .configReload:
            return "Configuration reloaded."
        case .configProject:
            return formatDataOrJSON(response: response)

        // MARK: Split extended (v3)

        case .splitSwap:
            return "Panes swapped."
        case .splitZoom:
            return "Pane zoom toggled."

        // MARK: Output (v3)

        case .capturePane:
            return formatDataOrJSON(response: response)

        // MARK: Notification CLI (v3)

        case .notificationList:
            return formatDataOrJSON(response: response)
        case .notificationClear:
            return "Notifications cleared."

        // MARK: Remote Workspace (exposed v3)

        case .remoteList:
            return formatDataOrJSON(response: response)
        case .remoteConnect:
            return "Connected."
        case .remoteDisconnect:
            return "Disconnected."
        case .remoteStatus:
            return formatDataOrJSON(response: response)
        case .remoteTunnels:
            return formatDataOrJSON(response: response)

        // MARK: Plugin Management (exposed v3)

        case .pluginList:
            return formatDataOrJSON(response: response)
        case .pluginEnable:
            return "Plugin enabled."
        case .pluginDisable:
            return "Plugin disabled."

        // MARK: Browser (exposed v3)

        case .browserNavigate:
            return "Navigated."
        case .browserBack:
            return "Navigated back."
        case .browserForward:
            return "Navigated forward."
        case .browserReload:
            return "Page reloaded."
        case .browserGetState:
            return formatDataOrJSON(response: response)
        case .browserEval:
            return formatDataOrJSON(response: response)
        case .browserGetText:
            return formatDataOrJSON(response: response)
        case .browserListTabs:
            return formatDataOrJSON(response: response)

        // SSH (v4)
        case .ssh:
            let dest = response.data?["destination"] ?? ""
            return "SSH session opened: \(dest)"
        }
    }

    /// Formats an error response for terminal output.
    ///
    /// - Parameter error: The error to format.
    /// - Returns: A formatted string ready for stderr.
    public static func formatError(_ error: CLIError) -> String {
        return error.userMessage
    }

    // MARK: - Private: Command-specific formatting

    /// Formats a `list-tabs` response as pretty-printed JSON.
    private static func formatListTabs(response: CLISocketResponse) -> String {
        guard let data = response.data else {
            return "[]"
        }

        if let jsonString = data["tabs"] {
            return prettyPrintJSON(jsonString)
        }

        return formatDataAsJSON(data)
    }

    /// Formats a `status` response as human-readable text.
    private static func formatStatus(response: CLISocketResponse) -> String {
        guard let data = response.data else {
            return "Cocxy Terminal - status unavailable"
        }

        var lines: [String] = []
        lines.append("Cocxy Terminal v\(data["version"] ?? "unknown")")

        if let tabInfo = data["tabs"] {
            lines.append("Tabs: \(tabInfo)")
        }

        if let activeTab = data["active"] {
            lines.append("Active: \(activeTab)")
        }

        if let socketInfo = data["socket"] {
            lines.append("Socket: \(socketInfo)")
        }

        return lines.joined(separator: "\n")
    }

    /// Formats JSON data from a specific key in the response.
    private static func formatJSONData(response: CLISocketResponse, key: String) -> String {
        guard let data = response.data else {
            return "[]"
        }

        if let jsonString = data[key] {
            return prettyPrintJSON(jsonString)
        }

        return formatDataAsJSON(data)
    }

    /// Formats the response data as JSON, or returns the raw values if no data.
    private static func formatDataOrJSON(response: CLISocketResponse) -> String {
        guard let data = response.data else {
            return ""
        }
        if let content = data["content"] {
            return prettyPrintJSON(content)
        }
        if let events = data["events"] {
            return prettyPrintJSON(events)
        }
        if let results = data["results"] {
            return prettyPrintJSON(results)
        }
        return formatDataAsJSON(data)
    }

    /// Pretty-prints a JSON string.
    private static func prettyPrintJSON(_ jsonString: String) -> String {
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return jsonString
        }
        return prettyString
    }

    /// Formats a dictionary as a JSON string.
    private static func formatDataAsJSON(_ data: [String: String]) -> String {
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: data,
            options: [.prettyPrinted, .sortedKeys]
        ),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return "{}"
        }
        return jsonString
    }
}
