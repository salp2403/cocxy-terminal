// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyDRemoteManifest.swift - Manifest and checksum verification for cocxyd-remote.

import CryptoKit
import Foundation

extension RemotePlatform: Codable {
    private enum CodingKeys: String, CodingKey {
        case os
        case arch
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            os: try container.decode(String.self, forKey: .os),
            arch: try container.decode(String.self, forKey: .arch)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(os, forKey: .os)
        try container.encode(arch, forKey: .arch)
    }
}

struct CocxyDRemoteManifest: Codable, Equatable, Sendable {
    let version: String
    let platform: RemotePlatform
    let sha256: String
    let sizeBytes: Int
    let capabilities: Set<String>

    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func verifies(data: Data) -> Bool {
        data.count == sizeBytes && Self.sha256Hex(for: data) == sha256
    }
}
