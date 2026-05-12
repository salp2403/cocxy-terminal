// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProviderUsageOAuth.swift - Local OAuth token refresh coordinator
// for optional usage providers.

import Foundation

struct ProviderUsageOAuthToken: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct ProviderUsageOAuthTokenStore: Sendable {
    private let secretStore: any AgentSecretStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(secretStore: any AgentSecretStoring = KeychainAgentSecretStore()) {
        self.secretStore = secretStore
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ token: ProviderUsageOAuthToken, for provider: RateLimitSnapshot.AgentKind) throws {
        let data = try encoder.encode(token)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw AgentSecretError.dataConversionFailed
        }
        try secretStore.saveSecret(payload, account: account(for: provider))
    }

    func token(for provider: RateLimitSnapshot.AgentKind) throws -> ProviderUsageOAuthToken? {
        guard let payload = try secretStore.secret(account: account(for: provider)) else {
            return nil
        }
        guard let data = payload.data(using: .utf8) else {
            throw AgentSecretError.dataConversionFailed
        }
        return try decoder.decode(ProviderUsageOAuthToken.self, from: data)
    }

    func deleteToken(for provider: RateLimitSnapshot.AgentKind) throws {
        try secretStore.deleteSecret(account: account(for: provider))
    }

    private func account(for provider: RateLimitSnapshot.AgentKind) -> String {
        "rate-limit.oauth.\(provider.rawValue)"
    }
}

struct ProviderUsageOAuth: Sendable {
    typealias RefreshHandler = @Sendable (
        RateLimitSnapshot.AgentKind,
        ProviderUsageOAuthToken
    ) async throws -> ProviderUsageOAuthToken?

    private let tokenStore: ProviderUsageOAuthTokenStore
    private let now: @Sendable () -> Date
    private let refreshThreshold: TimeInterval
    private let refreshHandler: RefreshHandler

    init(
        tokenStore: ProviderUsageOAuthTokenStore = ProviderUsageOAuthTokenStore(),
        now: @escaping @Sendable () -> Date = { Date() },
        refreshThreshold: TimeInterval = 10 * 60,
        refreshHandler: @escaping RefreshHandler = { _, _ in nil }
    ) {
        self.tokenStore = tokenStore
        self.now = now
        self.refreshThreshold = refreshThreshold
        self.refreshHandler = refreshHandler
    }

    func refreshIfNeeded(
        for provider: RateLimitSnapshot.AgentKind
    ) async throws -> ProviderUsageOAuthToken? {
        guard let token = try tokenStore.token(for: provider) else {
            return nil
        }
        guard token.expiresAt.timeIntervalSince(now()) <= refreshThreshold else {
            return token
        }
        guard let refreshed = try await refreshHandler(provider, token) else {
            return token
        }
        try tokenStore.save(refreshed, for: provider)
        return refreshed
    }
}
