// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

#if canImport(Security)
import Security
#endif

public enum SignatureKeyStoreError: Error, Equatable, Sendable {
    case privateKeyRequired(String)
    case saveFailed(Int32)
    case loadFailed(Int32)
    case deleteFailed(Int32)
    case listFailed(Int32)
}

protocol SignatureKeyValueStore: AnyObject, Sendable {
    func save(data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
    func listAccounts() throws -> [String]
}

public final class SignatureKeychainStore: @unchecked Sendable {
    private let backend: SignatureKeyValueStore

    public convenience init(service: String = "dev.cocxy.command-signatures") {
        #if canImport(Security)
        self.init(backend: SecuritySignatureKeyValueStore(service: service))
        #else
        self.init(backend: MemorySignatureKeyValueStore())
        #endif
    }

    init(backend: SignatureKeyValueStore) {
        self.backend = backend
    }

    public func save(_ keyPair: SignatureKeyPair) throws {
        guard keyPair.hasPrivateKey else {
            throw SignatureKeyStoreError.privateKeyRequired(keyPair.keyID)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(keyPair)
        try backend.save(data: data, account: keyPair.keyID)
    }

    public func load(keyID: String) throws -> SignatureKeyPair? {
        guard let data = try backend.load(account: keyID) else { return nil }
        return try JSONDecoder().decode(SignatureKeyPair.self, from: data)
    }

    public func delete(keyID: String) throws {
        try backend.delete(account: keyID)
    }

    public func listKeyIDs() throws -> [String] {
        try backend.listAccounts().sorted()
    }
}

final class MemorySignatureKeyValueStore: SignatureKeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func save(data: Data, account: String) throws {
        lock.withLock {
            storage[account] = data
        }
    }

    func load(account: String) throws -> Data? {
        lock.withLock {
            storage[account]
        }
    }

    func delete(account: String) throws {
        _ = lock.withLock {
            storage.removeValue(forKey: account)
        }
    }

    func listAccounts() throws -> [String] {
        lock.withLock {
            Array(storage.keys).sorted()
        }
    }
}

#if canImport(Security)
final class SecuritySignatureKeyValueStore: SignatureKeyValueStore, @unchecked Sendable {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func save(data: Data, account: String) throws {
        var query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SignatureKeyStoreError.saveFailed(status)
        }
    }

    func load(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SignatureKeyStoreError.loadFailed(status)
        }
        return result as? Data
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SignatureKeyStoreError.deleteFailed(status)
        }
    }

    func listAccounts() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw SignatureKeyStoreError.listFailed(status)
        }
        guard let rows = result as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
