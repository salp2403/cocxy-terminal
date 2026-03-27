// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabSplitCoordinator.swift - Coordinates SplitManagers per tab.

import Foundation

// MARK: - Tab Split Coordinator

/// Coordinates `SplitManager` instances across tabs.
///
/// Each tab has its own `SplitManager` with independent split state.
/// The coordinator lazily creates a `SplitManager` when first requested
/// for a tab, and caches it for the lifetime of that tab.
///
/// When a tab is closed, `removeSplitManager(for:)` should be called
/// to release the associated resources.
///
/// ## Thread safety
///
/// All access must be on `@MainActor` (same as `SplitManager` and `TabManager`).
///
/// - SeeAlso: `SplitManager`
/// - SeeAlso: `TabManager`
@MainActor
final class TabSplitCoordinator {

    // MARK: - Private State

    /// Cache of SplitManagers keyed by their tab ID.
    private var managers: [TabID: SplitManager] = [:]

    // MARK: - Public API

    /// Returns the `SplitManager` for the given tab, creating one if needed.
    ///
    /// The first call for a given tab ID creates a new `SplitManager` with
    /// a single leaf. Subsequent calls return the same instance.
    ///
    /// - Parameter tabID: The ID of the tab.
    /// - Returns: The `SplitManager` for this tab.
    func splitManager(for tabID: TabID) -> SplitManager {
        if let existing = managers[tabID] {
            return existing
        }

        let newManager = SplitManager()
        managers[tabID] = newManager
        return newManager
    }

    /// Removes the `SplitManager` for a tab when it is closed.
    ///
    /// After removal, requesting a SplitManager for the same tab ID
    /// will create a new, fresh instance.
    ///
    /// - Parameter tabID: The ID of the tab being closed.
    func removeSplitManager(for tabID: TabID) {
        managers.removeValue(forKey: tabID)
    }

    /// Returns the number of tracked SplitManagers.
    ///
    /// Useful for testing and debugging.
    var count: Int {
        managers.count
    }
}
