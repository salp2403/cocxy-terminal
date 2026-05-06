// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDOMGrabWebKitSupport.swift - WebKit wiring helpers for DOM grab.

import Foundation
import WebKit

/// Small WebKit adapter for the browser DOM-grab pipeline.
///
/// Keeping the script-message setup and enable/disable JavaScript here lets
/// both browser hosts (`BrowserPanelView` and `BrowserContentView`) share the
/// same behavior instead of drifting between overlay and split-pane browsers.
@MainActor
enum BrowserDOMGrabWebKitSupport {

    /// Registers the bundled DOM-grab script and message bridge.
    static func install(
        on configuration: WKWebViewConfiguration,
        handler: BrowserDOMGrabHandler
    ) {
        let source = BrowserDOMGrabHandler.loadJavaScriptSource()
        if !source.isEmpty {
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(script)
        }

        configuration.userContentController.add(
            ScriptMessageProxy(handler: handler),
            name: BrowserDOMGrabHandler.messageName
        )
    }

    /// Removes the script-message bridge from a web view before teardown.
    static func uninstall(from webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: BrowserDOMGrabHandler.messageName
        )
    }

    /// JavaScript used to flip the in-page DOM-grab state.
    nonisolated static func setEnabledScript(_ enabled: Bool) -> String {
        let method = enabled ? "enable" : "disable"
        return """
        (function() {
            if (window.cocxyDOMGrab && typeof window.cocxyDOMGrab.\(method) === 'function') {
                window.cocxyDOMGrab.\(method)();
                return true;
            }
            return false;
        })();
        """
    }

    /// Applies the current state to a live web view. Safe when the page has
    /// not loaded the helper yet; the script simply returns false.
    static func setEnabled(
        _ enabled: Bool,
        on webView: WKWebView,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        webView.evaluateJavaScript(setEnabledScript(enabled)) { result, error in
            if let error {
                NSLog("[Cocxy] DOM grab JS error: %@", error.localizedDescription)
                completion?(false)
                return
            }
            completion?((result as? Bool) == true)
        }
    }
}
