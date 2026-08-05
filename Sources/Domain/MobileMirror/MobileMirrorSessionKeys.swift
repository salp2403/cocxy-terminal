// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorSessionKeys.swift - Purpose-separated mobile session keys.

import CryptoKit
import Foundation

struct MobileMirrorSessionKeys: Sendable {
    static let authenticationInfo = Data("dev.cocxy.mobile.action.v1".utf8)
    static let terminalEncryptionInfo = Data("dev.cocxy.mobile.terminal.v1".utf8)

    let actionToken: RelayToken
    let terminalEncryptionKey: Data

    static func derive(pairingSecret: Data, channelID: UUID) -> Self {
        let inputKeyMaterial = SymmetricKey(data: pairingSecret)
        let salt = Data(channelID.uuidString.lowercased().utf8)
        let authenticationKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: authenticationInfo,
            outputByteCount: 32
        )
        let encryptionKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: terminalEncryptionInfo,
            outputByteCount: 32
        )
        return Self(
            actionToken: RelayToken(secret: authenticationKey.data),
            terminalEncryptionKey: encryptionKey.data
        )
    }

    static func canonicalActionPayload(
        method: String,
        path: String,
        body: Data,
        timestamp: String,
        nonce: String
    ) -> Data {
        var payload = Data("\(method.uppercased())\n\(path)\n".utf8)
        payload.append(body)
        payload.append(Data("\n\(timestamp)\n\(nonce)".utf8))
        return payload
    }
}

private extension SymmetricKey {
    var data: Data {
        withUnsafeBytes { Data($0) }
    }
}
