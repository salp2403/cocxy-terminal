// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorPairingURL.swift - Pairing URL and out-of-band secret contract.

import Foundation

enum MobileMirrorPairingURL {
    static let pairingSecretFragmentKey = "pairing-key"

    static func make(
        transport: MobileMirrorRouterTransport,
        address: String,
        port: UInt16,
        offer: MobileMirrorPairingOffer
    ) -> URL? {
        guard !offer.token.isEmpty,
              !offer.pairingSecret.isEmpty,
              var components = transport.urlComponents(address: address, port: port) else {
            return nil
        }
        components.path = "/pair"
        components.queryItems = [URLQueryItem(name: "token", value: offer.token)]
        guard let pairingFragment = fragment([
            URLQueryItem(name: pairingSecretFragmentKey, value: offer.pairingSecret),
        ]) else { return nil }
        components.percentEncodedFragment = pairingFragment
        return components.url
    }

    private static func fragment(_ items: [URLQueryItem]) -> String? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery
    }
}
