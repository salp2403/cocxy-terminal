// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacOSNotificationAdapter.swift - Bridge to macOS UNUserNotificationCenter (T-031).

import Foundation

// MARK: - Notification Request Snapshot

/// Value type that captures the content of a notification request.
///
/// Used by `NotificationCenterProviding` to decouple from `UNNotificationContent`
/// so tests can inspect notification content without importing UserNotifications.
struct NotificationRequestSnapshot: Sendable {
    /// The notification identifier (used for deduplication by the OS).
    let identifier: String
    /// The notification title.
    let title: String
    /// The notification body text.
    let body: String
    /// The category identifier for action grouping.
    let categoryIdentifier: String
    /// Tab ID and other metadata.
    let userInfo: [String: String]
    /// Whether the notification should play a sound.
    let hasSound: Bool
    /// Sound name for this notification type. "default" uses the system default sound.
    /// Any other value is treated as a custom sound file name (must be bundled as .caf/.aiff).
    let soundName: String
}

// MARK: - Notification Authorization Options

/// Abstraction over `UNAuthorizationOptions` for testability.
struct NotificationAuthorizationOptions: OptionSet, Sendable {
    let rawValue: Int

    static let alert = NotificationAuthorizationOptions(rawValue: 1 << 0)
    static let sound = NotificationAuthorizationOptions(rawValue: 1 << 1)
    static let badge = NotificationAuthorizationOptions(rawValue: 1 << 2)
}

// MARK: - Notification Center Providing Protocol

/// Abstraction over `UNUserNotificationCenter` for testability.
///
/// Production code uses `RealNotificationCenter` which wraps
/// `UNUserNotificationCenter.current()`. Tests use `SpyNotificationCenter`.
@MainActor
protocol NotificationCenterProviding: AnyObject {
    /// Requests authorization to display notifications.
    ///
    /// - Parameter options: The types of notification interactions to request.
    /// - Returns: Whether the user granted authorization.
    func requestAuthorization(options: NotificationAuthorizationOptions) async -> Bool

    /// Adds a notification request to the notification center.
    ///
    /// - Parameter request: The notification content snapshot.
    func add(_ request: NotificationRequestSnapshot)
}

// MARK: - Notification Tab Routing Protocol

/// Routes a notification click to the correct tab.
///
/// Implemented by `MainWindowController` or a coordinator that can
/// activate a specific tab when the user clicks a macOS notification.
@MainActor
protocol NotificationTabRouting: AnyObject {
    /// Activates the tab with the given identifier.
    ///
    /// - Parameter id: The tab to bring to focus.
    func activateTab(id: TabID)
}

// MARK: - macOS Notification Adapter

/// Adapter that sends notifications through macOS's notification system.
///
/// Conforms to `SystemNotificationEmitting` so the `NotificationManagerImpl`
/// can dispatch notifications without knowing about `UNUserNotificationCenter`.
///
/// ## Architecture
///
/// ```
/// NotificationManagerImpl -> SystemNotificationEmitting (protocol)
///                                 |
///                         MacOSNotificationAdapter (this class)
///                                 |
///                         NotificationCenterProviding (protocol)
///                                 |
///                     UNUserNotificationCenter (production)
///                     or SpyNotificationCenter (tests)
/// ```
///
/// ## Permission Flow
///
/// Permissions are requested once. The result (granted or denied) is stored
/// in-memory. We do NOT re-request if the user already made a choice.
///
/// - SeeAlso: `SystemNotificationEmitting`
/// - SeeAlso: `NotificationCenterProviding`
@MainActor
final class MacOSNotificationAdapter: SystemNotificationEmitting {

    // MARK: - Properties

    /// The notification center abstraction.
    private let notificationCenter: NotificationCenterProviding

    /// The tab router for handling notification clicks.
    private let tabRouter: NotificationTabRouting

    /// The current config snapshot for sound preferences.
    private var config: CocxyConfig

    /// Whether we have already requested authorization (to avoid re-asking).
    private var hasRequestedPermission: Bool = false

    /// The category identifier used for all Cocxy agent notifications.
    private let categoryIdentifier = "COCXY_AGENT_STATE"

    // MARK: - Initialization

    /// Creates a MacOSNotificationAdapter.
    ///
    /// - Parameters:
    ///   - notificationCenter: The notification center to use for delivery.
    ///   - tabRouter: The router that handles notification click -> tab focus.
    ///   - config: The current application configuration.
    init(
        notificationCenter: NotificationCenterProviding,
        tabRouter: NotificationTabRouting,
        config: CocxyConfig
    ) {
        self.notificationCenter = notificationCenter
        self.tabRouter = tabRouter
        self.config = config
    }

    // MARK: - SystemNotificationEmitting

    func emit(_ notification: CocxyNotification) {
        let snapshot = NotificationRequestSnapshot(
            identifier: notification.id.uuidString,
            title: notification.title,
            body: notification.body,
            categoryIdentifier: categoryIdentifier,
            userInfo: ["tabID": notification.tabId.rawValue.uuidString],
            hasSound: config.notifications.sound,
            soundName: soundName(for: notification.type)
        )

        notificationCenter.add(snapshot)
    }

    /// Resolves the configured sound name for a given notification type.
    ///
    /// Maps each notification type to its per-type config field. Types without
    /// a dedicated config field (processExited, custom) use "default".
    private func soundName(for type: NotificationType) -> String {
        switch type {
        case .agentFinished:
            return config.notifications.soundFinished
        case .agentNeedsAttention:
            return config.notifications.soundAttention
        case .agentError:
            return config.notifications.soundError
        case .processExited, .custom:
            return "default"
        }
    }

    // MARK: - Permission Management

    /// Requests notification permission from the user if not already requested.
    ///
    /// This method is idempotent: calling it multiple times will only trigger
    /// one actual authorization request. The result (granted or denied) is
    /// cached in-memory.
    func requestPermissionIfNeeded() async {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true

        _ = await notificationCenter.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
    }

    // MARK: - Notification Click Handling

    /// Handles a notification click by routing to the associated tab.
    ///
    /// Extracts the tab ID from the notification's userInfo and asks the
    /// tab router to activate it.
    ///
    /// - Parameter tabIdString: The UUID string of the tab from userInfo.
    func handleNotificationClick(tabIdString: String) {
        guard let uuid = UUID(uuidString: tabIdString) else { return }
        let tabId = TabID(rawValue: uuid)
        tabRouter.activateTab(id: tabId)
    }

    // MARK: - Foreground Presentation

    /// Determines whether a notification should be shown when the app is in the foreground.
    ///
    /// A notification is shown if the tab that generated it is NOT the currently
    /// active tab. If the user is already looking at the tab, showing a system
    /// notification would be redundant.
    ///
    /// - Parameters:
    ///   - forTabId: The tab that generated the notification.
    ///   - activeTabId: The currently active (focused) tab.
    /// - Returns: `true` if the notification should be displayed.
    func shouldShowForegroundNotification(forTabId: TabID, activeTabId: TabID) -> Bool {
        forTabId != activeTabId
    }

    // MARK: - Config Updates

    /// Updates the configuration snapshot.
    ///
    /// Call this when the user changes notification preferences.
    ///
    /// - Parameter newConfig: The new application configuration.
    func updateConfig(_ newConfig: CocxyConfig) {
        config = newConfig
    }
}
