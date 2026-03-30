// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayKeychainStore.swift - Secure token persistence in macOS Keychain.

import Foundation
import Security

// MARK: - Relay Token Storing Protocol

/// Abstraction for relay token persistence.
///
/// Production implementation uses the macOS Keychain via `Security` framework.
/// Test implementation uses an in-memory dictionary.
protocol RelayTokenStoring: Sendable {
    func save(token: RelayToken, channelID: UUID) throws
    func load(channelID: UUID) throws -> RelayToken?
    func delete(channelID: UUID) throws
}

// MARK: - Keychain Errors

enum KeychainError: Error, Equatable {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
}

// MARK: - Relay Keychain Store

/// Production implementation that stores tokens in the macOS Keychain.
///
/// Uses `kSecClassGenericPassword` with:
/// - `kSecAttrService`: "com.cocxy.relay"
/// - `kSecAttrAccount`: channel UUID string
/// - `kSecValueData`: token secret bytes
final class RelayKeychainStore: RelayTokenStoring {

    private let service = "com.cocxy.relay"

    func save(token: RelayToken, channelID: UUID) throws {
        // Delete existing entry first (idempotent).
        try? delete(channelID: channelID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID.uuidString,
            kSecValueData as String: token.secret,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func load(channelID: UUID) throws -> RelayToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { return nil }

        guard let data = result as? Data else {
            throw KeychainError.dataConversionFailed
        }

        return RelayToken(secret: data)
    }

    func delete(channelID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID.uuidString,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - In-Memory Token Store (Testing)

/// Test double that stores tokens in memory.
final class InMemoryTokenStore: RelayTokenStoring, @unchecked Sendable {

    private var storage: [UUID: Data] = [:]

    func save(token: RelayToken, channelID: UUID) throws {
        storage[channelID] = token.secret
    }

    func load(channelID: UUID) throws -> RelayToken? {
        guard let data = storage[channelID] else { return nil }
        return RelayToken(secret: data)
    }

    func delete(channelID: UUID) throws {
        storage.removeValue(forKey: channelID)
    }
}
