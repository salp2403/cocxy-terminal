// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserViewModel.swift - Presentation logic for the in-app browser panel.

import Foundation
import Combine

// MARK: - Scriptable Browser Results

struct BrowserScriptEvaluationResult: Equatable, Sendable {
    let value: String?
    let error: String?

    static func success(_ value: String) -> BrowserScriptEvaluationResult {
        BrowserScriptEvaluationResult(value: value, error: nil)
    }

    static func failure(_ error: String) -> BrowserScriptEvaluationResult {
        BrowserScriptEvaluationResult(value: nil, error: error)
    }
}

enum BrowserScreenshotCaptureResult: Equatable, Sendable {
    case dataURL(String, byteCount: Int)
    case file(path: String, byteCount: Int)
    case failure(String)
}

enum BrowserCookieImportResult: Equatable, Sendable {
    case success
    case failure(String)
}

struct BrowserConsoleSnapshotEntry: Equatable, Sendable {
    let level: String
    let message: String
    let timestamp: Date
}

struct BrowserInitScript: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: String
    let createdAt: Date

    var length: Int {
        source.count
    }
}

enum BrowserDialogKind: String, Equatable, Sendable {
    case alert
    case confirm
    case prompt
}

enum BrowserDialogState: String, Equatable, Sendable {
    case pending
    case accepted
    case dismissed
}

enum BrowserDialogResolution: Equatable, Sendable {
    case accept(promptText: String?)
    case dismiss
}

struct BrowserDialogItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: BrowserDialogKind
    let message: String
    let defaultText: String?
    let url: String?
    let createdAt: Date
    var state: BrowserDialogState
    var resolvedAt: Date?
}

struct RemoteBrowserRouteRequest: Equatable, Sendable {
    let remotePort: Int
    let scheme: String
    let path: String
}

enum RemoteBrowserNoticeKind: String, Equatable, Sendable {
    case missingForward
    case proxyConnecting
    case proxyDegraded
    case proxyFailed
    case navigationFailed
}

struct RemoteBrowserNotice: Equatable, Sendable {
    let kind: RemoteBrowserNoticeKind
    let remoteProfile: RemoteBrowserProfile
    let routeRequest: RemoteBrowserRouteRequest?
    let failedURLString: String?
    let detail: String?
}

final class BrowserAutomationBridgeStore: @unchecked Sendable {
    typealias ScriptEvaluator = (String, TimeInterval) -> BrowserScriptEvaluationResult
    typealias ScreenshotCapturer = (String?, TimeInterval) -> BrowserScreenshotCaptureResult
    typealias CookieImporter = (BrowserImportedCookie, UUID, TimeInterval) -> BrowserCookieImportResult
    typealias InitScriptInstaller = (String, TimeInterval) -> BrowserScriptEvaluationResult

    private let lock = NSLock()
    private var evaluator: ScriptEvaluator?
    private var capturer: ScreenshotCapturer?
    private var cookieImporterValue: CookieImporter?
    private var initScriptInstallerValue: InitScriptInstaller?

