// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
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
