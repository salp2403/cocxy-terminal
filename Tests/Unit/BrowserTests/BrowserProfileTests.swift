// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserProfileTests.swift - Tests for browser profile model.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Browser Profile Tests

@Suite("BrowserProfile model")
struct BrowserProfileTests {

    // MARK: - Initialization

    @Test("Default initialization sets expected values")
    func defaultInitialization() {
        let profile = BrowserProfile(name: "Work")

        #expect(profile.name == "Work")
        #expect(profile.icon == "person.circle")
        #expect(profile.colorHex == "#FFFFFF")
        #expect(profile.isDefault == false)
        #expect(!profile.id.uuidString.isEmpty)
    }

    @Test("Custom initialization preserves all parameters")
    func customInitialization() {
        let fixedID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let profile = BrowserProfile(
            id: fixedID,
            name: "Personal",
            icon: "star.fill",
            colorHex: "#FF5733",
            isDefault: true,
            createdAt: fixedDate
        )

        #expect(profile.id == fixedID)
        #expect(profile.name == "Personal")
        #expect(profile.icon == "star.fill")
        #expect(profile.colorHex == "#FF5733")
        #expect(profile.isDefault == true)
        #expect(profile.createdAt == fixedDate)
    }

    // MARK: - Data Store Path

    @Test("Data store path contains the profile UUID")
    func dataStorePathContainsUUID() {
        let profile = BrowserProfile(name: "Test")

        #expect(profile.dataStorePath.contains(profile.id.uuidString))
    }

    @Test("Data store path is under the profiles base directory")
    func dataStorePathUnderBaseDirectory() {
        let profile = BrowserProfile(name: "Test")

        #expect(profile.dataStorePath.hasPrefix(BrowserProfile.profilesBaseDirectory))
    }

    @Test("Different profiles have different data store paths")
    func uniqueDataStorePaths() {
        let profileA = BrowserProfile(name: "A")
        let profileB = BrowserProfile(name: "B")

        #expect(profileA.dataStorePath != profileB.dataStorePath)
    }

    // MARK: - Codable Roundtrip

    @Test("Profile survives JSON encode-decode roundtrip")
    func codableRoundtrip() throws {
        let original = BrowserProfile(
            name: "Roundtrip",
            icon: "globe",
            colorHex: "#00FF00",
            isDefault: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BrowserProfile.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Equality

    @Test("Profiles with same ID and properties are equal")
    func equalProfiles() {
        let fixedID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let profileA = BrowserProfile(
            id: fixedID, name: "Same", icon: "star", colorHex: "#000",
            isDefault: false, createdAt: fixedDate
        )
        let profileB = BrowserProfile(
            id: fixedID, name: "Same", icon: "star", colorHex: "#000",
            isDefault: false, createdAt: fixedDate
        )

        #expect(profileA == profileB)
    }

    @Test("Profiles with different IDs are not equal")
    func differentProfiles() {
        let profileA = BrowserProfile(name: "A")
        let profileB = BrowserProfile(name: "A")

        #expect(profileA != profileB)
    }

    // MARK: - Default Profile Behavior

    @Test("isDefault defaults to false")
    func isDefaultFalseByDefault() {
        let profile = BrowserProfile(name: "Non-default")

        #expect(profile.isDefault == false)
    }

    @Test("isDefault can be set to true on creation")
    func isDefaultCanBeTrue() {
        let profile = BrowserProfile(name: "Main", isDefault: true)

        #expect(profile.isDefault == true)
    }
}
