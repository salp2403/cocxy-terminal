// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellSecretsStore.swift - Keychain-backed secret storage for Cocxy Cells.

import Foundation

#if canImport(Security)
import Security
#endif

enum CellSecretsStoreError: Error, Equatable, Sendable {
    case saveFailed(Int32)
    case loadFailed(Int32)
    case deleteFailed(Int32)
    case listFailed(Int32)
    case invalidAccountName(String)
}

struct CellSecretRef: Codable, Equatable, Hashable, Sendable {
    let provider: CellProviderKind
    let account: String
    let key: String

    var storageAccount: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return "cells:\(data.base64URLEncodedString())"
    }

    static func decode(storageAccount: String) throws -> CellSecretRef {
        guard storageAccount.hasPrefix("cells:") else {
            throw CellSecretsStoreError.invalidAccountName(storageAccount)
        }
        let encoded = String(storageAccount.dropFirst("cells:".count))
        let data = try Data(base64URLEncoded: encoded)
        return try JSONDecoder().decode(CellSecretRef.self, from: data)
    }
}

protocol CellSecretKeyValueStore: AnyObject, Sendable {
    func save(data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
    func listAccounts() throws -> [String]
}

final class CellSecretsStore: @unchecked Sendable {
    private let backend: CellSecretKeyValueStore

    convenience init(service: String = "dev.cocxy.cells.secrets") {
        #if canImport(Security)
        self.init(backend: SecurityCellSecretKeyValueStore(service: service))
        #else
        self.init(backend: MemoryCellSecretKeyValueStore())
        #endif
    }

    init(backend: CellSecretKeyValueStore) {
        self.backend = backend
    }

    func save(_ data: Data, for ref: CellSecretRef) throws {
        try backend.save(data: data, account: ref.storageAccount)
    }

    func load(_ ref: CellSecretRef) throws -> Data? {
        try backend.load(account: ref.storageAccount)
    }

    func delete(_ ref: CellSecretRef) throws {
        try backend.delete(account: ref.storageAccount)
    }

    func refs(for provider: CellProviderKind) throws -> [CellSecretRef] {
        try backend.listAccounts()
            .compactMap { try? CellSecretRef.decode(storageAccount: $0) }
            .filter { $0.provider == provider }
            .sorted { lhs, rhs in
                if lhs.account != rhs.account { return lhs.account < rhs.account }
                return lhs.key < rhs.key
            }
    }
}

final class MemoryCellSecretKeyValueStore: CellSecretKeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    var savedAccounts: [String] {
        lock.withLock { Array(storage.keys).sorted() }
    }

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
        savedAccounts
    }
}

#if canImport(Security)
final class SecurityCellSecretKeyValueStore: CellSecretKeyValueStore, @unchecked Sendable {
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
            throw CellSecretsStoreError.saveFailed(status)
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
            throw CellSecretsStoreError.loadFailed(status)
        }
        return result as? Data
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CellSecretsStoreError.deleteFailed(status)
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
            throw CellSecretsStoreError.listFailed(status)
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

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init(base64URLEncoded value: String) throws {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            throw CellSecretsStoreError.invalidAccountName(value)
        }
        self = data
    }
}
