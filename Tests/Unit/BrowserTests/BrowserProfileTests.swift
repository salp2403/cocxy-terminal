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
        let remote = RemoteBrowserProfile(
            connectionProfileID: UUID(),
            name: "Dev",
            host: "dev.internal",
            user: "said",
            sshPort: 2222,
            localForwardedPorts: [3000: 49152],
            socksPort: 1080,
            httpConnectPort: 18080,
            proxyHealth: .active,
            createdAt: fixedDate
        )

        let profile = BrowserProfile(
            id: fixedID,
            name: "Personal",
            icon: "star.fill",
            colorHex: "#FF5733",
            isDefault: true,
            createdAt: fixedDate,
            remoteProfile: remote
        )

        #expect(profile.id == fixedID)
        #expect(profile.name == "Personal")
        #expect(profile.icon == "star.fill")
        #expect(profile.colorHex == "#FF5733")
        #expect(profile.isDefault == true)
        #expect(profile.createdAt == fixedDate)
        #expect(profile.remoteProfile == remote)
        #expect(profile.isRemoteBacked == true)
        #expect(profile.contextLabel == "Dev (said@dev.internal:2222)")
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
            isDefault: true,
            remoteProfile: RemoteBrowserProfile(
                connectionProfileID: UUID(),
                name: "Remote Roundtrip",
                host: "remote.example",
                localForwardedPorts: [5173: 55173],
                proxyHealth: .degraded
            )
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BrowserProfile.self, from: data)

        #expect(decoded == original)
    }

    @Test("Profile decodes older JSON without remote profile as local")
    func backwardCompatibleLocalDecode() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Old",
          "icon": "person.circle",
          "colorHex": "#FFFFFF",
          "isDefault": true,
          "createdAt": \(createdAt.timeIntervalSince1970)
        }
        """

        let decoded = try JSONDecoder().decode(BrowserProfile.self, from: Data(json.utf8))

        #expect(decoded.id == id)
        #expect(decoded.name == "Old")
        #expect(decoded.remoteProfile == nil)
        #expect(decoded.isRemoteBacked == false)
        #expect(decoded.contextLabel == "Local")
    }

    @Test("Remote browser profile derives display and local forwarded URL without starting proxy")
    func remoteProfileDisplayAndForwardedURL() throws {
        let remoteConnection = RemoteConnectionProfile(
            id: UUID(),
            name: "Lab",
            host: "lab.internal",
            user: "dev",
            port: 2200
        )
        let profile = RemoteBrowserProfile(
            remoteConnectionProfile: remoteConnection,
            localForwardedPorts: [3000: 53000],
            socksPort: 1080,
            httpConnectPort: 18080,
            proxyHealth: .active
        )

        #expect(profile.connectionProfileID == remoteConnection.id)
        #expect(profile.displayTitle == "Lab (dev@lab.internal:2200)")
        #expect(profile.routingSummary.contains("health=active"))
        #expect(profile.routingSummary.contains("socks=127.0.0.1:1080"))
        #expect(profile.routingSummary.contains("http-connect=127.0.0.1:18080"))
        #expect(profile.routingSummary.contains("forwards=3000->53000"))
        #expect(profile.localURL(forRemotePort: 3000, path: "dashboard")?.absoluteString == "http://127.0.0.1:53000/dashboard")
        #expect(profile.localURL(forRemotePort: 5173) == nil)
    }

    @Test("Remote browser profile derives proxy ports and route from proxy state")
    func remoteProfileDerivesProxyStateAndRoute() throws {
        let remoteConnection = RemoteConnectionProfile(
            id: UUID(),
            name: "Stage",
            host: "stage.internal",
            user: "deploy",
            port: 22
        )

        let active = RemoteBrowserProfile(
            remoteConnectionProfile: remoteConnection,
            localForwardedPorts: [5173: 55173],
            proxyState: .active(socksPort: 1081, httpPort: 18888)
        )
        let route = try #require(active.route(forRemotePort: 5173, path: "/app"))

        #expect(active.proxyHealth == .active)
        #expect(active.socksPort == 1081)
        #expect(active.httpConnectPort == 18888)
        #expect(route.remoteAddress == "stage.internal:5173")
        #expect(route.localURL.absoluteString == "http://127.0.0.1:55173/app")

        let failing = RemoteBrowserProfile(
            remoteConnectionProfile: remoteConnection,
            proxyState: .failing(reason: "probe failed")
        )
        #expect(failing.proxyHealth == .failed)
        #expect(failing.proxyHealth.needsAttention == true)
        #expect(failing.socksPort == nil)
        #expect(failing.httpConnectPort == nil)
    }

    @Test("Remote browser profile applies proxy state updates without losing forwards")
    func remoteProfileAppliesProxyStateUpdates() throws {
        let remoteConnection = RemoteConnectionProfile(
            id: UUID(),
            name: "Stage",
            host: "stage.internal"
        )
        var profile = RemoteBrowserProfile(
            remoteConnectionProfile: remoteConnection,
            localForwardedPorts: [3000: 53000],
            proxyState: .active(socksPort: 1080, httpPort: nil)
        )

        profile.apply(proxyState: .failing(reason: "probe failed"))

        #expect(profile.localForwardedPorts == [3000: 53000])
        #expect(profile.proxyHealth == .failed)
        #expect(profile.socksPort == nil)
        #expect(profile.httpConnectPort == nil)

        let restored = profile.applying(proxyState: .active(socksPort: 1081, httpPort: 18888))

        #expect(restored.localForwardedPorts == [3000: 53000])
        #expect(restored.proxyHealth == .active)
        #expect(restored.socksPort == 1081)
        #expect(restored.httpConnectPort == 18888)
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
