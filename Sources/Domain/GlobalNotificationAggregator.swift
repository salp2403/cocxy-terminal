// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlobalNotificationAggregator.swift - Cross-window notification count aggregation.

import Foundation
import Combine

// MARK: - Protocol

/// Contract for aggregating notification state across all windows.
///
/// The aggregator reads unread flags from the `SessionRegistry` and
/// provides window-scoped and global counts. It does NOT duplicate
/// the per-tab notification storage in `NotificationManagerImpl` —
/// it only aggregates the boolean `hasUnreadNotification` flag that
/// each session entry carries.
///
/// ## Data Flow
///
/// ```
/// NotificationManagerImpl -> notify() -> marks Tab.hasUnreadNotification
///        |
///        v
/// SessionRegistry -> markUnread(sessionID)
///        |
///        v
/// GlobalNotificationAggregator (reads registry) -> publishes counts
///        |
///        ├─> DockBadgeController (total count)
///        └─> TabBarView (remote count for "N in other windows")
/// ```
@MainActor
protocol GlobalNotificationAggregating: AnyObject {
    /// Total unread notifications across ALL windows.
    var totalUnreadCount: Int { get }

    /// Unread notifications in a specific window.
    func unreadCount(for windowID: WindowID) -> Int

    /// Unread notifications in windows OTHER than the specified one.
    /// Used to show "N in other windows" in the sidebar footer.
    func remoteUnreadCount(excluding windowID: WindowID) -> Int

    /// Publisher that emits the total unread count on every change.
    var totalUnreadPublisher: AnyPublisher<Int, Never> { get }

    /// Publisher that emits when any window's unread count changes.
    /// Carries the window ID that changed and its new count.
    var windowUnreadPublisher: AnyPublisher<(windowID: WindowID, count: Int), Never> { get }
}

// MARK: - Implementation

/// Aggregates notification unread counts from the `SessionRegistry`.
///
/// Subscribes to the registry's `sessionUpdated` and `sessionRemoved`
/// publishers to detect notification state changes. Recomputes counts
/// from the registry's session entries on every change.
///
/// This is lightweight — no storage of notifications, just counting
/// boolean flags on existing `SessionEntry` values.
@MainActor
final class GlobalNotificationAggregatorImpl: GlobalNotificationAggregating {

    // MARK: - Dependencies

    private let registry: any SessionRegistering

    // MARK: - Subjects

    private let totalUnreadSubject = CurrentValueSubject<Int, Never>(0)
    private let windowUnreadSubject = PassthroughSubject<(windowID: WindowID, count: Int), Never>()

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(registry: any SessionRegistering) {
        self.registry = registry
        subscribeToRegistryChanges()
        recomputeTotalCount()
    }

    // MARK: - Protocol

    var totalUnreadCount: Int {
        registry.allSessions.filter(\.hasUnreadNotification).count
    }

    func unreadCount(for windowID: WindowID) -> Int {
        registry.sessions(in: windowID).filter(\.hasUnreadNotification).count
    }

    func remoteUnreadCount(excluding windowID: WindowID) -> Int {
        registry.allSessions
            .filter { $0.ownerWindowID != windowID && $0.hasUnreadNotification }
            .count
    }

    var totalUnreadPublisher: AnyPublisher<Int, Never> {
        totalUnreadSubject.eraseToAnyPublisher()
    }

    var windowUnreadPublisher: AnyPublisher<(windowID: WindowID, count: Int), Never> {
        windowUnreadSubject.eraseToAnyPublisher()
    }

    // MARK: - Subscriptions

    private func subscribeToRegistryChanges() {
        registry.sessionUpdated
            .sink { [weak self] event in
                guard let self else { return }
                switch event.change {
                case .notificationStateChanged:
                    let windowCount = self.unreadCount(for: event.windowID)
                    self.windowUnreadSubject.send((windowID: event.windowID, count: windowCount))
                    self.recomputeTotalCount()

                case .ownerChanged(let oldWindow, let newWindow):
                    guard self.registry.session(for: event.sessionID)?.hasUnreadNotification == true else {
                        return
                    }
                    self.windowUnreadSubject.send((windowID: oldWindow, count: self.unreadCount(for: oldWindow)))
                    self.windowUnreadSubject.send((windowID: newWindow, count: self.unreadCount(for: newWindow)))
                    self.recomputeTotalCount()

                case .titleChanged, .workingDirectoryChanged, .agentStateChanged, .transferStateChanged:
                    break
                }
            }
            .store(in: &cancellables)

        registry.sessionRemoved
            .sink { [weak self] removal in
                guard let self else { return }
                self.windowUnreadSubject.send((
                    windowID: removal.windowID,
                    count: self.unreadCount(for: removal.windowID)
                ))
                self.recomputeTotalCount()
            }
            .store(in: &cancellables)

        registry.sessionAdded
            .filter(\.hasUnreadNotification)
            .sink { [weak self] entry in
                guard let self else { return }
                let windowCount = self.unreadCount(for: entry.ownerWindowID)
                self.windowUnreadSubject.send((windowID: entry.ownerWindowID, count: windowCount))
                self.recomputeTotalCount()
            }
            .store(in: &cancellables)
    }

    private func recomputeTotalCount() {
        totalUnreadSubject.send(totalUnreadCount)
    }
}

// MARK: - UnreadCountPublishing Conformance

/// Allows the aggregator to be used as the dock badge count source,
/// replacing the single-window `NotificationManagerImpl`.
extension GlobalNotificationAggregatorImpl: UnreadCountPublishing {
    var unreadCountPublisher: AnyPublisher<Int, Never> {
        totalUnreadPublisher
    }
}
