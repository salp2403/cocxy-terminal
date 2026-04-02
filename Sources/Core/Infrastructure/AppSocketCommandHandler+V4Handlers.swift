// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+V4Handlers.swift - Handlers for previously-acknowledged CLI commands.

import Foundation

// MARK: - V4 Dashboard Handlers

extension AppSocketCommandHandler {

    /// Shows the dashboard panel if not already visible.
    func handleDashboardShow(_ request: SocketRequest) -> SocketResponse {
        guard let toggle = dashboardToggleProvider else {
            return .failure(id: request.id, error: "Dashboard not available")
        }
        // If status shows hidden, toggle to show.
        if let status = dashboardStatusProvider?(),
           status["visible"] == "true" {
            return .ok(id: request.id, data: ["status": "already_visible"])
        }
        let isVisible = toggle()
        return .ok(id: request.id, data: [
            "status": isVisible ? "shown" : "failed",
            "visible": isVisible ? "true" : "false"
        ])
    }

    /// Hides the dashboard panel if currently visible.
    func handleDashboardHide(_ request: SocketRequest) -> SocketResponse {
        guard let toggle = dashboardToggleProvider else {
            return .failure(id: request.id, error: "Dashboard not available")
        }
        if let status = dashboardStatusProvider?(),
           status["visible"] == "false" {
            return .ok(id: request.id, data: ["status": "already_hidden"])
        }
        let isVisible = toggle()
        return .ok(id: request.id, data: [
            "status": isVisible ? "failed" : "hidden",
            "visible": isVisible ? "true" : "false"
        ])
    }

    /// Toggles the dashboard panel visibility.
    func handleDashboardToggle(_ request: SocketRequest) -> SocketResponse {
        guard let toggle = dashboardToggleProvider else {
            return .failure(id: request.id, error: "Dashboard not available")
        }
        let isVisible = toggle()
        return .ok(id: request.id, data: [
            "status": "toggled",
            "visible": isVisible ? "true" : "false"
        ])
    }

    /// Returns the current dashboard status including session counts.
    func handleDashboardStatus(_ request: SocketRequest) -> SocketResponse {
        guard let provider = dashboardStatusProvider else {
            return .failure(id: request.id, error: "Dashboard not available")
        }
        return .ok(id: request.id, data: provider())
    }
}

// MARK: - V4 Timeline Handlers

extension AppSocketCommandHandler {

    /// Shows the timeline panel.
    func handleTimelineShow(_ request: SocketRequest) -> SocketResponse {
        guard let toggle = timelineToggleProvider else {
            return .failure(id: request.id, error: "Timeline not available")
        }
        toggle()
        return .ok(id: request.id, data: ["status": "shown"])
    }

    /// Exports the timeline in JSON or Markdown format.
    ///
    /// Optional params: `format` ("json" or "markdown", default "json").
    func handleTimelineExport(_ request: SocketRequest) -> SocketResponse {
        guard let exporter = timelineExportProvider else {
            return .failure(id: request.id, error: "Timeline not available")
        }
        let format = request.params?["format"] ?? "json"
        guard format == "json" || format == "markdown" else {
            return .failure(id: request.id, error: "Invalid format: \(format). Use 'json' or 'markdown'")
        }
        guard let data = exporter(format) else {
            return .failure(id: request.id, error: "No timeline data to export")
        }
        let content = String(data: data, encoding: .utf8) ?? ""
        return .ok(id: request.id, data: [
            "status": "exported",
            "format": format,
            "content": content
        ])
    }
}

// MARK: - V4 Split Handlers

extension AppSocketCommandHandler {

