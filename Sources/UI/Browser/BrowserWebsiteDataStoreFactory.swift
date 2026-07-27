// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserWebsiteDataStoreFactory.swift - Isolated WebKit routing configuration.

import Foundation
import Network
import WebKit

@MainActor
enum BrowserWebsiteDataStoreFactory {
    private struct RemoteDataStoreKey: Hashable {
        let ownerWindowID: WindowID
        let profileID: UUID
        let remotePort: Int
    }

    private static var remoteNetworkRuleLists: [String: WKContentRuleList] = [:]
    private static var remoteDataStores: [RemoteDataStoreKey: WKWebsiteDataStore] = [:]

    static func prepareRemoteNetworkIsolation(
        for capability: RemoteBrowserProxyCapability
    ) async throws {
        let browserHost = capability.browserHost
        if remoteNetworkRuleLists[browserHost] != nil { return }

        let escapedHost = NSRegularExpression.escapedPattern(for: browserHost)
        let rules: [[String: Any]] = ["^https?://", "^wss?://"].flatMap { filter in
            [
                [
                    "trigger": ["url-filter": filter],
                    "action": ["type": "block"],
                ],
                [
                    "trigger": [
                        "url-filter": "\(filter)\(escapedHost)[/:]",
                    ],
                    "action": ["type": "ignore-previous-rules"],
                ],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: rules)
        guard let encodedRules = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let identifier = "cocxy.remote-browser.\(capability.ownerWindowID.rawValue.uuidString)"
        let ruleList = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<WKContentRuleList, any Error>) in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedRules
            ) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.coderInvalidValue))
                }
            }
        }
        try Task.checkCancellation()
        remoteNetworkRuleLists[browserHost] = ruleList
    }

    /// Installs the precompiled allowlist before a remote URL can be loaded.
    /// Returning false is fail-closed: callers must leave the WebView blank.
    static func installRemoteNetworkIsolation(
        on configuration: WKWebViewConfiguration,
        capability: RemoteBrowserProxyCapability?
    ) -> Bool {
        guard let capability else { return true }
        guard let ruleList = remoteNetworkRuleLists[capability.browserHost] else {
            return false
        }
        configuration.userContentController.add(ruleList)
        return true
    }

    static func releaseRemoteDataStore(for capability: RemoteBrowserProxyCapability) {
        remoteDataStores[remoteDataStoreKey(for: capability)] = nil
    }

    static func sharesRemoteDataStoreScope(
        _ lhs: RemoteBrowserProxyCapability,
        _ rhs: RemoteBrowserProxyCapability
    ) -> Bool {
        remoteDataStoreKey(for: lhs) == remoteDataStoreKey(for: rhs)
    }

    static func make(
        profileID: UUID?,
        remoteCapability: RemoteBrowserProxyCapability?
    ) -> WKWebsiteDataStore {
        guard let remoteCapability else {
            if let profileID {
                return WKWebsiteDataStore(forIdentifier: profileID)
            }
            return .default()
        }

        precondition((1...65_535).contains(remoteCapability.localProxyPort))
        let rawPort = UInt16(remoteCapability.localProxyPort)
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: rawPort)!
        )
        var proxy = Network.ProxyConfiguration(socksv5Proxy: endpoint)
        proxy.applyCredential(
            username: ProxyCredentials.username,
            password: remoteCapability.credentials.password
        )
        proxy.allowFailover = false
        // The empty suffix routes every eligible request through the broker.
        // A content rule blocks every network origin except the capability
        // alias, while the broker enforces its exact host and port.
        proxy.matchDomains = [""]

        // Reuse only within this exact window/profile/service scope so a
        // credential rotation preserves cookies without crossing routes.
        let key = remoteDataStoreKey(for: remoteCapability)
        let dataStore = remoteDataStores[key] ?? WKWebsiteDataStore.nonPersistent()
        dataStore.proxyConfigurations = [proxy]
        remoteDataStores[key] = dataStore
        return dataStore
    }

    private static func remoteDataStoreKey(
        for capability: RemoteBrowserProxyCapability
    ) -> RemoteDataStoreKey {
        RemoteDataStoreKey(
            ownerWindowID: capability.ownerWindowID,
            profileID: capability.profileID,
            remotePort: capability.remotePort
        )
    }
}
