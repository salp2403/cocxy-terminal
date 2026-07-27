// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserWebsiteDataStoreFactorySwiftTestingTests.swift - WebKit route isolation tests.

import Foundation
import Testing
import WebKit
@testable import CocxyTerminal

@Suite("Browser website data store factory")
struct BrowserWebsiteDataStoreFactorySwiftTestingTests {
    @Test("Remote capability creates an isolated authenticated fail-closed store")
    @MainActor func remoteCapabilityIsIsolated() async throws {
        let ownerWindowID = WindowID()
        let profileID = UUID()
        let capability = RemoteBrowserProxyCapability(
            id: UUID(),
            ownerWindowID: ownerWindowID,
            profileID: profileID,
            remotePort: 3_000,
            localProxyPort: 53_000,
            credentials: ProxyCredentials(password: "route-secret"),
            expiresAt: Date().addingTimeInterval(60)
        )
        try await BrowserWebsiteDataStoreFactory.prepareRemoteNetworkIsolation(for: capability)

        let first = BrowserWebsiteDataStoreFactory.make(
            profileID: UUID(),
            remoteCapability: capability
        )
        let second = BrowserWebsiteDataStoreFactory.make(
            profileID: UUID(),
            remoteCapability: capability
        )

        #expect(first === second)
        #expect(!first.isPersistent)
        let configuration = try #require(first.proxyConfigurations.first)
        #expect(first.proxyConfigurations.count == 1)
        #expect(!configuration.allowFailover)
        #expect(configuration.matchDomains == [""])
        let webViewConfiguration = WKWebViewConfiguration()
        #expect(BrowserWebsiteDataStoreFactory.installRemoteNetworkIsolation(
            on: webViewConfiguration,
            capability: capability
        ))

        let renewedCapability = RemoteBrowserProxyCapability(
            id: UUID(),
            ownerWindowID: ownerWindowID,
            profileID: profileID,
            remotePort: 3_000,
            localProxyPort: 53_001,
            credentials: ProxyCredentials(password: "renewed-route-secret"),
            expiresAt: Date().addingTimeInterval(120)
        )
        let renewed = BrowserWebsiteDataStoreFactory.make(
            profileID: UUID(),
            remoteCapability: renewedCapability
        )
        #expect(renewed === first)

        BrowserWebsiteDataStoreFactory.releaseRemoteDataStore(for: capability)
        let reopened = BrowserWebsiteDataStoreFactory.make(
            profileID: UUID(),
            remoteCapability: capability
        )
        #expect(reopened !== first)
        BrowserWebsiteDataStoreFactory.releaseRemoteDataStore(for: capability)
    }

    @Test("Local browser without a profile keeps the shared default store")
    @MainActor func localBrowserUsesDefaultStore() {
        let store = BrowserWebsiteDataStoreFactory.make(
            profileID: nil,
            remoteCapability: nil
        )

        #expect(store === WKWebsiteDataStore.default())
    }
}
