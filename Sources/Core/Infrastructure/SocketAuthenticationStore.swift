// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketAuthenticationStore.swift - Session token generation and Keychain storage.

import CocxyShared
import Foundation
import Security

struct SocketAuthenticationRecord: Hashable, Sendable {
    let account: String
    let socketPath: String
}

protocol SocketAuthenticationStoring: AnyObject, Sendable {
    func save(token: String, socketPath: String) throws -> SocketAuthenticationRecord
    func delete(record: SocketAuthenticationRecord) throws
}

enum SocketAuthenticationStoreError: Error, Sendable {
    case randomGenerationFailed(OSStatus)
    case keychainSaveFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
}

extension SocketAuthenticationStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed(let status):
            return "Could not generate the socket authentication token (status \(status))."
        case .keychainSaveFailed(let status):
            return "Could not save the socket authentication token to Keychain (status \(status))."
        case .keychainDeleteFailed(let status):
            return "Could not delete the socket authentication token from Keychain (status \(status))."
        }
    }
}

enum SocketAuthenticationTokenGenerator {
    static func generate() throws -> String {
        var bytes = [UInt8](
            repeating: 0,
            count: SocketAuthenticationCredential.tokenByteCount
        )
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(
                kSecRandomDefault,
                buffer.count,
                buffer.baseAddress!
            )
        }
        guard status == errSecSuccess else {
            throw SocketAuthenticationStoreError.randomGenerationFailed(status)
        }

        let alphabet = Array("0123456789abcdef".utf8)
        var encoded = [UInt8]()
        encoded.reserveCapacity(SocketAuthenticationCredential.encodedTokenLength)
        for byte in bytes {
            encoded.append(alphabet[Int(byte >> 4)])
            encoded.append(alphabet[Int(byte & 0x0F)])
        }
        return String(decoding: encoded, as: UTF8.self)
    }
}

final class KeychainSocketAuthenticationStore: SocketAuthenticationStoring, @unchecked Sendable {
    private let service: String

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "dev.cocxy.terminal.development").socket-authentication"
    ) {
        self.service = service
    }

    func save(token: String, socketPath: String) throws -> SocketAuthenticationRecord {
        let pathQuery = pathQuery(socketPath: socketPath)
        SecItemDelete(pathQuery as CFDictionary)
        SecItemDelete(legacyQuery(socketPath: socketPath) as CFDictionary)

        let account = UUID().uuidString
        var item = pathQuery
        item[kSecAttrAccount as String] = account
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SocketAuthenticationStoreError.keychainSaveFailed(status)
        }
        return SocketAuthenticationRecord(
            account: account,
            socketPath: socketPath
        )
    }

    func delete(record: SocketAuthenticationRecord) throws {
        var query = pathQuery(socketPath: record.socketPath)
        query[kSecAttrAccount as String] = record.account
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SocketAuthenticationStoreError.keychainDeleteFailed(status)
        }
    }

    private func pathQuery(socketPath: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrGeneric as String: Data(socketPath.utf8),
        ]
    }

    private func legacyQuery(socketPath: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: socketPath,
        ]
    }
}
