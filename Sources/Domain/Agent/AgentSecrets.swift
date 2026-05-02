// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSecrets.swift - Provider API key storage for built-in Agent Mode.

import Foundation
import Security

extension AgentProviderKind {
    var requiresAPIKey: Bool {
        switch self {
        case .foundationModelsOnDevice:
            return false
        case .anthropic, .openai, .google:
            return true
        }
    }

    var keychainAccount: String {
        rawValue
    }
}

protocol AgentSecretStoring: Sendable {
    func saveAPIKey(_ apiKey: String, for provider: AgentProviderKind) throws
    func apiKey(for provider: AgentProviderKind) throws -> String?
    func deleteAPIKey(for provider: AgentProviderKind) throws
}

enum AgentSecretError: Error, Sendable, Equatable {
    case emptyAPIKey
    case providerDoesNotUseAPIKey(AgentProviderKind)
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
}

extension AgentSecretError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "API key cannot be empty."
        case .providerDoesNotUseAPIKey(let provider):
            return "\(provider.displayName) does not use an API key."
        case .saveFailed(let status):
            return "Could not save API key to Keychain (status \(status))."
        case .loadFailed(let status):
            return "Could not read API key from Keychain (status \(status))."
        case .deleteFailed(let status):
            return "Could not delete API key from Keychain (status \(status))."
        case .dataConversionFailed:
            return "Saved API key could not be decoded."
        }
    }
}

private extension AgentProviderKind {
    var displayName: String {
        switch self {
        case .foundationModelsOnDevice:
            return "Foundation Models"
        case .anthropic:
            return "Anthropic"
        case .openai:
            return "OpenAI"
        case .google:
            return "Google"
        }
    }
}

/// Validating facade for Agent provider secrets.
struct AgentSecrets: Sendable {
    private let store: any AgentSecretStoring

    init(store: any AgentSecretStoring = KeychainAgentSecretStore()) {
        self.store = store
    }

    func saveAPIKey(_ apiKey: String, for provider: AgentProviderKind) throws {
        guard provider.requiresAPIKey else {
            throw AgentSecretError.providerDoesNotUseAPIKey(provider)
        }

        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentSecretError.emptyAPIKey
        }

        try store.saveAPIKey(trimmed, for: provider)
    }

    func apiKey(for provider: AgentProviderKind) throws -> String? {
        guard provider.requiresAPIKey else { return nil }
        return try store.apiKey(for: provider)
    }

    func hasAPIKey(for provider: AgentProviderKind) throws -> Bool {
        try apiKey(for: provider) != nil
    }

    func deleteAPIKey(for provider: AgentProviderKind) throws {
        guard provider.requiresAPIKey else { return }
        try store.deleteAPIKey(for: provider)
    }
}

/// Production implementation backed by the macOS Keychain.
final class KeychainAgentSecretStore: AgentSecretStoring {
    static let service = "com.cocxy.agent"

    func saveAPIKey(_ apiKey: String, for provider: AgentProviderKind) throws {
        try? deleteAPIKey(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AgentSecretError.saveFailed(status)
        }
    }

    func apiKey(for provider: AgentProviderKind) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AgentSecretError.loadFailed(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw AgentSecretError.dataConversionFailed
        }

        return value
    }

    func deleteAPIKey(for provider: AgentProviderKind) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AgentSecretError.deleteFailed(status)
        }
    }
}

/// Test double that stores API keys in memory.
final class InMemoryAgentSecretStore: AgentSecretStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func saveAPIKey(_ apiKey: String, for provider: AgentProviderKind) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[provider.keychainAccount] = apiKey
    }

    func apiKey(for provider: AgentProviderKind) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[provider.keychainAccount]
    }

    func deleteAPIKey(for provider: AgentProviderKind) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: provider.keychainAccount)
    }
}
