// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DockBadgeController.swift - Dock icon badge management (T-033).

import Foundation
import Combine

// MARK: - Dock Tile Providing Protocol

/// Abstraction over `NSApp.dockTile` for testability.
///
/// Production code uses `SystemDockTile` which wraps `NSApp.dockTile`.
/// Tests use `SpyDockTile` to inspect badge changes.
@MainActor
protocol DockTileProviding: AnyObject {
    /// Sets the badge label on the dock tile.
    ///
    /// Pass `nil` to remove the badge.
    ///
    /// - Parameter label: The badge text, or `nil` to clear.
    func setBadgeLabel(_ label: String?)
}

// MARK: - Unread Count Publishing Protocol

/// Provides a publisher for unread notification count changes.
///
/// Decouples `DockBadgeController` from `NotificationManagerImpl` so
/// any source of unread counts can drive the dock badge.
@MainActor
protocol UnreadCountPublishing: AnyObject {
    /// Publisher that emits the total unread count whenever it changes.
    var unreadCountPublisher: AnyPublisher<Int, Never> { get }
}

// MARK: - Dock Badge Controller

/// Manages the unread count badge on the macOS Dock icon.
///
/// Subscribes to unread count changes via `UnreadCountPublishing` and
/// updates the dock tile badge accordingly. The badge is capped at "99+"
/// to avoid absurdly long labels.
///
/// ## Configuration
///
/// The badge can be disabled via `notifications.show-dock-badge = false`
/// in the configuration. When disabled, the badge is always cleared.
///
/// ## Lifecycle
///
/// 1. Create with dependencies.
/// 2. Call `bind()` to start observing unread count changes.
/// 3. The controller maintains the subscription until deallocated.
///
/// - SeeAlso: `DockTileProviding`
/// - SeeAlso: `UnreadCountPublishing`
@MainActor
final class DockBadgeController {

    // MARK: - Properties

    /// The dock tile abstraction for setting badge labels.
    private let dockTile: DockTileProviding

    /// The source of unread count changes.
    private let unreadCountSource: UnreadCountPublishing

    /// The current configuration snapshot.
    private let config: CocxyConfig

    /// The maximum count displayed literally. Above this, "99+" is shown.
    private let maxDisplayCount = 99

    /// The active subscription to unread count changes.
    private var cancellable: AnyCancellable?

    // MARK: - Initialization

    /// Creates a DockBadgeController.
    ///
    /// - Parameters:
    ///   - dockTile: The dock tile to update.
    ///   - unreadCountSource: The publisher of unread count changes.
    ///   - config: The application configuration.
    init(
        dockTile: DockTileProviding,
        unreadCountSource: UnreadCountPublishing,
        config: CocxyConfig
    ) {
        self.dockTile = dockTile
        self.unreadCountSource = unreadCountSource
        self.config = config
    }

    // MARK: - Binding

    /// Starts observing unread count changes and updating the dock badge.
    ///
    /// Call this once after initialization. The subscription is maintained
    /// until the controller is deallocated.
    func bind() {
        cancellable = unreadCountSource.unreadCountPublisher
            .sink { [weak self] count in
                self?.updateBadge(count: count)
            }
    }

    // MARK: - Private

    /// Updates the dock badge label based on the unread count and configuration.
    ///
    /// - Parameter count: The current unread notification count.
    private func updateBadge(count: Int) {
        guard config.notifications.showDockBadge else {
            dockTile.setBadgeLabel(nil)
            return
        }

        if count <= 0 {
            dockTile.setBadgeLabel(nil)
        } else if count > maxDisplayCount {
            dockTile.setBadgeLabel("\(maxDisplayCount)+")
        } else {
            dockTile.setBadgeLabel("\(count)")
        }
    }
}
