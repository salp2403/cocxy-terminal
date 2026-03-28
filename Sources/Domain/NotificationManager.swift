// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotificationManager.swift - Centralized notification management.

import Foundation
import Combine

// MARK: - System Notification Emitting Protocol

/// Abstraction for emitting system-level notifications (macOS UNUserNotificationCenter).
///
/// The `NotificationManagerImpl` uses this protocol to dispatch notifications
/// to the OS. Injecting this dependency allows tests to use a mock instead of
/// touching real system APIs.
///
/// - SeeAlso: `MacOSNotificationAdapter` (production implementation, T-031)
@MainActor
protocol SystemNotificationEmitting: AnyObject {
    /// Delivers a notification to the operating system.
    ///
    /// - Parameter notification: The notification to deliver.
    func emit(_ notification: CocxyNotification)
}

// MARK: - Attention Item

/// A single item in the attention queue representing an unread notification.
///
/// Items are ordered by urgency (derived from `NotificationType.Comparable`)
/// and then by timestamp (most recent first within the same urgency tier).
struct AttentionItem: Identifiable, Sendable {
    /// Unique identifier for this attention item.
    let id: UUID
    /// The tab that generated this notification.
    let tabId: TabID
    /// The type of notification.
    let type: NotificationType
    /// Short title from the original notification.
    let title: String
    /// Body text from the original notification.
    let body: String
    /// When the notification was created.
    let timestamp: Date
    /// Whether the user has acknowledged this notification.
    var isRead: Bool
}

// MARK: - Coalescence Key

/// Key used for coalescence deduplication: same tab + same notification type.
private struct CoalescenceKey: Hashable {
    let tabId: TabID
    let typeKey: String

    init(tabId: TabID, type: NotificationType) {
        self.tabId = tabId
        self.typeKey = Self.normalizeType(type)
    }

    private static func normalizeType(_ type: NotificationType) -> String {
        switch type {
        case .agentNeedsAttention: return "agentNeedsAttention"
        case .agentError: return "agentError"
        case .agentFinished: return "agentFinished"
        case .processExited: return "processExited"
        case .custom: return "custom"
        }
    }
}

// MARK: - Notification Manager Implementation

/// Concrete implementation of `NotificationManaging`.
///
/// Centralizes all notification logic:
/// - Receives events from `AgentDetectionEngine` and other modules.
/// - Applies coalescence (suppresses duplicate same-type notifications for
///   the same tab within a configurable window).
/// - Applies rate limiting (at most one system notification per tab within
///   a configurable window, regardless of type).
/// - Manages per-tab unread state via an attention queue.
/// - Delegates to a `SystemNotificationEmitting` adapter for macOS notifications.
/// - Exposes Combine publishers for UI consumers (tab badges, dock icon).
///
/// ## Coalescence vs Rate Limiting
///
/// These are two separate mechanisms:
///
/// - **Coalescence**: Prevents duplicate notifications of the *same type* for
///   the *same tab* within a short window (default 2s). Example: if a tab
///   flickers between working and waitingInput rapidly, only one
///   "agentNeedsAttention" notification is generated.
///
/// - **Rate limiting**: Prevents notification spam to the OS. At most one
///   system notification per tab within a longer window (default 5s). The
///   attention item is always created (for the badge), but the system push
///   is suppressed if the tab already emitted recently.
///
/// - SeeAlso: `NotificationManaging` protocol
/// - SeeAlso: `SystemNotificationEmitting` protocol
@MainActor
final class NotificationManagerImpl: NotificationManaging, UnreadCountPublishing {

    // MARK: - Published State

    /// All attention items, ordered by urgency then timestamp.
    private(set) var attentionQueue: [AttentionItem] = []

    // MARK: - NotificationManaging Conformance

    var unreadCount: Int {
        attentionQueue.filter { !$0.isRead }.count
    }

    var notificationsPublisher: AnyPublisher<CocxyNotification, Never> {
        notificationsSubject.eraseToAnyPublisher()
    }

