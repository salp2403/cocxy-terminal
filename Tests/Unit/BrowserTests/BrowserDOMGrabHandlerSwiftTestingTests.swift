// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import WebKit
@testable import CocxyTerminal

/// Unit coverage for `BrowserDOMGrabHandler.parsePayload`, the pure
/// helper that turns the JS-supplied dictionary into a typed
/// `BrowserDOMGrabPayload` before it reaches the rest of the surface
/// lifecycle.
///
/// The handler itself extends `NSObject` and conforms to
/// `WKScriptMessageHandler`, so the WebKit-side entry point is exercised
/// with the real browser at smoke time. The pure parser, on the other
/// hand, must reject malformed payloads deterministically — tests pin
/// every required key, the URL parsing, and the field forwarding so a
/// regression in the JS bridge surfaces here instead of at runtime.
@Suite("BrowserDOMGrabHandler.parsePayload")
struct BrowserDOMGrabHandlerSwiftTestingTests {

    // MARK: - Happy path

    @Test("a fully populated dictionary produces a typed payload with every field forwarded")
    func fullDictionaryProducesPayload() {
        let dict: [String: Any] = [
            "selector": "button#login",
            "url": "https://example.com/path?q=1",
            "title": "Example Login",
            "text": "Sign in",
        ]

        let payload = BrowserDOMGrabHandler.parsePayload(dict)

        #expect(payload != nil)
        #expect(payload?.selector == "button#login")
        #expect(payload?.pageURL.absoluteString == "https://example.com/path?q=1")
        #expect(payload?.pageTitle == "Example Login")
        #expect(payload?.visibleText == "Sign in")
        #expect(payload?.screenshotPath == nil)
    }

    // MARK: - Required-field validation

    @Test("missing selector key returns nil so the surface lifecycle never sees a half-built payload")
    func missingSelectorReturnsNil() {
        let dict: [String: Any] = [
            "url": "https://example.com",
            "title": "Example",
            "text": "Sign in",
        ]

        #expect(BrowserDOMGrabHandler.parsePayload(dict) == nil)
    }

    @Test("missing url key returns nil")
    func missingURLReturnsNil() {
        let dict: [String: Any] = [
            "selector": "button",
            "title": "Example",
            "text": "Sign in",
        ]

        #expect(BrowserDOMGrabHandler.parsePayload(dict) == nil)
    }

    @Test("malformed url string returns nil so an unparseable URL never reaches the formatter")
    func malformedURLReturnsNil() {
        let dict: [String: Any] = [
            "selector": "button",
            "url": "",
            "title": "Example",
            "text": "Sign in",
        ]

        #expect(BrowserDOMGrabHandler.parsePayload(dict) == nil)
    }

    @Test("missing title returns nil")
    func missingTitleReturnsNil() {
        let dict: [String: Any] = [
            "selector": "button",
            "url": "https://example.com",
            "text": "Sign in",
        ]

        #expect(BrowserDOMGrabHandler.parsePayload(dict) == nil)
    }

    @Test("missing text returns nil so prompters can rely on the field being either absent in the dict or present and respected")
    func missingTextReturnsNil() {
        let dict: [String: Any] = [
            "selector": "button",
            "url": "https://example.com",
            "title": "Example",
        ]

        #expect(BrowserDOMGrabHandler.parsePayload(dict) == nil)
    }

    // MARK: - Empty values are accepted, only nil keys reject

    @Test("an empty visible text is accepted — the formatter is responsible for omitting the line, not the parser")
    func emptyTextIsAccepted() {
        let dict: [String: Any] = [
            "selector": "img.logo",
            "url": "https://example.com",
            "title": "Example",
            "text": "",
        ]

        let payload = BrowserDOMGrabHandler.parsePayload(dict)

        #expect(payload != nil)
        #expect(payload?.visibleText == "")
    }
}

