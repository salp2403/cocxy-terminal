// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabManager.swift - Tab creation, destruction and ordering.

import Foundation
import Combine

// MARK: - Tab Manager

/// Manages the lifecycle and ordering of terminal tabs.
///
/// Responsibilities:
/// - Create new tabs with a default or specified working directory.
/// - Close tabs (with guard: cannot close the last tab).
/// - Reorder tabs (drag & drop support).
/// - Track the active (focused) tab.
/// - Expose the tab list as a Combine publisher for reactive UI updates.
///
/// ## Invariants
///
/// 1. There is always at least one tab.
/// 2. Exactly one tab has `isActive == true` at any time.
/// 3. When the active tab is closed, the next tab (or previous if last) is activated.
/// 4. When a new tab is created, it becomes the active tab.
///
/// Thread safety: All mutations happen on `@MainActor`.
///
/// - SeeAlso: `Tab` (the domain model managed by this service)
/// - SeeAlso: `TabBarViewModel` (consumes published state for UI)
@MainActor
final class TabManager: ObservableObject, TabActivating {

    // MARK: - Published State

    /// The ordered list of open tabs.
    @Published private(set) var tabs: [Tab]

    /// The ID of the currently active tab.
    @Published private(set) var activeTabID: TabID?

    // MARK: - Computed Properties

    /// The currently active tab, if any.
    var activeTab: Tab? {
        guard let activeID = activeTabID else { return nil }
        return tabs.first { $0.id == activeID }
    }

    // MARK: - Initialization

    /// Creates a TabManager with one initial tab.
    ///
    /// The initial tab uses the current working directory (falling back to
    /// the user's home directory) and detects the git branch if available.
    /// The tab is activated immediately.
    init() {
        let currentDirectoryPath = FileManager.default.currentDirectoryPath
        let currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        let gitProvider = GitInfoProviderImpl()
        let branch = gitProvider.currentBranch(at: currentDirectoryURL)

        var initialTab = Tab(
            workingDirectory: currentDirectoryURL,
            gitBranch: branch
        )
        initialTab.isActive = true
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
    }

    // MARK: - CRUD Operations

    /// Creates a new tab and activates it.
    ///
    /// The previously active tab is deactivated. The new tab is appended
    /// to the end of the tab list.
    ///
    /// - Parameter workingDirectory: The working directory for the new tab.
    ///   Defaults to the user's home directory.
    /// - Returns: The newly created tab.
    @discardableResult
    func addTab(workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> Tab {
        // Deactivate the current active tab.
        deactivateCurrentTab()

        let gitProvider = GitInfoProviderImpl()
        let branch = gitProvider.currentBranch(at: workingDirectory)

        var newTab = Tab(
            workingDirectory: workingDirectory,
            gitBranch: branch
        )
        newTab.isActive = true

        tabs.append(newTab)
        activeTabID = newTab.id

        return newTab
    }

    /// Removes a tab by its ID.
    ///
    /// Rules:
    /// - Cannot remove the last remaining tab (no-op).
    /// - Cannot remove a pinned tab (no-op).
    /// - If the removed tab was active, the next tab is activated.
    ///   If the removed tab was the last in the list, the previous tab
    ///   is activated instead.
    /// - Removing a non-existent ID is a no-op.
    ///
    /// - Parameter id: The ID of the tab to remove.
    func removeTab(id: TabID) {
        // Cannot remove the last tab.
        guard tabs.count > 1 else { return }

        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        // Pinned tabs cannot be closed.
        guard !tabs[index].isPinned else { return }

        let wasActive = tabs[index].isActive
        tabs.remove(at: index)

        if wasActive {
            // Activate the next tab, or the previous if we removed the last one.
            let newActiveIndex = min(index, tabs.count - 1)
            activateTabAtIndex(newActiveIndex)
        }
    }

    /// Toggles the pinned state of a tab.
    ///
    /// Pinned tabs are sorted to the top of the tab list and cannot be closed.
    /// Re-sorts the tab list after toggling to maintain pinned-first order.
    ///
    /// - Parameter id: The ID of the tab to pin or unpin.
    func togglePin(id: TabID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isPinned.toggle()
        sortTabsByPinState()
    }

    /// Re-sorts tabs so that pinned tabs appear before unpinned tabs.
    ///
    /// Preserves the relative order within each group (pinned and unpinned).
    private func sortTabsByPinState() {
        let pinned = tabs.filter(\.isPinned)
        let unpinned = tabs.filter { !$0.isPinned }
        tabs = pinned + unpinned
    }

    /// Changes the active tab.
    ///
    /// Deactivates the current tab and activates the one with the given ID.
    /// If the ID does not exist, this is a no-op.
    ///
    /// - Parameter id: The ID of the tab to activate.
    func setActive(id: TabID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        deactivateCurrentTab()
        activateTabAtIndex(index)
    }

    /// Moves a tab from one position to another.
    ///
    /// Both indices must be valid for the current tab list.
    /// Invalid indices are silently ignored.
    ///
    /// - Parameters:
    ///   - fromIndex: The current index of the tab.
    ///   - toIndex: The destination index for the tab.
    func moveTab(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex >= 0, fromIndex < tabs.count,
              toIndex >= 0, toIndex < tabs.count,
              fromIndex != toIndex else {
            return
        }

        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: toIndex)
    }