    var unreadCountPublisher: AnyPublisher<Int, Never> {
        unreadCountSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let notificationsSubject = PassthroughSubject<CocxyNotification, Never>()
    private let unreadCountSubject = PassthroughSubject<Int, Never>()

    /// Adapter for system-level notifications (injectable for testing).
    private let systemEmitter: SystemNotificationEmitting

    /// Current configuration snapshot.
    private var config: CocxyConfig

    /// Coalescence window in seconds. Duplicate same-type notifications for
    /// the same tab within this window are suppressed.
    private let coalescenceWindow: TimeInterval

    /// Rate limit window in seconds. At most one system notification per tab
    /// within this window.
    private let rateLimitPerTab: TimeInterval

    /// Tracks the last notification timestamp per coalescence key (tab + type).
    private var lastCoalescenceTimestamps: [CoalescenceKey: Date] = [:]

    /// Tracks the last system emission timestamp per tab (for rate limiting).
    private var lastEmissionTimestamps: [TabID: Date] = [:]

    // MARK: - Initialization

    /// Creates a NotificationManagerImpl.
    ///
    /// - Parameters:
    ///   - config: The application configuration. Notifications section controls
    ///     whether system notifications are sent.
    ///   - systemEmitter: Adapter for delivering system notifications.
    ///   - coalescenceWindow: Seconds within which duplicate same-type
    ///     notifications for the same tab are suppressed. Default 2.0.
    ///   - rateLimitPerTab: Seconds within which at most one system notification
    ///     is sent per tab. Default 5.0.
    init(
        config: CocxyConfig,
        systemEmitter: SystemNotificationEmitting,
        coalescenceWindow: TimeInterval = 2.0,
        rateLimitPerTab: TimeInterval = 5.0
    ) {
        self.config = config
        self.systemEmitter = systemEmitter
        self.coalescenceWindow = coalescenceWindow
        self.rateLimitPerTab = rateLimitPerTab
    }

    // MARK: - NotificationManaging: notify

    func notify(_ notification: CocxyNotification) {
        let now = Date()

        guard !isCoalesced(notification: notification, at: now) else { return }

        recordCoalescenceTimestamp(for: notification, at: now)
        enqueueAttentionItem(from: notification, at: now)
        publishNotification(notification)
        emitToSystemIfAllowed(notification, at: now)
    }

    // MARK: - NotificationManaging: markAsRead

    func markAsRead(tabId: TabID) {
        var changed = false
        for index in attentionQueue.indices {
            if attentionQueue[index].tabId == tabId && !attentionQueue[index].isRead {
                attentionQueue[index].isRead = true
                changed = true
            }
        }
        if changed {
            unreadCountSubject.send(unreadCount)
        }
    }

    // MARK: - NotificationManaging: markAllAsRead

    func markAllAsRead() {
        var changed = false
        for index in attentionQueue.indices {
            if !attentionQueue[index].isRead {
                attentionQueue[index].isRead = true
                changed = true
            }
        }
        if changed {
            unreadCountSubject.send(unreadCount)
        }
    }

    // MARK: - NotificationManaging: gotoNextUnread

    func gotoNextUnread() -> TabID? {
        guard let firstUnread = attentionQueue.first(where: { !$0.isRead }) else {
            return nil
        }
        let tabId = firstUnread.tabId
        markAsRead(tabId: tabId)
        return tabId
    }

    // MARK: - Additional Public API

    /// Returns the tab ID of the next unread item without marking it as read.
    ///
    /// Useful for UI previews that need to show what will happen on "goto next".
    /// - Returns: The tab ID of the highest-urgency unread item, or nil.
    func peekNextUnread() -> TabID? {
        attentionQueue.first(where: { !$0.isRead })?.tabId
    }

    /// Returns the number of unread notifications for a specific tab.
    ///
    /// - Parameter tabId: The tab to query.
    /// - Returns: Number of unread notifications for the tab.
    func unreadCountForTab(_ tabId: TabID) -> Int {
        attentionQueue.filter { $0.tabId == tabId && !$0.isRead }.count
    }

    /// Handles a notification action (e.g., user clicked on a macOS notification).
    ///
    /// Marks all notifications for the given tab as read.
    /// - Parameter tabId: The tab associated with the clicked notification.
    func handleNotificationAction(tabId: TabID) {
        markAsRead(tabId: tabId)
    }

    /// Returns the most recent unread notification for a specific tab.
    ///
    /// Used by the tab bar to show a hover preview of what the notification says.
    /// - Parameter tabId: The tab to query.
    /// - Returns: The most recent unread attention item, or nil if none.
    func latestUnreadForTab(_ tabId: TabID) -> AttentionItem? {
        attentionQueue.last { $0.tabId == tabId && !$0.isRead }
    }

    /// Convenience method that translates agent state changes into notifications.
    ///
    /// Only states that require user attention generate notifications:
    /// - `waitingInput` -> `agentNeedsAttention` (high urgency)
    /// - `finished` -> `agentFinished` (medium urgency)
    /// - `error` -> `agentError` (high urgency)
    ///
    /// States `idle`, `launched`, and `working` do NOT generate notifications.
    ///
    /// - Parameters:
    ///   - state: The new agent state.
    ///   - previousState: The state before the transition.
    ///   - tabId: The tab where the state change occurred.
    ///   - tabTitle: Display title of the tab (used in notification text).
    ///   - agentName: Name of the detected agent, if any.
    func handleStateChange(
        state: AgentState,
        previousState: AgentState,
        for tabId: TabID,
        tabTitle: String,
        agentName: String?
    ) {
        let notificationType: NotificationType
        let title: String
        let body: String

        let agentLabel = agentName ?? "Agent"

        switch state {
        case .waitingInput:
            notificationType = .agentNeedsAttention
            title = "\(agentLabel) needs your input"
            body = "Tab \"\(tabTitle)\" is waiting for input."

        case .finished:
            notificationType = .agentFinished
            title = "\(agentLabel) completed task"
            body = "Tab \"\(tabTitle)\" has finished."

        case .error:
            notificationType = .agentError
            title = "\(agentLabel) encountered an error"
            body = "Tab \"\(tabTitle)\" has an error."

        case .idle, .launched, .working:
            // These states do not generate notifications.
            return
        }

        let notification = CocxyNotification(
            type: notificationType,
            tabId: tabId,
            title: title,
            body: body
        )
        notify(notification)
    }

    /// Updates the configuration snapshot.
    ///
    /// Call this when the user changes notification preferences.
    /// The change takes effect immediately for the next notification.
    ///
    /// - Parameter newConfig: The new application configuration.
    func updateConfig(_ newConfig: CocxyConfig) {
        config = newConfig
    }

    // MARK: - Private Helpers

    /// Returns true if this notification should be suppressed by coalescence.
    ///
    /// A notification is coalesced when the same tab + same type combination
    /// was already notified within the coalescence window.
    private func isCoalesced(notification: CocxyNotification, at now: Date) -> Bool {
        let key = CoalescenceKey(tabId: notification.tabId, type: notification.type)
        guard let lastTimestamp = lastCoalescenceTimestamps[key] else { return false }
        return now.timeIntervalSince(lastTimestamp) < coalescenceWindow
    }

    /// Records the timestamp for a coalescence key.
    private func recordCoalescenceTimestamp(for notification: CocxyNotification, at now: Date) {
        let key = CoalescenceKey(tabId: notification.tabId, type: notification.type)
        lastCoalescenceTimestamps[key] = now
    }

    /// Creates an attention item from a notification and appends it to the queue.
    private func enqueueAttentionItem(from notification: CocxyNotification, at now: Date) {
        let item = AttentionItem(
            id: notification.id,
            tabId: notification.tabId,
            type: notification.type,
            title: notification.title,
            body: notification.body,
            timestamp: now,
            isRead: false
        )
        attentionQueue.append(item)
        sortAttentionQueue()
    }

    /// Publishes the notification through Combine subjects.
    private func publishNotification(_ notification: CocxyNotification) {
        notificationsSubject.send(notification)
        unreadCountSubject.send(unreadCount)
    }

    /// Emits the notification to the system if config allows and rate limit is not exceeded.
    private func emitToSystemIfAllowed(_ notification: CocxyNotification, at now: Date) {
        guard config.notifications.macosNotifications else { return }

        if let lastEmission = lastEmissionTimestamps[notification.tabId],
           now.timeIntervalSince(lastEmission) < rateLimitPerTab {
            return
        }

        lastEmissionTimestamps[notification.tabId] = now
        systemEmitter.emit(notification)
    }

    /// Sorts the attention queue by urgency (highest first), then by
    /// timestamp (most recent first within the same urgency tier).
    private func sortAttentionQueue() {
        attentionQueue.sort { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type < rhs.type
            }
            return lhs.timestamp > rhs.timestamp
        }
    }
}