    var scriptEvaluator: ScriptEvaluator? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return evaluator
        }
        set {
            lock.lock()
            evaluator = newValue
            lock.unlock()
        }
    }

    var screenshotCapturer: ScreenshotCapturer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return capturer
        }
        set {
            lock.lock()
            capturer = newValue
            lock.unlock()
        }
    }

    var cookieImporter: CookieImporter? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return cookieImporterValue
        }
        set {
            lock.lock()
            cookieImporterValue = newValue
            lock.unlock()
        }
    }

    var initScriptInstaller: InitScriptInstaller? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return initScriptInstallerValue
        }
        set {
            lock.lock()
            initScriptInstallerValue = newValue
            lock.unlock()
        }
    }

    func evaluate(
        script: String,
        timeout: TimeInterval
    ) -> BrowserScriptEvaluationResult? {
        guard let scriptEvaluator else { return nil }
        return scriptEvaluator(script, timeout)
    }

    func captureScreenshot(
        outputPath: String?,
        timeout: TimeInterval
    ) -> BrowserScreenshotCaptureResult? {
        guard let screenshotCapturer else { return nil }
        return screenshotCapturer(outputPath, timeout)
    }

    func importCookie(
        _ cookie: BrowserImportedCookie,
        profileID: UUID,
        timeout: TimeInterval
    ) -> BrowserCookieImportResult? {
        guard let cookieImporter else { return nil }
        return cookieImporter(cookie, profileID, timeout)
    }

    func installInitScript(
        _ script: String,
        timeout: TimeInterval
    ) -> BrowserScriptEvaluationResult? {
        guard let initScriptInstaller else { return nil }
        return initScriptInstaller(script, timeout)
    }
}

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

    // MARK: - Downloads State

    /// Active and completed downloads tracked by the browser.
    @Published var downloads: [DownloadItem] = []

    /// User-added scripts injected at document start for future page loads.
    @Published private(set) var initScripts: [BrowserInitScript] = []

    /// JavaScript alert/confirm/prompt dialogs captured from WebKit.
    @Published private(set) var browserDialogs: [BrowserDialogItem] = []

    // MARK: - Find-in-Page State

    /// The current find-in-page search text.
    @Published var findSearchText: String = ""

    /// The 1-based index of the currently highlighted match.
    @Published var findCurrentMatch: Int = 0

    /// Total number of matches found on the page.
    @Published var findTotalMatches: Int = 0

    /// Whether click-to-capture mode is active in the current browser page.
    @Published var isDOMGrabActive: Bool = false

    /// Optional remote workspace context for the active browser surface.
    ///
    /// Nil means the browser is local. Non-nil is metadata only; proxy
    /// lifecycle stays owned by RemoteWorkspace services.
    @Published private(set) var activeRemoteBrowserProfile: RemoteBrowserProfile?

    /// Actionable notice for remote route failures or degraded proxy state.
    @Published private(set) var remoteBrowserNotice: RemoteBrowserNotice?

    // MARK: - Navigation Actions

    /// Navigation action signals consumed by the WKWebView wrapper.
    /// The coordinator reads these to trigger navigation, back, forward, reload,
    /// JavaScript evaluation, and DOM-grab state changes.
    enum NavigationAction {
        case load(URL)
        case goBack
        case goForward
        case reload
        case evaluateJS(String)
        case setDOMGrabEnabled(Bool)
    }

    /// Publisher that emits navigation actions for the web view coordinator to observe.
    let navigationActionSubject = PassthroughSubject<NavigationAction, Never>()

    // MARK: - History Recording

    /// History store for recording page visits. Injected by the window controller.
    var historyStore: BrowserHistoryStoring?

    /// Callback invoked when the WebKit DOM-grab bridge captures an element.
    var onDOMGrabPayload: ((BrowserDOMGrabPayload) -> Void)?

    /// Synchronous bridge used by the local socket API for browser automation.
    ///
    /// WKWebView is owned by the UI layer, so the view model keeps only this
    /// injected closure. Existing fire-and-forget JavaScript still goes through
    /// `navigationActionSubject` when this bridge is not installed.
    nonisolated let automationBridge = BrowserAutomationBridgeStore()

    private var browserDialogCompletions: [UUID: (BrowserDialogResolution) -> Void] = [:]
    private var lastRemoteBrowserRouteRequest: RemoteBrowserRouteRequest?

    var scriptEvaluator: BrowserAutomationBridgeStore.ScriptEvaluator? {
        get { automationBridge.scriptEvaluator }
        set { automationBridge.scriptEvaluator = newValue }
    }

    /// Native screenshot bridge installed by the active WebKit host.
    var screenshotCapturer: BrowserAutomationBridgeStore.ScreenshotCapturer? {
        get { automationBridge.screenshotCapturer }
        set { automationBridge.screenshotCapturer = newValue }
    }

    /// Native cookie import bridge installed by the active WebKit host.
    var cookieImporter: BrowserAutomationBridgeStore.CookieImporter? {
        get { automationBridge.cookieImporter }
        set { automationBridge.cookieImporter = newValue }
    }

    /// Native init-script bridge installed by the active WebKit host.
    var initScriptInstaller: BrowserAutomationBridgeStore.InitScriptInstaller? {
        get { automationBridge.initScriptInstaller }
        set { automationBridge.initScriptInstaller = newValue }
    }

    private(set) var consoleSnapshotEntries: [BrowserConsoleSnapshotEntry] = []

    /// The active browser profile ID, used to associate visits and WebKit
    /// storage with a profile. Published so active browser hosts can rebuild
    /// their `WKWebView` with the matching `WKWebsiteDataStore`.
    @Published var activeProfileID: UUID?

    /// Records a page visit to the history store.
    ///
    /// Silently ignores errors to avoid disrupting navigation.
    /// Internal URLs (about:blank, error pages) are not recorded.
    ///
    /// - Parameters:
    ///   - url: The URL string of the visited page.
    ///   - title: The page title, if available.
    func recordPageVisit(url: String, title: String?) {
        guard let historyStore else { return }
        // Skip internal/blank URLs that are not real visits.
        let lowered = url.lowercased()
        guard !lowered.isEmpty,
              !lowered.hasPrefix("about:"),
              URL(string: url)?.scheme != nil else { return }

        let profileID = activeProfileID ?? UUID()
        do {
            try historyStore.recordVisit(url: url, title: title, profileID: profileID)
        } catch {
            NSLog("[BrowserViewModel] Failed to record visit: %@", String(describing: error))
        }
    }

    /// Switches the active browser profile and reloads the current page inside
    /// the newly selected WebKit data store.
    ///
    /// The UI host owns the actual `WKWebView` lifecycle; publishing this value
    /// lets the host recreate the web view with `WKWebsiteDataStore` scoped to
    /// the selected profile. Hosts also perform a direct initial load after
    /// recreation so the page lands in the correct profile even if this signal
    /// races ahead of the new subscriber.
    func activateProfile(_ profileID: UUID?) {
        guard activeProfileID != profileID else { return }
        activeProfileID = profileID
        navigationActionSubject.send(.load(currentURL ?? BrowserTab.defaultURL))
    }

    func attachRemoteBrowserProfile(_ remoteProfile: RemoteBrowserProfile) {
        activeRemoteBrowserProfile = remoteProfile
        remoteBrowserNotice = nil
        publishProxyNoticeIfNeeded(for: remoteProfile)
    }

    @discardableResult
    func openRemoteForward(
        _ remoteProfile: RemoteBrowserProfile,
        remotePort: Int,
        scheme: String = "http",
        path: String = "/"
    ) -> RemoteBrowserRoute? {
        let request = RemoteBrowserRouteRequest(remotePort: remotePort, scheme: scheme, path: path)
        lastRemoteBrowserRouteRequest = request

        guard let route = remoteProfile.route(
            forRemotePort: remotePort,
            scheme: scheme,
            path: path
        ) else {
            remoteBrowserNotice = RemoteBrowserNotice(
                kind: .missingForward,
                remoteProfile: remoteProfile,
                routeRequest: request,
                failedURLString: nil,
                detail: nil
            )
            return nil
        }
        activeRemoteBrowserProfile = remoteProfile
        navigate(to: route.localURL.absoluteString)
        remoteBrowserNotice = nil
        publishProxyNoticeIfNeeded(for: remoteProfile)
        return route
    }

    func clearRemoteBrowserProfile() {
        activeRemoteBrowserProfile = nil
        remoteBrowserNotice = nil
        lastRemoteBrowserRouteRequest = nil
    }

    func updateRemoteBrowserProxyState(_ proxyState: ProxyState) {
        guard var remoteProfile = activeRemoteBrowserProfile else { return }
        remoteProfile.apply(proxyState: proxyState)
        activeRemoteBrowserProfile = remoteProfile
        publishProxyNoticeIfNeeded(for: remoteProfile)
    }

    func recordRemoteBrowserNavigationFailure(error: Error, failedURL: URL?) {
        guard let remoteProfile = activeRemoteBrowserProfile else { return }
        let request = routeRequest(forLocalURL: failedURL) ?? lastRemoteBrowserRouteRequest
        remoteBrowserNotice = RemoteBrowserNotice(
            kind: .navigationFailed,
            remoteProfile: remoteProfile,
            routeRequest: request,
            failedURLString: failedURL?.absoluteString ?? currentURL?.absoluteString ?? urlString,
            detail: error.localizedDescription
        )
    }

    func recordRemoteBrowserNavigationSucceeded(url: URL?) {
        guard activeRemoteBrowserProfile != nil else { return }
        switch remoteBrowserNotice?.kind {
        case .missingForward, .navigationFailed:
            remoteBrowserNotice = nil
        case .proxyConnecting, .proxyDegraded, .proxyFailed, nil:
            break
        }
    }

    @discardableResult
    func retryRemoteBrowserNotice() -> RemoteBrowserRoute? {
        guard let notice = remoteBrowserNotice else { return nil }
        guard let request = notice.routeRequest else {
            reload()
            return nil
        }

        let profile = activeRemoteBrowserProfile ?? notice.remoteProfile
        return openRemoteForward(
            profile,
            remotePort: request.remotePort,
            scheme: request.scheme,
            path: request.path
        )
    }

    func dismissRemoteBrowserNotice() {
        remoteBrowserNotice = nil
    }

    private func routeRequest(forLocalURL url: URL?) -> RemoteBrowserRouteRequest? {
        guard let url,
              let localPort = url.port,
              let remoteProfile = activeRemoteBrowserProfile,
              let match = remoteProfile.localForwardedPorts.first(where: { $0.value == localPort }) else {
            return nil
        }

        let path = url.path.isEmpty ? "/" : url.path
        return RemoteBrowserRouteRequest(
            remotePort: match.key,
            scheme: url.scheme ?? "http",
            path: path
        )
    }

    private func publishProxyNoticeIfNeeded(for remoteProfile: RemoteBrowserProfile) {
        let kind: RemoteBrowserNoticeKind?
        switch remoteProfile.proxyHealth {
        case .connecting:
            kind = .proxyConnecting
        case .degraded:
            kind = .proxyDegraded
        case .failed:
            kind = .proxyFailed
        case .disconnected, .active:
            kind = nil
        }

        guard let kind else {
            if remoteBrowserNotice?.kind != .missingForward,
               remoteBrowserNotice?.kind != .navigationFailed {
                remoteBrowserNotice = nil
            }
            return
        }

        remoteBrowserNotice = RemoteBrowserNotice(
            kind: kind,
            remoteProfile: remoteProfile,
            routeRequest: lastRemoteBrowserRouteRequest,
            failedURLString: currentURL?.absoluteString,
            detail: nil
        )
    }

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
        let trimmed = Self.repairedEditableURLInput(rawInput)
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
        navigationActionSubject.send(.load(url))
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
            navigationActionSubject.send(.load(newActiveTab.url))
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
        navigationActionSubject.send(.load(tab.url))
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

    func evaluateJavaScriptForResult(
        _ script: String,
        timeout: TimeInterval = 3,
        requiresBridge: Bool = false
    ) -> BrowserScriptEvaluationResult {
        guard let scriptEvaluator else {
            navigationActionSubject.send(.evaluateJS(script))
            return requiresBridge
                ? .failure("Browser page is not ready for synchronous automation")
                : .success("")
        }
        return scriptEvaluator(script, timeout)
    }

    @discardableResult
    func addInitScript(_ source: String) -> BrowserInitScript {
        let script = BrowserInitScript(id: UUID(), source: source, createdAt: Date())
        initScripts.append(script)
        return script
    }

    func getInitScriptList() -> [[String: String]] {
        let formatter = ISO8601DateFormatter()
        return initScripts.map { script in
            [
                "id": script.id.uuidString,
                "length": "\(script.length)",
                "createdAt": formatter.string(from: script.createdAt)
            ]
        }
    }

    @discardableResult
    func recordJavaScriptDialog(
        kind: BrowserDialogKind,
        message: String,
        defaultText: String? = nil,
        url: String? = nil,
        completion: @escaping (BrowserDialogResolution) -> Void
    ) -> BrowserDialogItem {
        let item = BrowserDialogItem(
            id: UUID(),
            kind: kind,
            message: message,
            defaultText: defaultText,
            url: url,
            createdAt: Date(),
            state: .pending,
            resolvedAt: nil
        )
        browserDialogs.append(item)
        browserDialogCompletions[item.id] = completion
        pruneBrowserDialogHistory()
        return item
    }

    func isJavaScriptDialogPending(_ id: UUID) -> Bool {
        browserDialogs.contains { $0.id == id && $0.state == .pending }
    }

    func resolveJavaScriptDialog(
        id rawID: String?,
        resolution: BrowserDialogResolution
    ) -> BrowserDialogItem? {
        let targetID: UUID?
        if let rawID, !rawID.isEmpty {
            guard let parsed = UUID(uuidString: rawID) else { return nil }
            targetID = parsed
        } else {
            targetID = browserDialogs.first { $0.state == .pending }?.id
        }
        guard let targetID,
              let index = browserDialogs.firstIndex(where: { $0.id == targetID && $0.state == .pending }) else {
            return nil
        }

        let newState: BrowserDialogState
        switch resolution {
        case .accept:
            newState = .accepted
        case .dismiss:
            newState = .dismissed
        }
        browserDialogs[index].state = newState
        browserDialogs[index].resolvedAt = Date()

        let completion = browserDialogCompletions.removeValue(forKey: targetID)
        completion?(resolution)
        return browserDialogs[index]
    }

    func getBrowserDialogList() -> [[String: String]] {
        let formatter = ISO8601DateFormatter()
        return browserDialogs.suffix(50).map { dialog in
            var row: [String: String] = [
                "id": dialog.id.uuidString,
                "type": dialog.kind.rawValue,
                "state": dialog.state.rawValue,
                "message": dialog.message,
                "createdAt": formatter.string(from: dialog.createdAt)
            ]
            if let defaultText = dialog.defaultText {
                row["defaultText"] = defaultText
            }
            if let url = dialog.url {
                row["url"] = url
            }
            if let resolvedAt = dialog.resolvedAt {
                row["resolvedAt"] = formatter.string(from: resolvedAt)
            }
            return row
        }
    }

    private func pruneBrowserDialogHistory() {
        while browserDialogs.count > 100,
              let index = browserDialogs.firstIndex(where: { $0.state != .pending }) {
            browserDialogCompletions.removeValue(forKey: browserDialogs[index].id)
            browserDialogs.remove(at: index)
        }
    }

    func captureScreenshot(
        outputPath: String?,
        timeout: TimeInterval = 3
    ) -> BrowserScreenshotCaptureResult {
        guard let screenshotCapturer else {
            return .failure("Browser page is not ready for screenshot capture")
        }
        return screenshotCapturer(outputPath, timeout)
    }

    func recordConsoleEntry(level: String, message: String, timestamp: Date = Date()) {
        consoleSnapshotEntries.append(
            BrowserConsoleSnapshotEntry(level: level, message: message, timestamp: timestamp)
        )
        if consoleSnapshotEntries.count > 200 {
            consoleSnapshotEntries.removeFirst(consoleSnapshotEntries.count - 200)
        }
    }

    // MARK: - DOM Grab

    /// Toggles click-to-capture mode for the current browser page.
    func toggleDOMGrabMode() {
        setDOMGrabMode(!isDOMGrabActive)
    }

    /// Sets click-to-capture mode and notifies the active WebKit host.
    func setDOMGrabMode(_ enabled: Bool) {
        guard isDOMGrabActive != enabled else {
            navigationActionSubject.send(.setDOMGrabEnabled(enabled))
            return
        }
        isDOMGrabActive = enabled
        navigationActionSubject.send(.setDOMGrabEnabled(enabled))
    }

    /// Receives a typed DOM grab from the WebKit message handler.
    func handleDOMGrabPayload(_ payload: BrowserDOMGrabPayload) {
        onDOMGrabPayload?(payload)
        if isDOMGrabActive {
            setDOMGrabMode(false)
        }
    }

    /// Returns the current browser state as a dictionary of string values.
    ///
    /// All values are serialized to strings for compatibility with the
    /// socket protocol wire format (`[String: String]`).
    func getState() -> [String: String] {
        var state = [
            "url": currentURL?.absoluteString ?? "",
            "title": pageTitle,
            "isLoading": "\(isLoading)",
            "canGoBack": "\(canGoBack)",
            "canGoForward": "\(canGoForward)",
            "tabCount": "\(browserTabs.count)",
            "activeTabID": activeTabID?.uuidString ?? "",
            "profileID": activeProfileID?.uuidString ?? "",
            "browserRoute": activeRemoteBrowserProfile == nil ? "local" : "remote"
        ]
        if let remote = activeRemoteBrowserProfile {
            state["remoteBrowserProfileID"] = remote.id.uuidString
            state["remoteConnectionProfileID"] = remote.connectionProfileID.uuidString
            state["remoteDisplayTitle"] = remote.displayTitle
            state["remoteHost"] = remote.host
            state["remoteProxyHealth"] = remote.proxyHealth.rawValue
            state["remoteRouting"] = remote.routingSummary
            if let socksPort = remote.socksPort {
                state["remoteSOCKSPort"] = "\(socksPort)"
            }
            if let httpConnectPort = remote.httpConnectPort {
                state["remoteHTTPConnectPort"] = "\(httpConnectPort)"
            }
        }
        if let notice = remoteBrowserNotice {
            state["remoteNotice"] = notice.kind.rawValue
            state["remoteNoticeProfileID"] = notice.remoteProfile.id.uuidString
            if let request = notice.routeRequest {
                state["remoteNoticePort"] = "\(request.remotePort)"
            }
            if let failedURLString = notice.failedURLString {
                state["remoteNoticeURL"] = failedURLString
            }
            if let detail = notice.detail {
                state["remoteNoticeDetail"] = detail
            }
        }
        return state
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
                "title": tab.displayTitle,
                "isActive": tab.id == activeTabID ? "true" : "false"
            ]
        }
    }

    // MARK: - Downloads Management

    /// Adds a new download item to the tracked downloads list.
    ///
    /// - Parameter item: The download to track.
    func addDownload(_ item: DownloadItem) {
        downloads.append(item)
    }

    /// Updates an existing download item by its ID.
    ///
    /// - Parameter item: The updated download item.
    func updateDownload(_ item: DownloadItem) {
        guard let index = downloads.firstIndex(where: { $0.id == item.id }) else { return }
        downloads[index] = item
    }

    /// Removes all completed and failed downloads from the list.
    func clearCompletedDownloads() {
        downloads.removeAll { $0.isFinished }
    }

    // MARK: - Find-in-Page

    /// Executes a find-in-page search by injecting JavaScript.
    ///
    /// Uses `window.find()` to highlight matches in the page. Updates
    /// match count by querying the page via the Performance API.
    ///
    /// - Parameter text: The text to search for. Empty string clears the search.
    func findInPage(_ text: String) {
        findSearchText = text
        guard !text.isEmpty else {
            findCurrentMatch = 0
            findTotalMatches = 0
            // Clear selection by searching for empty string.
            navigationActionSubject.send(.evaluateJS(
                "window.getSelection().removeAllRanges();"
            ))
            return
        }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let countScript = """
        (function() {
            var count = 0;
            var pos = 0;
            var text = document.body.innerText;
            var query = '\(escaped)'.toLowerCase();
            var lower = text.toLowerCase();
            while ((pos = lower.indexOf(query, pos)) !== -1) {
                count++;
                pos += query.length;
            }
            return count;
        })();
        """
        navigationActionSubject.send(.evaluateJS(countScript))
        let findScript = "window.find('\(escaped)', false, false, true);"
        navigationActionSubject.send(.evaluateJS(findScript))
        findCurrentMatch = 1
    }

    /// Navigates to the next find-in-page match.
    func findNextMatch() {
        guard !findSearchText.isEmpty else { return }
        let escaped = findSearchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        navigationActionSubject.send(.evaluateJS(
            "window.find('\(escaped)', false, false, true);"
        ))
        if findTotalMatches > 0 {
            findCurrentMatch = (findCurrentMatch % findTotalMatches) + 1
        }
    }

    /// Navigates to the previous find-in-page match.
    func findPreviousMatch() {
        guard !findSearchText.isEmpty else { return }
        let escaped = findSearchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        navigationActionSubject.send(.evaluateJS(
            "window.find('\(escaped)', false, true, true);"
        ))
        if findTotalMatches > 0 {
            findCurrentMatch = findCurrentMatch <= 1 ? findTotalMatches : findCurrentMatch - 1
        }
    }

    /// Clears the find-in-page state and removes highlights.
    func clearFind() {
        findSearchText = ""
        findCurrentMatch = 0
        findTotalMatches = 0
        navigationActionSubject.send(.evaluateJS(
            "window.getSelection().removeAllRanges();"
        ))
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

    /// Repairs common address-bar editing mistakes before URL normalization.
    ///
    /// URL fields keep the current page URL visible. If the user clicks into
    /// the field and types a new full URL without fully clearing the old one,
    /// AppKit can leave a malformed value such as
    /// `http://localhost:3000/http://cocxy.dev/`. In that case, the most
    /// recently typed explicit URL is the user's intent.
    static func repairedEditableURLInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let regex = try? NSRegularExpression(
            pattern: #"https?://"#,
            options: [.caseInsensitive]
        ) else {
            return trimmed
        }

        let matches = regex.matches(in: trimmed, range: nsRange)
        guard matches.count > 1,
              let last = matches.last,
              let range = Range(last.range, in: trimmed) else {
            return trimmed
        }
        if let delimiter = trimmed.firstIndex(where: { $0 == "?" || $0 == "#" }),
           range.lowerBound > delimiter {
            return trimmed
        }
        return String(trimmed[range.lowerBound...])
    }
}
