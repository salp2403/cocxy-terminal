// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserContentView.swift - Embeddable browser panel for workspace splits.

import AppKit
import WebKit
@preconcurrency import Combine
import SwiftUI

// MARK: - Browser Content View

/// NSView that hosts a WKWebView for embedding in split panes.
///
/// Unlike `BrowserPanelView` (a SwiftUI overlay), this is a native AppKit view
/// designed to live inside a `SplitContainer` leaf. It includes a compact URL bar
/// at the top and a WKWebView filling the remaining space.
///
/// ## Layout
///
/// ```
/// +----------------------------------+
/// | [<] [>] [URL bar............] [R] |  <- 32pt toolbar
/// +----------------------------------+
/// |                                  |
/// |         WKWebView                |
/// |                                  |
/// +----------------------------------+
/// ```
///
/// - SeeAlso: `BrowserViewModel` for navigation state.
/// - SeeAlso: `PanelType.browser`
@MainActor
final class BrowserContentView: NSView {

    // MARK: - Properties

    /// The view model driving this browser panel.
    let viewModel: BrowserViewModel

    /// The web view rendering page content.
    private var webView: WKWebView?

    /// The URL text field.
    private var urlField: NSTextField?

    /// Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// KVO observations for WKWebView properties.
    private var observations: [NSKeyValueObservation] = []

    /// Height of the compact navigation bar.
    private static let toolbarHeight: CGFloat = 32

    // MARK: - Browser Feature State

    /// Console capture installed on the web view.
    private var consoleCapture: BrowserConsoleCapture?

    /// Network monitor polling the web view.
    private var networkMonitor: BrowserNetworkMonitor?

    /// Console entries collected from the page.
    private var consoleEntries: [ConsoleEntry] = []

    /// The hosting view for the DevTools panel.
    private var devToolsHostingView: NSView?

    /// The hosting view for the find bar.
    private var findBarHostingView: NSView?

    /// The hosting view for the downloads panel.
    private var downloadsHostingView: NSView?

    /// Web view bottom constraint, adjusted when DevTools or Downloads are visible.
    private var webViewBottomConstraint: NSLayoutConstraint?

    /// Constraint that positions the find bar below the toolbar.
    private var findBarTopConstraint: NSLayoutConstraint?

    /// Reference to the toolbar view for constraint anchoring.
    private var toolbarContainer: NSView?

    // MARK: - Initialization

    init(viewModel: BrowserViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupUI()
        bindViewModel()
        installBrowserInstrumentation()
        // Load after binding so the subscription catches the navigation action.
        DispatchQueue.main.async { [weak viewModel] in
            viewModel?.loadDefaultPage()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BrowserContentView does not support NSCoding")
    }

    deinit {
        let monitor = networkMonitor
        let capture = consoleCapture
        let wv = webView
        // Schedule cleanup on main actor since deinit is nonisolated.
        // observations and cancellables are released by ARC (KVO observations
        // are invalidated on dealloc; AnyCancellable cancels on dealloc).
        Task { @MainActor in
            monitor?.stopMonitoring()
            wv?.navigationDelegate = nil
            if let wv {
                capture?.uninstall(from: wv)
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        // Toolbar container.
        let toolbar = NSView()
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = CocxyColors.mantle.cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        // Back button.
        let backButton = createToolbarButton(
            symbol: "chevron.left",
            action: #selector(goBackAction)
        )
        toolbar.addSubview(backButton)

        // Forward button.
        let forwardButton = createToolbarButton(
            symbol: "chevron.right",
            action: #selector(goForwardAction)
        )
        toolbar.addSubview(forwardButton)

        // Reload button.
        let reloadButton = createToolbarButton(
            symbol: "arrow.clockwise",
            action: #selector(reloadAction)
        )
        toolbar.addSubview(reloadButton)

        // Find button.
        let findButton = createToolbarButton(
            symbol: "magnifyingglass",
            action: #selector(toggleFindBarAction)
        )
        findButton.toolTip = "Find in page"
        toolbar.addSubview(findButton)

        // DevTools button.
        let devToolsButton = createToolbarButton(
            symbol: "wrench.and.screwdriver",
            action: #selector(toggleDevToolsAction)
        )
        devToolsButton.toolTip = "Developer Tools"
        toolbar.addSubview(devToolsButton)

        // URL field.
        let field = NSTextField()
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.textColor = CocxyColors.text
        field.backgroundColor = CocxyColors.surface0.withAlphaComponent(0.6)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.placeholderString = "Enter URL..."
        field.stringValue = viewModel.urlString
        field.target = self
        field.action = #selector(urlFieldAction)
        field.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(field)
        self.urlField = field

        // Layout toolbar buttons.
        backButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        findButton.translatesAutoresizingMaskIntoConstraints = false
        devToolsButton.translatesAutoresizingMaskIntoConstraints = false

        self.toolbarContainer = toolbar

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),

            backButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24),
            backButton.heightAnchor.constraint(equalToConstant: 24),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 24),
            forwardButton.heightAnchor.constraint(equalToConstant: 24),

            field.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: findButton.leadingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 22),

