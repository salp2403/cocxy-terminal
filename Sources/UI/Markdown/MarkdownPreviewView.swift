// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownPreviewView.swift - WKWebView-based markdown preview with Mermaid + KaTeX.
//
// The preview loads a single HTML template containing Catppuccin Mocha CSS,
// Mermaid.js, and KaTeX.js. Content updates replace only the body via
// `evaluateJavaScript("updateContent('...')")`, keeping JS libraries warm.
//
// Mermaid diagrams render from fenced `mermaid` code blocks.
// Math expressions render from $...$ (inline) and $$...$$ (display) delimiters
// via KaTeX auto-render.

import AppKit
import WebKit

// MARK: - Preview View

/// WKWebView-based markdown preview supporting Mermaid diagrams and KaTeX math.
///
/// Replaces the previous NSTextView + NSAttributedString approach to enable
/// rich rendering via JavaScript libraries. The public API remains unchanged:
/// set `document` to update, call `scrollToHeading(title:)` to navigate.
@MainActor
final class MarkdownPreviewView: NSView {

    // MARK: - Properties

    private let webView: WKWebView
    private var isTemplateLoaded = false
    private var pendingHTML: String?

    /// Current document. Setting this re-renders the preview.
    var document: MarkdownDocument = .empty {
        didSet { updatePreview() }
    }

    // MARK: - Init

    init() {
        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        setupUI()
        loadTemplate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownPreviewView does not support NSCoding")
    }

    // MARK: - Public

    /// Scrolls the preview to a heading matching the given title.
    func scrollToHeading(title: String) {
        let escaped = escapeJSString(title)
        webView.evaluateJavaScript("scrollToHeading('\(escaped)')") { _, _ in }
    }

    /// Scrolls the preview to a proportional position (0.0 = top, 1.0 = bottom).
    func scrollToFraction(_ fraction: CGFloat) {
        guard isTemplateLoaded else { return }
        let clamped = min(1.0, max(0.0, fraction))
        webView.evaluateJavaScript(
            "window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(clamped))"
        ) { _, _ in }
    }

    /// Creates a print operation for PDF export via the system print dialog.
    func createPrintOperation() -> NSPrintOperation? {
        guard isTemplateLoaded else { return nil }
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        return webView.printOperation(with: printInfo)
    }

    /// Captures the fully rendered DOM (including Mermaid SVGs and KaTeX spans)
    /// as a standalone HTML string with CSS inlined.
    func captureRenderedHTML(completion: @escaping (String?) -> Void) {
        guard isTemplateLoaded else {
            completion(nil)
            return
        }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
            if let html = result as? String {
                completion(html)
            } else {
                NSLog("captureRenderedHTML error: %@", String(describing: error))
                completion(nil)
            }
        }
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Template Loading

    private func loadTemplate() {
        let mermaidJS = loadResourceFile(named: "mermaid.min", ext: "js")
        let katexJS = loadResourceFile(named: "katex.min", ext: "js")
        let katexCSS = loadResourceFile(named: "katex.min", ext: "css")
        let autoRenderJS = loadResourceFile(named: "katex-auto-render.min", ext: "js")

        let html = MarkdownPreviewTemplate.build(
            mermaidJS: mermaidJS,
            katexJS: katexJS,
            katexCSS: katexCSS,
            autoRenderJS: autoRenderJS
        )

        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Reads a JS/CSS resource from the Markdown resources directory.
    ///
    /// Resolution: `Bundle.main/Resources/Markdown/` in production `.app`,
    /// then project root `Resources/Markdown/` for development.
    private func loadResourceFile(named name: String, ext: String) -> String {
        let fileName = "\(name).\(ext)"

        // Production .app: Contents/Resources/Markdown/
        if let mainURL = Bundle.main.resourceURL {
            let fileURL = mainURL
                .appendingPathComponent("Markdown", isDirectory: true)
                .appendingPathComponent(fileName)
            if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
                return contents
            }
        }

        // Development: project root Resources/Markdown/
        // Resolve via the executable's grandparent (works for swift run).
        if let execURL = Bundle.main.executableURL {
            // swift run: .build/arm64-apple-macosx/debug/CocxyTerminal
            // Walk up to project root and check Resources/
            var candidate = execURL.deletingLastPathComponent()
            for _ in 0..<5 {
                let fileURL = candidate
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("Markdown", isDirectory: true)
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

    // MARK: - Content Updates

    private func updatePreview() {
        let html = MarkdownHTMLRenderer.renderDocument(document)

        guard isTemplateLoaded else {
            pendingHTML = html
            return
        }

        injectContent(html)
    }

    private func injectContent(_ html: String) {
        let escaped = escapeJSString(html)
        webView.evaluateJavaScript("updateContent('\(escaped)')") { _, error in
            if let error {
                NSLog("MarkdownPreviewView JS error: %@", String(describing: error))
            }
        }
    }

    // MARK: - JS String Escaping

    private func escapeJSString(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "'", with: "\\'")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        // U+2028 (Line Separator) and U+2029 (Paragraph Separator) are
        // valid in JSON/Unicode strings but act as line terminators inside
        // JS string literals, breaking evaluateJavaScript.
        result = result.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        result = result.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return result
    }
}

// MARK: - WKNavigationDelegate

extension MarkdownPreviewView: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isTemplateLoaded = true

        // Flush any content that arrived before the template loaded.
        if let html = pendingHTML {
            pendingHTML = nil
            injectContent(html)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // Allow initial template load and JS-driven navigations.
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
            return
        }

        // External links: open in default browser instead of navigating away.
        if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
