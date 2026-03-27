// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserPanelView.swift - In-app browser panel with WKWebView.

import SwiftUI
import WebKit
import Combine

// MARK: - Browser Panel View

/// A side panel embedding a WKWebView for browsing web content without leaving the terminal.
///
/// ## Layout
///
/// ```
/// +-- Browser ----------------------------+
/// | [<] [>] [URL bar...............] [R] [x]|
/// |                                        |
/// |  +----------------------------------+  |
/// |  |                                  |  |
/// |  |         WKWebView               |  |
/// |  |                                  |  |
/// |  +----------------------------------+  |
/// +----------------------------------------+
/// ```
///
/// ## Behavior
///
/// - Toggle with Cmd+Shift+B.
/// - Fixed width: 480pt.
/// - Slides in from the right edge.
/// - Default URL: `http://localhost:3000`.
/// - URL bar accepts freeform input; scheme is added automatically.
///
/// - SeeAlso: `BrowserViewModel`
/// - SeeAlso: `WebViewRepresentable`
struct BrowserPanelView: View {

    @ObservedObject var viewModel: BrowserViewModel
    var onDismiss: () -> Void

    /// Fixed width of the browser panel.
    static let panelWidth: CGFloat = 480

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            browserTabBar
            Divider()
            toolbarView
            Divider()
            webContentView
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Browser Panel")
        .onAppear {
            viewModel.loadDefaultPage()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Browser")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close browser panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Browser Tab Bar

    private var browserTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.browserTabs) { tab in
                    browserTabItem(tab)
                }

                // Add tab button.
                Button(action: { viewModel.addBrowserTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .frame(width: 24, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add browser tab")

                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
        .background(Color(nsColor: CocxyColors.crust))
    }

    private func browserTabItem(_ tab: BrowserTab) -> some View {
        let isActive = tab.id == viewModel.activeTabID
        let showClose = viewModel.browserTabs.count > 1

        return HStack(spacing: 4) {
            Text(tab.title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(
                    isActive
                        ? Color(nsColor: CocxyColors.text)
                        : Color(nsColor: CocxyColors.subtext0)
                )
                .lineLimit(1)
                .truncationMode(.tail)

            if showClose {
                Button(action: { viewModel.closeBrowserTab(tab.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close browser tab")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive
                      ? Color(nsColor: CocxyColors.surface0)
                      : Color.clear
                )
        )
        .onTapGesture {
            viewModel.selectBrowserTab(tab.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Browser tab: \(tab.title)")
    }

    // MARK: - Toolbar (URL bar + navigation)

    private var toolbarView: some View {
        HStack(spacing: 6) {
            navigationButtons
            urlField
            reloadButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            Button(action: { viewModel.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(
                        viewModel.canGoBack
                            ? Color(nsColor: CocxyColors.text)
                            : Color(nsColor: CocxyColors.surface2)
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .disabled(!viewModel.canGoBack)
            .accessibilityLabel("Go back")
            .accessibilityValue(viewModel.canGoBack ? "available" : "unavailable")

            Button(action: { viewModel.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(
                        viewModel.canGoForward
                            ? Color(nsColor: CocxyColors.text)
                            : Color(nsColor: CocxyColors.surface2)
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .disabled(!viewModel.canGoForward)
            .accessibilityLabel("Go forward")
            .accessibilityValue(viewModel.canGoForward ? "available" : "unavailable")
        }
    }

    private var urlField: some View {
        URLBarField(
            text: $viewModel.urlString,
            onSubmit: { viewModel.navigate(to: viewModel.urlString) }
        )
        .frame(height: 26)
        .accessibilityLabel("URL input field")
    }

    private var reloadButton: some View {
        Button(action: { viewModel.reload() }) {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(nsColor: CocxyColors.text))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .accessibilityLabel(viewModel.isLoading ? "Loading" : "Reload page")
    }

    // MARK: - Web Content

    private var webContentView: some View {
        Group {
            if viewModel.currentURL != nil {
                WebViewRepresentable(viewModel: viewModel)
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 32))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("No page loaded")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("Enter a URL above to browse.\nDefault: localhost:3000")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - URL Bar Field (NSTextField wrapper)

/// Native NSTextField wrapper that reliably captures Enter key presses.
///
/// SwiftUI's `TextField.onSubmit` can fail when embedded inside
/// `NSHostingView` overlays due to first responder chain issues.
/// This wrapper uses `NSTextField` directly with a delegate to
/// guarantee that pressing Enter always triggers navigation.
struct URLBarField: NSViewRepresentable {

    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        field.textColor = CocxyColors.text
        field.backgroundColor = CocxyColors.surface0
        field.drawsBackground = true
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .default
        field.placeholderString = "Search or enter URL"
        field.stringValue = text
        field.cell?.truncatesLastVisibleLine = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.borderWidth = 1
        field.layer?.borderColor = CocxyColors.surface1.cgColor
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - WKWebView Representable

/// Bridges WKWebView into SwiftUI via `NSViewRepresentable`.
///
/// Uses the Coordinator pattern to act as `WKNavigationDelegate`, updating
/// the `BrowserViewModel` properties (isLoading, canGoBack, canGoForward,
/// pageTitle, currentURL) in response to web view navigation events.
///
/// The coordinator subscribes to `BrowserViewModel.navigationActionSubject`
/// to receive load, back, forward, and reload commands from the view model.
struct WebViewRepresentable: NSViewRepresentable {

    @ObservedObject var viewModel: BrowserViewModel

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif

        // Set dark background while page loads.
        webView.wantsLayer = true
        webView.layer?.backgroundColor = CocxyColors.base.cgColor

        context.coordinator.webView = webView
        context.coordinator.subscribeToNavigationActions()

        // Navigation is driven by the onAppear -> loadDefaultPage ->
        // navigationActionSubject flow. No direct load here to avoid
        // double-loading the URL.

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // State updates are driven by the coordinator via Combine subscriptions,
        // not by SwiftUI diffs. This avoids re-entrant navigation loops.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {

        private let viewModel: BrowserViewModel
        private var cancellables = Set<AnyCancellable>()
        weak var webView: WKWebView?

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        /// Subscribes to the view model's navigation action subject.
        ///
        /// Each emitted action is dispatched to the corresponding WKWebView method.
        /// Runs on `DispatchQueue.main` to ensure UI safety.
        func subscribeToNavigationActions() {
            viewModel.navigationActionSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak self] action in
                    guard let webView = self?.webView else { return }
                    switch action {
                    case .load(let url):
                        let request = URLRequest(url: url)
                        webView.load(request)
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
                .store(in: &cancellables)
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.viewModel.isLoading = true
                self.syncNavigationState(from: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.viewModel.isLoading = false
                self.syncNavigationState(from: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.viewModel.isLoading = false
                self.syncNavigationState(from: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                self.viewModel.isLoading = false
                self.syncNavigationState(from: webView)
            }
        }

        /// Filters navigation to only allow http/https schemes.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// Handles target=_blank links by loading them in the same web view.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// Allows HTTPS certificate errors for localhost dev servers.
        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.host == "localhost" || challenge.protectionSpace.host == "127.0.0.1",
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        // MARK: - State Sync

        /// Synchronizes the view model with the current WKWebView state.
        ///
        /// Called after each navigation event to keep the URL bar, page title,
        /// and navigation button states in sync with the web view.
        @MainActor
        private func syncNavigationState(from webView: WKWebView) {
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward
            let title = webView.title ?? ""
            viewModel.updateActiveTabTitle(title)
            if let url = webView.url {
                viewModel.currentURL = url
                viewModel.urlString = url.absoluteString
            }
        }
    }
}
