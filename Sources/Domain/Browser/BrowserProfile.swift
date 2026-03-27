// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserProfile.swift - Domain model for browser profile isolation.

import Foundation

// MARK: - Browser Profile

/// A browser profile that isolates cookies, storage, and cache.
///
/// Each profile maintains its own WebKit data store directory under
/// `~/.config/cocxy/browser/profiles/<uuid>/`. This ensures that
/// sessions across profiles never share authentication state, cookies,
/// or cached resources.
///
/// One profile is always marked as default and cannot be deleted.
///
/// - SeeAlso: ``BrowserProfileManager`` for CRUD and switching.
/// - SeeAlso: ``BrowserProfileStore`` for persistence.
struct BrowserProfile: Identifiable, Codable, Equatable, Sendable {

    /// Unique identifier for this profile.
    let id: UUID

    /// User-visible name (e.g., "Personal", "Work").
    var name: String

    /// SF Symbol name for visual identification.
    var icon: String

    /// Hex color string for visual distinction in the UI (e.g., "#FF5733").
    var colorHex: String

    /// Whether this is the default profile. Exactly one profile must be default.
    var isDefault: Bool

    /// Timestamp when this profile was created.
    let createdAt: Date

    /// Creates a new browser profile.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Display name for the profile.
    ///   - icon: SF Symbol name. Defaults to "person.circle".
    ///   - colorHex: Hex color. Defaults to "#FFFFFF".
    ///   - isDefault: Whether this is the default profile. Defaults to false.
    ///   - createdAt: Creation timestamp. Defaults to now.
    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "person.circle",
        colorHex: String = "#FFFFFF",
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    // MARK: - Paths

    /// Base directory for all browser profile data stores.
    static let profilesBaseDirectory: String = {
        NSHomeDirectory() + "/.config/cocxy/browser/profiles"
    }()

    /// Directory path for this profile's isolated WebKit data store.
    var dataStorePath: String {
        "\(Self.profilesBaseDirectory)/\(id.uuidString)"
    }
}
