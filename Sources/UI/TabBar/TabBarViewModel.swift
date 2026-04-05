// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabBarViewModel.swift - Presentation logic for the tab bar.

import Foundation
import Combine

// MARK: - Tab Display Item

/// A display-ready representation of a single tab in the tab bar.
///
/// Transforms the domain `Tab` model into properties the view can render
/// directly without importing domain logic. No AppKit dependency (ADR-002).
struct TabDisplayItem: Identifiable, Equatable {
    let id: TabID
    let displayTitle: String
    let subtitle: String?
    let statusColorName: String
    let badgeText: String?
    let isActive: Bool
    let hasUnreadNotification: Bool
    let agentState: AgentState
    /// Whether this tab is pinned (sorted to top, cannot be closed).
    var isPinned: Bool = false
    // Rich sidebar fields
    var agentStatusText: String = ""
    var directoryPath: String = ""
    var timeSinceActivity: String = ""
    var gitBranch: String?
    var processName: String?
    /// SSH session display string (e.g., "root@server.example.com:2222").
    var sshDisplay: String?
    /// Number of unread notifications for this tab. Zero hides the badge.
    var unreadNotificationCount: Int = 0
    /// Preview text of the latest unread notification (for hover tooltip).
    var notificationPreview: String?
    /// Cumulative tool calls by the agent. Zero when no agent or idle.
    var agentToolCount: Int = 0
    /// Cumulative errors by the agent. Zero when no agent or idle.
    var agentErrorCount: Int = 0
    /// Human-readable agent duration (e.g., "2m", "1h"). Nil when no agent.
    var agentDurationText: String?
}

// MARK: - Tab Bar View Model

/// Presentation logic for the vertical tab bar.
///
/// Transforms the domain tab list from `TabManager` into display-ready
/// `TabDisplayItem` values for the view. Does NOT import AppKit (ADR-002).
///
/// Listens to `TabManager.$tabs` and `TabManager.$activeTabID` via
/// Combine and re-computes the display items whenever the data changes.
///
/// - SeeAlso: ADR-002 (MVVM pattern)
/// - SeeAlso: `TabBarView` (the view this model drives)
/// - SeeAlso: `TabManager` (the domain service this model reads from)
@MainActor
final class TabBarViewModel: ObservableObject {

    // MARK: - Published State

    /// Display-ready tab items for the view to render.
    @Published private(set) var tabItems: [TabDisplayItem] = []

    /// The ID of the currently active tab.
    @Published private(set) var activeTabID: TabID?

    // MARK: - Dependencies

    /// The domain-level tab manager.
    private let tabManager: TabManager

    /// The notification manager for per-tab unread counts and previews.
    /// Injected after init via `setNotificationManager(_:)` because the
    /// notification stack is initialized after the window controller.
    private weak var notificationManager: NotificationManagerImpl?

    /// Closure invoked to create a new tab with full surface setup.
    /// Wired by `MainWindowController` to route through `createTab()` which
    /// creates the terminal surface, PTY, and view hierarchy.
    var onAddTab: (() -> Void)?

    /// Closure invoked when a tab should be closed with full resource cleanup.
    /// When set, `closeTab(id:)` delegates to this closure instead of calling
    /// `tabManager.removeTab` directly. Wired by `MainWindowController` to
    /// route through `closeTab(_:)` which destroys surfaces, buffers, and splits.
    var onCloseTab: ((TabID) -> Void)?

    /// Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a TabBarViewModel backed by the given TabManager.
    ///
    /// Immediately synchronizes with the manager's current state and
    /// subscribes to future changes.
    ///
    /// - Parameter tabManager: The domain tab manager to observe.
    init(tabManager: TabManager) {
        self.tabManager = tabManager
        syncWithManager()
        subscribeToChanges()
    }

    /// Injects the notification manager and subscribes to notification changes.
    ///
    /// Called by AppDelegate after `initializeNotificationStack()` completes,
    /// since the notification manager is created after the window controller.
    func setNotificationManager(_ manager: NotificationManagerImpl) {
        self.notificationManager = manager
        manager.notificationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncWithManager()
            }
            .store(in: &cancellables)
        manager.unreadCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncWithManager()
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Selects a tab by its ID.
    ///
    /// Delegates to `TabManager.setActive(id:)`.
    /// - Parameter id: The tab to activate.
    func selectTab(id: TabID) {
        tabManager.setActive(id: id)
        notificationManager?.markAsRead(tabId: id)
        syncWithManager()
    }