            findButton.trailingAnchor.constraint(equalTo: devToolsButton.leadingAnchor, constant: -2),
            findButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            findButton.widthAnchor.constraint(equalToConstant: 24),
            findButton.heightAnchor.constraint(equalToConstant: 24),

            devToolsButton.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -2),
            devToolsButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            devToolsButton.widthAnchor.constraint(equalToConstant: 24),
            devToolsButton.heightAnchor.constraint(equalToConstant: 24),

            reloadButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -4),
            reloadButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 24),
            reloadButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Web view.
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        addSubview(wv)
        self.webView = wv

        let bottomConstraint = wv.bottomAnchor.constraint(equalTo: bottomAnchor)
        self.webViewBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomConstraint,
        ])

        // KVO on WKWebView properties.
        observations.append(wv.observe(\.canGoBack, options: .new) { [weak self] webView, _ in
            Task { @MainActor in self?.viewModel.canGoBack = webView.canGoBack }
        })
        observations.append(wv.observe(\.canGoForward, options: .new) { [weak self] webView, _ in
            Task { @MainActor in self?.viewModel.canGoForward = webView.canGoForward }
        })
        observations.append(wv.observe(\.isLoading, options: .new) { [weak self] webView, _ in
            Task { @MainActor in self?.viewModel.isLoading = webView.isLoading }
        })
        observations.append(wv.observe(\.title, options: .new) { [weak self] webView, _ in
            Task { @MainActor in self?.viewModel.pageTitle = webView.title ?? "" }
        })
        observations.append(wv.observe(\.url, options: .new) { [weak self] webView, _ in
            Task { @MainActor in
                self?.viewModel.currentURL = webView.url
                if let urlStr = webView.url?.absoluteString {
                    self?.urlField?.stringValue = urlStr
                }
            }
        })
    }

    private func createToolbarButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = image.withSymbolConfiguration(
                .init(pointSize: 12, weight: .medium)
            )
        }
        button.contentTintColor = CocxyColors.subtext0
        button.target = self
        button.action = action
        return button
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        viewModel.navigationActionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.handleNavigation(action)
            }
            .store(in: &cancellables)
    }

    private func handleNavigation(_ action: BrowserViewModel.NavigationAction) {
        guard let webView else { return }
        switch action {
        case .load(let url):
            webView.load(URLRequest(url: url))
        case .goBack:
            webView.goBack()
        case .goForward:
            webView.goForward()
        case .reload:
            webView.reload()
        case .evaluateJS(let script):
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    NSLog("[Cocxy] JS eval error: %@", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func urlFieldAction(_ sender: NSTextField) {
        viewModel.navigate(to: sender.stringValue)
    }

    @objc private func goBackAction(_ sender: Any?) {
        viewModel.goBack()
    }

    @objc private func goForwardAction(_ sender: Any?) {
        viewModel.goForward()
    }

    @objc private func reloadAction(_ sender: Any?) {
        viewModel.reload()
    }

    // MARK: - Browser Instrumentation

    /// Installs console capture and network monitoring on the web view.
    private func installBrowserInstrumentation() {
        guard let webView else { return }

        let capture = BrowserConsoleCapture()
        capture.install(on: webView)
        capture.onNewEntry = { [weak self] entry in
            Task { @MainActor in
                self?.consoleEntries.append(entry)
            }
        }
        self.consoleCapture = capture

        let monitor = BrowserNetworkMonitor()
        monitor.startMonitoring(webView)
        self.networkMonitor = monitor
    }

    // MARK: - Feature Toggle Actions

    @objc private func toggleFindBarAction(_ sender: Any?) {
        if findBarHostingView != nil {
            dismissFindBar()
        } else {
            showFindBar()
        }
    }

    @objc private func toggleDevToolsAction(_ sender: Any?) {
        if devToolsHostingView != nil {
            dismissDevTools()
        } else {
            showDevTools()
        }
    }

    // MARK: - Find Bar

    private func showFindBar() {
        guard findBarHostingView == nil, let toolbarContainer else { return }

        let findBarView = BrowserFindBar(
            searchText: Binding(
                get: { [weak self] in self?.viewModel.findSearchText ?? "" },
                set: { [weak self] in self?.viewModel.findSearchText = $0 }
            ),
            currentMatch: viewModel.findCurrentMatch,
            totalMatches: viewModel.findTotalMatches,
            onSearch: { [weak self] text in self?.viewModel.findInPage(text) },
            onNextMatch: { [weak self] in self?.viewModel.findNextMatch() },
            onPreviousMatch: { [weak self] in self?.viewModel.findPreviousMatch() },
            onDismiss: { [weak self] in self?.dismissFindBar() }
        )
        let hosting = NSHostingView(rootView: findBarView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.heightAnchor.constraint(equalToConstant: 36),
        ])

        if let webView {
            // Remove old top constraint and add new one below find bar.
            for constraint in constraints where
                constraint.firstItem === webView && constraint.firstAnchor == webView.topAnchor {
                constraint.isActive = false
            }
            webView.topAnchor.constraint(equalTo: hosting.bottomAnchor).isActive = true
        }

        self.findBarHostingView = hosting
    }

    private func dismissFindBar() {
        viewModel.clearFind()
        findBarHostingView?.removeFromSuperview()
        findBarHostingView = nil

        // Restore web view top constraint to toolbar.
        if let webView, let toolbarContainer {
            for constraint in constraints where
                constraint.firstItem === webView && constraint.firstAnchor == webView.topAnchor {
                constraint.isActive = false
            }
            webView.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor).isActive = true
        }
    }

    // MARK: - DevTools

    private func showDevTools() {
        guard devToolsHostingView == nil, let networkMonitor else { return }

        let devToolsView = BrowserDevToolsView(
            consoleEntries: consoleEntries,
            networkMonitor: networkMonitor,
            domNodes: [],
            onClearConsole: { [weak self] in self?.consoleEntries.removeAll() },
            onClearNetwork: { [weak self] in self?.networkMonitor?.clear() },
            onRefreshDOM: {},
            onDismiss: { [weak self] in self?.dismissDevTools() }
        )
        let hosting = NSHostingView(rootView: devToolsView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        // Adjust web view bottom to make room.
        webViewBottomConstraint?.isActive = false
        webViewBottomConstraint = webView?.bottomAnchor.constraint(equalTo: hosting.topAnchor)
        webViewBottomConstraint?.isActive = true

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.heightAnchor.constraint(equalToConstant: 200),
        ])

        self.devToolsHostingView = hosting
    }

    private func dismissDevTools() {
        devToolsHostingView?.removeFromSuperview()
        devToolsHostingView = nil

        // Restore web view bottom to the view's bottom.
        webViewBottomConstraint?.isActive = false
        webViewBottomConstraint = webView?.bottomAnchor.constraint(equalTo: bottomAnchor)
        webViewBottomConstraint?.isActive = true
    }
}

