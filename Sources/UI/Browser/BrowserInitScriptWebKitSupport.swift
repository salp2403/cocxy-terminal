// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserInitScriptWebKitSupport.swift - Managed document-start scripts for approved browser grants.

import Foundation
import WebKit

@MainActor
enum BrowserInitScriptWebKitSupport {
    nonisolated static let managedSourcePrefix = "/* cocxy-managed-init-script:"

    private final class ManagedScriptState {
        weak var webView: WKWebView?
        var scripts: [WKUserScript] = []

        init(webView: WKWebView) {
            self.webView = webView
        }
    }

    private static var managedScriptStates: [ObjectIdentifier: ManagedScriptState] = [:]

    static func install(on webView: WKWebView, viewModel: BrowserViewModel) {
        let browserViewID = UUID()
        viewModel.attachInitScriptBridge(
            browserViewID: browserViewID,
            webViewIdentifier: ObjectIdentifier(webView),
            navigationCanceller: { [weak webView] in
                webView?.stopLoading()
            }
        ) { [weak webView] scripts in
            guard let webView else {
                return .failure("Browser web view is not available")
            }
            return synchronize(scripts, in: webView)
        }
    }

    static func uninstall(from webView: WKWebView, viewModel: BrowserViewModel) {
        viewModel.detachInitScriptBridge(
            webViewIdentifier: ObjectIdentifier(webView)
        )
        managedScriptStates.removeValue(forKey: ObjectIdentifier(webView))
    }

    static func synchronize(
        _ scripts: [BrowserInitScript],
        in webView: WKWebView
    ) -> BrowserScriptEvaluationResult {
        guard scripts.allSatisfy({
            BrowserInitScriptSecurity.digest($0.source) == $0.scriptDigest
        }) else {
            return .failure("Browser init script integrity validation failed")
        }

        let state = managedScriptState(for: webView)
        let managedScriptIdentifiers = Set(state.scripts.map(ObjectIdentifier.init))
        let controller = webView.configuration.userContentController
        let preservedScripts = controller.userScripts.filter {
            !managedScriptIdentifiers.contains(ObjectIdentifier($0))
        }
        controller.removeAllUserScripts()
        for script in preservedScripts {
            controller.addUserScript(script)
        }
        var installedScripts: [WKUserScript] = []
        for script in scripts {
            let userScript = WKUserScript(
                source: managedSource(for: script),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .page
            )
            controller.addUserScript(userScript)
            installedScripts.append(userScript)
        }
        state.scripts = installedScripts
        return .success("synchronized")
    }

    private static func managedScriptState(for webView: WKWebView) -> ManagedScriptState {
        let identifier = ObjectIdentifier(webView)
        if let state = managedScriptStates[identifier], state.webView === webView {
            return state
        }
        let state = ManagedScriptState(webView: webView)
        managedScriptStates[identifier] = state
        return state
    }

    nonisolated static func managedSource(for script: BrowserInitScript) -> String {
        let originLiteral = javaScriptStringLiteral(script.origin.serialized)
        let sourceLiteral = javaScriptStringLiteral(script.source)
        let expirationMilliseconds = Int64(script.expiresAt.timeIntervalSince1970 * 1_000)
        return """
        \(managedSourcePrefix)\(script.id.uuidString) */
        if (window.location.origin === \(originLiteral) && Date.now() < \(expirationMilliseconds)) {
            (0, eval)(\(sourceLiteral));
        }
        """
    }

    private nonisolated static func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: [value],
            options: [.withoutEscapingSlashes]
        ),
              var encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