    /// Closes a tab by its ID.
    ///
    /// When `onCloseTab` is set, delegates to that closure for full resource
    /// cleanup (surface destruction, buffer removal, split teardown).
    /// Falls back to `TabManager.removeTab(id:)` when no closure is wired.
    /// The last tab cannot be closed (TabManager invariant).
    ///
    /// - Parameter id: The tab to close.
    func closeTab(id: TabID) {
        // Pinned tabs are protected from closure at every level.
        if let tab = tabManager.tab(for: id), tab.isPinned {
            return
        }

        if let onCloseTab {
            onCloseTab(id)
        } else {
            tabManager.removeTab(id: id)
        }
        syncWithManager()
    }

    /// Reorders a tab from one index to another.
    ///
    /// Delegates to `TabManager.moveTab(from:to:)`.
    /// - Parameters:
    ///   - fromIndex: Current position of the tab.
    ///   - toIndex: Destination position.
    func moveTab(from fromIndex: Int, to toIndex: Int) {
        tabManager.moveTab(from: fromIndex, to: toIndex)
        syncWithManager()
    }

    /// Creates a new tab with full surface setup.
    ///
    /// Delegates to `onAddTab` when wired, which routes through
    /// `MainWindowController.createTab()` to create the terminal surface,
    /// PTY process, and view hierarchy. Falls back to model-only creation
    /// when the closure is not set (tests).
    func addNewTab() {
        if let onAddTab {
            onAddTab()
        } else {
            let workingDirectory = tabManager.activeTab?.workingDirectory
                ?? FileManager.default.homeDirectoryForCurrentUser
            tabManager.addTab(workingDirectory: workingDirectory)
        }
        syncWithManager()
    }

    /// Toggles the pinned state of a tab.
    ///
    /// Pinned tabs sort to the top and cannot be closed.
    /// - Parameter id: The tab to pin or unpin.
    func togglePin(id: TabID) {
        tabManager.togglePin(id: id)
        syncWithManager()
    }

    /// Closes all tabs except the one with the given ID.
    ///
    /// When `onCloseTab` is set, delegates each removal to that closure for
    /// full resource cleanup. Falls back to `TabManager.removeTab(id:)`.
    /// After all removals, activates the kept tab.
    ///
    /// - Parameter id: The tab ID to keep open.
    func closeOtherTabs(except id: TabID) {
        let idsToRemove = tabManager.tabs
            .filter { $0.id != id && !$0.isPinned }
            .map(\.id)

        for tabID in idsToRemove {
            if let onCloseTab {
                onCloseTab(tabID)
            } else {
                tabManager.removeTab(id: tabID)
            }
        }

        tabManager.setActive(id: id)
        syncWithManager()
    }

    // MARK: - Rename

    /// Renames a tab with the given title.
    ///
    /// Trims whitespace from the input. If the result is empty, the custom
    /// title is cleared and the tab reverts to its auto-generated name.
    ///
    /// - Parameters:
    ///   - id: The tab to rename.
    ///   - newTitle: The desired title (trimmed; empty clears the custom title).
    func renameTab(id: TabID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        tabManager.renameTab(id: id, newTitle: trimmed.isEmpty ? nil : trimmed)
        syncWithManager()
    }

    // MARK: - Synchronization

