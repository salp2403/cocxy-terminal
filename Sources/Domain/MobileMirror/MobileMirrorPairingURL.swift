// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorPairingURL.swift - Pairing URL and out-of-band secret contract.

import Foundation

enum MobileMirrorPairingURL {
    static let pairingSecretFragmentKey = "pairing-key"

    static func local(
        address: String,
        port: UInt16,
        token: String,
        pairingSecret: String
    ) -> URL? {
        guard port > 0,
              !token.isEmpty,
              !pairingSecret.isEmpty else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = address
        components.port = Int(port)
        components.path = "/pair"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        components.percentEncodedFragment = fragment([
            URLQueryItem(name: pairingSecretFragmentKey, value: pairingSecret),
        ])
        return components.url
    }

    static func sshTunnel(
        address: String,
        port: UInt16,
        token: String,
        pairingSecret: String
    ) -> URL? {
        guard port > 0, !token.isEmpty, !pairingSecret.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = address
        components.port = Int(port)
        components.path = "/pair"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        components.percentEncodedFragment = fragment([
            URLQueryItem(name: pairingSecretFragmentKey, value: pairingSecret),
        ])
        return components.url
    }

    static func pairingSecret(from url: URL) -> String? {
        fragmentValue(pairingSecretFragmentKey, from: url)
    }

    private static func fragment(_ items: [URLQueryItem]) -> String? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery
    }

    private static func fragmentValue(_ name: String, from url: URL) -> String? {
        guard let fragment = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.percentEncodedFragment else {
            return nil
        }
        var components = URLComponents()
        components.percentEncodedQuery = fragment
        let value = components.queryItems?.first(where: { $0.name == name })?.value
        return value?.isEmpty == false ? value : nil
    }
}