    /// Creates a new split pane in the active tab.
    ///
    /// Optional params: `direction` ("vertical" or "horizontal", default "horizontal").
    func handleSplitCreate(_ request: SocketRequest) -> SocketResponse {
        guard let provider = splitCreateProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }
        let direction = request.params?["direction"] ?? "horizontal"
        let isVertical = direction == "vertical"
        let created = provider(isVertical)
        if created {
            return .ok(id: request.id, data: [
                "status": "created",
                "direction": direction
            ])
        }
        return .failure(id: request.id, error: "Cannot create split (max 4 panes or no active tab)")
    }

    /// Lists all split panes in the active tab.
    func handleSplitList(_ request: SocketRequest) -> SocketResponse {
        guard let provider = splitInfoProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }
        let panes = provider()
        var data: [String: String] = ["count": "\(panes.count)"]
        for (index, pane) in panes.enumerated() {
            data["pane_\(index)_leaf_id"] = pane.leafID
            data["pane_\(index)_terminal_id"] = pane.terminalID
            data["pane_\(index)_focused"] = pane.isFocused ? "true" : "false"
        }
        return .ok(id: request.id, data: data)
    }

    /// Focuses a split pane by its DFS index.
    ///
    /// Required params: `index` (0-based pane index).
    func handleSplitFocus(_ request: SocketRequest) -> SocketResponse {
        guard let provider = splitFocusProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }
        guard let indexStr = request.params?["index"],
              let index = Int(indexStr) else {
            return .failure(id: request.id, error: "Missing or invalid param: index")
        }
        let focused = provider(index)
        if focused {
            return .ok(id: request.id, data: ["status": "focused", "index": "\(index)"])
        }
        return .failure(id: request.id, error: "Pane index out of range")
    }

    /// Closes the currently focused split pane.
    func handleSplitClose(_ request: SocketRequest) -> SocketResponse {
        guard let provider = splitCloseProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }
        let closed = provider()
        if closed {
            return .ok(id: request.id, data: ["status": "closed"])
        }
        return .failure(id: request.id, error: "Cannot close last pane")
    }

    /// Resizes a split pane by setting its divider ratio.
    ///
    /// Required params: `id` (split node UUID), `ratio` (0.1-0.9).
    func handleSplitResize(_ request: SocketRequest) -> SocketResponse {
        guard let provider = splitResizeProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }
        guard let splitID = request.params?["id"] else {
            return .failure(id: request.id, error: "Missing required param: id")
        }
        guard let ratioStr = request.params?["ratio"],
              let ratio = Double(ratioStr) else {
            return .failure(id: request.id, error: "Missing or invalid param: ratio (0.1-0.9)")
        }
        let resized = provider(splitID, CGFloat(ratio))
        if resized {
            return .ok(id: request.id, data: [
                "status": "resized",
                "ratio": String(format: "%.2f", ratio)
            ])
        }
        return .failure(id: request.id, error: "Invalid split ID or ratio out of range")
    }
}

// MARK: - V4 Search Handler

extension AppSocketCommandHandler {

    /// Toggles the search bar in the active terminal.
    func handleSearch(_ request: SocketRequest) -> SocketResponse {
        guard let toggle = searchToggleProvider else {
            return .failure(id: request.id, error: "Search not available")
        }
        toggle()
        return .ok(id: request.id, data: ["status": "toggled"])
    }
}

// MARK: - V4 Terminal I/O Handlers

extension AppSocketCommandHandler {

    /// Sends text directly to the active terminal's PTY.
    ///
    /// Required params: `text` (the string to send).
    func handleSend(_ request: SocketRequest) -> SocketResponse {
        guard let provider = sendTextProvider else {
            return .failure(id: request.id, error: "Terminal not available")
        }
        guard let text = request.params?["text"], !text.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: text")
        }
        let sent = provider(text)
        if sent {
            return .ok(id: request.id, data: ["status": "sent", "length": "\(text.count)"])
        }
        return .failure(id: request.id, error: "No active terminal surface")
    }

    /// Sends a named key to the active terminal.
    ///
    /// Required params: `key` (key name like "enter", "tab", "escape", "backspace").
    func handleSendKey(_ request: SocketRequest) -> SocketResponse {
        guard let provider = sendKeyProvider else {
            return .failure(id: request.id, error: "Terminal not available")
        }
        guard let key = request.params?["key"], !key.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: key")
        }
        let sent = provider(key)
        if sent {
            return .ok(id: request.id, data: ["status": "sent", "key": key])
        }
        return .failure(id: request.id, error: "Unknown key: \(key)")
    }
}

// MARK: - V4 Hook Management Handlers

extension AppSocketCommandHandler {

    /// Lists the hook events that Cocxy is configured to receive.
    func handleHooksList(_ request: SocketRequest) -> SocketResponse {
        // Read configured hooks from the settings file.
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path

        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return .ok(id: request.id, data: ["count": "0", "status": "no_hooks_configured"])
        }

        var hookData: [String: String] = ["count": "\(hooks.count)"]
        var index = 0
        for (eventName, config) in hooks {
            hookData["hook_\(index)_event"] = eventName
            if let matchers = config as? [[String: Any]] {
                hookData["hook_\(index)_matchers"] = "\(matchers.count)"
            }
            index += 1
        }
        return .ok(id: request.id, data: hookData)
    }

    /// Hook handler command — used internally by the CLI to process hook events.
    func handleHookHandler(_ request: SocketRequest) -> SocketResponse {
        .ok(id: request.id, data: [
            "status": "ready",
            "info": "Use hook-event command with payload parameter to forward hook events"
        ])
    }
}

// MARK: - V4 SSH Handler

extension AppSocketCommandHandler {

    /// Opens an SSH session in a new tab.
    ///
    /// Required params: `destination` (user@host format).
    /// Optional params: `port`, `identity` (path to SSH key).
    func handleSSH(_ request: SocketRequest) -> SocketResponse {
        guard let provider = sshProvider else {
            return .failure(id: request.id, error: "SSH not available")
        }
        guard let destination = request.params?["destination"], !destination.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: destination (user@host)")
        }
        let port = request.params?["port"].flatMap { Int($0) }
        let identityFile = request.params?["identity"]

        guard let result = provider(destination, port, identityFile) else {
            return .failure(id: request.id, error: "Failed to open SSH session")
        }

        return .ok(id: request.id, data: [
            "status": "connected",
            "id": result.id,
            "title": result.title,
            "destination": destination
        ])
    }
}