    /// Re-computes display items from the current TabManager state.
    ///
    /// Called on initialization and whenever the TabManager publishes changes.
    func syncWithManager() {
        activeTabID = tabManager.activeTabID
        tabItems = tabManager.tabs.map { tab in
            let unreadCount = notificationManager?.unreadCountForTab(tab.id) ?? 0
            let latestUnread = notificationManager?.latestUnreadForTab(tab.id)
            let previewText: String? = latestUnread.map { "\($0.title) — \($0.body)" }

            return TabDisplayItem(
                id: tab.id,
                displayTitle: sshTitle(for: tab) ?? truncatedTitle(tab.displayTitle),
                subtitle: buildSubtitle(gitBranch: tab.gitBranch, processName: tab.processName),
                statusColorName: colorName(for: tab.agentState),
                badgeText: badgeText(for: tab.agentState),
                isActive: tab.isActive,
                hasUnreadNotification: unreadCount > 0,
                agentState: tab.agentState,
                isPinned: tab.isPinned,
                agentStatusText: agentStatusText(for: tab.agentState, processName: tab.processName, activity: tab.agentActivity),
                directoryPath: shortPath(tab.workingDirectory),
                timeSinceActivity: relativeTime(since: tab.lastActivityAt),
                gitBranch: tab.gitBranch,
                processName: tab.processName,
                sshDisplay: tab.sshSession?.displayTitleWithPort,
                unreadNotificationCount: unreadCount,
                notificationPreview: previewText,
                agentToolCount: tab.agentToolCount,
                agentErrorCount: tab.agentErrorCount,
                agentDurationText: agentDuration(for: tab)
            )
        }
    }

    // MARK: - Private Helpers

    /// Subscribes to TabManager changes via Combine.
    ///
    /// Since both TabManager and TabBarViewModel are `@MainActor`, we
    /// sink directly without `.receive(on:)` to get synchronous updates.
    /// The `.dropFirst()` avoids re-syncing on the initial value (already
    /// handled by `syncWithManager()` in init).
    private func subscribeToChanges() {
        tabManager.$tabs
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncWithManager()
            }
            .store(in: &cancellables)

        tabManager.$activeTabID
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncWithManager()
            }
            .store(in: &cancellables)
    }

    /// Truncates a title to a maximum length with ellipsis.
    private func truncatedTitle(_ title: String) -> String {
        let maxLength = TabViewModel.maxTitleLength
        guard title.count > maxLength else { return title }
        return String(title.prefix(maxLength)) + "..."
    }

    /// Returns the SSH display title if the tab has an active SSH session.
    private func sshTitle(for tab: Tab) -> String? {
        guard let session = tab.sshSession else { return nil }
        return truncatedTitle(session.displayTitleWithPort)
    }

    /// Builds a subtitle string from optional git branch and process name.
    private func buildSubtitle(gitBranch: String?, processName: String?) -> String? {
        switch (gitBranch, processName) {
        case let (.some(branch), .some(process)):
            return "\(branch) \u{2022} \(process)"
        case let (.some(branch), .none):
            return branch
        case let (.none, .some(process)):
            return process
        case (.none, .none):
            return nil
        }
    }

    /// Returns a semantic color name for an agent state.
    private func colorName(for state: AgentState) -> String {
        switch state {
        case .idle:
            return "gray"
        case .launched, .working:
            return "blue"
        case .waitingInput:
            return "yellow"
        case .finished:
            return "green"
        case .error:
            return "red"
        }
    }

    /// Returns badge text for an agent state, or nil for idle.
    private func badgeText(for state: AgentState) -> String? {
        switch state {
        case .idle:
            return nil
        case .launched:
            return "Launched"
        case .working:
            return "Working"
        case .waitingInput:
            return "Input"
        case .finished:
            return "Done"
        case .error:
            return "Error"
        }
    }

    // MARK: - Rich Sidebar Helpers

    /// Returns a human-readable status text for the agent state.
    private func agentStatusText(for state: AgentState, processName: String?, activity: String?) -> String {
        switch state {
        case .idle:
            return processName ?? "Ready"
        case .launched:
            return "Agent launching..."
        case .working:
            // Show the actual tool + file when available, not just "Working..."
            return activity ?? "Working..."
        case .waitingInput:
            return "Waiting for input"
        case .finished:
            return "Task completed"
        case .error:
            return "Error occurred"
        }
    }

    /// Returns a shortened path replacing the home directory with ~.
    private func shortPath(_ url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            let relative = String(path.dropFirst(home.count))
            return "~" + relative
        }
        return path
    }

    /// Returns the running duration of the agent in this tab, or nil if idle.
    private func agentDuration(for tab: Tab) -> String? {
        guard let agent = tab.detectedAgent,
              tab.agentState != .idle else { return nil }
        let seconds = Int(Date().timeIntervalSince(agent.startedAt))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h\(minutes % 60)m"
    }

    /// Returns a relative time string (e.g., "2m", "1h", "now").
    private func relativeTime(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
