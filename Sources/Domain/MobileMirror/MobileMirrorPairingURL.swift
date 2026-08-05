// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorPairingURL.swift - Pairing URL and certificate pin contract.

import Foundation

enum MobileMirrorPairingURL {
    static let certificatePinFragmentKey = "tls-sha256"

    static func local(
        address: String,
        port: UInt16,
        token: String,
        certificateFingerprint: String
    ) -> URL? {
        guard port > 0, !token.isEmpty, !certificateFingerprint.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = address
        components.port = Int(port)
        components.path = "/pair"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        components.fragment = "\(certificatePinFragmentKey)=\(certificateFingerprint)"
        return components.url
    }

    static func certificateFingerprint(from url: URL) -> String? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            return nil
        }
        let prefix = "\(certificatePinFragmentKey)="
        guard fragment.hasPrefix(prefix) else { return nil }
        let value = String(fragment.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    static func displayFingerprint(_ value: String) -> String {
        stride(from: 0, to: value.count, by: 4).map { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: min(4, value.count - offset))
            return String(value[start..<end])
        }.joined(separator: " ")
    }
}
