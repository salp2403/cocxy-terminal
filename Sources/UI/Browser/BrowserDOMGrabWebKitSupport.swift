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

    /// Keeps the privileged message handler and cooperative helper outside
    /// the page JavaScript world. Page scripts can still render and receive
    /// real user clicks, but cannot call the native bridge directly.
    static let contentWorld = WKContentWorld.world(name: "com.cocxy.dom-grab")

    /// Registers the bundled DOM-grab script and message bridge.
    static func install(
        on configuration: WKWebViewConfiguration,
        handler: BrowserDOMGrabHandler,
        sourceOverride: String? = nil
    ) {
        let source = sourceOverride ?? BrowserDOMGrabHandler.loadJavaScriptSource()
        if !source.isEmpty {
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: contentWorld
            )
            configuration.userContentController.addUserScript(script)
        }

        configuration.userContentController.add(
            ScriptMessageProxy(handler: handler),
            contentWorld: contentWorld,
            name: BrowserDOMGrabHandler.messageName
        )
    }

    /// Removes the script-message bridge from a web view before teardown.
    static func uninstall(from webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: BrowserDOMGrabHandler.messageName,
            contentWorld: contentWorld
        )
    }

    /// JavaScript used to install or revoke one exact isolated-world grant.
    nonisolated static func setAuthorizationScript(_ authorizationID: UUID?) -> String {
        let operation: String
        if let authorizationID {
            operation = "return window.cocxyDOMGrab.enable(\"\(authorizationID.uuidString.lowercased())\") === true;"
        } else {
            operation = "window.cocxyDOMGrab.disable(); return true;"
        }
        return """
        (function() {
            if (window.cocxyDOMGrab &&
                typeof window.cocxyDOMGrab.enable === 'function' &&
                typeof window.cocxyDOMGrab.disable === 'function') {
                \(operation)
            }
            return false;
        })();
        """
    }

    /// Applies the current one-shot grant to a live web view. Safe when the
    /// page has not loaded the helper yet; the script simply returns false.
    static func setAuthorization(
        _ authorizationID: UUID?,
        on webView: WKWebView,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        webView.evaluateJavaScript(
            setAuthorizationScript(authorizationID),
            in: nil,
            in: contentWorld
        ) { result in
            switch result {
            case .success(let value):
                completion?((value as? Bool) == true)
            case .failure(let error):
                NSLog("[Cocxy] DOM grab JS error: %@", error.localizedDescription)
                completion?(false)
            }
        }
    }
}
