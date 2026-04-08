// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickSwitchController.swift - Quick switch to next unread tab (T-032).

import Foundation

// MARK: - Tab Activating Protocol

/// Abstraction for activating a specific tab.
///
/// Decouples `QuickSwitchController` from `TabManager` so the feature
/// can be tested without a full tab manager dependency.
@MainActor
protocol TabActivating: AnyObject {
    /// Activates the tab with the given identifier.
    ///
    /// - Parameter id: The tab to activate.
    func setActive(id: TabID)
}

// MARK: - Quick Switch Result

/// The outcome of a quick switch operation.
///
/// Contains the tab that was activated and a human-readable description
/// suitable for showing in a transient HUD overlay.
struct QuickSwitchResult {
    /// The tab that was activated.
    let tabId: TabID
    /// Human-readable description (e.g., "Switched to unread tab").
    let description: String
}

// MARK: - Quick Switch Controller

/// Coordinates the "Quick Switch" feature (Cmd+Shift+U).
///
/// Quick Switch jumps the user to the next tab with unread attention items.
/// Each invocation asks the `NotificationManaging` service for the next
/// unread tab and activates it via `TabActivating`.
///
/// The rotation is driven by `NotificationManaging.gotoNextUnread()` which
/// returns the highest-urgency unread item and marks it as read. Successive
/// calls naturally rotate through all pending items.
///
/// ## Usage
///
/// ```swift
/// let controller = QuickSwitchController(
///     notificationManager: notificationManager,
///     tabActivator: tabManager
/// )
/// let result = controller.performQuickSwitch()
/// if let result {
///     showHUD(result.description)
/// }
/// ```
///
/// - SeeAlso: `NotificationManaging.gotoNextUnread()`
/// - SeeAlso: `TabActivating`
@MainActor
final class QuickSwitchController {

    // MARK: - Properties

    /// The notification manager that tracks unread attention items.
    private let notificationManager: NotificationManaging

    /// The tab activator that brings a tab to focus.
    private let tabActivator: TabActivating

    /// Optional provider for a user-visible tab title used in HUD messages.
    private let tabNameProvider: ((TabID) -> String?)?

    // MARK: - Initialization

    /// Creates a QuickSwitchController.
    ///
    /// - Parameters:
    ///   - notificationManager: The notification manager for unread state.
    ///   - tabActivator: The service that can activate a specific tab.
    init(
        notificationManager: NotificationManaging,
        tabActivator: TabActivating,
        tabNameProvider: ((TabID) -> String?)? = nil
    ) {
        self.notificationManager = notificationManager
        self.tabActivator = tabActivator
        self.tabNameProvider = tabNameProvider
    }

    // MARK: - Quick Switch

    /// Performs a quick switch to the next tab with unread attention.
    ///
    /// Asks the notification manager for the next unread tab, activates it,
    /// and returns a result describing what happened. Returns `nil` if there
    /// are no tabs with pending attention.
    ///
    /// - Returns: A `QuickSwitchResult` describing the activated tab, or `nil`.
    func performQuickSwitch() -> QuickSwitchResult? {
        guard let tabId = notificationManager.gotoNextUnread() else {
            return nil
        }

        tabActivator.setActive(id: tabId)

        let description: String
        if let title = tabNameProvider?(tabId), !title.isEmpty {
            description = "Switched to: \(title)"
        } else {
            description = "Switched to unread tab"
        }

        return QuickSwitchResult(
            tabId: tabId,
            description: description
        )
    }
}
