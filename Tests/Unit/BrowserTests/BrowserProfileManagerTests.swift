// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserProfileManagerTests.swift - Tests for browser profile management.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Mock Profile Store

/// In-memory profile store for deterministic testing.
final class MockBrowserProfileStore: BrowserProfileStore, @unchecked Sendable {
    var savedProfiles: [BrowserProfile] = []
    var deletedProfileIDs: [UUID] = []
    var shouldThrowOnLoad = false
    var shouldThrowOnSave = false

    func loadProfiles() throws -> [BrowserProfile] {
        if shouldThrowOnLoad {
            throw NSError(domain: "test", code: 1)
        }
        return savedProfiles
    }

    func saveProfiles(_ profiles: [BrowserProfile]) throws {
        if shouldThrowOnSave {
            throw NSError(domain: "test", code: 2)
        }
        savedProfiles = profiles
    }

    func deleteProfileData(id: UUID) throws {
        deletedProfileIDs.append(id)
    }
}

// MARK: - Browser Profile Manager Tests

@Suite("BrowserProfileManager")
@MainActor
struct BrowserProfileManagerTests {

    // MARK: - Initialization

    @Test("Creates default profile when store is empty")
    func createsDefaultProfileWhenEmpty() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)

        #expect(manager.profiles.count == 1)
        #expect(manager.profiles[0].isDefault == true)
        #expect(manager.profiles[0].name == "Default")
        #expect(manager.activeProfileID == manager.profiles[0].id)
    }

    @Test("Loads persisted profiles from store")
    func loadsPersistedProfiles() {
        let store = MockBrowserProfileStore()
        let existing = BrowserProfile(name: "Existing", isDefault: true)
        store.savedProfiles = [existing]

        let manager = BrowserProfileManager(store: store)

        #expect(manager.profiles.count == 1)
        #expect(manager.profiles[0].id == existing.id)
        #expect(manager.activeProfileID == existing.id)
    }

    // MARK: - Create

    @Test("Create profile adds to list")
    func createProfileAddsToList() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let initialCount = manager.profiles.count

        let created = manager.createProfile(name: "Work", icon: "briefcase", colorHex: "#3498DB")

        #expect(manager.profiles.count == initialCount + 1)
        #expect(created.name == "Work")
        #expect(created.icon == "briefcase")
        #expect(created.colorHex == "#3498DB")
        #expect(created.isDefault == false)
    }

    @Test("Create profile persists to store")
    func createProfilePersists() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)

        _ = manager.createProfile(name: "Persisted", icon: "star", colorHex: "#FFF")

        #expect(store.savedProfiles.count == 2)
        #expect(store.savedProfiles.last?.name == "Persisted")
    }

    // MARK: - Delete

    @Test("Delete non-default profile removes it")
    func deleteNonDefaultProfile() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let created = manager.createProfile(name: "Deletable", icon: "trash", colorHex: "#000")

        manager.deleteProfile(id: created.id)

        #expect(manager.profiles.count == 1)
        #expect(!manager.profiles.contains(where: { $0.id == created.id }))
    }

    @Test("Cannot delete default profile")
    func cannotDeleteDefaultProfile() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let defaultID = manager.profiles.first(where: { $0.isDefault })!.id
        let countBefore = manager.profiles.count

        manager.deleteProfile(id: defaultID)

        #expect(manager.profiles.count == countBefore)
        #expect(manager.profiles.contains(where: { $0.id == defaultID }))
    }

    @Test("Deleting active profile switches to default")
    func deletingActiveProfileSwitchesToDefault() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let defaultID = manager.profiles[0].id
        let created = manager.createProfile(name: "Active", icon: "circle", colorHex: "#000")
        manager.switchProfile(to: created.id)

        #expect(manager.activeProfileID == created.id)

        manager.deleteProfile(id: created.id)

        #expect(manager.activeProfileID == defaultID)
    }

    @Test("Delete profile calls store.deleteProfileData")
    func deleteProfileCleansUpData() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let created = manager.createProfile(name: "Cleanup", icon: "trash", colorHex: "#000")

        manager.deleteProfile(id: created.id)

        #expect(store.deletedProfileIDs.contains(created.id))
    }

    // MARK: - Switch

    @Test("Switch to existing profile changes active ID")
    func switchToExistingProfile() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let created = manager.createProfile(name: "Target", icon: "arrow.right", colorHex: "#000")

        manager.switchProfile(to: created.id)

        #expect(manager.activeProfileID == created.id)
    }

    @Test("Switch to non-existent profile is no-op")
    func switchToNonExistentProfileIsNoOp() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let originalActive = manager.activeProfileID

        manager.switchProfile(to: UUID())

        #expect(manager.activeProfileID == originalActive)
    }

    // MARK: - Update

    @Test("Update profile changes stored values")
    func updateProfileChangesValues() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        var created = manager.createProfile(name: "Old Name", icon: "circle", colorHex: "#000")

        created.name = "New Name"
        created.icon = "star.fill"
        manager.updateProfile(created)

        let updated = manager.profiles.first(where: { $0.id == created.id })
        #expect(updated?.name == "New Name")
        #expect(updated?.icon == "star.fill")
    }

    @Test("Update non-existent profile is no-op")
    func updateNonExistentProfileIsNoOp() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let countBefore = manager.profiles.count

        let ghost = BrowserProfile(name: "Ghost")
        manager.updateProfile(ghost)

        #expect(manager.profiles.count == countBefore)
    }

    // MARK: - Active Profile

    @Test("activeProfile returns the currently active profile")
    func activeProfileReturnsCurrentProfile() {
        let store = MockBrowserProfileStore()
        let manager = BrowserProfileManager(store: store)
        let created = manager.createProfile(name: "Active", icon: "circle", colorHex: "#000")
        manager.switchProfile(to: created.id)

        #expect(manager.activeProfile.id == created.id)
        #expect(manager.activeProfile.name == "Active")
    }
}
