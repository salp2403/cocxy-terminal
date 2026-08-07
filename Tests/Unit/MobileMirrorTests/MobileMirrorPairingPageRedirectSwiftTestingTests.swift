// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import WebKit
@testable import CocxyTerminal

@Suite("Mobile mirror pairing page redirect", .serialized)
struct MobileMirrorPairingPageRedirectSwiftTestingTests: MobileMirrorRouterTestSupport {
    @Test("confirmed pairing redirects through the real page script without dropping the QR fragment")
    @MainActor
    func pairingPagePreservesQRFragment() async throws {
        let authority = MobileMirrorPairingAuthority()
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            transport: .localTLS,
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            localization: try webLocalization(.english),
            snapshotProvider: { _ in .empty },
            actionHandler: { _, _, _, _ in .empty },
            pendingPairingHandler: { _ in }
        )
        router.updatePublicPort(43120)
        let offer = authority.makeOffer()
        let result = await router.route(
            request: request(path: "/pair", query: ["token": offer.token]),
            identity: MobileMirrorClientIdentity(remoteAddress: "10.0.0.5", userAgent: "Phone")
        )
        let html = try #require(String(data: response(from: result).body, encoding: .utf8))
        let scheme = "cocxy-pairing-test"
        let handler = MobileMirrorPairingSchemeHandler(pairingHTML: html)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { webView.stopLoading() }
        let fragment = "pairing-key=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
        let initialURL = try #require(URL(string: "\(scheme)://relay/pair#\(fragment)"))

        webView.load(URLRequest(url: initialURL))
        for _ in 0..<100 {
            if webView.url?.path == "/", webView.url?.fragment == fragment { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(webView.url?.path == "/")
        #expect(webView.url?.fragment == fragment)
        #expect(handler.pairStatusRequestCount > 0)
    }
}
