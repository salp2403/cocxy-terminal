// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDOMGrabHandler.swift - WKScriptMessageHandler bridge for the
// browser-panel DOM grab feature.

import Foundation
import WebKit

/// Receives DOM-grab payloads from the in-page JS shipped with the
/// browser panel and forwards them as typed `BrowserDOMGrabPayload`
/// values to the surface lifecycle.
///
/// ## Wiring
///
/// The handler is registered against `WKUserContentController` via the
/// shared `ScriptMessageProxy` weak-handler pattern (the same shape the
/// markdown preview uses) so the controller does not retain the handler
/// — that prevents the strong-ref cycle WKWebView creates between its
/// configuration and any directly-attached message handler.
///
/// ## Payload shape
///
/// The JS posts a dictionary with the exact keys parsed by
/// `parsePayload(_:)`. Tests pin the contract so a regression in either
/// side fails at unit time:
///
/// ```js
/// window.webkit.messageHandlers.cocxyDOMGrab.postMessage({
///     selector: "button#login",
///     url: location.href,
///     title: document.title,
///     text: element.innerText
/// });
/// ```
@MainActor
final class BrowserDOMGrabHandler: NSObject, WKScriptMessageHandler {

    /// Name used for both the `WKUserContentController` registration and
    /// the JS `messageHandlers` lookup. Pinned as a single source of
    /// truth so a typo on either side surfaces as an immediate test
    /// failure.
    static let messageName: String = "cocxyDOMGrab"

    /// Closure invoked on the main actor whenever a complete payload is
    /// received from the JS bridge. The surface lifecycle wires this to
    /// the formatter + bridge.writeBytes path that injects the grab
    /// into the active terminal pane.
    var onPayload: ((BrowserDOMGrabPayload) -> Void)?

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              let body = message.body as? [String: Any],
              let payload = Self.parsePayload(body) else {
            return
        }
        onPayload?(payload)
    }

    // MARK: - Pure parser (testable without WKScriptMessage)

    /// Turns the JS-supplied dictionary into a typed
    /// `BrowserDOMGrabPayload`. Every required key must be present and
    /// of the expected type — a missing or malformed entry returns
    /// `nil` so the surface lifecycle never sees a half-built payload.
    ///
    /// Empty strings are accepted for `text` because the formatter is
    /// responsible for omitting the corresponding line in the rendered
    /// payload; rejecting them here would lose grabs of icon-only or
    /// image-only nodes that have no visible text by definition.
    ///
    /// `nonisolated` because the parser is a pure value transform — it
    /// reads no instance state and produces no side effects, so tests
    /// and any future off-main caller can invoke it without paying a
    /// hop to the main actor.
    ///
    /// - Parameter body: Raw dictionary as posted by the JS bridge.
    /// - Returns: Typed payload, or `nil` if the dictionary is missing
    ///   any required key or contains an unparseable URL.
    nonisolated static func parsePayload(_ body: [String: Any]) -> BrowserDOMGrabPayload? {
        guard let selector = body["selector"] as? String,
              let urlString = body["url"] as? String,
              let pageURL = URL(string: urlString),
              !urlString.isEmpty,
              let pageTitle = body["title"] as? String,
              let visibleText = body["text"] as? String else {
            return nil
        }
        return BrowserDOMGrabPayload(
            selector: selector,
            pageURL: pageURL,
            pageTitle: pageTitle,
            visibleText: visibleText,
            timestamp: Date(),
            screenshotPath: nil
        )
    }

    /// Loads the bundled `dom-grab.js` source. Returns the empty string
    /// when the resource cannot be located so the WKWebView setup
    /// proceeds gracefully — the toolbar toggle in that case is a
    /// soft-disabled no-op instead of a hard crash.
    ///
    /// Resolution mirrors the markdown-preview pattern: production
    /// `.app` reads `Contents/Resources/JS/`, while development
    /// (`swift run`) walks up from the executable looking for the
    /// project's `Resources/JS/` directory.
    nonisolated static func loadJavaScriptSource() -> String {
        let fileName = "dom-grab.js"

        if let mainURL = Bundle.main.resourceURL {
            let fileURL = mainURL
                .appendingPathComponent("JS", isDirectory: true)
                .appendingPathComponent(fileName)
            if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
                return contents
            }
        }

        if let execURL = Bundle.main.executableURL {
            var candidate = execURL.deletingLastPathComponent()
            for _ in 0..<5 {
                let fileURL = candidate
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("JS", isDirectory: true)
                    .appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
                    return contents
                }
                candidate = candidate.deletingLastPathComponent()
            }
        }

        return ""
    }
}
