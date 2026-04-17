// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController.swift - Main window management and layout.

import AppKit
import Combine
import SwiftUI

// MARK: - Main Window Controller

/// Controls the main application window layout.
///
/// The window contains a `CocxyCoreView` as its content view,
/// connected to a `TerminalViewModel` that manages the terminal state.
///
/// ## Window configuration
///
/// - Transparent titlebar for a clean terminal appearance.
/// - Full size content view so the terminal extends behind the titlebar.
/// - Default size calculated from config (columns x rows x font metrics).
/// - Minimum size (320x240) to prevent unusably small windows.
/// - Frame autosave for position persistence between sessions.
///
/// ## Lifecycle
///
/// ```
/// MainWindowController(bridge:configService:)  -- Creates window + view + viewModel
///   .showWindow(nil)                           -- Shows the window and makes it key
///   window close                               -- Cleanup via windowWillClose
/// ```
///
/// ## Extensions
///
/// Responsibilities are distributed across focused extension files:
/// - `+Overlays.swift` — SwiftUI overlay lifecycle (Command Palette, Dashboard, etc.)
/// - `+TabLifecycle.swift` — Tab creation, destruction, and surface wiring.
/// - `+SplitActions.swift` — Split pane creation, navigation, and management.
/// - `+SurfaceLifecycle.swift` — Terminal surface creation/destruction/OSC handling.
/// - `+StatusBar.swift` — Status bar content and refresh.
/// - `+Theme.swift` — Theme cycling and config application.
/// - `+TabStrip.swift` — Horizontal tab strip refresh logic.
/// - `+RemoteWorkspace.swift` — Remote workspace panel lifecycle.
/// - `+BrowserPro.swift` — Browser Pro overlay panels (history, bookmarks).
///
/// - SeeAlso: `CocxyCoreView`
/// - SeeAlso: `TerminalViewModel`
/// - SeeAlso: `ConfigService`
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, DashboardTabNavigating {
    static let codeReviewPanelWidthDefaultsKey = "agentCodeReviewPanelWidth"

    static func clampStoredCodeReviewPanelWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, CodeReviewPanelView.minimumPanelWidth), CodeReviewPanelView.maximumPanelWidth)
    }

    static func loadStoredCodeReviewPanelWidth() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: codeReviewPanelWidthDefaultsKey)
        let candidate = stored > 0 ? CGFloat(stored) : CodeReviewPanelView.defaultPanelWidth
        return clampStoredCodeReviewPanelWidth(candidate)
    }

    static func storeCodeReviewPanelWidth(_ width: CGFloat) {
        UserDefaults.standard.set(Double(width), forKey: codeReviewPanelWidthDefaultsKey)
    }

    // MARK: - Properties

    /// Unique identifier for this window. Stable for the window's lifetime.
    /// Used by the session registry to track session ownership.
    let windowID = WindowID()

    /// Reference to the central session registry for multi-window sync.
    /// Injected by AppDelegate after window creation. When nil, multi-window
    /// features are gracefully disabled (single-window fallback).
    var sessionRegistry: (any SessionRegistering)?

    /// Aggregator for cross-window notification counts. Injected by AppDelegate.
    /// Provides "N in other windows" count for the sidebar footer.
    var notificationAggregator: (any GlobalNotificationAggregating)? {
        didSet { subscribeToRemoteUnreadCount() }
    }

    /// Cancellable for the remote unread count subscription.
    private var remoteUnreadCancellable: AnyCancellable?

    /// Workspace wake observers that refresh terminal rendering after macOS
    /// display sleep / system wake. Without this safety net, a visible surface
    /// can remain visually blank until another UI action (for example a tab
    /// switch) requests a redraw.
    private var workspaceWakeObservers: [NSObjectProtocol] = []

    /// Event bus for receiving cross-window events (theme sync, config
    /// reload, focus session). Injected by AppDelegate.
    var windowEventBus: (any WindowEventBroadcasting)? {
        didSet { subscribeToWindowEvents() }
    }

    /// Cancellable for the window event bus subscription.
    private var eventBusCancellable: AnyCancellable?

    /// Maps tab IDs to their corresponding session IDs in the registry.
    /// Populated when a tab is created and cleaned up when it's closed.
    var tabSessionMap: [TabID: SessionID] = [:]

    /// The ViewModel driving the terminal surface in this window.
    let terminalViewModel: TerminalViewModel

    /// The terminal host view that renders the active terminal surface.
    /// Mutable from extensions (TabLifecycle needs to nil it during tab close).
    internal var terminalSurfaceView: TerminalHostView?

    /// Reference to the terminal engine. Mutable so AppDelegate can
    /// replace it during theme switching.
    var bridge: any TerminalEngine

    /// Optional reference to the configuration service.
    let configService: ConfigService?

    /// Snapshot of the last applied config, used to detect which properties
    /// changed and whether a bridge restart is needed.
    var lastAppliedConfig: CocxyConfig?

    /// Manages the lifecycle and ordering of tabs.
    let tabManager: TabManager

    /// Presentation logic for the tab bar sidebar.
    private(set) var tabBarViewModel: TabBarViewModel?

    /// The vertical tab bar sidebar view.
    private(set) var tabBarView: TabBarView?

    /// The tab ID currently displayed on screen. Updated ONLY at the end of
    /// handleTabSwitch after all visual changes are complete. Used to identify
    /// the outgoing tab when saving split state — independent of TabManager's
    /// activeTabID which may already point to the incoming tab by the time
    /// the Combine subscription fires.
    var displayedTabID: TabID?

    /// Maps tab IDs to their associated surface IDs.
    /// Internal access for session restoration in AppDelegate.
    var tabSurfaceMap: [TabID: SurfaceID] = [:]

    /// Maps tab IDs to their terminal host views.
    /// Internal access for session restoration in AppDelegate.
    var tabSurfaceViews: [TabID: TerminalHostView] = [:]

    /// Maps tab IDs to their terminal view models.
    /// Internal access for session restoration in AppDelegate.
    var tabViewModels: [TabID: TerminalViewModel] = [:]

    /// Coordinates split pane managers per tab.
    let tabSplitCoordinator = TabSplitCoordinator()

    /// The split container view for the active tab (when splits are active).
    private(set) var splitContainer: SplitContainer?

    /// Watcher for the active tab's `.cocxy.toml` project config.
    /// Stopped and recreated on every tab switch.
    private var projectConfigWatcher: ProjectConfigWatcher?

    /// Subscriptions for config change notifications.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - SwiftUI Overlay State (used by MainWindowController+Overlays.swift)

    var commandPaletteViewModel: CommandPaletteViewModel?
    var commandPaletteHostingView: NSHostingView<CommandPaletteView>?
    var isCommandPaletteVisible: Bool = false

    var dashboardViewModel: AgentDashboardViewModel?
    var dashboardHostingView: NSHostingView<DashboardPanelView>?
    var isDashboardVisible: Bool = false

    var searchBarViewModel: ScrollbackSearchBarViewModel?
    var searchBarHostingView: NSHostingView<ScrollbackSearchBarView>?
    var isSearchBarVisible: Bool = false
    var searchQueryCancellable: AnyCancellable?

    var smartRoutingViewModel: SmartRoutingOverlayViewModel?
    var smartRoutingHostingView: NSHostingView<AnyView>?
    var isSmartRoutingVisible: Bool = false

    var timelineHostingView: NSView?
    var timelineViewModel: TimelineViewModel?
    var isTimelineVisible: Bool = false
    private(set) lazy var timelineDispatcher = TimelineNavigationDispatcher()

    var welcomeHostingView: NSHostingView<WelcomeOverlayView>?
    var isWelcomeVisible: Bool = false

    /// Hosting view for the agent progress overlay shown in the terminal corner.
    var agentProgressHostingView: NSView?

    var notificationPanelViewModel: NotificationPanelViewModel?
    var notificationPanelHostingView: NSHostingView<NotificationPanelView>?
    var isNotificationPanelVisible: Bool = false

    var browserViewModel: BrowserViewModel?
    var browserHostingView: NSHostingView<BrowserPanelView>?
    var isBrowserVisible: Bool = false

    var codeReviewViewModel: CodeReviewPanelViewModel?
    var codeReviewHostingView: NSHostingView<CodeReviewPanelView>?
    var isCodeReviewVisible: Bool = false
    var codeReviewPanelWidth: CGFloat = MainWindowController.loadStoredCodeReviewPanelWidth()
    private(set) var preferredCodeReviewPanelWidth: CGFloat = MainWindowController.loadStoredCodeReviewPanelWidth()
    var codeReviewCancellables = Set<AnyCancellable>()
    var injectedCodeReviewViewModel: CodeReviewPanelViewModel?

    // MARK: - Remote Workspace Overlay State

    var remoteConnectionViewModel: RemoteConnectionViewModel?
    var remoteWorkspaceHostingView: NSView?
    var isRemoteWorkspaceVisible: Bool = false

    // MARK: - Remote Workspace Dependencies

    /// Remote connection manager injected by AppDelegate.
    var remoteConnectionManager: RemoteConnectionManager?

    /// Remote profile store injected by AppDelegate.
    var remoteProfileStore: RemoteProfileStore?

    /// SSH tunnel manager injected by AppDelegate.
    var tunnelManager: SSHTunnelManager?

    /// SSH key manager injected by AppDelegate.
    var sshKeyManager: SSHKeyManager?

    // MARK: - Browser Pro Dependencies

    /// Browser profile manager injected by AppDelegate.
    var browserProfileManager: BrowserProfileManager?

    /// Browser history store injected by AppDelegate.
    var browserHistoryStore: BrowserHistoryStoring?

    /// Browser bookmark store injected by AppDelegate.
    var browserBookmarkStore: BrowserBookmarkStoring?

    /// The Sparkle auto-update manager. Injected by AppDelegate.
    var sparkleUpdater: SparkleUpdater?

    // MARK: - Browser Pro Overlay State

    var browserHistoryHostingView: NSView?
    var isBrowserHistoryVisible: Bool = false

    var browserBookmarksHostingView: NSView?
    var isBrowserBookmarksVisible: Bool = false

    /// Preferences window, retained to prevent premature deallocation.
    var preferencesWindow: NSWindow?

    /// Delegate that intercepts preferences window close for unsaved changes.
    /// Retained here because NSWindow.delegate is weak.
    var preferencesWindowDelegate: PreferencesWindowDelegate?

    /// Buffer that captures terminal output for scrollback search.
    /// Each tab has its own buffer; this is the active tab's buffer.
    /// Internal setter: extensions (+SurfaceLifecycle) swap buffers during tab switch.
    var terminalOutputBuffer = TerminalOutputBuffer()

    /// Per-tab output buffers keyed by tab ID.
    var tabOutputBuffers: [TabID: TerminalOutputBuffer] = [:]

    /// Last known working directory for every live terminal surface.
    ///
    /// Tabs expose a single working directory at the model level, but split
    /// panes can diverge after `cd` commands. Tracking surface-scoped CWDs lets
    /// CocxyCore semantic callbacks resolve the correct directory without
    /// assuming all panes in a tab share the same location forever.
    var surfaceWorkingDirectories: [SurfaceID: URL] = [:]

    /// Per-tab command duration trackers keyed by tab ID.
    /// Each tracker parses OSC 133 ;B (start) and ;D (finish) from raw terminal output.
    var tabCommandTrackers: [TabID: CommandDurationTracker] = [:]

    /// Per-surface inline image detectors keyed by surface ID.
    ///
    /// Inline image payloads need to render back into the originating surface,
    /// so split panes cannot safely share a single detector instance.
    var surfaceImageDetectors: [SurfaceID: InlineImageOSCDetector] = [:]

    /// The container view that wraps the terminal area and overlays.
    var terminalContainerView: NSView?

    /// The container view for full-window overlays.
    private(set) var overlayContainerView: NSView?

    /// Dashboard ViewModel injected by AppDelegate for real agent data.
    /// When set, the dashboard panel shows live agent sessions instead of an empty view.
    var injectedDashboardViewModel: AgentDashboardViewModel?

    /// Timeline store injected by AppDelegate for real event data.
    /// When set, the timeline panel shows live agent events instead of an empty list.
    var injectedTimelineStore: AgentTimelineStoreImpl?

    /// Notification manager injected by AppDelegate for OSC notification forwarding.
    /// When set, incoming OSC notifications are forwarded to the notification pipeline.
    var injectedNotificationManager: NotificationManagerImpl?

    /// Agent detection engine injected by AppDelegate.
    /// When set, terminal output from ALL surfaces is routed to the engine.
    var injectedAgentDetectionEngine: AgentDetectionEngineImpl?

    /// Per-surface agent state store injected by AppDelegate.
    ///
    /// Used during surface teardown so stale per-surface state is
    /// released at the same moment the engine's debounce/hook buckets
    /// are cleared. Remains `nil` when agent detection is disabled —
    /// teardown paths guard for `nil` and skip the reset.
    var injectedPerSurfaceStore: AgentStatePerSurfaceStore?

    /// Session diff tracker injected by AppDelegate for the code review panel.
    var injectedSessionDiffTracker: SessionDiffTracking?

    /// Port scanner for detecting active dev servers. Injected by AppDelegate.
    var portScanner: PortScannerImpl?

    /// Remote port scanner for detecting dev servers on SSH-connected hosts.
    var remotePortScanner: RemotePortScanner?

    /// Service that monitors foreground processes for SSH detection.
    private(set) var processMonitor: ProcessMonitorService?

    // MARK: - Theme State

    /// Index of the currently active terminal color scheme.
    var activeThemeIndex = 0

    /// Available terminal color schemes for cycling.
    static let themeNames = [
        "Catppuccin Mocha",
        "One Dark",
        "Dracula",
        "Solarized Dark",
    ]

    // MARK: - Split State

    /// Maximum number of panes allowed per tab (2 levels of split).
    static let maxPaneCount = 4

    /// The root NSSplitView when the current tab has splits.
    /// Nil when there is a single pane.
    var activeSplitView: NSSplitView?

    /// All split terminal host views keyed by their surface ID, for recursive splits.
    var splitSurfaceViews: [SurfaceID: TerminalHostView] = [:]

    /// All split view models keyed by their surface ID, for recursive splits.
    var splitViewModels: [SurfaceID: TerminalViewModel] = [:]

    /// Non-terminal panel views in splits, keyed by content UUID.
    var panelContentViews: [UUID: NSView] = [:]

    /// Inline image renderers keyed by surface view identity.
    /// Lazily created per surface view in +SurfaceLifecycle.
    var inlineImageRenderers: [ObjectIdentifier: InlineImageRenderer] = [:]

    // MARK: - Per-Tab Split State

    /// Saved NSSplitView hierarchies for tabs that are not currently visible.
    /// When switching tabs, the active split view is removed from the container
    /// and stored here. On return, it is restored to the container.
    var savedTabSplitViews: [TabID: NSSplitView] = [:]

    /// Saved split host views per tab. Keyed by tab ID, each value
    /// maps surface IDs to their terminal host view instances.
    var savedTabSplitSurfaceViews: [TabID: [SurfaceID: TerminalHostView]] = [:]

    /// Saved split view models per tab.
    var savedTabSplitViewModels: [TabID: [SurfaceID: TerminalViewModel]] = [:]

    /// Saved non-terminal panel views per tab.
    var savedTabPanelContentViews: [TabID: [UUID: NSView]] = [:]

    /// Suppresses reactive tab switches while a full session restore is
    /// rebuilding tabs, surfaces, and split hierarchies.
    ///
    /// Without this gate, `insertExternalTab` publishes intermediate active-tab
    /// changes before the corresponding surface tree exists, which can leave the
    /// visible terminal blank after restore/update relaunches.
    var isPerformingProgrammaticTabRestore: Bool = false

    // MARK: - Initialization

    /// Creates a MainWindowController with the given bridge and optional config.
    ///
    /// - Parameters:
    ///   - bridge: The terminal engine bridge used for surface creation.
    ///   - configService: Optional configuration service for reading window settings.
    init(bridge: any TerminalEngine, configService: ConfigService? = nil, tabManager: TabManager? = nil) {
        self.bridge = bridge
        self.configService = configService
        self.tabManager = tabManager ?? TabManager()
        self.terminalViewModel = TerminalViewModel(engine: bridge)
        let configuredFontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize
        terminalViewModel.setDefaultFontSize(configuredFontSize)

        // Calculate window size from config, or use sensible defaults.
        let windowSize = Self.calculateWindowSize(from: configService)

        let windowRect = NSRect(origin: .zero, size: windowSize)
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        self.lastAppliedConfig = configService?.current
        configureWindow(window)
        installWorkspaceWakeObservers()
        subscribeToConfigChanges()
        subscribeToActiveTabChanges()
        startProcessMonitor()
    }

    /// Required initializer for NSCoding. Not used in practice.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MainWindowController does not support NSCoding")
    }

    // MARK: - Window Size Calculation

    /// Calculates window size based on configuration.
    ///
    /// Uses font size and a default of 80 columns x 24 rows to compute
    /// pixel dimensions. Falls back to 1200x800 when no config is provided.
    ///
    /// - Parameter configService: The configuration service to read from.
    /// - Returns: The calculated window size.
    private static func calculateWindowSize(from configService: ConfigService?) -> NSSize {
        guard let config = configService?.current else {
            return NSSize(width: 1200, height: 800)
        }

        // Estimate cell size from font metrics.
        // A monospace font at a given size typically has width ~0.6x height.
        let fontSize = config.appearance.fontSize
        let estimatedCellWidth = fontSize * 0.6
        let estimatedCellHeight = fontSize * 1.2

        let defaultColumns: Double = 80
        let defaultRows: Double = 24
        let padding = config.appearance.windowPadding * 2

        let width = (defaultColumns * estimatedCellWidth) + padding
        let height = (defaultRows * estimatedCellHeight) + padding

        // Ensure minimum reasonable size.
        return NSSize(
            width: max(width, 320),
            height: max(height, 240)
        )
    }

    // MARK: - Window Configuration

    /// The main split view (sidebar | terminal area).
    /// Internal access for extensions (+Theme applies tab position).
    var mainSplitView: NSSplitView?

    /// Sidebar width constraints.
    /// Internal access for extensions (+Theme applies tab position).
    static let sidebarWidth: CGFloat = 240
    private static let sidebarMinWidth: CGFloat = 200
    private static let sidebarMaxWidth: CGFloat = 380

    /// Status bar height.
    private static let statusBarHeight: CGFloat = 24

    /// Horizontal tab strip height.
    private static let tabStripHeight: CGFloat = 32

    /// The status bar hosting view at the bottom of the window.
    private(set) var statusBarHostingView: NSHostingView<StatusBarView>?

    /// The horizontal tab strip at the top of the window.
    private(set) var horizontalTabStripView: NSView?

    private func configureWindow(_ window: NSWindow) {
        configureWindowProperties(window)

        let windowSize = Self.calculateWindowSize(from: configService)
        let contentFrame = NSRect(origin: .zero, size: windowSize)

        let sidebar = buildSidebar()
        let surfaceView = buildTerminalSurface()
        let (splitView, outerContainer, strip) = buildMainSplitView(
            contentFrame: contentFrame, sidebar: sidebar
        )
        _ = buildTerminalArea(in: outerContainer, surfaceView: surfaceView)
        let rootView = buildRootView(
            contentFrame: contentFrame, splitView: splitView
        )

        window.contentView = rootView

        applyTabPosition(
            configService?.current.appearance.tabPosition ?? .left,
            sidebar: sidebar,
            strip: strip
        )

        if let firstTabID = tabManager.tabs.first?.id {
            tabSurfaceViews[firstTabID] = surfaceView
            tabViewModels[firstTabID] = terminalViewModel
        }
    }

    // MARK: - Window Configuration Helpers

    private func configureWindowProperties(_ window: NSWindow) {
        window.title = "Cocxy Terminal"
        window.minSize = NSSize(width: 700, height: 450)
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("CocxyMainWindow")
        window.delegate = self
        window.backgroundColor = CocxyColors.base
    }

    private func buildSidebar() -> TabBarView {
        let tabBarVM = TabBarViewModel(tabManager: tabManager)
        tabBarVM.onAddTab = { [weak self] in self?.createTab() }
        tabBarVM.onCloseTab = { [weak self] tabID in self?.closeTab(tabID) }
        tabBarVM.dragDataProvider = { [weak self] tabID in
            guard let self else { return nil }
            return SessionDragData(
                sessionID: self.sessionIDForTab(tabID),
                tabID: tabID,
                sourceWindowID: self.windowID
            )
        }
        // Route the sidebar pill through the per-surface resolver so splits
        // running independent agents drive the tab pill via the focused
        // pane instead of being flattened onto the tab-level fields.
        tabBarVM.agentStateResolver = { [weak self] tab in
            guard let self else { return SurfaceAgentState(from: tab) }
            return self.resolveSurfaceAgentState(for: tab.id, tab: tab)
        }

        let sidebar = TabBarView(viewModel: tabBarVM)
        sidebar.onCommandPalette = { [weak self] in self?.toggleCommandPalette() }
        sidebar.onNotificationPanel = { [weak self] in self?.toggleNotificationPanel() }
        sidebar.onAcceptTabDrop = { [weak self] dragData in
            self?.handleTabDrop(dragData) ?? false
        }
        if let appearance = configService?.current.appearance {
            sidebar.setSidebarTransparent(appearance.backgroundOpacity < 1.0)
        }
        sidebar.confirmCloseProcess = configService?.current.general.confirmCloseProcess ?? false
        sidebar.flashTabEnabled = configService?.current.notifications.flashTab ?? true
        sidebar.badgeOnTabEnabled = configService?.current.notifications.badgeOnTab ?? true
        self.tabBarViewModel = tabBarVM
        self.tabBarView = sidebar
        return sidebar
    }

    private func buildTerminalSurface() -> TerminalHostView {
        let surfaceView = CocxyCoreView(viewModel: terminalViewModel)
        self.terminalSurfaceView = surfaceView
        return surfaceView
    }

    private func buildMainSplitView(
        contentFrame: NSRect,
        sidebar: TabBarView
    ) -> (NSSplitView, NSView, HorizontalTabStripView) {
        let splitView = NSSplitView(frame: contentFrame)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        splitView.delegate = self
        self.mainSplitView = splitView

        sidebar.frame = NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: contentFrame.height)
        sidebar.autoresizingMask = [.height]

        let terminalContainerFrame = NSRect(
            x: Self.sidebarWidth + 1, y: 0,
            width: contentFrame.width - Self.sidebarWidth - 1,
            height: contentFrame.height
        )
        let outerContainer = NSView(frame: terminalContainerFrame)
        outerContainer.autoresizingMask = [.width, .height]

        let strip = buildTabStrip(in: outerContainer)
        outerContainer.addSubview(strip)
        self.horizontalTabStripView = strip

        splitView.addSubview(sidebar)
        splitView.addSubview(outerContainer)
        splitView.adjustSubviews()

        return (splitView, outerContainer, strip)
    }

    private func buildTabStrip(in container: NSView) -> HorizontalTabStripView {
        let stripH = Self.tabStripHeight
        let strip = HorizontalTabStripView(
            frame: NSRect(x: 0, y: container.bounds.height - stripH,
                          width: container.bounds.width, height: stripH)
        )
        strip.autoresizingMask = [.width, .minYMargin]
        strip.onAddTab = { [weak self] in self?.performVisualSplit(isVertical: true) }
        strip.onAddStackedTerminal = { [weak self] in self?.performVisualSplit(isVertical: false) }
        strip.onAddBrowser = { [weak self] in self?.splitWithBrowserAction(nil) }
        strip.onAddMarkdown = { [weak self] in self?.splitWithMarkdownAction(nil) }
        strip.onSplitSideBySide = { [weak self] in self?.performVisualSplit(isVertical: false) }
        strip.onSplitStacked = { [weak self] in self?.performVisualSplit(isVertical: true) }
        strip.onOpenBrowser = { [weak self] in self?.splitWithBrowserAction(nil) }
        strip.onOpenMarkdown = { [weak self] in self?.splitWithMarkdownAction(nil) }
        strip.onReload = { [weak self] in self?.reloadFocusedBrowserPanel() }
        strip.onGoBack = { [weak self] in self?.goBackFocusedBrowserPanel() }
        strip.onGoForward = { [weak self] in self?.goForwardFocusedBrowserPanel() }
        strip.onClosePanel = { [weak self] in self?.closeSplitAction(nil) }
        strip.onSelectTab = { [weak self] index in self?.handleStripSelectTab(at: index) }
        strip.onCloseTab = { [weak self] index in self?.handleStripCloseTab(at: index) }
        strip.onSwapTabs = { [weak self] from, to in self?.handleStripSwapTabs(from: from, to: to) }
        strip.onRenameTab = { [weak self] index, name in self?.handleStripRenameTab(at: index, newTitle: name) }

        // Apply initial vibrancy state from config.
        if let appearance = configService?.current.appearance {
            strip.setTransparent(appearance.backgroundOpacity < 1.0)
        }

        return strip
    }

    private func buildTerminalArea(in outerContainer: NSView, surfaceView: TerminalHostView) -> NSView {
        let stripH = Self.tabStripHeight
        let terminalArea = NSView(frame: NSRect(
            x: 0, y: 0,
            width: outerContainer.bounds.width,
            height: outerContainer.bounds.height - stripH
        ))
        terminalArea.autoresizingMask = [.width, .height]
        outerContainer.addSubview(terminalArea)
        self.terminalContainerView = terminalArea

        surfaceView.frame = terminalArea.bounds
        surfaceView.autoresizingMask = [.width, .height]
        terminalArea.addSubview(surfaceView)
        return terminalArea
    }

    private func buildRootView(contentFrame: NSRect, splitView: NSSplitView) -> NSView {
        let rootView = NSView(frame: contentFrame)
        rootView.autoresizingMask = [.width, .height]

        // Status bar at the bottom.
        let isTransparent = configService?.current.appearance.backgroundOpacity ?? 1.0 < 1.0
        var statusBar = StatusBarView(
            hostname: currentHostname(),
            gitBranch: tabManager.activeTab?.gitBranch,
            agentSummary: computeAgentSummary(),
            activePorts: [],
            sshSession: tabManager.activeTab?.sshSession
        )
        statusBar.useVibrancy = isTransparent
        let statusBarHost = NSHostingView(rootView: statusBar)
        statusBarHost.frame = NSRect(x: 0, y: 0, width: contentFrame.width, height: Self.statusBarHeight)
        statusBarHost.wantsLayer = true
        statusBarHost.layer?.backgroundColor = isTransparent
            ? NSColor.clear.cgColor
            : CocxyColors.crust.cgColor
        statusBarHost.autoresizingMask = [.width]
        rootView.addSubview(statusBarHost)
        self.statusBarHostingView = statusBarHost

        // Split view fills everything above the status bar.
        splitView.frame = NSRect(
            x: 0, y: Self.statusBarHeight,
            width: contentFrame.width,
            height: contentFrame.height - Self.statusBarHeight
        )
        splitView.autoresizingMask = [.width, .height]
        rootView.addSubview(splitView)

        // Overlay layer on top of everything.
        let overlayLayer = PassthroughView(frame: rootView.bounds)
        overlayLayer.autoresizingMask = [.width, .height]
        overlayLayer.wantsLayer = true
        rootView.addSubview(overlayLayer)
        self.overlayContainerView = overlayLayer

        return rootView
    }

    // MARK: - Tab Strip Callbacks

    private func handleStripSelectTab(at index: Int) {
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return }
        syncFocusedLeafSelectionFromFirstResponder()
        let sm = tabSplitCoordinator.splitManager(for: tabID)
        let leaves = sm.rootNode.allLeafIDs()
        guard index < leaves.count else { return }
        let leaf = leaves[index]
        sm.focusLeaf(id: leaf.leafID)

        let contentID = leaf.terminalID
        if let panelView = panelContentViews[contentID] {
            window?.makeFirstResponder(panelView)
        } else {
            let leafViews = collectLeafViews()
            if index < leafViews.count {
                window?.makeFirstResponder(leafViews[index])
            } else if let primarySurface = terminalSurfaceView {
                window?.makeFirstResponder(primarySurface)
            }
        }
        refreshTabStrip()
    }

    private func handleStripCloseTab(at index: Int) {
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return }
        syncFocusedLeafSelectionFromFirstResponder()
        let sm = tabSplitCoordinator.splitManager(for: tabID)
        let leaves = sm.rootNode.allLeafIDs()
        guard index < leaves.count, leaves.count > 1 else { return }

        // Count how many terminal leaves remain (not panels).
        let terminalLeafCount = leaves.filter { leaf in
            panelContentViews[leaf.terminalID] == nil
        }.count
        let isClosingTerminal = panelContentViews[leaves[index].terminalID] == nil

        // Prevent closing the last terminal when panels are still open.
        // Without a terminal, the tab becomes unusable.
        if isClosingTerminal && terminalLeafCount <= 1 {
            return
        }

        sm.focusLeaf(id: leaves[index].leafID)
        closeSplitAction(nil)
    }

    /// Closes the last panel/pane in the split tree (LIFO order).
    ///
    /// Prioritizes closing non-terminal panels (browser, markdown) first.
    /// If only terminals remain, closes the last terminal (unless it's the
    /// only one left). Works correctly with multiple panes.
    private func closeLastPanel() {
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return }
        syncFocusedLeafSelectionFromFirstResponder()
        let sm = tabSplitCoordinator.splitManager(for: tabID)
        let leaves = sm.rootNode.allLeafIDs()
        guard leaves.count > 1 else { return }

        // Find the last non-terminal panel to close (LIFO).
        // If no panels exist, close the last terminal.
        let targetIndex: Int
        if let lastPanelIndex = leaves.lastIndex(where: { panelContentViews[$0.terminalID] != nil }) {
            targetIndex = lastPanelIndex
        } else {
            // All are terminals — close the last one.
            targetIndex = leaves.count - 1
        }

        // Focus the target leaf and close it.
        sm.focusLeaf(id: leaves[targetIndex].leafID)
        closeSplitAction(nil)
    }

    private func handleStripSwapTabs(from fromIndex: Int, to toIndex: Int) {
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return }
        let sm = tabSplitCoordinator.splitManager(for: tabID)
        let previousLeaves = sm.rootNode.allLeafIDs()
        let leafViewsBeforeSwap = collectLeafViews()
        sm.swapLeaves(at: fromIndex, with: toIndex)

        let leafViews = leafViewsBeforeSwap
        guard fromIndex < leafViews.count, toIndex < leafViews.count else {
            refreshTabStrip()
            return
        }

        let viewA = leafViews[fromIndex]
        let viewB = leafViews[toIndex]

        if let parentA = viewA.superview as? NSSplitView,
           let parentB = viewB.superview as? NSSplitView,
           parentA === parentB {
            guard let idxA = parentA.subviews.firstIndex(of: viewA),
                  let idxB = parentA.subviews.firstIndex(of: viewB) else {
                refreshTabStrip()
                return
            }
            let frameA = viewA.frame
            let frameB = viewB.frame
            viewA.removeFromSuperview()
            viewB.removeFromSuperview()
            let first = min(idxA, idxB)
            let second = max(idxA, idxB)
            let (viewAtFirst, viewAtSecond) = idxA < idxB ? (viewB, viewA) : (viewA, viewB)
            parentA.insertArrangedSubview(viewAtFirst, at: first)
            parentA.insertArrangedSubview(viewAtSecond, at: second)
            viewAtFirst.frame = frameA
            viewAtSecond.frame = frameB
            parentA.adjustSubviews()
        } else {
            // When the panes live under different split parents, swapping the
            // visual hierarchy locally becomes fragile. Rebuild from the split
            // model so the rendered order stays consistent with the domain tree.
            let viewsByTerminalID = Dictionary(
                uniqueKeysWithValues: zip(previousLeaves, leafViews).map { ($0.terminalID, $1) }
            )
            rebuildSplitViewHierarchy(for: tabID, viewsByTerminalIDOverride: viewsByTerminalID)
            return
        }

        refreshTabStrip()
    }

    private func handleStripRenameTab(at index: Int, newTitle: String) {
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return }
        let sm = tabSplitCoordinator.splitManager(for: tabID)
        let leaves = sm.rootNode.allLeafIDs()
        guard index < leaves.count else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        sm.setPanelTitle(for: leaves[index].terminalID, title: trimmed.isEmpty ? nil : trimmed)
        refreshTabStrip()
    }

    // MARK: - Config Subscription

    /// Subscribes to config changes to update window properties dynamically.
    private func subscribeToConfigChanges() {
        guard let configService = configService else { return }

        configService.configChangedPublisher
            .dropFirst() // Skip the current value, we already applied it.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                self?.applyConfig(newConfig)
            }
            .store(in: &cancellables)
    }

    /// Subscribes to remote unread count changes from the aggregator.
    ///
    /// Updates the sidebar footer label with the count of unread
    /// notifications in OTHER windows.
    private func subscribeToRemoteUnreadCount() {
        remoteUnreadCancellable?.cancel()
        guard let aggregator = notificationAggregator else { return }

        remoteUnreadCancellable = aggregator.windowUnreadPublisher
            .map { _ in () }
            .merge(with: aggregator.totalUnreadPublisher.map { _ in () })
            .sink { [weak self] _ in
                guard let self else { return }
                let remote = aggregator.remoteUnreadCount(excluding: self.windowID)
                self.tabBarView?.updateRemoteUnreadCount(remote)
            }

        // Set initial value.
        let remote = aggregator.remoteUnreadCount(excluding: windowID)
        tabBarView?.updateRemoteUnreadCount(remote)
    }

    /// Subscribes to cross-window events from the event bus.
    ///
    /// Each window listens for events that require a response:
    /// - `.focusSession`: The owning window activates the tab.
    /// - Other events are handled by AppDelegate globally.
    private func subscribeToWindowEvents() {
        eventBusCancellable?.cancel()
        guard let bus = windowEventBus else { return }

        eventBusCancellable = bus.events
            .sink { [weak self] event in
                self?.handleWindowEvent(event)
            }
    }

    /// Processes a single event from the window event bus.
    private func handleWindowEvent(_ event: WindowEvent) {
        switch event {
        case .focusSession(let sessionID):
            // Only act if this window owns the session.
            guard let entry = sessionRegistry?.session(for: sessionID),
                  entry.ownerWindowID == windowID else { return }
            // Bring window to front and switch to the tab.
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            _ = focusTab(id: entry.tabID)

        case .themeChanged, .fontChanged, .configReloaded,
             .globalShortcut, .custom:
            // These are handled at the AppDelegate level which already
            // iterates all window controllers. Individual windows do not
            // need to react to these bus events directly.
            break
        }
    }

    /// Initializes the process monitor for SSH/process detection.
    ///
    /// Starts the process monitor service and subscribes to process changes.
    ///
    /// The monitor polls the PTY foreground process group every 2 seconds and
    /// falls back to shell-process metadata when the PTY cannot answer directly.
    /// When a tab's foreground process changes (e.g., `zsh` -> `ssh`), it
    /// updates the tab model and refreshes the UI.
    ///
    /// Tabs are registered with `processMonitor.registerTab(_:shellPID:ptyMasterFD:)`
    /// in `createAndWireSurface` and `createTerminalSurface`.
    private func startProcessMonitor() {
        let monitor = ProcessMonitorService()
        self.processMonitor = monitor
        monitor.start()

        monitor.processChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleProcessChange(event)
            }
            .store(in: &cancellables)
    }

    /// Handles a foreground process change for a tab.
    private func handleProcessChange(_ event: ProcessChangeEvent) {
        tabManager.updateTab(id: event.tabID) { tab in
            tab.processName = event.processName
            tab.sshSession = event.sshSession
            tab.lastActivityAt = Date()
        }
        if let cocxyBridge = bridge as? CocxyCoreBridge,
           let surfaceID = surfaceIDs(for: event.tabID).first {
            cocxyBridge.syncCurrentStreamWithForegroundProcess(pid: event.pid, for: surfaceID)
        }
        tabBarViewModel?.syncWithManager()
        refreshStatusBar()
        refreshTabStrip()
    }

    /// Subscribes to active tab changes to switch the terminal surface view.
    ///
    /// When the user clicks a tab in the sidebar, TabManager updates `activeTabID`.
    /// This subscription catches that change and swaps the visible terminal surface.
    private func subscribeToActiveTabChanges() {
        tabManager.$activeTabID
            .dropFirst() // Skip the initial value (already set up during init).
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newActiveID in
                guard let self, let tabID = newActiveID else { return }
                guard !self.isPerformingProgrammaticTabRestore else { return }
                self.handleTabSwitch(to: tabID)
            }
            .store(in: &cancellables)
    }

    // Overlay methods are in MainWindowController+Overlays.swift.
    // Surface lifecycle methods are in MainWindowController+SurfaceLifecycle.swift.
    // Split actions are in MainWindowController+SplitActions.swift.
    // Tab strip refresh is in MainWindowController+TabStrip.swift.
    // Status bar methods are in MainWindowController+StatusBar.swift.
    // Theme methods are in MainWindowController+Theme.swift.

    // MARK: - NSWindowDelegate

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Deregister this window from the session registry. This cascades:
        // all sessions owned by this window are removed and removal events
        // are published so other windows can update their UI.
        sessionRegistry?.removeWindow(windowID)

        processMonitor?.stop()

        // Nil-ify all overlay ViewModels to break closure retain cycles.
        commandPaletteViewModel = nil
        dashboardViewModel = nil
        searchBarViewModel = nil
        smartRoutingViewModel = nil
        notificationPanelViewModel?.onNavigateToTab = nil
        notificationPanelViewModel = nil
        browserViewModel = nil
        timelineHostingView?.removeFromSuperview()
        timelineHostingView = nil
        welcomeHostingView?.removeFromSuperview()
        welcomeHostingView = nil

        // Clean stored closures on the sidebar and tab strip to prevent leaks.
        tabBarView?.onCommandPalette = nil
        tabBarView?.onNotificationPanel = nil
        tabBarView?.onAcceptTabDrop = nil
        tabBarViewModel?.onAddTab = nil
        tabBarViewModel?.onCloseTab = nil
        tabBarViewModel?.dragDataProvider = nil

        if let strip = horizontalTabStripView as? HorizontalTabStripView {
            strip.onAddTab = nil
            strip.onAddBrowser = nil
            strip.onAddMarkdown = nil
            strip.onAddStackedTerminal = nil
            strip.onSplitSideBySide = nil
            strip.onSplitStacked = nil
            strip.onOpenBrowser = nil
            strip.onOpenMarkdown = nil
            strip.onReload = nil
            strip.onGoBack = nil
            strip.onGoForward = nil
            strip.onClosePanel = nil
            strip.onSelectTab = nil
            strip.onCloseTab = nil
            strip.onSwapTabs = nil
            strip.onRenameTab = nil
        }

        searchQueryCancellable?.cancel()
        searchQueryCancellable = nil
        eventBusCancellable?.cancel()
        eventBusCancellable = nil
        remoteUnreadCancellable?.cancel()
        remoteUnreadCancellable = nil
        removeWorkspaceWakeObservers()

        destroyAllSurfaces()

        // Remove this controller from the app delegate's additional window list
        // to prevent memory leaks when Cmd+N windows are closed.
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.additionalWindowControllers.removeAll { $0 === self }
        }
    }

    func windowDidResize(_ notification: Notification) {
        adjustLayoutForWindowSize()
    }

    // MARK: - Display / Backing Safety Net

    /// Fallback path for the transparent-on-display-change bug.
    ///
    /// `CocxyCoreView` also observes `NSWindow.didChangeScreenNotification`
    /// locally to refresh its Metal layer and re-anchor the display link,
    /// but that path only fires while the view is attached to the window.
    /// Detached or hidden surface views (saved split panes for inactive
    /// tabs, surfaces awaiting reattachment after a tab switch, etc.)
    /// have no window reference and therefore never receive the local
    /// notification.
    ///
    /// This delegate path is the safety net: it walks every managed
    /// surface view — primary, tab-mapped, split-mapped, AND saved split
    /// surfaces from inactive tabs — and forces a CVDisplayLink re-anchor
    /// on each. It then defers to `refreshVisibleTerminalInteractionState`
    /// to handle the visible-view layout refresh that tab switch already
    /// uses.
    func windowDidChangeScreen(_ notification: Notification) {
        refreshAllSurfaceDisplayLinkAnchors()
        refreshVisibleTerminalInteractionState()
    }

    func windowDidChangeScreenProfile(_ notification: Notification) {
        refreshAllSurfaceDisplayLinkAnchors()
        refreshVisibleTerminalInteractionState()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        refreshAllSurfaceDisplayLinkAnchors()
        refreshVisibleTerminalInteractionState()
    }

    /// Walks every `TerminalHostView` managed by this controller and
    /// invokes `refreshDisplayLinkAnchor()` exactly once per distinct
    /// view (deduplicated by `ObjectIdentifier`).
    ///
    /// Sources walked, in order:
    /// 1. `terminalSurfaceView` (the currently active primary surface)
    /// 2. `tabSurfaceViews` (per-tab primary surfaces)
    /// 3. `splitSurfaceViews` (current visible split panes)
    /// 4. `savedTabSplitSurfaceViews` (split panes saved for inactive
    ///    tabs — these are detached from the window hierarchy and would
    ///    miss the local screen-change observer otherwise).
    ///
    /// The same view appearing in multiple slots (for example, the
    /// primary view that is also stored in `tabSurfaceViews` for its
    /// owning tab) is anchored exactly once.
    private func refreshAllSurfaceDisplayLinkAnchors() {
        var seen = Set<ObjectIdentifier>()

        func anchor(_ view: TerminalHostView?) {
            guard let view else { return }
            guard seen.insert(ObjectIdentifier(view)).inserted else { return }
            view.refreshDisplayLinkAnchor()
        }

        anchor(terminalSurfaceView)
        for view in tabSurfaceViews.values { anchor(view) }
        for view in splitSurfaceViews.values { anchor(view) }
        for savedSplits in savedTabSplitSurfaceViews.values {
            for view in savedSplits.values { anchor(view) }
        }
    }

    /// Re-anchors every managed terminal surface and requests an immediate
    /// redraw for the currently visible ones.
    ///
    /// This is the recovery path for cases where macOS display sleep/wake or
    /// app reactivation leaves the Metal-backed terminal visually stale until a
    /// later UI event forces a redraw.
    func recoverTerminalRenderingAfterWake() {
        refreshAllSurfaceDisplayLinkAnchors()
        refreshVisibleTerminalInteractionState()
    }

    private func installWorkspaceWakeObservers() {
        guard workspaceWakeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        workspaceWakeObservers = [
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.recoverTerminalRenderingAfterWake()
                    }
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            self?.recoverTerminalRenderingAfterWake()
                        }
                    }
                }
            ),
            center.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main,
                using: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.recoverTerminalRenderingAfterWake()
                    }
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            self?.recoverTerminalRenderingAfterWake()
                        }
                    }
                }
            ),
        ]
    }

    private func removeWorkspaceWakeObservers() {
        guard !workspaceWakeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceWakeObservers {
            center.removeObserver(observer)
        }
        workspaceWakeObservers.removeAll()
    }

    // MARK: - Responsive Layout

    /// Minimum window width before side panels are auto-dismissed.
    private static let panelAutoHideThreshold: CGFloat = 800

    /// Minimum window width before the sidebar collapses.
    private static let sidebarCollapseThreshold: CGFloat = 600

    /// Adjusts panel visibility based on the current window size.
    ///
    /// When the window is too narrow for side panels, they are automatically
    /// dismissed to avoid overlapping the terminal content. The sidebar
    /// collapses to zero width below a smaller threshold.
    private func adjustLayoutForWindowSize() {
        guard let windowWidth = window?.frame.width else { return }

        // Auto-dismiss side panels when window is too narrow.
        if windowWidth < Self.panelAutoHideThreshold {
            if isDashboardVisible { dismissDashboard() }
            if isTimelineVisible { dismissTimeline() }
            if isNotificationPanelVisible { dismissNotificationPanel() }
            if isBrowserVisible { dismissBrowser() }
        }

        // Collapse sidebar when window is very narrow.
        if windowWidth < Self.sidebarCollapseThreshold && !isTabBarHidden {
            toggleTabBarAction(nil)
        }

        if isTimelineVisible || isDashboardVisible || isCodeReviewVisible {
            layoutRightDockedAgentPanels()
        }
    }

    func windowDidBecomeMain(_ notification: Notification) {
        // Ensure the terminal view has focus when the window becomes main.
        focusActiveTerminalSurface()
        refreshVisibleTerminalInteractionState()
    }

    func updatePreferredCodeReviewPanelWidth(_ width: CGFloat) {
        let clampedWidth = MainWindowController.clampStoredCodeReviewPanelWidth(width)
        guard clampedWidth != preferredCodeReviewPanelWidth else { return }
        preferredCodeReviewPanelWidth = clampedWidth
        MainWindowController.storeCodeReviewPanelWidth(clampedWidth)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusActiveTerminalSurface()
        synchronizeActiveSurfaceFocusState(focused: true)
        refreshVisibleTerminalInteractionState()
        injectedAgentDetectionEngine?.resumeTimingDetector()
    }

    func windowDidResignKey(_ notification: Notification) {
        synchronizeActiveSurfaceFocusState(focused: false)
        injectedAgentDetectionEngine?.pauseTimingDetector()
    }

    // MARK: - Tab-to-Session Mapping

    /// Returns the session ID associated with a tab in the registry.
    ///
    /// Falls back to a synthetic `SessionID` based on the tab's raw UUID
    /// when no mapping exists (pre-registry tabs or tests without registry).
    ///
    /// - Parameter tabID: The tab to look up.
    /// - Returns: The session ID for this tab.
    func sessionIDForTab(_ tabID: TabID) -> SessionID {
        if let existing = tabSessionMap[tabID] {
            return existing
        }
        // Deterministic fallback: derive from tabID UUID so the same tab
        // always produces the same session ID, even without a registry.
        return SessionID(rawValue: tabID.rawValue)
    }

    // MARK: - Tab-to-Surface Mapping

    /// Returns the terminal surface view associated with the given tab.
    ///
    /// - Parameter tabID: The tab to look up.
    /// - Returns: The surface view, or nil if no mapping exists.
    func surfaceViewForTab(_ tabID: TabID) -> TerminalHostView? {
        tabSurfaceViews[tabID]
    }

    /// Returns the terminal view model associated with the given tab.
    ///
    /// - Parameter tabID: The tab to look up.
    /// - Returns: The view model, or nil if no mapping exists.
    func viewModelForTab(_ tabID: TabID) -> TerminalViewModel? {
        tabViewModels[tabID]
    }

    /// The number of tab-to-surface mappings. Should match `tabManager.tabs.count`.
    var surfaceViewCount: Int {
        tabSurfaceViews.count
    }

    /// The tab currently shown on screen, falling back to TabManager's active tab
    /// during early setup before `displayedTabID` is established.
    var visibleTabID: TabID? {
        displayedTabID ?? tabManager.activeTabID
    }

    /// The primary terminal ViewModel for the currently visible tab.
    var visibleTabViewModel: TerminalViewModel? {
        guard let tabID = visibleTabID else { return terminalSurfaceView?.terminalViewModel }
        return tabViewModels[tabID] ?? terminalSurfaceView?.terminalViewModel
    }

    /// The terminal surface that should receive interaction right now.
    ///
    /// This prefers the actually focused split pane and only falls back to the
    /// visible tab's primary surface. It avoids targeting stale bootstrap
    /// surfaces after restores, tab switches, or split promotion.
    var activeTerminalSurfaceView: TerminalHostView? {
        if let focused = focusedSplitSurfaceView {
            return focused
        }

        if let visibleTabID, let visiblePrimary = tabSurfaceViews[visibleTabID] {
            return visiblePrimary
        }

        return terminalSurfaceView ?? splitSurfaceViews.values.first
    }

    /// Restores first responder to the active terminal surface, if any.
    func focusActiveTerminalSurface() {
        guard let surfaceView = activeTerminalSurfaceView else { return }
        window?.makeFirstResponder(surfaceView)
        synchronizeActiveSurfaceFocusState(
            focused: window?.isKeyWindow == true && window?.firstResponder === surfaceView
        )
    }

    /// Mirrors the host window's focus state into the active CocxyCore surface.
    ///
    /// AppKit does not guarantee a `becomeFirstResponder` / `resignFirstResponder`
    /// round-trip when the same view survives a window activation change, so the
    /// host also notifies the engine explicitly on key-window transitions.
    func synchronizeActiveSurfaceFocusState(focused: Bool) {
        guard let surfaceID = activeTerminalSurfaceView?.terminalViewModel?.surfaceID else { return }
        bridge.notifyFocus(focused, for: surfaceID)
    }

    /// Returns every terminal view model associated with a tab, including split panes.
    func viewModelsForTab(_ tabID: TabID) -> [TerminalViewModel] {
        var result: [TerminalViewModel] = []
        var seen = Set<ObjectIdentifier>()

        func append(_ viewModel: TerminalViewModel?) {
            guard let viewModel else { return }
            let key = ObjectIdentifier(viewModel)
            guard seen.insert(key).inserted else { return }
            result.append(viewModel)
        }

        append(tabViewModels[tabID])

        if displayedTabID == tabID {
            for viewModel in splitViewModels.values {
                append(viewModel)
            }
        } else {
            let storedViewModels = savedTabSplitViewModels[tabID] ?? [:]
            for viewModel in storedViewModels.values {
                append(viewModel)
            }
        }

        return result
    }

    /// Returns every terminal host view associated with a tab, including split panes.
    func surfaceViewsForTab(_ tabID: TabID) -> [TerminalHostView] {
        var result: [TerminalHostView] = []
        var seen = Set<ObjectIdentifier>()

        func append(_ surfaceView: TerminalHostView?) {
            guard let surfaceView else { return }
            let key = ObjectIdentifier(surfaceView)
            guard seen.insert(key).inserted else { return }
            result.append(surfaceView)
        }

        append(tabSurfaceViews[tabID])

        if displayedTabID == tabID {
            for surfaceView in splitSurfaceViews.values {
                append(surfaceView)
            }
        } else {
            let storedSurfaceViews = savedTabSplitSurfaceViews[tabID] ?? [:]
            for surfaceView in storedSurfaceViews.values {
                append(surfaceView)
            }
        }

        return result
    }

    /// The effective configuration for a tab after applying project overrides.
    func effectiveConfig(for tabID: TabID) -> CocxyConfig {
        let globalConfig = configService?.current ?? .defaults
        guard let projectOverrides = tabManager.tab(for: tabID)?.projectConfig else {
            return globalConfig
        }
        return globalConfig.applying(projectOverrides: projectOverrides)
    }

    /// Applies a font change to the tab's live surfaces without affecting other tabs.
    func applyFontToTab(_ tabID: TabID, size: CGFloat) {
        let effective = effectiveConfig(for: tabID)
        let fontSize = Double(size)

        for viewModel in viewModelsForTab(tabID) {
            viewModel.setCurrentFontSize(size)
        }

        if let cocxyBridge = bridge as? CocxyCoreBridge {
            cocxyBridge.applyFont(
                family: effective.appearance.fontFamily,
                size: fontSize,
                to: surfaceIDs(for: tabID)
            )
        } else {
            for surfaceView in surfaceViewsForTab(tabID) {
                surfaceView.updateInteractionMetrics()
                surfaceView.requestImmediateRedraw()
            }
        }
    }

    /// Switches the visible terminal surface to the one belonging to the given tab.
    ///
    /// Saves the current tab's entire split view hierarchy (NSSplitView tree,
    /// split surface views, view models, and panel content views) into per-tab
    /// dictionaries. Then restores the target tab's saved split state, or falls
    /// back to showing only the primary surface if the target has no splits.
    ///
    /// This ensures that splits in tab 1 do not leak into tab 2 when switching.
    ///
    /// - Parameter tabID: The tab whose surface should become visible.
    // MARK: - DashboardTabNavigating

    func focusTab(id: TabID) -> Bool {
        guard tabManager.tab(for: id) != nil else { return false }
        if tabManager.activeTabID != id {
            tabManager.setActive(id: id)
        } else {
            handleTabSwitch(to: id)
        }
        return true
    }

    func handleTabSwitch(to tabID: TabID) {
        guard let container = terminalContainerView else { return }

        let primarySurfaceView = tabSurfaceViews[tabID]
        let storedPrimarySplitSurface = savedTabSplitSurfaceViews[tabID]?
            .sorted { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }
            .first?
            .value
        let targetSurfaceView = primarySurfaceView
            ?? storedPrimarySplitSurface
            ?? terminalSurfaceView

        // Idempotent only when the visible hierarchy is still attached.
        if displayedTabID == tabID,
           isVisibleHierarchyAttached(for: tabID, in: container) {
            refreshStatusBar()
            refreshTabStrip()
            refreshVisibleTerminalInteractionState()
            return
        }

        // 1. Save the outgoing tab's split state.
        if let outgoing = displayedTabID, outgoing != tabID {
            // Persist the live split hierarchy for the outgoing tab.
            if let splitView = activeSplitView {
                splitView.removeFromSuperview()
                savedTabSplitViews[outgoing] = splitView
            } else {
                terminalSurfaceView?.removeFromSuperview()
            }
            savedTabSplitSurfaceViews[outgoing] = splitSurfaceViews
            savedTabSplitViewModels[outgoing] = splitViewModels
            savedTabPanelContentViews[outgoing] = panelContentViews
        } else {
            // No valid outgoing tab (initial setup): just clear container.
            activeSplitView?.removeFromSuperview()
            terminalSurfaceView?.removeFromSuperview()
        }

        // 2. Restore the target tab's split state.
        let restoredSplitView = savedTabSplitViews.removeValue(forKey: tabID)
        splitSurfaceViews = savedTabSplitSurfaceViews.removeValue(forKey: tabID) ?? [:]
        splitViewModels = savedTabSplitViewModels.removeValue(forKey: tabID) ?? [:]
        panelContentViews = savedTabPanelContentViews.removeValue(forKey: tabID) ?? [:]

        if let splitView = restoredSplitView {
            splitView.frame = container.bounds
            splitView.autoresizingMask = [.width, .height]
            container.addSubview(splitView, positioned: .below, relativeTo: nil)
            activeSplitView = splitView
        } else if let targetSurfaceView {
            activeSplitView = nil
            targetSurfaceView.frame = container.bounds
            targetSurfaceView.autoresizingMask = [.width, .height]
            container.addSubview(targetSurfaceView, positioned: .below, relativeTo: nil)
        } else {
            activeSplitView = nil
            refreshStatusBar()
            refreshTabStrip()
            return
        }

        // 3. Update active references.
        if let targetSurfaceView {
            self.terminalSurfaceView = targetSurfaceView
        }
        self.displayedTabID = tabID

        if let buffer = tabOutputBuffers[tabID] {
            terminalOutputBuffer = buffer
        }

        // 4. Resize is handled automatically by the active terminal host view
        // when the view is laid out in the container. That path uses actual backing
        // pixel dimensions from the view, which is more accurate than the approximate
        // cell sizes we computed here before. Calling resize twice caused a brief
        // flicker when the approximate and actual sizes diverged.

        if let responderSurface = (focusedPaneView() as? TerminalHostView) ?? targetSurfaceView {
            window?.makeFirstResponder(responderSurface)
            responderSurface.hideNotificationRing()
            if let targetSurfaceView, responderSurface !== targetSurfaceView {
                targetSurfaceView.hideNotificationRing()
            }
        }
        refreshVisibleTerminalInteractionState()

        // Propagate read state to the session registry so other windows
        // can clear their badge counts for this session.
        sessionRegistry?.markRead(sessionIDForTab(tabID))

        refreshStatusBar()
        refreshTabStrip()
        updateAgentProgressOverlay()
        applyProjectConfig(for: tabID)
    }

    private func isVisibleHierarchyAttached(for tabID: TabID, in container: NSView) -> Bool {
        if let splitView = activeSplitView {
            return splitView.superview === container
        }

        guard let targetSurfaceView = tabSurfaceViews[tabID] else {
            return false
        }

        return targetSurfaceView.superview === container
    }

    /// Re-syncs the currently visible terminal host views with the live window
    /// geometry and requests an immediate redraw.
    ///
    /// This closes a subtle gap where a surface can process PTY output while it
    /// is detached or still zero-sized. Reattaching the view without an
    /// explicit refresh can leave the terminal visually blank until the next
    /// chunk of output arrives.
    func refreshVisibleTerminalInteractionState() {
        var seen = Set<ObjectIdentifier>()
        let visibleViews = [terminalSurfaceView].compactMap { $0 } + Array(splitSurfaceViews.values)

        for surfaceView in visibleViews {
            let identifier = ObjectIdentifier(surfaceView)
            guard seen.insert(identifier).inserted else { continue }
            surfaceView.updateInteractionMetrics()
            surfaceView.requestImmediateRedraw()
        }
    }

    // MARK: - Project Config

    /// Applies per-project config overrides to the active tab's terminal.
    ///
    /// Called on every tab switch. If the tab has a `.cocxy.toml` config,
    /// its overrides are merged with the global config and applied to the
    /// terminal view model (font size) and window appearance (padding, opacity).
    /// When no project config exists, the global config is reapplied to ensure
    /// switching FROM a project tab TO a non-project tab restores defaults.
    func applyProjectConfig(for tabID: TabID) {
        guard let tab = tabManager.tab(for: tabID) else { return }

        let effective = effectiveConfig(for: tabID)

        // Apply font size to every surface in the tab so restore, zoom and
        // split panes stay visually consistent with the effective config.
        for viewModel in viewModelsForTab(tabID) {
            viewModel.setDefaultFontSize(effective.appearance.fontSize)
        }

        if let cocxyBridge = bridge as? CocxyCoreBridge {
            cocxyBridge.applyFont(
                family: effective.appearance.fontFamily,
                size: effective.appearance.fontSize,
                to: surfaceIDs(for: tabID)
            )
        }

        // Only the visible tab is allowed to mutate window chrome and active
        // project watchers. Background tabs must not override the current UI.
        if visibleTabID == tabID {
            applyEffectiveAppearance(effective.appearance)
            restartProjectConfigWatcher(for: tab)
        }
    }

    /// Returns the working directory associated with a specific terminal surface.
    ///
    /// Used by CocxyCore's semantic layer to map surface-scoped events back to
    /// the owning tab, including split panes that inherit the tab directory.
    func workingDirectory(for surfaceID: SurfaceID) -> URL? {
        if let surfaceWorkingDirectory = surfaceWorkingDirectories[surfaceID] {
            return surfaceWorkingDirectory
        }

        if let tabID = tabID(for: surfaceID) {
            return tabManager.tab(for: tabID)?.workingDirectory
        }

        return nil
    }

    /// Returns the terminal host view that owns a surface ID, if it is still tracked.
    ///
    /// This is used for surface-scoped UI callbacks such as inline image
    /// rendering and shell prompt overlays so split panes do not accidentally
    /// target the primary terminal view.
    func surfaceView(for surfaceID: SurfaceID) -> TerminalHostView? {
        if let tabID = tabSurfaceMap.first(where: { $0.value == surfaceID })?.key {
            return tabSurfaceViews[tabID]
        }

        if let splitView = splitSurfaceViews[surfaceID] {
            return splitView
        }

        for views in savedTabSplitSurfaceViews.values {
            if let splitView = views[surfaceID] {
                return splitView
            }
        }

        return nil
    }

    /// Resolves the owning tab for a given surface ID.
    func tabID(for surfaceID: SurfaceID) -> TabID? {
        if let tabID = tabSurfaceMap.first(where: { $0.value == surfaceID })?.key {
            return tabID
        }

        if splitSurfaceViews[surfaceID] != nil {
            return displayedTabID ?? tabManager.activeTabID
        }

        for (tabID, savedViews) in savedTabSplitSurfaceViews where savedViews[surfaceID] != nil {
            return tabID
        }

        return nil
    }

    /// Returns all surface IDs associated with a tab, including split panes.
    func surfaceIDs(for tabID: TabID) -> [SurfaceID] {
        var ids: [SurfaceID] = []
        var seen = Set<SurfaceID>()

        func append(_ surfaceID: SurfaceID?) {
            guard let surfaceID, seen.insert(surfaceID).inserted else { return }
            ids.append(surfaceID)
        }

        append(tabSurfaceMap[tabID])

        if displayedTabID == tabID {
            for surfaceID in splitSurfaceViews.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
                append(surfaceID)
            }
        }

        let savedSplitIDs = savedTabSplitSurfaceViews[tabID]?.keys.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        } ?? []
        for surfaceID in savedSplitIDs {
            append(surfaceID)
        }

        return ids
    }

    /// Restarts the file watcher for the active tab's `.cocxy.toml`.
    ///
    /// Stops any existing watcher and starts a new one pointing to the
    /// `.cocxy.toml` in the tab's working directory (or nearest parent).
    private func restartProjectConfigWatcher(for tab: Tab) {
        projectConfigWatcher?.stopWatching()
        projectConfigWatcher = nil

        // Find the .cocxy.toml path (same traversal as loadConfig).
        let service = ProjectConfigService()
        let configPath = service.findConfigPath(for: tab.workingDirectory)
        guard let configPath else { return }

        let watcher = ProjectConfigWatcher(configFilePath: configPath)
        watcher.startWatching { [weak self, tabID = tab.id] in
            // Re-load project config and re-apply.
            guard let self else { return }
            let newConfig = ProjectConfigService().loadConfig(
                for: self.tabManager.tab(for: tabID)?.workingDirectory
                    ?? FileManager.default.homeDirectoryForCurrentUser
            )
            self.tabManager.updateTab(id: tabID) { tab in
                tab.projectConfig = newConfig
            }
            self.applyProjectConfig(for: tabID)
        }
        self.projectConfigWatcher = watcher
    }

    /// Applies appearance settings to the window chrome.
    ///
    /// Updates background opacity and vibrancy for the window, sidebar,
    /// tab strip, and status bar. Called when switching tabs with different
    /// project configs or when the user changes the background-opacity setting.
    func applyEffectiveAppearance(_ appearance: AppearanceConfig) {
        guard let window = window else { return }

        let isTransparent = appearance.backgroundOpacity < 1.0

        // Apply background opacity to the window.
        // When transparent: apply alpha to the current background color (set by theme).
        // When opaque: restore full alpha on the current color (preserves theme choice).
        window.isOpaque = !isTransparent
        window.backgroundColor = window.backgroundColor?.withAlphaComponent(
            isTransparent ? appearance.backgroundOpacity : 1.0
        )

        // Propagate vibrancy state to all chrome components.
        tabBarView?.setSidebarTransparent(isTransparent)

        if let strip = horizontalTabStripView as? HorizontalTabStripView {
            strip.setTransparent(isTransparent)
        }

        // Update status bar vibrancy and hosting view background.
        if let hostingView = statusBarHostingView {
            hostingView.layer?.backgroundColor = isTransparent
                ? NSColor.clear.cgColor
                : CocxyColors.crust.cgColor
            hostingView.rootView.useVibrancy = isTransparent
        }
    }

    // MARK: - Tab Actions

    /// Creates a new tab using the active tab's working directory.
    /// Wired to Cmd+T via the File menu.
    @objc func newTabAction(_ sender: Any?) {
        createTab()
    }

    /// Closes the active tab. Wired to Cmd+W via the File menu.
    @objc func closeTabAction(_ sender: Any?) {
        guard let activeID = tabManager.activeTabID else { return }
        closeTab(activeID)
    }

    /// Navigates to the next tab. Wired to Cmd+Shift+].
    @objc func nextTabAction(_ sender: Any?) {
        tabManager.nextTab()
    }

    /// Navigates to the previous tab. Wired to Cmd+Shift+[.
    @objc func previousTabAction(_ sender: Any?) {
        tabManager.previousTab()
    }

    /// Navigates to a tab by its 1-based index (Cmd+1 through Cmd+9).
    @objc func gotoTab1(_ sender: Any?) { tabManager.gotoTab(at: 0) }
    @objc func gotoTab2(_ sender: Any?) { tabManager.gotoTab(at: 1) }
    @objc func gotoTab3(_ sender: Any?) { tabManager.gotoTab(at: 2) }
    @objc func gotoTab4(_ sender: Any?) { tabManager.gotoTab(at: 3) }
    @objc func gotoTab5(_ sender: Any?) { tabManager.gotoTab(at: 4) }
    @objc func gotoTab6(_ sender: Any?) { tabManager.gotoTab(at: 5) }
    @objc func gotoTab7(_ sender: Any?) { tabManager.gotoTab(at: 6) }
    @objc func gotoTab8(_ sender: Any?) { tabManager.gotoTab(at: 7) }
    @objc func gotoTab9(_ sender: Any?) { tabManager.gotoTab(at: 8) }

    // MARK: - Quick Switch Action

    /// Quick Switch to the next tab with unread attention. Wired to Cmd+Shift+U.
    ///
    /// Delegates to the `quickSwitchController` if configured, otherwise no-op.
    @objc func quickSwitchAction(_ sender: Any?) {
        guard let quickSwitch = quickSwitchController else { return }
        _ = quickSwitch.performQuickSwitch()
    }

    /// The Quick Switch controller. Set by AppDelegate after initialization.
    var quickSwitchController: QuickSwitchController?

    // MARK: - Zoom Actions

    /// Increases the terminal font size by one step. Wired to Cmd++ via the View menu.
    @objc func zoomInAction(_ sender: Any?) {
        guard let tabID = visibleTabID,
              let viewModel = viewModelForTab(tabID) else { return }
        let newSize = viewModel.zoomIn()
        applyFontToTab(tabID, size: newSize)
    }

    /// Decreases the terminal font size by one step. Wired to Cmd+- via the View menu.
    @objc func zoomOutAction(_ sender: Any?) {
        guard let tabID = visibleTabID,
              let viewModel = viewModelForTab(tabID) else { return }
        let newSize = viewModel.zoomOut()
        applyFontToTab(tabID, size: newSize)
    }

    /// Resets the terminal font size to the configured default. Wired to Cmd+0 via the View menu.
    @objc func resetZoomAction(_ sender: Any?) {
        guard let tabID = visibleTabID,
              let viewModel = viewModelForTab(tabID) else { return }
        let newSize = viewModel.resetZoom()
        applyFontToTab(tabID, size: newSize)
    }

    // MARK: - Tab Bar Toggle

    /// Whether the tab bar sidebar is currently hidden.
    private(set) var isTabBarHidden: Bool = false

    /// Toggles the visibility of the tab bar sidebar. Wired to View > Toggle Tab Bar.
    ///
    /// Uses NSSplitView's collapse support to hide/show the sidebar subview.
    /// When hiding, the sidebar collapses to zero width. When showing, it
    /// restores to the configured sidebar width.
    @objc func toggleTabBarAction(_ sender: Any?) {
        guard let splitView = mainSplitView, let sidebar = tabBarView else { return }

        if isTabBarHidden {
            // Restore the sidebar by setting its position to the default width.
            splitView.setPosition(Self.sidebarWidth, ofDividerAt: 0)
            sidebar.isHidden = false
            isTabBarHidden = false
        } else {
            // Collapse the sidebar by setting divider position to 0.
            splitView.setPosition(0, ofDividerAt: 0)
            sidebar.isHidden = true
            isTabBarHidden = true
        }
    }

    // MARK: - New Window Action

    /// Creates a new application window. Wired to Cmd+N via the File menu.
    ///
    /// Creates a new `MainWindowController` with a fresh tab and terminal,
    /// registers it with the `AppDelegate` for lifecycle management.
    @objc func newWindowAction(_ sender: Any?) {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let newController = appDelegate.makeWindowController(registerInitialSession: true) else {
            NSLog("[MainWindowController] Cannot create new window: no bridge available")
            return
        }

        newController.showWindow(nil)
        newController.window?.center()
        newController.createTerminalSurface()

        if let surfaceView = newController.terminalSurfaceView {
            newController.window?.makeFirstResponder(surfaceView)
        }

        appDelegate.additionalWindowControllers.append(newController)
    }

    // MARK: - Help Action

    /// Opens the help documentation. Wired to Help > Cocxy Terminal Help.
    ///
    /// Attempts to open the docs directory in Finder. Falls back to opening
    /// the README if the docs directory does not exist.
    @objc func openHelpAction(_ sender: Any?) {
        let bundlePath = Bundle.main.bundlePath
        let projectRoot = URL(fileURLWithPath: bundlePath)
            .deletingLastPathComponent()

        // Try docs directory first, then README.
        let candidates = [
            projectRoot.appendingPathComponent("docs"),
            projectRoot.appendingPathComponent("README.md"),
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                NSWorkspace.shared.open(candidate)
                return
            }
        }

        NSLog("[MainWindowController] Help: no documentation found near %@", bundlePath)
    }

    // MARK: - NSSplitViewDelegate (Sidebar Width Control)

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard splitView === mainSplitView, dividerIndex == 0 else {
            return proposedMinimumPosition
        }
        return Self.sidebarMinWidth
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard splitView === mainSplitView, dividerIndex == 0 else {
            return proposedMaximumPosition
        }
        return Self.sidebarMaxWidth
    }

    func splitView(
        _ splitView: NSSplitView,
        canCollapseSubview subview: NSView
    ) -> Bool {
        // The sidebar can be collapsed; the terminal cannot.
        return subview === tabBarView
    }

    func splitView(
        _ splitView: NSSplitView,
        shouldAdjustSizeOfSubview view: NSView
    ) -> Bool {
        // When the window resizes, only adjust the terminal (index 1), not the sidebar.
        return view !== tabBarView
    }
}

// MARK: - Passthrough View

/// An NSView that passes mouse events through to views behind it
/// when it has no subviews (no overlays visible).
///
/// Used as the overlay container so that mouse clicks reach the terminal
/// when no overlay (Command Palette, Dashboard, etc.) is shown.
@MainActor
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        // If the only hit is ourselves (no subview matched), pass through.
        return result === self ? nil : result
    }
}

@MainActor
final class FocusableHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }
}
