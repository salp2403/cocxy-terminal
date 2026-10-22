// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuBarStatusItem.swift - macOS menu bar icon with agent count badge.

import AppKit
import Combine

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
/// menuBar.updateAgentCount(MenuBarAgentSummary.summarize(sessions))
/// ```
///
/// - SeeAlso: `AgentDashboardViewModel` (provides the counts)
@MainActor
final class MenuBarStatusItem: NSObject, NSMenuDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private(set) var agentMenu: NSMenu?
    private var localizer: AppLocalizer
    private(set) var currentSummary = MenuBarAgentSummary.empty

    /// Callback invoked when "Show Cocxy" is selected from the menu.
    var onShowApp: (() -> Void)?

    /// Callback invoked when "Show Dashboard" is selected.
    var onShowDashboard: (() -> Void)?

    /// Callback invoked when the user selects a concrete session row.
    var onNavigateToSession: ((String) -> Void)?

    /// Pulls the latest summary when the menu is about to open. The publisher
    /// remains responsible for live badge updates between menu openings.
    var onRequestAgentSummary: (() -> MenuBarAgentSummary)?

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        self.localizer = localizer
        super.init()
    }

    // MARK: - Install

    /// Creates and installs the status bar item in the macOS menu bar.
    func install() {
        guard statusItem == nil else { return }

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
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu

        statusItem = item
        agentMenu = menu
        rebuildMenu()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        rebuildMenu()
    }

    // MARK: - Update

    /// Binds the real dashboard publisher to this status item.
    func bindAgentSessions(
        _ publisher: AnyPublisher<[AgentSessionInfo], Never>,
        surfaceIDForHookSession: @escaping (String) -> SurfaceID?
    ) -> AnyCancellable {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateAgentCount(
                    MenuBarAgentSummary.summarize(
                        sessions,
                        surfaceIDForHookSession: surfaceIDForHookSession
                    )
                )
            }
    }

    /// Stores rows independently from badge availability or badge count.
    func updateAgentCount(_ summary: MenuBarAgentSummary) {
        currentSummary = summary
        statusItem?.button?.title = summary.badgeTitle
        rebuildMenu()
    }

    // MARK: - Private

    private func rebuildMenu() {
        guard let menu = agentMenu else { return }
        menu.removeAllItems()

        if currentSummary.rows.isEmpty {
            let noAgents = NSMenuItem(
                title: Self.localizedNoActiveAgents(using: localizer),
                action: nil,
                keyEquivalent: ""
            )
            noAgents.isEnabled = false
            menu.addItem(noAgents)

            let explanation = NSMenuItem(
                title: Self.localizedNoActiveAgentsMessage(using: localizer),
                action: nil,
                keyEquivalent: ""
            )
            explanation.isEnabled = false
            explanation.indentationLevel = 1
            menu.addItem(explanation)
        } else {
            for session in currentSummary.rows {
                let item = NSMenuItem(
                    title: Self.localizedSessionTitle(
                        name: session.name,
                        state: session.state.rawValue,
                        activity: session.activity,
                        using: localizer
                    ),
                    action: #selector(handleNavigateToSession(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = session.sessionID
                item.isEnabled = true

                // State icon
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                item.image = NSImage(
                    systemSymbolName: Self.symbolName(forAgentState: session.state.rawValue),
                    accessibilityDescription: Self.localizedAgentState(
                        session.state.rawValue,
                        using: localizer
                    )
                )?.withSymbolConfiguration(config)

                menu.addItem(item)
            }

            if currentSummary.overflowCount > 0 {
                let overflow = NSMenuItem(
                    title: Self.localizedMoreAgents(
                        currentSummary.overflowCount,
                        using: localizer
                    ),
                    action: nil,
                    keyEquivalent: ""
                )
                overflow.isEnabled = false
                overflow.indentationLevel = 1
                menu.addItem(overflow)
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

    }

    static func localizedNoActiveAgents(using localizer: AppLocalizer) -> String {
        localizer.string("agentDashboard.empty.all.title", fallback: "No active agents")
    }

    static func localizedNoActiveAgentsMessage(using localizer: AppLocalizer) -> String {
        localizer
            .string(
                "agentDashboard.empty.all.message",
                fallback: "Run an agent in the terminal to see its activity here."
            )
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func localizedMoreAgents(_ count: Int, using localizer: AppLocalizer) -> String {
        String(
            format: localizer.string("menuBar.moreAgents", fallback: "+%d more"),
            count
        )
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

    @objc private func handleNavigateToSession(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String else { return }
        onNavigateToSession?(sessionID)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let latestSummary = onRequestAgentSummary?() {
            currentSummary = latestSummary
            statusItem?.button?.title = latestSummary.badgeTitle
        }
        rebuildMenu()
    }

    /// Removes the status item from the menu bar.
    func uninstall() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        agentMenu?.delegate = nil
        agentMenu = nil
    }
}
