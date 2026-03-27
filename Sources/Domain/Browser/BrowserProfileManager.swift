// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserProfileManager.swift - CRUD and switching for browser profiles.

import Foundation

// MARK: - Browser Profile Store Protocol

/// Persistence contract for browser profiles.
///
/// Implementations handle reading and writing profile data to disk.
/// The default implementation uses a JSON file at
/// `~/.config/cocxy/browser/profiles.json`.
///
/// - SeeAlso: ``JSONBrowserProfileStore`` for the default implementation.
protocol BrowserProfileStore: Sendable {

    /// Loads all profiles from persistent storage.
    ///
    /// - Returns: The list of saved profiles. Empty if none exist.
    /// - Throws: If the storage cannot be read.
    func loadProfiles() throws -> [BrowserProfile]

    /// Saves the complete list of profiles, replacing any previous data.
    ///
    /// - Parameter profiles: The profiles to persist.
    /// - Throws: If the storage cannot be written.
    func saveProfiles(_ profiles: [BrowserProfile]) throws

    /// Deletes the on-disk data store directory for a profile.
    ///
    /// This removes cookies, cache, and local storage for the profile.
    ///
    /// - Parameter id: The profile whose data should be deleted.
    /// - Throws: If the directory cannot be removed.
    func deleteProfileData(id: UUID) throws
}

// MARK: - Browser Profile Manager

/// Manages browser profiles: creation, deletion, switching, and updates.
///
/// Maintains a published list of profiles and the currently active profile.
/// The default profile cannot be deleted. On initialization, if no profiles
/// exist, a default profile named "Default" is created automatically.
///
/// - SeeAlso: ``BrowserProfile``
/// - SeeAlso: ``BrowserProfileStore``
@MainActor
final class BrowserProfileManager: ObservableObject {

    // MARK: - Published State

    /// All available browser profiles.
    @Published private(set) var profiles: [BrowserProfile]

    /// The ID of the currently active profile.
    @Published var activeProfileID: UUID

    // MARK: - Dependencies

    private let store: BrowserProfileStore

    // MARK: - Initialization

    /// Creates a profile manager backed by the given store.
    ///
    /// Loads persisted profiles on init. If none exist, creates a default profile.
    ///
    /// - Parameter store: The persistence layer for profiles.
    init(store: BrowserProfileStore) {
        self.store = store

        let loaded: [BrowserProfile]
        do {
            loaded = try store.loadProfiles()
        } catch {
            #if DEBUG
            print("[BrowserProfileManager] Failed to load profiles: \(error)")
            #endif
            loaded = []
        }

        if loaded.isEmpty {
            let defaultProfile = BrowserProfile(
                name: "Default",
                icon: "person.circle",
                colorHex: "#FFFFFF",
                isDefault: true
            )
            self.profiles = [defaultProfile]
            self.activeProfileID = defaultProfile.id
            try? store.saveProfiles([defaultProfile])
        } else {
            self.profiles = loaded
            self.activeProfileID = loaded.first(where: { $0.isDefault })?.id
                ?? loaded.first?.id
                ?? UUID()
        }
    }

    // MARK: - Computed Properties

    /// The currently active profile.
    var activeProfile: BrowserProfile {
        profiles.first(where: { $0.id == activeProfileID })
            ?? profiles.first
            ?? BrowserProfile(name: "Default", isDefault: true)
    }

    // MARK: - CRUD Operations

    /// Creates a new profile and adds it to the list.
    ///
    /// The new profile is not set as default. Only one profile can be default.
    ///
    /// - Parameters:
    ///   - name: Display name for the profile.
    ///   - icon: SF Symbol name.
    ///   - colorHex: Hex color for visual distinction.
    /// - Returns: The newly created profile.
    @discardableResult
    func createProfile(name: String, icon: String, colorHex: String) -> BrowserProfile {
        let profile = BrowserProfile(
            name: name,
            icon: icon,
            colorHex: colorHex,
            isDefault: false
        )
        profiles.append(profile)
        persist()
        return profile
    }

    /// Deletes a profile by its ID.
    ///
    /// The default profile cannot be deleted. If the active profile is deleted,
    /// the manager switches to the default profile.
    ///
    /// - Parameter id: The ID of the profile to delete.
    func deleteProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        guard !profiles[index].isDefault else { return }

        profiles.remove(at: index)

        if activeProfileID == id {
            activeProfileID = profiles.first(where: { $0.isDefault })?.id
                ?? profiles.first?.id
                ?? UUID()
        }

        try? store.deleteProfileData(id: id)
        persist()
    }

    /// Switches the active profile.
    ///
    /// No-op if the ID does not match any existing profile.
    ///
    /// - Parameter id: The ID of the profile to activate.
    func switchProfile(to id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    /// Updates an existing profile's mutable properties.
    ///
    /// Matches by `id`. No-op if the profile is not found.
    ///
    /// - Parameter profile: The profile with updated values.
    func updateProfile(_ profile: BrowserProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile

        if profile.isDefault {
            for i in profiles.indices where profiles[i].id != profile.id {
                profiles[i].isDefault = false
            }
        }

        persist()
    }

    // MARK: - Persistence

    private func persist() {
        try? store.saveProfiles(profiles)
    }
}

// MARK: - JSON File Store

/// Default file-based profile store using JSON serialization.
///
/// Stores profiles in `~/.config/cocxy/browser/profiles.json`.
/// Creates the directory structure on first write.
final class JSONBrowserProfileStore: BrowserProfileStore {

    /// Path to the JSON file.
    let filePath: String

    /// Creates a store at the given path.
    ///
    /// - Parameter filePath: Path to the JSON file. Defaults to the standard config location.
    init(filePath: String = NSHomeDirectory() + "/.config/cocxy/browser/profiles.json") {
        self.filePath = filePath
    }

    func loadProfiles() throws -> [BrowserProfile] {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([BrowserProfile].self, from: data)
    }

    func saveProfiles(_ profiles: [BrowserProfile]) throws {
        let url = URL(fileURLWithPath: filePath)
        let directory = url.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: url, options: .atomic)
    }

    func deleteProfileData(id: UUID) throws {
        let path = BrowserProfile.profilesBaseDirectory + "/\(id.uuidString)"
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }
}
