// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserViewModel.swift - Presentation logic for the in-app browser panel.

import Foundation
import Combine

// MARK: - Browser View Model

/// Presentation logic for the in-app browser panel.
///
/// Manages URL navigation state, loading indicators, navigation history,
/// and a multi-tab browsing experience. Each tab maintains its own URL
/// and title independently.
///
/// ## Default Behavior
///
/// On first open, the browser creates a single tab navigating to
/// `http://localhost:3000` -- the most common local dev server address.
///
/// ## URL Normalization
///
/// When the user types a URL without a scheme, the view model prepends `https://`.
/// This handles the common case of typing `example.com` instead of `https://example.com`.
///
/// - SeeAlso: `BrowserPanelView`
/// - SeeAlso: `BrowserTab`
@MainActor
final class BrowserViewModel: ObservableObject {

    // MARK: - Published State

    /// The text currently shown in the URL bar input field.
    @Published var urlString: String = "http://localhost:3000"

    /// The URL currently loaded in the web view. Nil when no page is loaded.
    @Published var currentURL: URL?

    /// Whether the web view is currently loading a page.
    @Published var isLoading: Bool = false

    /// Whether backward navigation is available in the web view history.
    @Published var canGoBack: Bool = false

    /// Whether forward navigation is available in the web view history.
    @Published var canGoForward: Bool = false

    /// The title of the currently loaded page.
    @Published var pageTitle: String = ""

    // MARK: - Multi-Tab State

    /// All open browser tabs.
    @Published var browserTabs: [BrowserTab] = []

    /// The ID of the currently active browser tab.
    @Published var activeTabID: UUID?

    // MARK: - Navigation Actions

    /// Navigation action signals consumed by the WKWebView wrapper.
    /// The coordinator reads these to trigger navigation, back, forward, and reload.
    enum NavigationAction {
        case load(URL)
        case goBack
        case goForward
        case reload
        case evaluateJS(String)
    }

    /// Publisher that emits navigation actions for the web view coordinator to observe.
    let navigationActionSubject = PassthroughSubject<NavigationAction, Never>()

    // MARK: - Initialization

    init() {
        let initialTab = BrowserTab()
        browserTabs = [initialTab]
        activeTabID = initialTab.id
    }

    // MARK: - Navigation

    /// Validates and navigates to the given URL string.
    ///
    /// Prepends `https://` when no scheme is present. Ignores empty strings
    /// and strings that cannot be parsed as URLs after normalization.
    ///
    /// - Parameter rawInput: The URL string to navigate to.
    func navigate(to rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = normalizeURLString(trimmed)
        guard let url = URL(string: normalized) else { return }

        urlString = normalized
        currentURL = url

        // Sync URL to the active tab.
        if let index = browserTabs.firstIndex(where: { $0.id == activeTabID }) {
            browserTabs[index].url = url
        }

        navigationActionSubject.send(.load(url))
    }

    /// Navigates the web view backward in history.
    func goBack() {
        navigationActionSubject.send(.goBack)
    }

    /// Navigates the web view forward in history.
    func goForward() {
        navigationActionSubject.send(.goForward)
    }

    /// Reloads the current page in the web view.
    func reload() {
        navigationActionSubject.send(.reload)
    }

    /// Loads the default URL (`http://localhost:3000`).
    ///
    /// Called when the panel first appears to provide immediate utility.
    func loadDefaultPage() {
        navigate(to: urlString)
    }

    // MARK: - Multi-Tab Management

    /// Adds a new browser tab and makes it active.
    ///
    /// - Parameter url: The initial URL for the new tab. Defaults to `http://localhost:3000`.
    func addBrowserTab(url: URL = BrowserTab.defaultURL) {
        let newTab = BrowserTab(url: url)
        browserTabs.append(newTab)
        activeTabID = newTab.id
        urlString = url.absoluteString
        currentURL = url
        pageTitle = ""
    }

