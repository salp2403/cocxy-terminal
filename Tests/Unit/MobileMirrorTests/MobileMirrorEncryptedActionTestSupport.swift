// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Foundation
@testable import CocxyTerminal

enum MobileMirrorEncryptedActionTestSupport {
    static func sessionKeys(
        for offer: MobileMirrorPairingOffer
    ) throws -> MobileMirrorSessionKeys {
        guard let secret = MobileMirrorPairingAuthority.decodeBase64URL(offer.pairingSecret) else {
            throw MobileMirrorEncryptedActionFixtureError.invalidPairingSecret
        }
        return MobileMirrorSessionKeys.derive(pairingSecret: secret, channelID: offer.id)
    }

    static func requestBody(
        action: MobileMirrorAction,
        key: Data,
        sequence: UInt64
    ) throws -> Data {
        try requestBody(
            plaintext: JSONEncoder().encode(action),
            key: key,
            sequence: sequence
        )
    }

    static func requestBody(
        plaintext: Data,
        key: Data,
        sequence: UInt64
    ) throws -> Data {
        guard key.count == 32 else {
            throw MobileMirrorEncryptedActionFixtureError.invalidKey
        }
        var header = [UInt8](repeating: 0, count: 26)
        header.replaceSubrange(0..<4, with: Data("CXYE".utf8))
        header[4] = 2
        header[5] = 1
        for offset in 0..<8 {
            header[6 + offset] = UInt8(truncatingIfNeeded: sequence >> (56 - offset * 8))
        }
        header.replaceSubrange(14..<18, with: [0x54, 0x45, 0x53, 0x54])
        for offset in 0..<8 {
            header[18 + offset] = UInt8(truncatingIfNeeded: sequence >> (56 - offset * 8))
        }

        let authenticatedHeader = Data(header)
        let nonce = try AES.GCM.Nonce(data: authenticatedHeader[14..<26])
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: nonce,
            authenticating: authenticatedHeader
        )
        var envelope = authenticatedHeader
        envelope.append(sealed.ciphertext)
        envelope.append(sealed.tag)
        let encoded = base64URL(envelope)
        return Data("{\"envelope\":\"\(encoded)\"}".utf8)
    }

    static func signedHeaders(
        body: Data,
        actionToken: RelayToken,
        cookie: String,
        origin: String,
        timestamp: String = String(UInt64(Date().timeIntervalSince1970)),
        nonce: String = UUID().uuidString
    ) -> [String: String] {
        [
            "cookie": "\(MobileMirrorRequestRouter.cookieName)=\(cookie)",
            "origin": origin,
            "content-type": "application/json",
            "x-cocxy-timestamp": timestamp,
            "x-cocxy-nonce": nonce,
            "x-cocxy-signature": signature(
                body: body,
                timestamp: timestamp,
                nonce: nonce,
                actionToken: actionToken
            ),
        ]
    }

    static func signature(
        body: Data,
        timestamp: String,
        nonce: String,
        actionToken: RelayToken
    ) -> String {
        let payload = MobileMirrorSessionKeys.canonicalActionPayload(
            method: "POST",
            path: "/mobile/api/action",
            body: body,
            timestamp: timestamp,
            nonce: nonce
        )
        return base64URL(actionToken.sign(payload))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class MobileMirrorTestRelayTLSIdentity: @unchecked Sendable {
    let identity: MobileMirrorEphemeralTLSIdentity
    let fingerprint: String

    private let bindAddress: String
    private let keychain: TemporaryMobileMirrorKeychain

    init(bindAddress: String) throws {
        let keychain = try TemporaryMobileMirrorKeychain()
        let identity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: bindAddress,
            keychain: keychain.reference
        )
        self.bindAddress = bindAddress
        self.keychain = keychain
        self.identity = identity
        self.fingerprint = testCertificateFingerprint(identity.certificate)
    }

    var provider: MobileMirrorLocalRelay.TLSIdentityProvider {
        let bindAddress = bindAddress
        let identity = identity
        return { requestedAddress in
            guard requestedAddress == bindAddress else {
                throw MobileMirrorEncryptedActionFixtureError.unexpectedBindAddress
            }
            return identity
        }
    }
}

actor MobileMirrorPendingRecorder {
    private(set) var value: MobileMirrorPendingPairing?
    func record(_ pending: MobileMirrorPendingPairing) { value = pending }
}

actor MobileMirrorActionRecorder {
    private(set) var values: [MobileMirrorAction] = []
    func record(_ action: MobileMirrorAction) { values.append(action) }
}

actor MobileMirrorRejectionRecorder {
    private(set) var reasons: [MobileMirrorActionAudit.RejectionReason] = []

    func record(
        _ reason: MobileMirrorActionAudit.RejectionReason,
        channelID: UUID,
        identity: MobileMirrorClientIdentity
    ) {
        _ = channelID
        _ = identity
        reasons.append(reason)
    }
}

enum RelayAuditWriterTestFailure: Error {
    case injected
}

private enum MobileMirrorEncryptedActionFixtureError: Error {
    case invalidKey
    case invalidPairingSecret
    case unexpectedBindAddress
}
