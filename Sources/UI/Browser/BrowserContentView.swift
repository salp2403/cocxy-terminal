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

    /// Shared browser profile manager injected by the window controller.
    private let profileManager: BrowserProfileManager?

    /// Called when the user requests the Browser Pro history panel.
    private let onToggleHistory: (() -> Void)?

    /// Called when the user requests the Browser Pro bookmarks panel.
    private let onToggleBookmarks: (() -> Void)?

    /// Local app-language resolver.
    private let localizer: AppLocalizer

    /// The web view rendering page content.
    private var webView: WKWebView?

    /// Button that toggles click-to-capture mode for the current page.
    private var domGrabButton: NSButton?

    /// Handler retained while the current WKWebView is alive.
    private var domGrabHandler: BrowserDOMGrabHandler?

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

    init(
        viewModel: BrowserViewModel,
        profileManager: BrowserProfileManager? = nil,
        onToggleHistory: (() -> Void)? = nil,
        onToggleBookmarks: (() -> Void)? = nil,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.viewModel = viewModel
        self.profileManager = profileManager
        self.onToggleHistory = onToggleHistory
        self.onToggleBookmarks = onToggleBookmarks
        self.localizer = localizer
        super.init(frame: .zero)
        self.viewModel.activeProfileID = profileManager?.activeProfileID ?? viewModel.activeProfileID
        setupUI()
        bindViewModel()
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
                BrowserDOMGrabWebKitSupport.uninstall(from: wv)
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
        reloadButton.toolTip = localized("browser.panel.reload", fallback: "Reload page")

        let historyButton = createToolbarButton(
            symbol: "clock.arrow.circlepath",
            action: #selector(toggleHistoryAction)
        )
        historyButton.toolTip = localized("browser.history.title", fallback: "History")

        let bookmarksButton = createToolbarButton(
            symbol: "bookmark",
            action: #selector(toggleBookmarksAction)
        )
        bookmarksButton.toolTip = localized("browser.bookmarks.title", fallback: "Bookmarks")

        // Find button.
        let findButton = createToolbarButton(
            symbol: "magnifyingglass",
            action: #selector(toggleFindBarAction)
        )
        findButton.toolTip = localized("browser.find.accessibility", fallback: "Find in page")
        toolbar.addSubview(findButton)

        let domGrabButton = createToolbarButton(
            symbol: "cursorarrow.click.2",
            action: #selector(toggleDOMGrabAction)
        )
        domGrabButton.toolTip = localized("browser.panel.domGrab.grab", fallback: "Grab DOM element")
        self.domGrabButton = domGrabButton

        // DevTools button.
        let devToolsButton = createToolbarButton(
            symbol: "wrench.and.screwdriver",
            action: #selector(toggleDevToolsAction)
        )
        devToolsButton.toolTip = localized("browser.devTools.help", fallback: "Developer Tools")

        let rightStack = NSStackView()
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 2
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(rightStack)

        if let profileManager {
            let newProfileNameFormat = localized("browser.profile.newName", fallback: "Profile %d")
            let selector = BrowserProfileSelector(
                profileManager: profileManager,
                onCreateProfile: {
                    profileManager.createProfile(
                        name: String(format: newProfileNameFormat, profileManager.profiles.count + 1),
                        icon: "person.circle",
                        colorHex: "#89B4FA"
                    )
                },
                onManageProfiles: nil,
                localizer: localizer
            )
            let profileHost = NSHostingView(rootView: selector)
            profileHost.translatesAutoresizingMaskIntoConstraints = false
            rightStack.addArrangedSubview(profileHost)
            profileHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
            profileHost.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }

        rightStack.addArrangedSubview(historyButton)
        rightStack.addArrangedSubview(bookmarksButton)
        rightStack.addArrangedSubview(findButton)
        rightStack.addArrangedSubview(domGrabButton)
        rightStack.addArrangedSubview(devToolsButton)
        rightStack.addArrangedSubview(reloadButton)

        // URL field.
        let field = BrowserURLTextField()
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.textColor = CocxyColors.text
        field.backgroundColor = CocxyColors.surface0.withAlphaComponent(0.6)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.placeholderString = localized("browser.content.url.placeholder", fallback: "Enter URL...")
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
        domGrabButton.translatesAutoresizingMaskIntoConstraints = false
        devToolsButton.translatesAutoresizingMaskIntoConstraints = false
        historyButton.translatesAutoresizingMaskIntoConstraints = false
        bookmarksButton.translatesAutoresizingMaskIntoConstraints = false

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
            field.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 22),

            rightStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -4),
            rightStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            findButton.widthAnchor.constraint(equalToConstant: 24),
            findButton.heightAnchor.constraint(equalToConstant: 24),

            domGrabButton.widthAnchor.constraint(equalToConstant: 24),
            domGrabButton.heightAnchor.constraint(equalToConstant: 24),

            devToolsButton.widthAnchor.constraint(equalToConstant: 24),
            devToolsButton.heightAnchor.constraint(equalToConstant: 24),

            historyButton.widthAnchor.constraint(equalToConstant: 24),
            historyButton.heightAnchor.constraint(equalToConstant: 24),

            bookmarksButton.widthAnchor.constraint(equalToConstant: 24),
            bookmarksButton.heightAnchor.constraint(equalToConstant: 24),

            reloadButton.widthAnchor.constraint(equalToConstant: 24),
            reloadButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        installWebViewForActiveProfile(loadCurrentURL: false)
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

    private func installWebViewForActiveProfile(loadCurrentURL: Bool) {
        let previousWebView = webView
        if let previousWebView {
            consoleCapture?.uninstall(from: previousWebView)
            BrowserDOMGrabWebKitSupport.uninstall(from: previousWebView)
        }
        networkMonitor?.stopMonitoring()
        observations.removeAll()
        previousWebView?.navigationDelegate = nil
        previousWebView?.removeFromSuperview()
        webViewBottomConstraint = nil

        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        if let profileID = viewModel.activeProfileID {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: profileID)
        }
        let domGrabHandler = BrowserDOMGrabHandler()
        domGrabHandler.onPayload = { [weak viewModel] payload in
            viewModel?.handleDOMGrabPayload(payload)
        }
        BrowserDOMGrabWebKitSupport.install(on: config, handler: domGrabHandler)
        self.domGrabHandler = domGrabHandler

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        BrowserWebViewAppearance.configure(wv)
        addSubview(wv, positioned: .below, relativeTo: toolbarContainer)
        webView = wv

        let topAnchor = findBarHostingView?.bottomAnchor ?? toolbarContainer?.bottomAnchor ?? self.topAnchor
        let bottomAnchor = devToolsHostingView?.topAnchor ?? downloadsHostingView?.topAnchor ?? self.bottomAnchor
        let bottomConstraint = wv.bottomAnchor.constraint(equalTo: bottomAnchor)
        webViewBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: topAnchor),
            wv.leadingAnchor.constraint(equalTo: leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomConstraint,
        ])

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
            Task { @MainActor in self?.viewModel.updateActiveTabTitle(webView.title ?? "") }
        })
        observations.append(wv.observe(\.url, options: .new) { [weak self] webView, _ in
            Task { @MainActor in
                self?.viewModel.currentURL = webView.url
                if let urlStr = webView.url?.absoluteString {
                    self?.urlField?.stringValue = urlStr
                }
            }
        })

        installBrowserInstrumentation()

        if loadCurrentURL, let url = viewModel.currentURL {
            wv.load(URLRequest(url: url))
        }
        BrowserDOMGrabWebKitSupport.setEnabled(viewModel.isDOMGrabActive, on: wv)
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        viewModel.navigationActionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.handleNavigation(action)
            }
            .store(in: &cancellables)

        viewModel.$isDOMGrabActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.updateDOMGrabButton(active: active)
            }
            .store(in: &cancellables)

        profileManager?.$activeProfileID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profileID in
                guard let self, self.viewModel.activeProfileID != profileID else { return }
                self.viewModel.activeProfileID = profileID
                if self.findBarHostingView != nil {
                    self.dismissFindBar()
                }
                if self.devToolsHostingView != nil {
                    self.dismissDevTools()
                }
                self.installWebViewForActiveProfile(loadCurrentURL: true)
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
        case .setDOMGrabEnabled(let enabled):
            BrowserDOMGrabWebKitSupport.setEnabled(enabled, on: webView)
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

    @objc private func toggleDOMGrabAction(_ sender: Any?) {
        viewModel.toggleDOMGrabMode()
    }

    @objc private func toggleHistoryAction(_ sender: Any?) {
        onToggleHistory?()
    }

    @objc private func toggleBookmarksAction(_ sender: Any?) {
        onToggleBookmarks?()
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

    private func updateDOMGrabButton(active: Bool) {
        domGrabButton?.contentTintColor = active
            ? CocxyColors.blue
            : CocxyColors.subtext0
        domGrabButton?.toolTip = active
            ? localized("browser.panel.domGrab.stop", fallback: "Stop DOM grab")
            : localized("browser.panel.domGrab.grab", fallback: "Grab DOM element")
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
            onDismiss: { [weak self] in self?.dismissFindBar() },
            localizer: localizer
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
            onDismiss: { [weak self] in self?.dismissDevTools() },
            localizer: localizer
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

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserContentView: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard BrowserNavigationPolicy.allows(navigationAction.request.url) else {
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
            BrowserDOMGrabWebKitSupport.setEnabled(
                self.viewModel.isDOMGrabActive,
                on: webView
            )
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

    /// Loads an HTML error page into the web view when navigation fails.
    ///
    /// Shows the error description and the URL that failed to load,
    /// styled to match the Catppuccin Mocha terminal theme.
    private func showErrorPage(error: Error, failedURL: URL?) {
        guard let webView else { return }
        BrowserErrorPageRenderer.render(
            error: error,
            failedURL: failedURL,
            fallbackURLString: viewModel.urlString,
            localizer: localizer,
            into: webView
        )
    }
}
