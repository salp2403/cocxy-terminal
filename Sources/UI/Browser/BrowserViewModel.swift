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

struct BrowserAutomationPageIdentity: Equatable, @unchecked Sendable {
    let viewModelIdentifier: ObjectIdentifier
    let webViewIdentifier: ObjectIdentifier
    let tabID: UUID
    let url: String
    let navigationGeneration: UInt64
}

enum BrowserAutomationNavigationOperation: Equatable, Sendable {
    case load(URL)
    case goBack
    case goForward
    case reload
}

enum BrowserCookieImportResult: Equatable, Sendable {
    case success
    case partial(importedCount: Int, totalCount: Int, message: String)
    case indeterminate(
        importedCount: Int,
        totalCount: Int,
        uncertainCount: Int,
        message: String
    )
    case failure(String)
}

struct BrowserConsoleSnapshotEntry: Equatable, Sendable {
    let level: String
    let message: String
    let timestamp: Date
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
    typealias AuthorizedScriptEvaluator = (
        BrowserAutomationPageIdentity,
        String,
        TimeInterval
    ) -> BrowserScriptEvaluationResult
    typealias AuthorizedScreenshotCapturer = (
        BrowserAutomationPageIdentity,
        String?,
        TimeInterval
    ) -> BrowserScreenshotCaptureResult
    typealias AuthorizedNavigator = (
        BrowserAutomationPageIdentity,
        BrowserAutomationNavigationOperation,
        TimeInterval
    ) -> Bool
    typealias CookieImporter = (BrowserImportedCookie, UUID, TimeInterval) -> BrowserCookieImportResult
    typealias InitScriptSynchronizer = ([BrowserInitScript]) -> BrowserScriptEvaluationResult
    typealias InitScriptNavigationCanceller = () -> Void

    private let lock = NSLock()
    private var evaluator: ScriptEvaluator?
    private var capturer: ScreenshotCapturer?
    private var authorizedEvaluator: AuthorizedScriptEvaluator?
    private var authorizedCapturer: AuthorizedScreenshotCapturer?
    private var authorizedNavigator: AuthorizedNavigator?
    private var cookieImporterValue: CookieImporter?
    private var initScriptSynchronizerValue: InitScriptSynchronizer?
    private var initScriptNavigationCancellerValue: InitScriptNavigationCanceller?

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

