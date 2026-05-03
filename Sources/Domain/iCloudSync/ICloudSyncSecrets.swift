// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncSecrets.swift - Keychain-backed local secret storage for iCloud Sync.

import Foundation
import Security

protocol ICloudSyncSecretStoring: Sendable {
    func saveSecret(_ secret: String, account: String) throws
    func secret(account: String) throws -> String?
    func deleteSecret(account: String) throws
}

enum ICloudSyncSecretError: Error, Sendable, Equatable {
    case emptyMasterPassword
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
}

extension ICloudSyncSecretError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyMasterPassword:
            return "Master password cannot be empty."
        case .saveFailed(let status):
            return "Could not save iCloud Sync master password to Keychain (status \(status))."
        case .loadFailed(let status):
            return "Could not read iCloud Sync master password from Keychain (status \(status))."
        case .deleteFailed(let status):
            return "Could not delete iCloud Sync master password from Keychain (status \(status))."
        case .dataConversionFailed:
            return "Saved iCloud Sync master password could not be decoded."
        }
    }
}

struct ICloudSyncSecrets: Sendable {
    private static let masterPasswordAccount = "master-password"

    private let store: any ICloudSyncSecretStoring

    init(store: any ICloudSyncSecretStoring = KeychainICloudSyncSecretStore()) {
        self.store = store
    }

    func saveMasterPassword(_ password: String) throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ICloudSyncSecretError.emptyMasterPassword
        }
        try store.saveSecret(trimmed, account: Self.masterPasswordAccount)
    }

    func masterPassword() throws -> String? {
        try store.secret(account: Self.masterPasswordAccount)
    }

    func hasMasterPassword() throws -> Bool {
        try masterPassword() != nil
    }

    func deleteMasterPassword() throws {
        try store.deleteSecret(account: Self.masterPasswordAccount)
    }
}

final class KeychainICloudSyncSecretStore: ICloudSyncSecretStoring {
    static let service = "com.cocxy.icloud-sync"

    func saveSecret(_ secret: String, account: String) throws {
        try? deleteSecret(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ICloudSyncSecretError.saveFailed(status)
        }
    }

    func secret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ICloudSyncSecretError.loadFailed(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw ICloudSyncSecretError.dataConversionFailed
        }

        return value
    }

    func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ICloudSyncSecretError.deleteFailed(status)
        }
    }
}

final class InMemoryICloudSyncSecretStore: ICloudSyncSecretStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func saveSecret(_ secret: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[account] = secret
    }

    func secret(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    func deleteSecret(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: account)
    }
}