    /// Mutates a tab in-place using the provided closure.
    ///
    /// If the ID does not exist, this is a no-op.
    ///
    /// - Parameters:
    ///   - id: The ID of the tab to update.
    ///   - mutation: A closure that mutates the tab.
    func updateTab(id: TabID, mutation: (inout Tab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        mutation(&tabs[index])
    }

    // MARK: - Rename

    /// Sets or clears a custom title for a tab.
    ///
    /// When `newTitle` is non-nil, the tab's `displayTitle` will return
    /// the custom title instead of the auto-generated directory+branch name.
    /// Pass `nil` to revert to the auto-generated title.
    ///
    /// - Parameters:
    ///   - id: The ID of the tab to rename.
    ///   - newTitle: The custom title, or nil to clear.
    func renameTab(id: TabID, newTitle: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].customTitle = newTitle
    }

    // MARK: - Navigation

    /// Activates the next tab in the list (circular).
    ///
    /// If the current tab is the last, wraps around to the first.
    /// With a single tab, this is a no-op.
    func nextTab() {
        guard tabs.count > 1 else { return }
        guard let currentIndex = currentActiveIndex() else { return }

        let nextIndex = (currentIndex + 1) % tabs.count
        deactivateCurrentTab()
        activateTabAtIndex(nextIndex)
    }

    /// Activates the previous tab in the list (circular).
    ///
    /// If the current tab is the first, wraps around to the last.
    /// With a single tab, this is a no-op.
    func previousTab() {
        guard tabs.count > 1 else { return }
        guard let currentIndex = currentActiveIndex() else { return }

        let previousIndex = (currentIndex - 1 + tabs.count) % tabs.count
        deactivateCurrentTab()
        activateTabAtIndex(previousIndex)
    }

    /// Activates the tab at a specific index (0-based).
    ///
    /// Used for Cmd+1...9 keyboard shortcuts to jump to a specific tab.
    /// Invalid indices (negative or out of bounds) are silently ignored.
    ///
    /// - Parameter index: The 0-based index of the tab to activate.
    func gotoTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        deactivateCurrentTab()
        activateTabAtIndex(index)
    }

    // MARK: - Lookup

    /// Returns the tab with the given ID, or nil if not found.
    ///
    /// - Parameter id: The tab ID to search for.
    /// - Returns: The matching tab, or nil.
    func tab(for id: TabID) -> Tab? {
        tabs.first { $0.id == id }
    }

    // MARK: - Private Helpers

    /// Deactivates the currently active tab.
    private func deactivateCurrentTab() {
        if let activeIndex = currentActiveIndex() {
            tabs[activeIndex].isActive = false
        }
    }

    /// Activates the tab at the given index and updates `activeTabID`.
    private func activateTabAtIndex(_ index: Int) {
        guard index >= 0, index < tabs.count else { return }
        tabs[index].isActive = true
        activeTabID = tabs[index].id
    }

    /// Returns the index of the currently active tab.
    private func currentActiveIndex() -> Int? {
        guard let activeID = activeTabID else { return nil }
        return tabs.firstIndex { $0.id == activeID }
    }
}