    var authorizedScriptEvaluator: AuthorizedScriptEvaluator? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return authorizedEvaluator
        }
        set {
            lock.lock()
            authorizedEvaluator = newValue
            lock.unlock()
        }
    }

    var authorizedScreenshotCapturer: AuthorizedScreenshotCapturer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return authorizedCapturer
        }
        set {
            lock.lock()
            authorizedCapturer = newValue
            lock.unlock()
        }
    }

    var authorizedNavigationPerformer: AuthorizedNavigator? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return authorizedNavigator
        }
        set {
            lock.lock()
            authorizedNavigator = newValue
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

    var initScriptSynchronizer: InitScriptSynchronizer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return initScriptSynchronizerValue
        }
        set {
            lock.lock()
            initScriptSynchronizerValue = newValue
            lock.unlock()
        }
    }

    var initScriptNavigationCanceller: InitScriptNavigationCanceller? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return initScriptNavigationCancellerValue
        }
        set {
            lock.lock()
            initScriptNavigationCancellerValue = newValue
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

    func evaluate(
        authorizedPage: BrowserAutomationPageIdentity,
        script: String,
        timeout: TimeInterval
    ) -> BrowserScriptEvaluationResult? {
        guard let authorizedScriptEvaluator else { return nil }
        return authorizedScriptEvaluator(authorizedPage, script, timeout)
    }

    func captureScreenshot(
        outputPath: String?,
        timeout: TimeInterval
    ) -> BrowserScreenshotCaptureResult? {
        guard let screenshotCapturer else { return nil }
        return screenshotCapturer(outputPath, timeout)
    }

    func captureScreenshot(
        authorizedPage: BrowserAutomationPageIdentity,
        outputPath: String?,
        timeout: TimeInterval
    ) -> BrowserScreenshotCaptureResult? {
        guard let authorizedScreenshotCapturer else { return nil }
        return authorizedScreenshotCapturer(authorizedPage, outputPath, timeout)
    }

    func performNavigation(
        authorizedPage: BrowserAutomationPageIdentity,
        operation: BrowserAutomationNavigationOperation,
        timeout: TimeInterval
    ) -> Bool? {
        guard let authorizedNavigationPerformer else { return nil }
        return authorizedNavigationPerformer(authorizedPage, operation, timeout)
    }

    func importCookie(
        _ cookie: BrowserImportedCookie,
        profileID: UUID,
        timeout: TimeInterval
    ) -> BrowserCookieImportResult? {
        guard let cookieImporter else { return nil }
        return cookieImporter(cookie, profileID, timeout)
    }

    func synchronizeInitScripts(_ scripts: [BrowserInitScript]) -> BrowserScriptEvaluationResult? {
        guard let initScriptSynchronizer else { return nil }
        return initScriptSynchronizer(scripts)
    }

    func cancelInitScriptNavigation() {
        initScriptNavigationCanceller?()
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
    @Published var currentURL: URL? {
        didSet {
            if oldValue != currentURL {
                markAutomationNavigationBoundary()
            }
            guard !initScripts.isEmpty,
                  oldValue.flatMap(BrowserOrigin.init(url:))
                    != currentURL.flatMap(BrowserOrigin.init(url:)) else {
                return
            }
            revokeAllInitScripts(stopInFlightNavigation: false)
        }
    }

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
    @Published var activeTabID: UUID? {
        didSet {
            if oldValue != activeTabID {
                markAutomationNavigationBoundary()
                revokeAllInitScripts()
                revokeDOMGrabAuthorization()
            }
        }
    }

    // MARK: - Downloads State

    /// Active and completed downloads tracked by the browser.
    @Published var downloads: [DownloadItem] = []

    /// User-added scripts injected at document start for future page loads.
    private(set) var initScripts: [BrowserInitScript] = []

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

    /// Exact one-shot grant installed only in the isolated WebKit world.
    private(set) var domGrabAuthorizationID: UUID?
    private var domGrabAuthorizationGeneration: UInt64?
    private var domGrabNavigationGeneration: UInt64 = 0
    private var isDOMGrabNavigationInProgress = false
    private var domGrabExpirationTask: Task<Void, Never>?

    static let domGrabAuthorizationLifetime: TimeInterval = 60

    /// Optional remote workspace context for the active browser surface.
    ///
    /// Nil means the browser is local. Non-nil is metadata only; proxy
    /// lifecycle stays owned by RemoteWorkspace services.
    @Published private(set) var activeRemoteBrowserProfile: RemoteBrowserProfile?

    /// In-memory capability used only by the active remote browser WebView.
    /// Its password is intentionally excluded from scriptable/browser state.
    @Published private(set) var activeRemoteBrowserProxyCapability: RemoteBrowserProxyCapability?

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
        case setDOMGrabAuthorization(UUID?)
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
    private(set) var automationWebViewIdentifier: ObjectIdentifier?
    private(set) var automationNavigationGeneration: UInt64 = 0

    private var browserDialogCompletions: [UUID: (BrowserDialogResolution) -> Void] = [:]
    private var lastRemoteBrowserRouteRequest: RemoteBrowserRouteRequest?
    var onRetryRemoteBrowserRoute: ((RemoteBrowserRouteRequest) -> Void)?
    private var initScriptExpirationTask: Task<Void, Never>?
    private var initScriptWebViewIdentifier: ObjectIdentifier?
    private var consumedInitScriptAuthorizationExpirations: [UUID: Date] = [:]
    private var initScriptRemoteConnectionIsAvailable = true
    private var initScriptRemoteForwardLeaseIsAvailable = true
    private(set) var initScriptBrowserViewID: UUID?
    var isInitScriptBridgeAvailable: Bool {
        initScriptBrowserViewID != nil && automationBridge.initScriptSynchronizer != nil
    }
    var isInitScriptRemoteAuthorityAvailable: Bool {
        activeRemoteBrowserProfile == nil || (
            initScriptRemoteConnectionIsAvailable
                && initScriptRemoteForwardLeaseIsAvailable
        )
    }

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

    func installAutomationWebView(identifier: ObjectIdentifier) {
        automationWebViewIdentifier = identifier
        markAutomationNavigationBoundary()
    }

    func markAutomationNavigationBoundary() {
        automationNavigationGeneration &+= 1
    }

    func currentAutomationPageIdentity() -> BrowserAutomationPageIdentity? {
        guard let automationWebViewIdentifier,
              let activeTabID,
              let url = currentURL?.absoluteString ?? URL(string: urlString)?.absoluteString else {
            return nil
        }
        return BrowserAutomationPageIdentity(
            viewModelIdentifier: ObjectIdentifier(self),
            webViewIdentifier: automationWebViewIdentifier,
            tabID: activeTabID,
            url: url,
            navigationGeneration: automationNavigationGeneration
        )
    }

    func isCurrentAutomationPage(
        _ identity: BrowserAutomationPageIdentity,
        webViewIdentifier: ObjectIdentifier,
        webViewURL: String?
    ) -> Bool {
        ObjectIdentifier(self) == identity.viewModelIdentifier
            && automationWebViewIdentifier == identity.webViewIdentifier
            && webViewIdentifier == identity.webViewIdentifier
            && activeTabID == identity.tabID
            && automationNavigationGeneration == identity.navigationGeneration
            && (currentURL?.absoluteString ?? URL(string: urlString)?.absoluteString) == identity.url
            && webViewURL == identity.url
    }

    private(set) var consoleSnapshotEntries: [BrowserConsoleSnapshotEntry] = []

    /// The active browser profile ID, used to associate visits and WebKit
    /// storage with a profile. Published so active browser hosts can rebuild
    /// their `WKWebView` with the matching `WKWebsiteDataStore`.
    @Published var activeProfileID: UUID? {
        didSet {
            if oldValue != activeProfileID {
                markAutomationNavigationBoundary()
                revokeAllInitScripts()
                revokeDOMGrabAuthorization()
            }
        }
    }

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
        if activeRemoteBrowserProxyCapability != nil {
            clearRemoteBrowserProfile()
        }
        activeProfileID = profileID
        navigationActionSubject.send(.load(currentURL ?? BrowserTab.defaultURL))
    }

    func attachRemoteBrowserProfile(_ remoteProfile: RemoteBrowserProfile) {
        setActiveRemoteBrowserProfile(remoteProfile)
        initScriptRemoteConnectionIsAvailable = false
        initScriptRemoteForwardLeaseIsAvailable = remoteProfile.localForwardedPorts.isEmpty
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
        setActiveRemoteBrowserProfile(remoteProfile)
        initScriptRemoteConnectionIsAvailable = false
        initScriptRemoteForwardLeaseIsAvailable = remoteProfile.localForwardedPorts.isEmpty
        navigate(to: route.localURL.absoluteString)
        remoteBrowserNotice = nil
        publishProxyNoticeIfNeeded(for: remoteProfile)
        return route
    }

    @discardableResult
    func openRemoteBrokeredRoute(
        _ remoteProfile: RemoteBrowserProfile,
        capability: RemoteBrowserProxyCapability,
        scheme: String = "http",
        path: String = "/"
    ) -> RemoteBrowserRoute? {
        let normalizedScheme = scheme.lowercased()
        guard ["http", "https"].contains(normalizedScheme),
              capability.profileID == remoteProfile.connectionProfileID,
              capability.remotePort > 0,
              capability.expiresAt > Date() else {
            return nil
        }

        var components = URLComponents()
        components.scheme = normalizedScheme
        components.host = capability.browserHost
        components.port = capability.remotePort
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        guard let browserURL = components.url else { return nil }

        let request = RemoteBrowserRouteRequest(
            remotePort: capability.remotePort,
            scheme: normalizedScheme,
            path: components.path
        )
        lastRemoteBrowserRouteRequest = request

        var routedProfile = remoteProfile
        routedProfile.localForwardedPorts = [:]
        routedProfile.socksPort = capability.localProxyPort
        routedProfile.httpConnectPort = nil
        routedProfile.proxyHealth = .active

        applyAutomationNavigationURL(browserURL)
        setActiveRemoteBrowserProfile(routedProfile)
        initScriptRemoteConnectionIsAvailable = false
        initScriptRemoteForwardLeaseIsAvailable = true
        remoteBrowserNotice = nil
        activeRemoteBrowserProxyCapability = capability

        return RemoteBrowserRoute(
            profile: routedProfile,
            remotePort: capability.remotePort,
            localURL: browserURL
        )
    }

    @discardableResult
    func refreshRemoteBrowserProxyCapability(
        _ capability: RemoteBrowserProxyCapability
    ) -> Bool {
        guard var remoteProfile = activeRemoteBrowserProfile,
              remoteProfile.connectionProfileID == capability.profileID,
              lastRemoteBrowserRouteRequest?.remotePort == capability.remotePort,
              capability.expiresAt > Date() else {
            return false
        }

        remoteProfile.socksPort = capability.localProxyPort
        remoteProfile.httpConnectPort = nil
        remoteProfile.proxyHealth = .active
        setActiveRemoteBrowserProfile(remoteProfile)
        remoteBrowserNotice = nil
        activeRemoteBrowserProxyCapability = capability
        return true
    }

    func markRemoteBrowserProxyFailed(_ detail: String?) {
        guard var remoteProfile = activeRemoteBrowserProfile,
              activeRemoteBrowserProxyCapability != nil else { return }
        remoteProfile.proxyHealth = .failed
        setActiveRemoteBrowserProfile(remoteProfile)
        remoteBrowserNotice = RemoteBrowserNotice(
            kind: .proxyFailed,
            remoteProfile: remoteProfile,
            routeRequest: lastRemoteBrowserRouteRequest,
            failedURLString: currentURL?.absoluteString,
            detail: detail
        )
    }

    func allowsNavigationForActiveRemoteRoute(_ url: URL?) -> Bool {
        guard let capability = activeRemoteBrowserProxyCapability else { return true }
        guard capability.expiresAt > Date(), let url else { return false }
        switch url.scheme?.lowercased() {
        case "http", "ws":
            return url.host?.caseInsensitiveCompare(capability.browserHost) == .orderedSame
                && (url.port ?? 80) == capability.remotePort
        case "https", "wss":
            return url.host?.caseInsensitiveCompare(capability.browserHost) == .orderedSame
                && (url.port ?? 443) == capability.remotePort
        default:
            return true
        }
    }

    func allowsDevelopmentServerTrust(host: String) -> Bool {
        guard let capability = activeRemoteBrowserProxyCapability else {
            return host == "localhost" || host == "127.0.0.1"
        }
        return capability.expiresAt > Date()
            && activeRemoteBrowserProfile?.proxyHealth == .active
            && host.caseInsensitiveCompare(capability.browserHost) == .orderedSame
    }

    func clearRemoteBrowserProfile() {
        if activeRemoteBrowserProxyCapability != nil,
           let blankURL = URL(string: "about:blank") {
            // Never reload a brokered route after removing its proxy.
            applyAutomationNavigationURL(blankURL)
        }
        setActiveRemoteBrowserProfile(nil)
        initScriptRemoteConnectionIsAvailable = true
        initScriptRemoteForwardLeaseIsAvailable = true
        remoteBrowserNotice = nil
        lastRemoteBrowserRouteRequest = nil
        activeRemoteBrowserProxyCapability = nil
    }

    func updateInitScriptRemoteConnectionAvailability(
        activeConnectionProfileIDs: Set<UUID>
    ) {
        guard let remoteProfile = activeRemoteBrowserProfile else {
            initScriptRemoteConnectionIsAvailable = true
            return
        }
        let isAvailable = activeConnectionProfileIDs.contains(
            remoteProfile.connectionProfileID
        )
        let shouldRevoke = initScriptRemoteConnectionIsAvailable
            && !isAvailable
            && !initScripts.isEmpty
        initScriptRemoteConnectionIsAvailable = isAvailable
        if shouldRevoke {
            revokeAllInitScripts()
        }
    }

    func updateInitScriptRemoteForwardLeaseAvailability(
        scanningProfileID: UUID?,
        forwardedPortMappings: [Int: Int]
    ) {
        guard let remoteProfile = activeRemoteBrowserProfile else {
            initScriptRemoteForwardLeaseIsAvailable = true
            return
        }
        let requiredMappings = remoteProfile.localForwardedPorts
        let isAvailable = requiredMappings.isEmpty || (
            scanningProfileID == remoteProfile.connectionProfileID
                && requiredMappings.allSatisfy { remotePort, localPort in
                    forwardedPortMappings[remotePort] == localPort
                }
        )
        let shouldRevoke = initScriptRemoteForwardLeaseIsAvailable
            && !isAvailable
            && !initScripts.isEmpty
        initScriptRemoteForwardLeaseIsAvailable = isAvailable
        if shouldRevoke {
            revokeAllInitScripts()
        }
    }

    func updateRemoteBrowserProxyState(_ proxyState: ProxyState) {
        guard activeRemoteBrowserProxyCapability == nil else { return }
        guard var remoteProfile = activeRemoteBrowserProfile else { return }
        remoteProfile.apply(proxyState: proxyState)
        setActiveRemoteBrowserProfile(remoteProfile)
        publishProxyNoticeIfNeeded(for: remoteProfile)
    }

    private func setActiveRemoteBrowserProfile(_ remoteProfile: RemoteBrowserProfile?) {
        if !Self.hasSameInitScriptAuthority(activeRemoteBrowserProfile, remoteProfile) {
            revokeAllInitScripts()
        }
        activeRemoteBrowserProfile = remoteProfile
    }

    private static func hasSameInitScriptAuthority(
        _ lhs: RemoteBrowserProfile?,
        _ rhs: RemoteBrowserProfile?
    ) -> Bool {
        lhs.map(BrowserInitScriptRemoteRouteAuthority.init)
            == rhs.map(BrowserInitScriptRemoteRouteAuthority.init)
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

        if notice.kind == .proxyFailed,
           activeRemoteBrowserProxyCapability != nil,
           let onRetryRemoteBrowserRoute {
            onRetryRemoteBrowserRoute(request)
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
        guard let url = preparedNavigationURL(from: rawInput),
              allowsNavigationForActiveRemoteRoute(url) else { return }
        applyAutomationNavigationURL(url)
        navigationActionSubject.send(.load(url))
    }

    func preparedNavigationURL(from rawInput: String) -> URL? {
        Self.preparedNavigationURLValue(from: rawInput)
    }

    nonisolated static func preparedNavigationURLValue(from rawInput: String) -> URL? {
        let trimmed = Self.repairedEditableURLInput(rawInput)
        guard !trimmed.isEmpty else { return nil }

        let normalized = normalizeURLString(trimmed)
        return URL(string: normalized)
    }

    func applyAutomationNavigationURL(_ url: URL) {
        revokeDOMGrabAuthorization()
        urlString = url.absoluteString
        currentURL = url

        // Sync URL to the active tab.
        if let index = browserTabs.firstIndex(where: { $0.id == activeTabID }) {
            browserTabs[index].url = url
        }
    }

    /// Navigates the web view backward in history.
    func goBack() {
        revokeDOMGrabAuthorization()
        navigationActionSubject.send(.goBack)
    }

    /// Navigates the web view forward in history.
    func goForward() {
        revokeDOMGrabAuthorization()
        navigationActionSubject.send(.goForward)
    }

    /// Reloads the current page in the web view.
    func reload() {
        revokeDOMGrabAuthorization()
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
        clearRemoteRouteIfNeeded(for: url)
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
        removeInitScripts(for: tabID)
        browserTabs.remove(at: closingIndex)

        if wasActive {
            // Activate the nearest neighbor (prefer the tab to the left).
            let newIndex = min(closingIndex, browserTabs.count - 1)
            let newActiveTab = browserTabs[newIndex]
            clearRemoteRouteIfNeeded(for: newActiveTab.url)
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
        revokeDOMGrabAuthorization()
        clearRemoteRouteIfNeeded(for: tab.url)
        activeTabID = tab.id
        urlString = tab.url.absoluteString
        currentURL = tab.url
        pageTitle = tab.title
        navigationActionSubject.send(.load(tab.url))
    }

    private func clearRemoteRouteIfNeeded(for url: URL) {
        guard activeRemoteBrowserProxyCapability != nil,
              !allowsNavigationForActiveRemoteRoute(url) else { return }
        clearRemoteBrowserProfile()
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

    func makeInitScriptAuthorizationRequest(
        source: BrowserInitScriptRequestSource,
        script: String,
        at date: Date = Date()
    ) -> BrowserInitScriptAuthorizationRequest? {
        guard BrowserInitScriptSecurity.isValidSource(script),
              let context = currentInitScriptContext() else {
            return nil
        }
        return BrowserInitScriptAuthorizationRequest(
            source: source,
            script: script,
            context: context,
            tabDisplayTitle: currentInitScriptTabDisplayTitle(),
            remoteDisplayTitle: activeRemoteBrowserProfile.map {
                "\($0.displayTitle); \($0.routingSummary)"
            },
            createdAt: date
        )
    }

    func isInitScriptAuthorizationCurrent(
        _ authorization: BrowserInitScriptAuthorizationRequest,
        at date: Date = Date()
    ) -> Bool {
        guard let context = currentInitScriptContext() else { return false }
        return authorization.matches(
            script: authorization.script,
            context: context,
            at: date
        )
    }

    func attachInitScriptBridge(
        browserViewID: UUID,
        webViewIdentifier: ObjectIdentifier,
        navigationCanceller: @escaping BrowserAutomationBridgeStore.InitScriptNavigationCanceller = {},
        synchronizer: @escaping BrowserAutomationBridgeStore.InitScriptSynchronizer
    ) {
        if initScriptWebViewIdentifier != webViewIdentifier
            || initScriptBrowserViewID != browserViewID {
            revokeAllInitScripts()
        }
        initScriptBrowserViewID = browserViewID
        initScriptWebViewIdentifier = webViewIdentifier
        automationBridge.initScriptNavigationCanceller = navigationCanceller
        automationBridge.initScriptSynchronizer = synchronizer
        _ = automationBridge.synchronizeInitScripts([])
    }

    func detachInitScriptBridge(webViewIdentifier: ObjectIdentifier) {
        guard initScriptWebViewIdentifier == webViewIdentifier else { return }
        revokeAllInitScripts()
        automationBridge.initScriptSynchronizer = nil
        automationBridge.initScriptNavigationCanceller = nil
        initScriptBrowserViewID = nil
        initScriptWebViewIdentifier = nil
    }

    @discardableResult
    func addInitScript(
        authorization: BrowserInitScriptAuthorizationRequest,
        at date: Date = Date(),
        lifetime: TimeInterval = BrowserInitScriptAuthorizationRequest.authorizationLifetime
    ) throws -> BrowserInitScript {
        pruneExpiredInitScripts(at: date)
        guard BrowserInitScriptSecurity.isValidSource(authorization.script) else {
            throw BrowserInitScriptRegistrationError.invalidSource
        }
        consumedInitScriptAuthorizationExpirations = consumedInitScriptAuthorizationExpirations.filter {
            date < $0.value
        }
        guard consumedInitScriptAuthorizationExpirations[authorization.id] == nil else {
            throw BrowserInitScriptRegistrationError.authorizationConsumed
        }
        consumedInitScriptAuthorizationExpirations[authorization.id] = authorization.expiresAt
        guard isInitScriptAuthorizationCurrent(authorization, at: date) else {
            throw BrowserInitScriptRegistrationError.contextChanged
        }
        guard initScripts.count < BrowserInitScriptSecurity.maximumActiveScripts else {
            throw BrowserInitScriptRegistrationError.capacityReached
        }

        let script = BrowserInitScript(
            authorization: authorization,
            approvedAt: date,
            lifetime: min(
                max(0, lifetime),
                BrowserInitScriptAuthorizationRequest.authorizationLifetime
            )
        )
        let synchronizedScripts = initScripts + [script]
        guard let synchronization = automationBridge.synchronizeInitScripts(synchronizedScripts) else {
            clearInitScriptsAfterSynchronizationFailure()
            throw BrowserInitScriptRegistrationError.bridgeUnavailable
        }
        if let error = synchronization.error {
            clearInitScriptsAfterSynchronizationFailure()
            throw BrowserInitScriptRegistrationError.synchronizationFailed(error)
        }
        initScripts = synchronizedScripts
        rescheduleInitScriptExpiration()
        return script
    }

    @discardableResult
    func removeInitScript(id: UUID) -> Bool {
        let remainingScripts = initScripts.filter { $0.id != id }
        guard remainingScripts.count != initScripts.count else { return false }
        applyInitScriptRevocation(remainingScripts)
        return true
    }

    func revokeAllInitScripts(stopInFlightNavigation: Bool = true) {
        initScriptExpirationTask?.cancel()
        initScriptExpirationTask = nil
        if stopInFlightNavigation {
            automationBridge.cancelInitScriptNavigation()
        }
        _ = automationBridge.synchronizeInitScripts([])
        initScripts.removeAll()
    }

    func canAddInitScript(at date: Date = Date()) -> Bool {
        pruneExpiredInitScripts(at: date)
        return initScripts.count < BrowserInitScriptSecurity.maximumActiveScripts
    }

    func revokeInitScriptsIfMainNavigationLeavesApprovedOrigin(
        url: URL?,
        isMainFrame: Bool
    ) {
        guard isMainFrame, !initScripts.isEmpty else { return }
        let navigationOrigin = url.flatMap(BrowserOrigin.init(url:))
        guard initScripts.contains(where: { $0.origin != navigationOrigin }) else { return }
        revokeAllInitScripts(stopInFlightNavigation: false)
    }

    func authorizedInitScriptSource(
        id: UUID,
        origin: BrowserOrigin,
        isMainFrame: Bool,
        at date: Date = Date()
    ) -> String? {
        authorizedInitScripts(origin: origin, isMainFrame: isMainFrame, at: date)
            .first(where: { $0.id == id })?
            .source
    }

    func authorizedInitScripts(
        origin: BrowserOrigin,
        isMainFrame: Bool,
        at date: Date = Date()
    ) -> [BrowserInitScript] {
        pruneExpiredInitScripts(at: date)
        guard let activeTabID, let initScriptBrowserViewID else { return [] }
        return initScripts.filter {
            $0.isAuthorized(
                browserViewID: initScriptBrowserViewID,
                tabID: activeTabID,
                origin: origin,
                browserProfileID: activeProfileID,
                remoteBrowserProfileID: activeRemoteBrowserProfile?.id,
                remoteConnectionProfileID: activeRemoteBrowserProfile?.connectionProfileID,
                remoteRouteAuthority: activeRemoteBrowserProfile.map(
                    BrowserInitScriptRemoteRouteAuthority.init
                ),
                isMainFrame: isMainFrame,
                at: date
            )
        }
    }

    func getInitScriptList(at date: Date = Date()) -> [[String: String]] {
        pruneExpiredInitScripts(at: date)
        let formatter = ISO8601DateFormatter()
        return initScripts.map { script in
            [
                "id": script.id.uuidString,
                "length": "\(script.length)",
                "browserViewID": script.browserViewID.uuidString,
                "tabID": script.tabID.uuidString,
                "origin": script.origin.serialized,
                "browserProfileID": script.browserProfileID?.uuidString ?? "default",
                "remoteBrowserProfileID": script.remoteBrowserProfileID?.uuidString ?? "local",
                "remoteConnectionProfileID": script.remoteConnectionProfileID?.uuidString ?? "local",
                "createdAt": formatter.string(from: script.createdAt),
                "expiresAt": formatter.string(from: script.expiresAt),
                "mainFrameOnly": script.mainFrameOnly ? "true" : "false"
            ]
        }
    }

    private func currentInitScriptContext() -> BrowserInitScriptContext? {
        guard isInitScriptRemoteAuthorityAvailable else {
            return nil
        }
        guard let initScriptBrowserViewID,
              let activeTabID,
              let activeTab = browserTabs.first(where: { $0.id == activeTabID }),
              let origin = BrowserOrigin(url: currentURL ?? activeTab.url) else {
            return nil
        }
        return BrowserInitScriptContext(
            viewModelIdentifier: ObjectIdentifier(self),
            browserViewID: initScriptBrowserViewID,
            tabID: activeTabID,
            origin: origin,
            browserProfileID: activeProfileID,
            remoteBrowserProfileID: activeRemoteBrowserProfile?.id,
            remoteConnectionProfileID: activeRemoteBrowserProfile?.connectionProfileID,
            remoteRouteAuthority: activeRemoteBrowserProfile.map(
                BrowserInitScriptRemoteRouteAuthority.init
            )
        )
    }

    private func currentInitScriptTabDisplayTitle() -> String {
        let title = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        let activeTabURL = activeTabID.flatMap { tabID in
            browserTabs.first(where: { $0.id == tabID })?.url
        }
        return BrowserTab.fallbackDisplayTitle(
            for: currentURL ?? activeTabURL ?? BrowserTab.defaultURL
        )
    }

    private func pruneExpiredInitScripts(at date: Date) {
        let remainingScripts = initScripts.filter { date < $0.expiresAt }
        guard remainingScripts.count != initScripts.count else { return }
        applyInitScriptRevocation(remainingScripts)
    }

    private func removeInitScripts(for tabID: UUID) {
        let remainingScripts = initScripts.filter { $0.tabID != tabID }
        guard remainingScripts.count != initScripts.count else { return }
        applyInitScriptRevocation(remainingScripts)
    }

    private func applyInitScriptRevocation(_ remainingScripts: [BrowserInitScript]) {
        automationBridge.cancelInitScriptNavigation()
        guard automationBridge.synchronizeInitScripts(remainingScripts)?.error == nil else {
            clearInitScriptsAfterSynchronizationFailure()
            return
        }
        initScripts = remainingScripts
        rescheduleInitScriptExpiration()
    }

    private func clearInitScriptsAfterSynchronizationFailure() {
        automationBridge.cancelInitScriptNavigation()
        _ = automationBridge.synchronizeInitScripts([])
        initScripts.removeAll()
        initScriptExpirationTask?.cancel()
        initScriptExpirationTask = nil
    }

    private func rescheduleInitScriptExpiration() {
        initScriptExpirationTask?.cancel()
        guard let nextExpiration = initScripts.map(\.expiresAt).min() else {
            initScriptExpirationTask = nil
            return
        }

        let delay = max(0, nextExpiration.timeIntervalSinceNow)
        initScriptExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.pruneExpiredInitScripts(at: Date())
            self?.rescheduleInitScriptExpiration()
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
    func setDOMGrabMode(
        _ enabled: Bool,
        lifetime: TimeInterval = BrowserViewModel.domGrabAuthorizationLifetime
    ) {
        if enabled {
            if let domGrabAuthorizationID {
                navigationActionSubject.send(.setDOMGrabAuthorization(domGrabAuthorizationID))
                return
            }
            guard !isDOMGrabNavigationInProgress else { return }
            let authorizationID = UUID()
            domGrabAuthorizationID = authorizationID
            domGrabAuthorizationGeneration = domGrabNavigationGeneration
            isDOMGrabActive = true
            scheduleDOMGrabExpiration(authorizationID: authorizationID, lifetime: lifetime)
            navigationActionSubject.send(.setDOMGrabAuthorization(authorizationID))
            return
        }

        domGrabExpirationTask?.cancel()
        domGrabExpirationTask = nil
        domGrabAuthorizationID = nil
        domGrabAuthorizationGeneration = nil
        isDOMGrabActive = false
        navigationActionSubject.send(.setDOMGrabAuthorization(nil))
    }

    /// Revokes the one-shot capture capability without emitting redundant
    /// WebKit work when no capture is armed.
    func revokeDOMGrabAuthorization() {
        guard domGrabAuthorizationID != nil || isDOMGrabActive else { return }
        setDOMGrabMode(false)
    }

    /// A DOM-grab capability belongs to one main-frame document. Subframe
    /// navigations do not replace that document and must not disturb the UI.
    @discardableResult
    func revokeDOMGrabAuthorizationForNavigation(isMainFrame: Bool) -> UInt64? {
        guard isMainFrame else { return nil }
        domGrabNavigationGeneration &+= 1
        isDOMGrabNavigationInProgress = true
        revokeDOMGrabAuthorization()
        return domGrabNavigationGeneration
    }

    /// Marks the current main-frame navigation as settled. A new user action
    /// is required after this point; an old grant is never replayed.
    func completeDOMGrabNavigation(generation: UInt64) {
        guard generation == domGrabNavigationGeneration else { return }
        isDOMGrabNavigationInProgress = false
    }

    /// Keeps native authorization fail-closed when the isolated helper could
    /// not apply an enable request to the live WebKit document.
    func handleDOMGrabWebKitUpdate(authorizationID: UUID, applied: Bool) {
        guard !applied, domGrabAuthorizationID == authorizationID else { return }
        revokeDOMGrabAuthorization()
    }

    /// Receives a typed DOM grab from the WebKit message handler.
    @discardableResult
    func handleDOMGrabPayload(
        _ payload: BrowserDOMGrabPayload,
        authorizationID: UUID
    ) -> Bool {
        guard isDOMGrabActive,
              domGrabAuthorizationID == authorizationID,
              domGrabAuthorizationGeneration == domGrabNavigationGeneration,
              !isDOMGrabNavigationInProgress else { return false }

        // Consume the one-shot native authorization before invoking a
        // callback. A reentrant or replayed message therefore observes an
        // inactive mode and cannot trigger a second side effect.
        setDOMGrabMode(false)
        onDOMGrabPayload?(payload)
        return true
    }

    private func scheduleDOMGrabExpiration(
        authorizationID: UUID,
        lifetime: TimeInterval
    ) {
        domGrabExpirationTask?.cancel()
        domGrabExpirationTask = Task { @MainActor [weak self] in
            let boundedLifetime = lifetime.isFinite
                ? min(max(0, lifetime), BrowserViewModel.domGrabAuthorizationLifetime)
                : BrowserViewModel.domGrabAuthorizationLifetime
            let duration = Duration.milliseconds(Int64(boundedLifetime * 1_000))
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled,
                  self?.domGrabAuthorizationID == authorizationID else { return }
            self?.revokeDOMGrabAuthorization()
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
    private nonisolated static func normalizeURLString(_ input: String) -> String {
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
    nonisolated static func repairedEditableURLInput(_ input: String) -> String {
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
