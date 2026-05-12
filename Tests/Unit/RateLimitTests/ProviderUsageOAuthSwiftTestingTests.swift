// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ProviderUsageOAuth")
struct ProviderUsageOAuthSwiftTestingTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("token store round-trips OAuth tokens through the injected secret store")
    func tokenStoreRoundTripsTokens() throws {
        let secrets = InMemoryAgentSecretStore()
        let store = ProviderUsageOAuthTokenStore(secretStore: secrets)
        let token = ProviderUsageOAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(600)
        )

        try store.save(token, for: .cursor)

        #expect(try store.token(for: .cursor) == token)
        #expect(try store.token(for: .copilot) == nil)
    }

    @Test("refresh is skipped when no token is stored")
    func refreshSkipsMissingToken() async throws {
        let oauth = ProviderUsageOAuth(
            tokenStore: ProviderUsageOAuthTokenStore(secretStore: InMemoryAgentSecretStore()),
            now: { now },
            refreshHandler: { _, _ in
                Issue.record("refresh handler should not run without a stored token")
                return nil
            }
        )

        let token = try await oauth.refreshIfNeeded(for: .cursor)

        #expect(token == nil)
    }

    @Test("refresh is skipped when the token is not near expiry")
    func refreshSkipsFreshToken() async throws {
        let store = ProviderUsageOAuthTokenStore(secretStore: InMemoryAgentSecretStore())
        let token = ProviderUsageOAuthToken(
            accessToken: "fresh",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(60 * 60)
        )
        try store.save(token, for: .cursor)
        let oauth = ProviderUsageOAuth(
            tokenStore: store,
            now: { now },
            refreshThreshold: 600,
            refreshHandler: { _, _ in
                Issue.record("fresh token must not be refreshed")
                return nil
            }
        )

        let resolved = try await oauth.refreshIfNeeded(for: .cursor)

        #expect(resolved == token)
    }

    @Test("near-expiry token refreshes and persists the replacement")
    func refreshesNearExpiryToken() async throws {
        let store = ProviderUsageOAuthTokenStore(secretStore: InMemoryAgentSecretStore())
        let old = ProviderUsageOAuthToken(
            accessToken: "old",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(120)
        )
        let refreshed = ProviderUsageOAuthToken(
            accessToken: "new",
            refreshToken: "refresh-new",
            expiresAt: now.addingTimeInterval(60 * 60)
        )
        try store.save(old, for: .copilot)
        let oauth = ProviderUsageOAuth(
            tokenStore: store,
            now: { now },
            refreshThreshold: 600,
            refreshHandler: { provider, token in
                #expect(provider == .copilot)
                #expect(token == old)
                return refreshed
            }
        )

        let resolved = try await oauth.refreshIfNeeded(for: .copilot)

        #expect(resolved == refreshed)
        #expect(try store.token(for: .copilot) == refreshed)
    }
}
