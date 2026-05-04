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
    private var localizer: AppLocalizer
    private var lastSessions: [(name: String, state: String, activity: String?)] = []

    /// Callback invoked when "Show Cocxy" is selected from the menu.
    var onShowApp: (() -> Void)?

    /// Callback invoked when "Show Dashboard" is selected.
    var onShowDashboard: (() -> Void)?

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        self.localizer = localizer
    }

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

        self.statusItem = item
        rebuildMenu()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        rebuildMenu()
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
            lastSessions = []
            rebuildMenu()
        } else {
            // Show count next to icon with color hint.
            var parts: [String] = []
            if working > 0 { parts.append("\(working)↻") }
            if waiting > 0 { parts.append("\(waiting)⏳") }
            if errors > 0 { parts.append("\(errors)⚠") }
            button.title = " " + parts.joined(separator: " ")
            lastSessions = sessions
            rebuildMenu()
        }
    }

    // MARK: - Private

    private func rebuildMenu() {
        let menu = NSMenu()

        if lastSessions.isEmpty {
            let noAgents = NSMenuItem(
                title: Self.localizedNoActiveAgents(using: localizer),
                action: nil,
                keyEquivalent: ""
            )
            noAgents.isEnabled = false
            menu.addItem(noAgents)
        } else {
            for session in lastSessions.reversed() {
                let item = NSMenuItem(
                    title: Self.localizedSessionTitle(
                        name: session.name,
                        state: session.state,
                        activity: session.activity,
                        using: localizer
                    ),
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false

                // State icon
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                item.image = NSImage(
                    systemSymbolName: Self.symbolName(forAgentState: session.state),
                    accessibilityDescription: Self.localizedAgentState(session.state, using: localizer)
                )?.withSymbolConfiguration(config)

                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let showApp = menu.addItem(
            withTitle: Self.localizedShowCocxy(using: localizer),
            action: #selector(handleShowApp),
            keyEquivalent: ""
        )
        showApp.target = self

        let showDashboard = menu.addItem(
            withTitle: Self.localizedShowDashboard(using: localizer),
            action: #selector(handleShowDashboard),
            keyEquivalent: ""
        )
        showDashboard.target = self

        menu.addItem(.separator())
        let quit = menu.addItem(
            withTitle: Self.localizedQuitCocxy(using: localizer),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]

        statusItem?.menu = menu
        agentMenu = menu
    }

    static func localizedNoActiveAgents(using localizer: AppLocalizer) -> String {
        localizer.string("agentDashboard.empty.all.title", fallback: "No active agents")
    }

    static func localizedShowCocxy(using localizer: AppLocalizer) -> String {
        localizer.string("menuBar.showCocxy", fallback: "Show Cocxy")
    }

    static func localizedShowDashboard(using localizer: AppLocalizer) -> String {
        localizer.string("menuBar.showDashboard", fallback: "Show Dashboard")
    }

    static func localizedQuitCocxy(using localizer: AppLocalizer) -> String {
        localizer.string("menuBar.quitCocxy", fallback: "Quit Cocxy")
    }

    static func localizedAgentState(_ state: String, using localizer: AppLocalizer) -> String {
        switch normalizedAgentStateToken(state) {
        case "idle":
            return localizer.string("agentDashboard.state.idle", fallback: "Idle")
        case "launching", "launched":
            return localizer.string("agentDashboard.state.launching", fallback: "Launching")
        case "working":
            return localizer.string("agentDashboard.state.working", fallback: "Working")
        case "waiting", "waitinginput", "waitingforinput":
            return localizer.string("agentDashboard.state.waitingForInput", fallback: "Waiting for input")
        case "blocked":
            return localizer.string("agentDashboard.state.blocked", fallback: "Blocked")
        case "error":
            return localizer.string("agentDashboard.state.error", fallback: "Error")
        case "finished":
            return localizer.string("agentDashboard.state.finished", fallback: "Finished")
        default:
            return state
        }
    }

    static func localizedSessionTitle(
        name: String,
        state: String,
        activity: String?,
        using localizer: AppLocalizer
    ) -> String {
        let localizedState = localizedAgentState(state, using: localizer)
        if let activity {
            return "\(name) — \(localizedState) — \(activity)"
        }
        return "\(name) — \(localizedState)"
    }

    static func symbolName(forAgentState state: String) -> String {
        switch normalizedAgentStateToken(state) {
        case "working":
            return "circle.fill"
        case "waiting", "waitinginput", "waitingforinput":
            return "questionmark.circle.fill"
        case "blocked", "error":
            return "exclamationmark.triangle.fill"
        case "finished":
            return "checkmark.circle.fill"
        case "launching", "launched":
            return "circle.dotted"
        default:
            return "circle"
        }
    }

    private static func normalizedAgentStateToken(_ state: String) -> String {
        state
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
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
