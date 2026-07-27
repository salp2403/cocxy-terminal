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
import CocxyMarkdownLib

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
    private let messageProxy: ScriptMessageProxy
    private var isTemplateLoaded = false
    private var latestContentGeneration: UInt64 = 0
    private var isContentUpdatePending = false
    private var pendingHTML: String?
    private var pendingActions: [() -> Void] = []
    private var localizer: AppLocalizer
    private var contentRuleGeneration: UInt64 = 0
    private(set) var approvedRemoteImageHosts: Set<String> = []
    private(set) var currentRemoteImageHosts: Set<String> = []

    /// Current document. Setting this re-renders the preview.
    var document: MarkdownDocument = .empty {
        didSet { updatePreview() }
    }

    /// Base directory for resolving relative image paths.
    /// Setting this reloads the template with the new baseURL so that
    /// `<img src="image.png">` resolves to a local file.
    var baseDirectory: URL? {
        didSet {
            if oldValue != baseDirectory {
                resetRemoteImageApprovals(updateContent: false)
                // Reset template state so updatePreview queues content into
                // pendingHTML instead of calling evaluateJavaScript on a page
                // that is mid-navigation. didFinish will flush pendingHTML.
                isTemplateLoaded = false
                isContentUpdatePending = false
                latestContentGeneration &+= 1
                // Discard pending export actions from the previous document —
                // they would run against the wrong page after the reload.
                pendingActions.removeAll()
                loadTemplate()
            }
        }
    }

    var onCheckboxToggle: ((Int, Bool) -> Void)?
    var onClickToSource: ((Int) -> Void)?
    var onCopyToClipboard: ((String) -> Void)?
    var onRemoteImagePolicyChange: (() -> Void)?

    var unapprovedRemoteImageHosts: Set<String> {
        currentRemoteImageHosts.subtracting(approvedRemoteImageHosts)
    }

    private(set) var lastSourceLineScrollRequestForTesting: Int?
    private(set) var lastHighlightedSourceLineForTesting: Int?

    // MARK: - Init

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        let config = WKWebViewConfiguration()
        let proxy = ScriptMessageProxy()
        config.userContentController.add(proxy, name: "cocxy")
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        self.messageProxy = proxy
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.localizer = localizer
        super.init(frame: .zero)
        proxy.handler = self
        setupUI()
        installRemoteImageContentRule(for: [], grantsApproval: false)
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
        evaluateWhenReady("scrollToHeading('\(escaped)')")
    }

    /// Scrolls to the nearest rendered block for the source line.
    func scrollToSourceLine(_ sourceLine: Int) {
        guard sourceLine >= 0 else { return }
        lastSourceLineScrollRequestForTesting = sourceLine
        evaluateWhenReady("scrollToSourceLine(\(sourceLine), true)")
    }

    /// Highlights the nearest rendered block for the source line without
    /// changing scroll position. Passing nil clears the current highlight.
    func highlightSourceLine(_ sourceLine: Int?) {
        lastHighlightedSourceLineForTesting = sourceLine
        if let sourceLine, sourceLine >= 0 {
            evaluateWhenReady("highlightSourceLine(\(sourceLine))")
        } else {
            evaluateWhenReady("clearSourceLineHighlight()")
        }
    }

    /// Scrolls the preview to a proportional position (0.0 = top, 1.0 = bottom).
    func scrollToFraction(_ fraction: CGFloat) {
        let clamped = min(1.0, max(0.0, fraction))
        evaluateWhenReady("scrollToFraction(\(clamped))")
    }

    /// Whether the preview template has finished loading and is ready for
    /// export operations. Callers can check this to defer actions.
    var isReady: Bool { isTemplateLoaded && !isContentUpdatePending }

    /// Enqueues an action to execute after the template finishes loading.
    /// If already loaded, executes immediately.
    func whenReady(_ action: @escaping () -> Void) {
        if isReady {
            action()
        } else {
            pendingActions.append(action)
        }
    }

    /// Creates a print operation for PDF export via the system print dialog.
    func createPrintOperation() -> NSPrintOperation? {
        guard isReady else { return nil }
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        return webView.printOperation(with: printInfo)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        guard self.localizer.resolvedLanguage != localizer.resolvedLanguage else {
            self.localizer = localizer
            return
        }
        self.localizer = localizer
        isTemplateLoaded = false
        loadTemplate()
        updatePreview()
    }

    /// Captures the fully rendered DOM (including Mermaid SVGs and KaTeX spans)
    /// as a standalone HTML string with CSS inlined.
    /// If the template is still loading (e.g., after a directory change), the
    /// capture is deferred until the template finishes loading.
    func captureRenderedHTML(completion: @escaping (String?) -> Void) {
        guard isReady else {
            pendingActions.append { [weak self] in
                self?.captureRenderedHTML(completion: completion)
            }
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

    func approveRemoteImageHosts(
        _ hosts: Set<String>,
        completion: ((Bool) -> Void)? = nil
    ) {
        let targetHosts = approvedRemoteImageHosts.union(hosts.map { $0.lowercased() })
        guard targetHosts != approvedRemoteImageHosts else {
            completion?(true)
            return
        }
        installRemoteImageContentRule(
            for: targetHosts,
            grantsApproval: true,
            completion: completion
        )
    }

    func resetRemoteImageApprovals(updateContent: Bool = true) {
        approvedRemoteImageHosts = []
        installRemoteImageContentRule(for: [], grantsApproval: false)
        if updateContent {
            updatePreview()
        }
        onRemoteImagePolicyChange?()
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
        let highlightJS = loadResourceFile(named: "highlight.min", ext: "js")
        let highlightCSS = loadResourceFile(named: "highlight-cocxy", ext: "css")

        let html = MarkdownPreviewTemplate.build(
            mermaidJS: mermaidJS,
            katexJS: katexJS,
            katexCSS: katexCSS,
            autoRenderJS: autoRenderJS,
            highlightJS: highlightJS,
            highlightCSS: highlightCSS,
            tableOfContentsTitle: localizer.string(
                "markdown.preview.toc.title",
                fallback: "Table of Contents"
            )
        )

        webView.loadHTMLString(html, baseURL: baseDirectory)
    }

    /// Reads a JS/CSS resource from the Markdown resources directory.
    ///
    /// Resolution: `Bundle.main/Resources/Markdown/` in production `.app`,
    /// then project root `Resources/Markdown/` for development.
    func loadResourceFile(named name: String, ext: String) -> String {
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
        let rendered = MarkdownHTMLRenderer.renderDocument(document)
        let processed = MarkdownImageInliner.makeSafeHTML(
            in: rendered,
            baseDirectory: baseDirectory,
            approvedRemoteHosts: approvedRemoteImageHosts
        )
        let previousRemoteHosts = currentRemoteImageHosts
        currentRemoteImageHosts = processed.remoteHosts
        let html = processed.html
        if previousRemoteHosts != currentRemoteImageHosts {
            onRemoteImagePolicyChange?()
        }

        guard isTemplateLoaded else {
            pendingHTML = html
            return
        }

        injectContent(html)
    }

    private func installRemoteImageContentRule(
        for approvedHosts: Set<String>,
        grantsApproval: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        contentRuleGeneration &+= 1
        let generation = contentRuleGeneration
        let normalizedHosts = Set(approvedHosts.map { $0.lowercased() })
        var trigger: [String: Any] = [
            "url-filter": "^https?://",
            "resource-type": ["image"],
        ]
        if !normalizedHosts.isEmpty {
            trigger["unless-domain"] = normalizedHosts.sorted()
        }
        let rules: [[String: Any]] = [[
            "trigger": trigger,
            "action": ["type": "block"],
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]),
              let encodedRules = String(data: data, encoding: .utf8)
        else {
            completion?(false)
            return
        }

        let identifier = "cocxy-markdown-images-\(Self.stableRuleHash(normalizedHosts))"
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encodedRules
        ) { [weak self] ruleList, _ in
            Task { @MainActor in
                guard let self, self.contentRuleGeneration == generation else {
                    completion?(false)
                    return
                }
                guard let ruleList else {
                    completion?(false)
                    return
                }
                let controller = self.webView.configuration.userContentController
                controller.removeAllContentRuleLists()
                controller.add(ruleList)
                if grantsApproval {
                    self.approvedRemoteImageHosts = normalizedHosts
                    self.updatePreview()
                    self.onRemoteImagePolicyChange?()
                }
                completion?(true)
            }
        }
    }

    private static func stableRuleHash(_ hosts: Set<String>) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in hosts.sorted().joined(separator: "\0").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func injectContent(_ html: String) {
        latestContentGeneration &+= 1
        let generation = latestContentGeneration
        isContentUpdatePending = true
        let escaped = escapeJSString(html)
        webView.evaluateJavaScript("(function(){ updateContent('\(escaped)'); return null; })()") { _, error in
            guard generation == self.latestContentGeneration else { return }
            self.isContentUpdatePending = false
            if let error {
                NSLog("MarkdownPreviewView JS error: %@", String(describing: error))
            }
            self.flushPendingActionsIfReady()
        }
    }

    private func evaluateWhenReady(_ script: String) {
        guard isReady else {
            pendingActions.append { [weak self] in
                self?.evaluatePreviewScript(script)
            }
            return
        }
        evaluatePreviewScript(script)
    }

    private func evaluatePreviewScript(_ script: String) {
        let wrappedScript = "(function(){ \(script); return null; })()"
        webView.evaluateJavaScript(wrappedScript) { _, error in
            if let error {
                NSLog("MarkdownPreviewView JS error: %@", String(describing: error))
            }
        }
    }

    private func flushPendingActionsIfReady() {
        guard isReady else { return }
        let actions = pendingActions
        pendingActions.removeAll()
        for action in actions {
            action()
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
            return
        }
        flushPendingActionsIfReady()
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
