// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginCapabilityGrants.swift - Persistent per-plugin sandbox capability grants.

import Foundation

#if canImport(Security)
import Security
#endif

enum PluginCapabilityGrantStoreError: Error, Equatable, Sendable {
    case saveFailed(Int32)
    case loadFailed(Int32)
    case deleteFailed(Int32)
    case listFailed(Int32)
}

struct PluginCapabilityRequest: Equatable, Sendable {
    let pluginID: String
    let capability: PluginCapability
    let reason: String
    let requestedAt: Date

    var sandboxCapabilities: Set<SandboxCapability> {
        capability.sandboxCapabilities
    }

    var auditSubjectID: String {
        "plugin.\(pluginID)"
    }

    var auditOperation: String {
        "request plugin capability \(capability.rawValue)"
    }
}

struct PluginCapabilityGrant: Codable, Equatable, Sendable {
    let pluginID: String
    let capability: PluginCapability
    let reason: String?
    let grantedAt: Date

    var keychainAccount: String {
        Self.keychainAccount(pluginID: pluginID, capability: capability)
    }

    static func keychainAccount(pluginID: String, capability: PluginCapability) -> String {
        "v1:\(capability.rawValue):\(encodeAccountComponent(pluginID))"
    }

    static func decodeKeychainAccount(_ account: String) -> (capability: PluginCapability, pluginID: String)? {
        let parts = account.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "v1",
              let capability = PluginCapability(rawValue: String(parts[1])),
              let pluginID = decodeAccountComponent(String(parts[2]))
        else {
            return nil
        }
        return (capability, pluginID)
    }

    private static func encodeAccountComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func decodeAccountComponent(_ value: String) -> String? {
        value.removingPercentEncoding
    }
}

protocol PluginCapabilityGrantBackingStore: AnyObject, Sendable {
    func save(data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
    func listAccounts() throws -> [String]
}

final class PluginCapabilityGrantStore: @unchecked Sendable {
    private let backend: any PluginCapabilityGrantBackingStore

    convenience init(service: String = "dev.cocxy.plugin-capability-grants") {
        #if canImport(Security)
        self.init(backend: SecurityPluginCapabilityGrantBackingStore(service: service))
        #else
        self.init(backend: MemoryPluginCapabilityGrantBackingStore())
        #endif
    }

    init(backend: any PluginCapabilityGrantBackingStore) {
        self.backend = backend
    }

    func grant(
        _ capability: PluginCapability,
        for pluginID: String,
        reason: String?,
        grantedAt: Date = Date()
    ) throws {
        let grant = PluginCapabilityGrant(
            pluginID: pluginID,
            capability: capability,
            reason: reason,
            grantedAt: grantedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(grant)
        try backend.save(data: data, account: grant.keychainAccount)
    }

    func isGranted(_ capability: PluginCapability, for pluginID: String) throws -> Bool {
        let account = PluginCapabilityGrant.keychainAccount(pluginID: pluginID, capability: capability)
        return try backend.load(account: account) != nil
    }

    func isGrantedWithoutThrowing(_ capability: PluginCapability, for pluginID: String) -> Bool {
        (try? isGranted(capability, for: pluginID)) ?? false
    }

    func revoke(_ capability: PluginCapability, for pluginID: String) throws {
        let account = PluginCapabilityGrant.keychainAccount(pluginID: pluginID, capability: capability)
        try backend.delete(account: account)
    }

    func grants(for pluginID: String) throws -> [PluginCapabilityGrant] {
        try allGrants().filter { $0.pluginID == pluginID }
    }

    func allGrants() throws -> [PluginCapabilityGrant] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var grants: [PluginCapabilityGrant] = []
        for account in try backend.listAccounts() {
            guard PluginCapabilityGrant.decodeKeychainAccount(account) != nil,
                  let data = try backend.load(account: account)
            else {
                continue
            }
            grants.append(try decoder.decode(PluginCapabilityGrant.self, from: data))
        }

        return grants.sorted {
            if $0.pluginID != $1.pluginID {
                return $0.pluginID < $1.pluginID
            }
            return $0.capability.rawValue < $1.capability.rawValue
        }
    }
}

final class MemoryPluginCapabilityGrantBackingStore: PluginCapabilityGrantBackingStore, @unchecked Sendable {
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
final class SecurityPluginCapabilityGrantBackingStore: PluginCapabilityGrantBackingStore, @unchecked Sendable {
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
            throw PluginCapabilityGrantStoreError.saveFailed(status)
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
            throw PluginCapabilityGrantStoreError.loadFailed(status)
        }
        return result as? Data
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PluginCapabilityGrantStoreError.deleteFailed(status)
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
            throw PluginCapabilityGrantStoreError.listFailed(status)
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
