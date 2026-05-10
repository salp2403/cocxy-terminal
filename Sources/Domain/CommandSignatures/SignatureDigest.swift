// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Foundation

public enum SignatureDigest {
    public static func sha256Base64(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func keyID(for publicKey: Data) -> String {
        String(sha256Hex(publicKey).prefix(16))
    }
}
