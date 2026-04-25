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
        case .hooksInstall, .hooksUninstall, .hooksStatus, .hookHandler, .setupHooks:
            // These commands are handled locally, not via socket.
            return response.data?.values.joined(separator: "\n") ?? ""
        case .review:
            return "Code review toggled."
        case .reviewRefresh:
            return "Code review refreshed."
        case .reviewSubmit:
            if let submitted = response.data?["submitted_comments"] ?? response.data?["submittedComments"] {
                return "Submitted \(submitted) comments."
            }
            return "Code review comments submitted."
        case .reviewStats:
            return formatDataOrJSON(response: response)
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
        case .webStart:
            return formatWebStatus(response: response, defaultHeadline: "Web terminal started")
        case .webStop:
            return "Web terminal stopped."
        case .webStatus:
            return formatWebStatus(response: response, defaultHeadline: "Web terminal")
        case .streamList:
            return formatDataOrJSON(response: response)
        case .streamCurrent:
            return "Current stream selected."
        case .protocolCapabilities:
            return "Protocol capabilities requested."
        case .protocolViewport:
            return "Protocol viewport sent."
        case .protocolSend:
            return "Protocol message sent."
        case .coreReset:
            return "Terminal reset."
        case .coreSignal:
            return "Signal sent to terminal process."
        case .coreProcess, .coreModes, .coreSearch, .coreLigatures, .coreProtocol,
             .coreSelection, .coreFontMetrics, .corePreedit, .coreSemantic:
            return formatDataOrJSON(response: response)
        case .imageList:
            return formatDataOrJSON(response: response)
        case .imageDelete:
            return "Inline image deleted."
        case .imageClear:
            return "Inline images cleared."
        case .worktreeAdd:
            guard let data = response.data,
                  let id = data["id"],
                  let branch = data["branch"],
                  let path = data["path"] else {
                return response.data?["status"] ?? "Worktree created."
            }
            return "Worktree \(id) created: branch \(branch) at \(path)"
        case .worktreeList:
            return formatDataOrJSON(response: response)
        case .worktreeRemove:
            guard let id = response.data?["id"] else {
                return "Worktree removed."
            }
            return "Worktree \(id) removed."
        case .worktreePrune:
            let count = response.data?["count"] ?? "0"
            return "Pruned \(count) orphan worktree\(count == "1" ? "" : "s")."
        case .githubStatus, .githubPRs, .githubIssues:
            return formatDataOrJSON(response: response)
        case .githubOpen:
            return response.data?["state"] ?? "GitHub pane toggled."
        case .githubRefresh:
            return "GitHub pane refreshed."
        case .githubPRMerge:
            // Prefer the human-readable summary we emit in the success
            // payload; fall back to the merged PR JSON if it is the
            // only field present, and finally to a generic string when
            // the response shape is unexpected.
            if let summary = response.data?["summary"], !summary.isEmpty {
                return summary
            }
            if let merged = response.data?["merged"], !merged.isEmpty {
                return merged
            }
            return "Pull request merged."
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

        if let searchMode = data["search_mode"] {
            let indexedRows = data["search_indexed_rows"] ?? "0"
            lines.append("Search: \(searchMode) (\(indexedRows) indexed rows)")
        }

        if let protocolObserved = data["protocol_v2_observed"] {
            let requested = data["protocol_v2_capabilities_requested"] ?? "false"
            let currentStream = data["current_stream_id"] ?? "0"
            lines.append(
                "Protocol v2: observed \(boolText(protocolObserved)), capabilities \(boolText(requested)), current stream \(currentStream)"
            )
        }

        if let cursorVisible = data["cursor_visible"] {
            let appCursor = data["app_cursor_mode"] ?? "false"
            let altScreen = data["alt_screen"] ?? "false"
            let bracketedPaste = data["bracketed_paste_mode"] ?? "false"
            let mouseTracking = data["mouse_tracking_mode"] ?? "0"
            let kittyKeyboard = data["kitty_keyboard_mode"] ?? "0"
            let preeditActive = data["preedit_active"] ?? "false"
            let cursorShape = data["cursor_shape"] ?? "0"
            let semanticBlockCount = data["semantic_block_count"] ?? "0"
            lines.append(
                "Modes: cursor \(boolText(cursorVisible)), app cursor \(boolText(appCursor)), alt screen \(boolText(altScreen)), bracketed paste \(boolText(bracketedPaste))"
            )
            lines.append(
                "Input: mouse mode \(mouseTracking), kitty keyboard \(kittyKeyboard), preedit \(boolText(preeditActive)), cursor shape \(cursorShape), semantic blocks \(semanticBlockCount)"
            )
        }

        if let childPID = data["child_pid"] {
            let processAlive = data["process_alive"] ?? "false"
            lines.append("Process: pid \(childPID), alive \(boolText(processAlive))")
        }

        if let cellWidth = data["font_cell_width"], let cellHeight = data["font_cell_height"] {
            let ascent = data["font_ascent"] ?? "0.00"
            let descent = data["font_descent"] ?? "0.00"
            let leading = data["font_leading"] ?? "0.00"
            lines.append(
                "Font: cell \(cellWidth)x\(cellHeight), ascent \(ascent), descent \(descent), leading \(leading)"
            )
        }

        if let selectionActive = data["selection_active"] {
            if selectionActive == "true",
               let startRow = data["selection_start_row"],
               let startCol = data["selection_start_col"],
               let endRow = data["selection_end_row"],
               let endCol = data["selection_end_col"] {
                let textBytes = data["selection_text_bytes"] ?? "0"
                lines.append(
                    "Selection: on (\(startRow):\(startCol) -> \(endRow):\(endCol), \(textBytes) bytes)"
                )
            } else {
                lines.append("Selection: off")
            }
        }

        if let preeditBytes = data["preedit_text_bytes"] {
            let cursorBytes = data["preedit_cursor_bytes"] ?? "0"
            let anchorRow = data["preedit_anchor_row"] ?? "0"
            let anchorCol = data["preedit_anchor_col"] ?? "0"
            lines.append(
                "Preedit detail: \(preeditBytes) bytes, cursor \(cursorBytes), anchor \(anchorRow):\(anchorCol)"
            )
        }

        if let semanticState = data["semantic_state_name"] {
            var parts = ["Semantic: state \(semanticState)"]
            if let currentBlock = data["semantic_current_block_name"] {
                parts.append("current \(currentBlock)")
            }
            let promptBlocks = data["semantic_prompt_blocks"] ?? "0"
            let commandInputBlocks = data["semantic_command_input_blocks"] ?? "0"
            let commandOutputBlocks = data["semantic_command_output_blocks"] ?? "0"
            let errorBlocks = data["semantic_error_blocks"] ?? "0"
            let toolBlocks = data["semantic_tool_blocks"] ?? "0"
            let agentBlocks = data["semantic_agent_blocks"] ?? "0"
            parts.append(
                "prompt \(promptBlocks), input \(commandInputBlocks), output \(commandOutputBlocks), error \(errorBlocks), tool \(toolBlocks), agent \(agentBlocks)"
            )
            lines.append(parts.joined(separator: ", "))
        }

        if let ligatures = data["ligatures_enabled"] {
            let hits = data["ligature_cache_hits"] ?? "0"
            let misses = data["ligature_cache_misses"] ?? "0"
            lines.append("Ligatures: \(boolText(ligatures)) (hits \(hits), misses \(misses))")
        }

        if let imageCount = data["image_count"] {
            let memory = data["image_memory_used_mib"] ?? "0"
            let budget = data["image_memory_limit_mib"] ?? "0"
            let sixel = data["image_sixel_enabled"] ?? "false"
            let kitty = data["image_kitty_enabled"] ?? "false"
            let atlasWidth = data["image_atlas_width"] ?? "0"
            let atlasHeight = data["image_atlas_height"] ?? "0"
            let atlasGeneration = data["image_atlas_generation"] ?? "0"
            let atlasDirty = data["image_atlas_dirty"] ?? "false"
            lines.append("Images: \(imageCount) loaded (\(memory)/\(budget) MiB, sixel \(boolText(sixel)), kitty \(boolText(kitty)))")
            lines.append("Image atlas: \(atlasWidth)x\(atlasHeight) gen \(atlasGeneration), dirty \(boolText(atlasDirty))")
        }

        if let streamCount = data["stream_count"] {
            lines.append("Streams: \(streamCount)")
        }

        if let webRunning = data["web_running"] {
            if webRunning == "true" {
                let bind = data["web_bind"] ?? "127.0.0.1"
                let port = data["web_port"] ?? "0"
                let connections = data["web_connections"] ?? "0"
                lines.append("Web terminal: running on \(bind):\(port) (\(connections) clients)")
            } else {
                lines.append("Web terminal: stopped")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatWebStatus(response: CLISocketResponse, defaultHeadline: String) -> String {
        guard let data = response.data else { return defaultHeadline }
        let running = data["running"] == "true"
        var lines = [defaultHeadline]
        lines.append("Status: \(running ? "running" : "stopped")")
        if let bind = data["bind"], let port = data["port"] {
            lines.append("Bind: \(bind):\(port)")
        }
        if let fps = data["max_fps"] {
            lines.append("Max FPS: \(fps)")
        }
        if let authRequired = data["auth_required"] {
            lines.append("Auth required: \(boolText(authRequired))")
        }
        if let connections = data["connections"] {
            lines.append("Connections: \(connections)")
        }
        if let lastEvent = data["last_event"] {
            lines.append("Last event: \(lastEvent)")
        }
        return lines.joined(separator: "\n")
    }

    private static func boolText(_ value: String) -> String {
        value == "true" ? "on" : "off"
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
