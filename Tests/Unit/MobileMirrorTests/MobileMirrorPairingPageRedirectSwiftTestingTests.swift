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

@Suite("Mobile mirror pairing page expiry", .serialized)
struct MobileMirrorPairingPageExpirySwiftTestingTests: MobileMirrorRouterTestSupport {
    private static let expiredSpanish = "El código de emparejamiento caducó. Crea uno nuevo en el Mac."

    @Test("an expired pending pairing answers a final localized status")
    func expiredPollIsFinal() async throws {
        let clock = MobileMirrorPairingTestClock()
        let authority = MobileMirrorPairingAuthority(clock: { clock.now })
        let router = try Self.router(authority: authority)
        let identity = MobileMirrorClientIdentity(remoteAddress: "10.0.0.6", userAgent: "Phone")
        let pending = try authority.consumeOffer(token: authority.makeOffer().token, identity: identity)
        clock.advance(by: MobileMirrorPairingAuthority.pairingTTL + 1)

        for _ in 0..<2 {
            let reply = try response(from: await router.route(
                request: request(path: "/mobile/api/pair-status", query: ["id": pending.id.uuidString]),
                identity: identity
            ))
            let payload = try #require(
                JSONSerialization.jsonObject(with: reply.body) as? [String: Any]
            )
            #expect(payload["status"] as? String == "expired")
            #expect(payload["ok"] as? Bool == false)
            #expect(payload["error"] as? String == Self.expiredSpanish)
            #expect(payload["code"] != nil)
        }
    }

    @Test("the pairing page stops polling once the Mac reports the code expired")
    @MainActor
    func pageStopsOnExpiredStatus() async throws {
        let body = #"{"status":"expired","ok":false,"error":"x","code":"session-expired"}"#
        let run = try await Self.loadPairingPage(pairStatusBody: body, ttl: 90)

        #expect(await Self.statusText(in: run.webView, becomes: Self.expiredSpanish))
        let settled = run.handler.pairStatusRequestCount
        try await Task.sleep(for: .seconds(2))
        #expect(run.handler.pairStatusRequestCount == settled)
        #expect(settled == 1)
    }

    @Test("the pairing page gives up when the code lifetime ends without an answer")
    @MainActor
    func pageStopsAtDeadline() async throws {
        let run = try await Self.loadPairingPage(pairStatusBody: #"{"status":"pending"}"#, ttl: 1)

        #expect(await Self.statusText(in: run.webView, becomes: Self.expiredSpanish))
        let settled = run.handler.pairStatusRequestCount
        try await Task.sleep(for: .seconds(2))
        #expect(run.handler.pairStatusRequestCount == settled)
    }

    private static func router(
        authority: MobileMirrorPairingAuthority
    ) throws -> MobileMirrorRequestRouter {
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            transport: .localTLS,
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            localization: try PairingLocalization().spanish(),
            snapshotProvider: { _ in .empty },
            actionHandler: { _, _, _, _ in .empty },
            pendingPairingHandler: { _ in }
        )
        router.updatePublicPort(43120)
        return router
    }

    @MainActor
    private static func loadPairingPage(
        pairStatusBody: String,
        ttl: TimeInterval
    ) async throws -> (webView: WKWebView, handler: MobileMirrorPairingSchemeHandler) {
        let authority = MobileMirrorPairingAuthority()
        let router = try router(authority: authority)
        let offer = authority.makeOffer(ttl: ttl)
        let page = try PairingLocalization().response(from: await router.route(
            request: PairingLocalization().request(path: "/pair", query: ["token": offer.token]),
            identity: MobileMirrorClientIdentity(remoteAddress: "10.0.0.7", userAgent: "Phone")
        ))
        let html = try #require(String(data: page.body, encoding: .utf8))
        let scheme = "cocxy-pairing-expiry"
        let handler = MobileMirrorPairingSchemeHandler(pairingHTML: html, pairStatusBody: pairStatusBody)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: try #require(URL(string: "\(scheme)://relay/pair"))))
        return (webView, handler)
    }

    @MainActor
    private static func statusText(in webView: WKWebView, becomes expected: String) async -> Bool {
        for _ in 0..<100 {
            let text = try? await webView.evaluateJavaScript(
                "document.getElementById('status')?.textContent"
            ) as? String
            if text == expected { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

private struct PairingLocalization: MobileMirrorRouterTestSupport {
    func spanish() throws -> MobileMirrorWebLocalization { try webLocalization(.spanish) }
}

final class MobileMirrorPairingTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}