    /// Closes the browser tab with the given ID.
    ///
    /// If only one tab remains, this is a no-op to prevent an empty browser.
    /// When the active tab is closed, the nearest neighbor becomes active.
    ///
    /// - Parameter tabID: The ID of the tab to close.
    func closeBrowserTab(_ tabID: UUID) {
        guard browserTabs.count > 1 else { return }
        guard let closingIndex = browserTabs.firstIndex(where: { $0.id == tabID }) else { return }

        let wasActive = tabID == activeTabID
        browserTabs.remove(at: closingIndex)

        if wasActive {
            // Activate the nearest neighbor (prefer the tab to the left).
            let newIndex = min(closingIndex, browserTabs.count - 1)
            let newActiveTab = browserTabs[newIndex]
            activeTabID = newActiveTab.id
            urlString = newActiveTab.url.absoluteString
            currentURL = newActiveTab.url
            pageTitle = newActiveTab.title
        }
    }

    /// Switches to the browser tab with the given ID.
    ///
    /// - Parameter tabID: The ID of the tab to activate. No-op if not found.
    func selectBrowserTab(_ tabID: UUID) {
        guard let tab = browserTabs.first(where: { $0.id == tabID }) else { return }
        activeTabID = tab.id
        urlString = tab.url.absoluteString
        currentURL = tab.url
        pageTitle = tab.title
    }

    /// Updates the title of the active tab.
    ///
    /// Called by the WKWebView coordinator when the page title changes.
    ///
    /// - Parameter title: The new page title.
    func updateActiveTabTitle(_ title: String) {
        pageTitle = title
        if let index = browserTabs.firstIndex(where: { $0.id == activeTabID }) {
            browserTabs[index].title = title
        }
    }

    // MARK: - Scriptable API

    /// Evaluates JavaScript in the active browser tab.
    ///
    /// The result is handled asynchronously by the WKWebView coordinator.
    /// Available only via local Unix socket (UID-authenticated).
    ///
    /// - Parameter script: The JavaScript code to evaluate.
    func evaluateJavaScript(_ script: String) {
        navigationActionSubject.send(.evaluateJS(script))
    }

    /// Returns the current browser state as a dictionary of string values.
    ///
    /// All values are serialized to strings for compatibility with the
    /// socket protocol wire format (`[String: String]`).
    func getState() -> [String: String] {
        [
            "url": currentURL?.absoluteString ?? "",
            "title": pageTitle,
            "isLoading": "\(isLoading)",
            "canGoBack": "\(canGoBack)",
            "canGoForward": "\(canGoForward)",
            "tabCount": "\(browserTabs.count)",
            "activeTabID": activeTabID?.uuidString ?? ""
        ]
    }

    /// Returns a serializable list of browser tabs.
    ///
    /// Each tab is represented as a dictionary with `id`, `url`, `title`,
    /// and `isActive` keys, matching the socket response format.
    func getTabList() -> [[String: String]] {
        browserTabs.map { tab in
            [
                "id": tab.id.uuidString,
                "url": tab.url.absoluteString,
                "title": tab.title,
                "isActive": tab.id == activeTabID ? "true" : "false"
            ]
        }
    }

    // MARK: - URL Normalization

    /// Normalizes a raw URL input by adding a scheme when missing.
    ///
    /// - If the input starts with `http://` or `https://`, returns it unchanged.
    /// - If the input looks like a localhost address, prepends `http://`.
    /// - Otherwise, prepends `https://`.
    ///
    /// - Parameter input: The raw URL string from the text field.
    /// - Returns: A normalized URL string with a scheme.
    private func normalizeURLString(_ input: String) -> String {
        let lowered = input.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return input
        }
        if lowered.hasPrefix("localhost") || lowered.hasPrefix("127.0.0.1") {
            return "http://\(input)"
        }
        return "https://\(input)"
    }
}
