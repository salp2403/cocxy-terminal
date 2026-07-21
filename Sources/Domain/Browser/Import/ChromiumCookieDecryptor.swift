// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ChromiumCookieDecryptor.swift - macOS Keychain-backed Chromium cookie decryption.

import CommonCrypto
import CryptoKit
import Foundation
import Security

protocol BrowserSafeStoragePasswordProviding: Sendable {
    func password(for source: BrowserImportSource) throws -> Data
}

protocol ChromiumCookieDecrypting: Sendable {
    func decrypt(
        _ encryptedValue: Data,
        domain: String,
        source: BrowserImportSource,
        databaseVersion: Int?
    ) throws -> String
}

enum ChromiumCookieDecryptionError: LocalizedError, Equatable {
    case unsupportedSource
    case keychainItemUnavailable
    case keychainAccessFailed(OSStatus)
    case invalidCiphertext
    case keyDerivationFailed
    case decryptionFailed
    case domainBindingMismatch
    case invalidValueEncoding

    var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "Cookie decryption is unavailable for this browser"
        case .keychainItemUnavailable:
            return "The browser Safe Storage key is unavailable"
        case .keychainAccessFailed(let status):
            return "The browser Safe Storage key could not be read (Keychain status \(status))"
        case .invalidCiphertext:
            return "The encrypted cookie format is invalid"
        case .keyDerivationFailed:
            return "The browser cookie key could not be derived"
        case .decryptionFailed:
            return "The encrypted cookie could not be decrypted"
        case .domainBindingMismatch:
            return "The encrypted cookie does not match its stored domain"
        case .invalidValueEncoding:
            return "The decrypted cookie value is not valid UTF-8"
        }
    }
}

struct KeychainBrowserSafeStoragePasswordProvider: BrowserSafeStoragePasswordProviding {
    private struct Candidate {
        let service: String
        let account: String
    }

    func password(for source: BrowserImportSource) throws -> Data {
        let candidates = keychainCandidates(for: source)
        guard !candidates.isEmpty else {
            throw ChromiumCookieDecryptionError.unsupportedSource
        }

        var lastStatus: OSStatus = errSecItemNotFound
        for candidate in candidates {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: candidate.service,
                kSecAttrAccount as String: candidate.account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data, !data.isEmpty {
                return data
            }
            if status == errSecSuccess {
                throw ChromiumCookieDecryptionError.keychainAccessFailed(errSecDecode)
            }
            guard status == errSecItemNotFound else {
                throw ChromiumCookieDecryptionError.keychainAccessFailed(status)
            }
            lastStatus = status
        }

        if lastStatus == errSecItemNotFound {
            throw ChromiumCookieDecryptionError.keychainItemUnavailable
        }
        throw ChromiumCookieDecryptionError.keychainAccessFailed(lastStatus)
    }

    private func keychainCandidates(for source: BrowserImportSource) -> [Candidate] {
        switch source {
        case .chrome:
            return [Candidate(service: "Chrome Safe Storage", account: "Chrome")]
        case .chromeCanary:
            return [
                Candidate(service: "Chrome Canary Safe Storage", account: "Chrome Canary"),
                Candidate(service: "Chrome Safe Storage", account: "Chrome"),
            ]
        case .chromium:
            return [Candidate(service: "Chromium Safe Storage", account: "Chromium")]
        case .edge, .edgeBeta, .edgeDev:
            return [Candidate(service: "Microsoft Edge Safe Storage", account: "Microsoft Edge")]
        case .brave, .braveBeta, .braveNightly:
            return [Candidate(service: "Brave Safe Storage", account: "Brave")]
        case .opera, .operaGX:
            return [Candidate(service: "Opera Safe Storage", account: "Opera")]
        case .vivaldi, .vivaldiSnapshot:
            return [Candidate(service: "Vivaldi Safe Storage", account: "Vivaldi")]
        case .arc, .arcBeta:
            return [Candidate(service: "Arc Safe Storage", account: "Arc")]
        case .firefox, .firefoxDeveloperEdition, .firefoxNightly,
             .librewolf, .waterfox, .floorp, .zen, .safari, .orion:
            return []
        }
    }
}

