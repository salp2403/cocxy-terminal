// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSidebarPreferences.swift - User preferences for the visual Vault pane.

import CoreGraphics
import Foundation
import CocxyVault

enum VaultSidebarWidthMode: String, CaseIterable, Codable, Sendable {
    case expanded
    case compact
    case iconOnly

    var panelWidth: CGFloat {
        switch self {
        case .expanded: return 320
        case .compact: return 180
        case .iconOnly: return 60
        }
    }

    var next: VaultSidebarWidthMode {
        switch self {
        case .expanded: return .compact
        case .compact: return .iconOnly
        case .iconOnly: return .expanded
        }
    }
}

final class VaultSidebarPreferences {
    private enum Key {
        static let sortOrder = "vaultSidebar.sortOrder"
        static let groupBy = "vaultSidebar.groupBy"
        static let widthMode = "vaultSidebar.widthMode"
        static let hasSeenOnboarding = "vaultSidebar.hasSeenOnboarding"
    }

    private let defaults: UserDefaults
    private let userStateStore: VaultUserStateStore

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.userStateStore = VaultUserStateStore(defaults: defaults)
    }

    var pinnedSessionIDs: Set<String> {
        get { userStateStore.pinnedSessionIDs }
        set { userStateStore.pinnedSessionIDs = newValue }
    }

    var sortOrder: VaultSortOrder {
        get {
            guard let rawValue = defaults.string(forKey: Key.sortOrder),
                  let value = VaultSortOrder(rawValue: rawValue) else {
                return .mostRecent
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.sortOrder) }
    }

    var groupBy: VaultGroupBy {
        get {
            guard let rawValue = defaults.string(forKey: Key.groupBy),
                  let value = VaultGroupBy(rawValue: rawValue) else {
                return .pinFirst
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.groupBy) }
    }

    var widthMode: VaultSidebarWidthMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.widthMode),
                  let value = VaultSidebarWidthMode(rawValue: rawValue) else {
                return .expanded
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.widthMode) }
    }

    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasSeenOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasSeenOnboarding) }
    }
}
