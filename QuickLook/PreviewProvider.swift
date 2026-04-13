// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PreviewProvider.swift - QuickLook preview extension for markdown documents.

import AppKit
import QuickLookUI
import WebKit
import CocxyMarkdownLib

final class PreviewProvider: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        return view
    }()

    private var pendingCompletion: ((Error?) -> Void)?

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        rootView.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: rootView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        self.view = rootView
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        loadViewIfNeeded()

        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            handler(NSError(domain: "CocxyQuickLook", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to read markdown file."
            ]))
            return
        }

        let document = MarkdownDocument.parse(source)
        let renderedDocument = MarkdownQuickLookHTMLSanitizer.makeOfflinePreviewHTML(
            from: MarkdownHTMLRenderer.renderDocument(document),
            baseDirectory: url.deletingLastPathComponent()
        )
        let html = MarkdownPreviewTemplate.build(
            mermaidJS: loadMarkdownResource(named: "mermaid.min", ext: "js"),
            katexJS: loadMarkdownResource(named: "katex.min", ext: "js"),
            katexCSS: loadMarkdownResource(named: "katex.min", ext: "css"),
            autoRenderJS: loadMarkdownResource(named: "katex-auto-render.min", ext: "js"),
            highlightJS: loadMarkdownResource(named: "highlight.min", ext: "js"),
            highlightCSS: loadMarkdownResource(named: "highlight-cocxy", ext: "css")
        )

        pendingCompletion = handler
        webView.loadHTMLString(
            html.replacingOccurrences(
                of: "<div id=\"content\"></div>",
                with: "<div id=\"content\">\(renderedDocument)</div>"
            ),
            baseURL: nil
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pendingCompletion?(nil)
        pendingCompletion = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        pendingCompletion?(error)
        pendingCompletion = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        pendingCompletion?(error)
        pendingCompletion = nil
    }

    private func loadMarkdownResource(named name: String, ext: String) -> String {
        let bundle = Bundle(for: PreviewProvider.self)

        if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Markdown"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }

        if let url = bundle.url(forResource: name, withExtension: ext),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }

        return ""
    }
}