// MARK: - WKNavigationDelegate

extension BrowserContentView: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Allow self-signed certificates for localhost dev servers.
        if challenge.protectionSpace.host == "localhost" || challenge.protectionSpace.host == "127.0.0.1" {
            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.viewModel.isLoading = false
            if let url = webView.url?.absoluteString {
                self.viewModel.recordPageVisit(url: url, title: webView.title)
            }
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.showErrorPage(error: error, failedURL: webView.url)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.showErrorPage(error: error, failedURL: webView.url)
        }
    }
}

// MARK: - Error Page

extension BrowserContentView {

    /// Escapes HTML special characters to prevent XSS when embedding
    /// user-controlled strings in HTML error pages.
    private func htmlEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
              .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Loads an HTML error page into the web view when navigation fails.
    ///
    /// Shows the error description and the URL that failed to load,
    /// styled to match the Catppuccin Mocha terminal theme.
    private func showErrorPage(error: Error, failedURL: URL?) {
        let urlDisplay = failedURL?.absoluteString ?? viewModel.urlString
        let errorHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                background: #1e1e2e;
                color: #cdd6f4;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 100vh;
                margin: 0;
                padding: 20px;
                box-sizing: border-box;
            }
            .container {
                text-align: center;
                max-width: 480px;
            }
            .icon { font-size: 48px; margin-bottom: 16px; }
            h1 { font-size: 18px; font-weight: 600; color: #f38ba8; margin: 0 0 8px; }
            .url {
                font-family: ui-monospace, SFMono-Regular, monospace;
                font-size: 12px;
                color: #89b4fa;
                word-break: break-all;
                margin: 12px 0;
                padding: 8px 12px;
                background: #313244;
                border-radius: 6px;
            }
            .detail { font-size: 13px; color: #a6adc8; line-height: 1.5; }
            .hint {
                margin-top: 20px;
                font-size: 12px;
                color: #6c7086;
            }
        </style>
        </head>
        <body>
        <div class="container">
            <div class="icon">&#9888;&#65039;</div>
            <h1>Cannot reach this page</h1>
            <div class="url">\(htmlEscape(urlDisplay))</div>
            <p class="detail">\(htmlEscape(error.localizedDescription))</p>
            <p class="hint">Type a URL in the address bar above or start a dev server.</p>
        </div>
        </body>
        </html>
        """
        webView?.loadHTMLString(errorHTML, baseURL: nil)
    }
}
