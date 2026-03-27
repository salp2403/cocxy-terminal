// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuBarStatusItem.swift - macOS menu bar icon with agent count badge.

import AppKit

// MARK: - Menu Bar Status Item

/// Manages a persistent macOS menu bar icon that shows the count of active
/// agent sessions across all Cocxy tabs.
///
/// ## Display
///
/// - Icon: Terminal symbol (⌘) when no agents active.
/// - Badge: Colored dot + count when agents are running.
/// - Menu: Click shows a dropdown with session summaries + quick actions.
///
/// ## Usage
///
/// ```swift
/// let menuBar = MenuBarStatusItem()
/// menuBar.install()
/// menuBar.updateAgentCount(working: 2, waiting: 1, errors: 0)
/// ```
///
/// - SeeAlso: `AgentDashboardViewModel` (provides the counts)
@MainActor
final class MenuBarStatusItem {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var agentMenu: NSMenu?

    /// Callback invoked when "Show Cocxy" is selected from the menu.
    var onShowApp: (() -> Void)?

    /// Callback invoked when "Show Dashboard" is selected.
    var onShowDashboard: (() -> Void)?

    // MARK: - Install

    /// Creates and installs the status bar item in the macOS menu bar.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let image = NSImage(
                systemSymbolName: "terminal",
                accessibilityDescription: "Cocxy Terminal"
            )?.withSymbolConfiguration(config)
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "No active agents", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let showApp = menu.addItem(
            withTitle: "Show Cocxy",
            action: #selector(handleShowApp),
            keyEquivalent: ""
        )
        showApp.target = self

        let showDashboard = menu.addItem(
            withTitle: "Show Dashboard",
            action: #selector(handleShowDashboard),
            keyEquivalent: ""
        )
        showDashboard.target = self

        menu.addItem(.separator())
        let quit = menu.addItem(
            withTitle: "Quit Cocxy",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]

        item.menu = menu
        self.statusItem = item
        self.agentMenu = menu
    }

    // MARK: - Update

    /// Updates the menu bar icon badge with current agent counts.
    ///
    /// - Parameters:
    ///   - working: Number of agents actively working.
    ///   - waiting: Number of agents waiting for input.
    ///   - errors: Number of agents in error state.
    ///   - sessions: Descriptions of active sessions for the dropdown menu.
    func updateAgentCount(
        working: Int,
        waiting: Int,
        errors: Int,
        sessions: [(name: String, state: String, activity: String?)] = []
    ) {
        guard let button = statusItem?.button else { return }

        let total = working + waiting + errors

        if total == 0 {
            button.title = ""
            updateMenuSessions([])
        } else {
            // Show count next to icon with color hint.
            var parts: [String] = []
            if working > 0 { parts.append("\(working)↻") }
            if waiting > 0 { parts.append("\(waiting)⏳") }
            if errors > 0 { parts.append("\(errors)⚠") }
            button.title = " " + parts.joined(separator: " ")
            updateMenuSessions(sessions)
        }
    }

    // MARK: - Private

    private func updateMenuSessions(
        _ sessions: [(name: String, state: String, activity: String?)]
    ) {
        guard let menu = agentMenu else { return }

        // Remove old session items (everything before the first separator).
        while menu.items.count > 0 && !menu.items[0].isSeparatorItem {
            menu.removeItem(at: 0)
        }

        if sessions.isEmpty {
            let noAgents = NSMenuItem(title: "No active agents", action: nil, keyEquivalent: "")
            noAgents.isEnabled = false
            menu.insertItem(noAgents, at: 0)
        } else {
            for (index, session) in sessions.reversed().enumerated() {
                let title: String
                if let activity = session.activity {
                    title = "\(session.name) — \(session.state) — \(activity)"
                } else {
                    title = "\(session.name) — \(session.state)"
                }
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false

                // State icon
                let iconName: String
                switch session.state.lowercased() {
                case "working": iconName = "circle.fill"
                case "waiting": iconName = "questionmark.circle.fill"
                case "error": iconName = "exclamationmark.triangle.fill"
                case "finished": iconName = "checkmark.circle.fill"
                default: iconName = "circle"
                }
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                item.image = NSImage(
                    systemSymbolName: iconName,
                    accessibilityDescription: session.state
                )?.withSymbolConfiguration(config)

                menu.insertItem(item, at: 0)
            }
        }
    }

    @objc private func handleShowApp() {
        onShowApp?()
    }

    @objc private func handleShowDashboard() {
        onShowDashboard?()
    }

    /// Removes the status item from the menu bar.
    func uninstall() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }
}