final class ChromiumCookieDecryptor: ChromiumCookieDecrypting, @unchecked Sendable {
    private enum CachedKey {
        case available(Data)
        case unavailable(String)
    }

    private let passwordProvider: any BrowserSafeStoragePasswordProviding
    private let lock = NSLock()
    private var keys: [BrowserImportSource: CachedKey] = [:]

    init(passwordProvider: any BrowserSafeStoragePasswordProviding = KeychainBrowserSafeStoragePasswordProvider()) {
        self.passwordProvider = passwordProvider
    }

    func decrypt(
        _ encryptedValue: Data,
        domain: String,
        source: BrowserImportSource,
        databaseVersion: Int?
    ) throws -> String {
        guard encryptedValue.count > 3 else {
            throw ChromiumCookieDecryptionError.invalidCiphertext
        }
        let prefix = String(data: encryptedValue.prefix(3), encoding: .ascii)
        guard prefix == "v10" || prefix == "v11" else {
            throw ChromiumCookieDecryptionError.invalidCiphertext
        }

        let key = try encryptionKey(for: source)
        let plaintext = try decryptAES128CBC(encryptedValue.dropFirst(3), key: key)
        let valueData = try removeDomainBindingIfNeeded(
            from: plaintext,
            domain: domain,
            databaseVersion: databaseVersion
        )
        guard let value = String(data: valueData, encoding: .utf8) else {
            throw ChromiumCookieDecryptionError.invalidValueEncoding
        }
        return value
    }

    private func encryptionKey(for source: BrowserImportSource) throws -> Data {
        lock.lock()
        if let cached = keys[source] {
            lock.unlock()
            switch cached {
            case .available(let key): return key
            case .unavailable(let message):
                throw BrowserImportError.cookieDecryptionFailed(message)
            }
        }
        lock.unlock()

        do {
            let password = try passwordProvider.password(for: source)
            let key = try Self.deriveKey(password: password)
            lock.lock()
            keys[source] = .available(key)
            lock.unlock()
            return key
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            lock.lock()
            keys[source] = .unavailable(message)
            lock.unlock()
            throw BrowserImportError.cookieDecryptionFailed(message)
        }
    }

    private static func deriveKey(password: Data) throws -> Data {
        let salt = Data("saltysalt".utf8)
        var key = Data(repeating: 0, count: kCCKeySizeAES128)
        let keyByteCount = key.count
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1_003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw ChromiumCookieDecryptionError.keyDerivationFailed
        }
        return key
    }

    private func decryptAES128CBC(_ ciphertext: Data.SubSequence, key: Data) throws -> Data {
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else {
            throw ChromiumCookieDecryptionError.invalidCiphertext
        }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let outputByteCount = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            ciphertextBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputByteCount,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw ChromiumCookieDecryptionError.decryptionFailed
        }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private func removeDomainBindingIfNeeded(
        from plaintext: Data,
        domain: String,
        databaseVersion: Int?
    ) throws -> Data {
        let expectedHash = Data(SHA256.hash(data: Data(domain.utf8)))
        let hasMatchingHash = plaintext.count >= expectedHash.count
            && Self.constantTimeEqual(plaintext.prefix(expectedHash.count), expectedHash)

        if databaseVersion.map({ $0 >= 24 }) == true {
            guard hasMatchingHash else {
                throw ChromiumCookieDecryptionError.domainBindingMismatch
            }
            return plaintext.dropFirst(expectedHash.count)
        }
        if hasMatchingHash {
            return plaintext.dropFirst(expectedHash.count)
        }
        return plaintext
    }

    private static func constantTimeEqual(_ lhs: Data.SubSequence, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}