@Suite("Browser DOM-grab WebKit isolation")
@MainActor
struct BrowserDOMGrabWebKitIsolationSwiftTestingTests {
    @Test("native handler rejects subframe payloads")
    func nativeHandlerRejectsSubframes() {
        let handler = BrowserDOMGrabHandler()
        let authorizationID = UUID()
        var receivedCount = 0
        handler.onPayload = { receivedAuthorizationID, _ in
            #expect(receivedAuthorizationID == authorizationID)
            receivedCount += 1
        }
        let body: [String: Any] = [
            "authorizationID": authorizationID.uuidString,
            "selector": "button#login",
            "url": "https://example.com",
            "title": "Example",
            "text": "Sign in",
        ]

        #expect(handler.receive(body, isMainFrame: false) == false)
        #expect(receivedCount == 0)
        #expect(handler.receive(body, isMainFrame: true))
        #expect(receivedCount == 1)
    }

    @Test("native handler rejects missing and malformed one-shot grants")
    func nativeHandlerRejectsInvalidAuthorizationIDs() {
        let handler = BrowserDOMGrabHandler()
        var receivedCount = 0
        handler.onPayload = { _, _ in receivedCount += 1 }
        let body: [String: Any] = [
            "selector": "button#login",
            "url": "https://example.com",
            "title": "Example",
            "text": "Sign in",
        ]

        #expect(handler.receive(body, isMainFrame: true) == false)
        #expect(handler.receive(
            body.merging(["authorizationID": "not-a-uuid"]) { _, new in new },
            isMainFrame: true
        ) == false)
        #expect(receivedCount == 0)
    }

    @Test("page JavaScript cannot reach or synthetically trigger the isolated native handler")
    func pageWorldCannotReachNativeHandler() async throws {
        let configuration = WKWebViewConfiguration()
        let handler = BrowserDOMGrabHandler()
        var receivedPayload = false
        handler.onPayload = { _, _ in receivedPayload = true }
        let authorizationID = UUID()
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Resources/JS/dom-grab.js"),
            encoding: .utf8
        )
        BrowserDOMGrabWebKitSupport.install(
            on: configuration,
            handler: handler,
            sourceOverride: source
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigationWaiter = BrowserDOMGrabNavigationWaiter()
        try await navigationWaiter.loadHTML(
            "<html><body><button id='target'>Capture</button></body></html>",
            in: webView
        )

        let pageWorldResult = try await webView.evaluateJavaScript("""
        typeof window.webkit === 'undefined' ||
        typeof window.webkit.messageHandlers.cocxyDOMGrab === 'undefined'
        """)
        let isolatedWorldResult = try await webView.evaluateJavaScript(
            "typeof window.webkit.messageHandlers.cocxyDOMGrab === 'object' && typeof window.cocxyDOMGrab === 'object'",
            in: nil,
            contentWorld: BrowserDOMGrabWebKitSupport.contentWorld
        )
        let enabledResult = try await webView.evaluateJavaScript(
            BrowserDOMGrabWebKitSupport.setAuthorizationScript(authorizationID),
            in: nil,
            contentWorld: BrowserDOMGrabWebKitSupport.contentWorld
        )
        let dispatchResult = try await webView.evaluateJavaScript("""
        document.getElementById('target').dispatchEvent(
            new MouseEvent('click', { bubbles: true, cancelable: true })
        )
        """)
        try await Task.sleep(for: .milliseconds(20))
        let remainsEnabled = try await webView.evaluateJavaScript(
            "window.cocxyDOMGrab.isEnabled()",
            in: nil,
            contentWorld: BrowserDOMGrabWebKitSupport.contentWorld
        )

        #expect((pageWorldResult as? Bool) == true)
        #expect((isolatedWorldResult as? Bool) == true)
        #expect((enabledResult as? Bool) == true)
        #expect((dispatchResult as? Bool) == true)
        #expect((remainsEnabled as? Bool) == true)
        #expect(receivedPayload == false)
        #expect(configuration.userContentController.userScripts.count == 1)
        let userScript = try #require(configuration.userContentController.userScripts.first)
        #expect(userScript.isForMainFrameOnly)
        #expect(source.contains("event.isTrusted"))
        #expect(source.contains("authorizationID"))
    }
}

@MainActor
private final class BrowserDOMGrabNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func loadHTML(_ html: String, in webView: WKWebView) async throws {
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finish()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        finish(error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        finish(error: error)
    }

    private func finish(error: Error? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
