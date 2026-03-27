// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController.swift - Main window management and layout.

import AppKit
import Combine
import SwiftUI

// MARK: - Main Window Controller

/// Controls the main application window layout.
///
/// The window contains a `TerminalSurfaceView` as its content view,
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
/// - SeeAlso: `TerminalSurfaceView`
/// - SeeAlso: `TerminalViewModel`
/// - SeeAlso: `ConfigService`
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate {

    // MARK: - Properties

    /// The ViewModel driving the terminal surface in this window.
    let terminalViewModel: TerminalViewModel

    /// The terminal surface view that renders the terminal.
    /// Mutable from extensions (TabLifecycle needs to nil it during tab close).
    internal var terminalSurfaceView: TerminalSurfaceView?

    /// Reference to the terminal engine bridge. Mutable so AppDelegate can
    /// replace it during theme switching (requires a fresh ghostty instance).
    var bridge: GhosttyBridge

    /// Optional reference to the configuration service.
    let configService: ConfigService?

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

    /// Maps tab IDs to their terminal surface views.
    /// Internal access for session restoration in AppDelegate.
    var tabSurfaceViews: [TabID: TerminalSurfaceView] = [:]

    /// Maps tab IDs to their terminal view models.
    /// Internal access for session restoration in AppDelegate.
    var tabViewModels: [TabID: TerminalViewModel] = [:]

    /// Coordinates split pane managers per tab.
    let tabSplitCoordinator = TabSplitCoordinator()

    /// The split container view for the active tab (when splits are active).
    private(set) var splitContainer: SplitContainer?

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

    var timelineHostingView: NSHostingView<TimelineView>?
    var isTimelineVisible: Bool = false
    private(set) lazy var timelineDispatcher: TimelineNavigationDispatcher = {
        let dispatcher = TimelineNavigationDispatcher()
        dispatcher.navigator = TimelineNavigatorStub()
        return dispatcher
    }()

    var welcomeHostingView: NSHostingView<WelcomeOverlayView>?
    var isWelcomeVisible: Bool = false

    var notificationPanelViewModel: NotificationPanelViewModel?
    var notificationPanelHostingView: NSHostingView<NotificationPanelView>?
    var isNotificationPanelVisible: Bool = false

    var browserViewModel: BrowserViewModel?
    var browserHostingView: NSHostingView<BrowserPanelView>?
    var isBrowserVisible: Bool = false

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

    /// Per-tab command duration trackers keyed by tab ID.
    /// Each tracker parses OSC 133 ;B (start) and ;D (finish) from raw terminal output.
    var tabCommandTrackers: [TabID: CommandDurationTracker] = [:]

    /// Per-tab inline image OSC detectors keyed by tab ID.
    /// Each detector parses OSC 1337 sequences with a 16MB buffer (vs 4KB
    /// in the general `OSCSequenceDetector`) to handle large image payloads.
    var tabImageDetectors: [TabID: InlineImageOSCDetector] = [:]

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

    /// Port scanner for detecting active dev servers. Injected by AppDelegate.
    var portScanner: PortScannerImpl?

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

    /// All split surface views keyed by their surface ID, for recursive splits.
    var splitSurfaceViews: [SurfaceID: TerminalSurfaceView] = [:]

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

    /// Saved split surface views per tab. Keyed by tab ID, each value
    /// maps surface IDs to their TerminalSurfaceView instances.
    var savedTabSplitSurfaceViews: [TabID: [SurfaceID: TerminalSurfaceView]] = [:]

    /// Saved split view models per tab.
    var savedTabSplitViewModels: [TabID: [SurfaceID: TerminalViewModel]] = [:]

    /// Saved non-terminal panel views per tab.
    var savedTabPanelContentViews: [TabID: [UUID: NSView]] = [:]

    // MARK: - Initialization

    /// Creates a MainWindowController with the given bridge and optional config.
    ///
    /// - Parameters:
    ///   - bridge: The terminal engine bridge used for surface creation.
    ///   - configService: Optional configuration service for reading window settings.
    init(bridge: GhosttyBridge, configService: ConfigService? = nil, tabManager: TabManager? = nil) {
        self.bridge = bridge
        self.configService = configService
        self.tabManager = tabManager ?? TabManager()
        self.terminalViewModel = TerminalViewModel(bridge: bridge)

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
        configureWindow(window)
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

        let sidebar = TabBarView(viewModel: tabBarVM)
        sidebar.onCommandPalette = { [weak self] in self?.toggleCommandPalette() }
        sidebar.onNotificationPanel = { [weak self] in self?.toggleNotificationPanel() }
        if let appearance = configService?.current.appearance {
            sidebar.setSidebarTransparent(appearance.backgroundOpacity < 1.0)
        }
        sidebar.confirmCloseProcess = configService?.current.general.confirmCloseProcess ?? false
        self.tabBarViewModel = tabBarVM
        self.tabBarView = sidebar
        return sidebar
    }

    private func buildTerminalSurface() -> TerminalSurfaceView {
        let surfaceView = TerminalSurfaceView(viewModel: terminalViewModel)
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
        strip.onClosePanel = { [weak self] in self?.closeLastPanel() }
        strip.onSelectTab = { [weak self] index in self?.handleStripSelectTab(at: index) }
        strip.onCloseTab = { [weak self] index in self?.handleStripCloseTab(at: index) }
        strip.onSwapTabs = { [weak self] from, to in self?.handleStripSwapTabs(from: from, to: to) }
        strip.onRenameTab = { [weak self] index, name in self?.handleStripRenameTab(at: index, newTitle: name) }
        return strip
    }

    private func buildTerminalArea(in outerContainer: NSView, surfaceView: TerminalSurfaceView) -> NSView {
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
        let statusBar = StatusBarView(
            hostname: currentHostname(),
            gitBranch: tabManager.activeTab?.gitBranch,
            agentSummary: computeAgentSummary(),
            activePorts: [],
            sshSession: tabManager.activeTab?.sshSession
        )
        let statusBarHost = NSHostingView(rootView: statusBar)
        statusBarHost.frame = NSRect(x: 0, y: 0, width: contentFrame.width, height: Self.statusBarHeight)
        statusBarHost.wantsLayer = true
        statusBarHost.layer?.backgroundColor = CocxyColors.crust.cgColor
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
        guard let tabID = tabManager.activeTabID else { return }
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
        guard let tabID = tabManager.activeTabID else { return }
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
        guard let tabID = tabManager.activeTabID else { return }
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
        guard let tabID = tabManager.activeTabID else { return }
        let sm = tabSplitCoordinator.splitManager(for: tabID)
        sm.swapLeaves(at: fromIndex, with: toIndex)

        let leafViews = collectLeafViews()
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
        }

        refreshTabStrip()
    }

    private func handleStripRenameTab(at index: Int, newTitle: String) {
        guard let tabID = tabManager.activeTabID else { return }
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

    /// Initializes the process monitor for SSH/process detection.
    ///
    /// The monitor subscribes to process changes but does NOT start polling
    /// automatically. Shell PID registration requires GhosttyBridge to expose
    /// the PTY child PID, which is not yet available.
    ///
    /// Starts the process monitor service and subscribes to process changes.
    ///
    /// The monitor polls foreground processes every 2 seconds using `sysctl`.
    /// When a tab's foreground process changes (e.g., `zsh` -> `ssh`), it
    /// updates the tab model and refreshes the UI.
    ///
    /// Tabs are registered with `processMonitor.registerTab(_:shellPID:)`
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
        }
        tabBarViewModel?.syncWithManager()
        refreshStatusBar()
        refreshTabStrip()
    }

    /// Returns the PIDs of child processes of the current app process.
    ///
    /// Used before and after `createSurface` to identify the new shell
    /// process by comparing snapshots.
    func snapshotChildPIDs() -> [pid_t] {
        ForegroundProcessDetector.childProcesses(of: getpid()) ?? []
    }

    /// Finds the first PID in `current` that was not present in `previous`.
    ///
    /// Used after `createSurface` to identify the newly spawned shell PID
    /// so it can be registered with the process monitor for SSH detection.
    ///
    /// - Parameters:
    ///   - current: Child PIDs after surface creation.
    ///   - previous: Child PIDs before surface creation.
    /// - Returns: The new shell PID, or nil if no new process was found.
    func findNewShellPID(current: [pid_t], previous: [pid_t]) -> pid_t? {
        let previousSet = Set(previous)
        return current.first { !previousSet.contains($0) }
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

        if let strip = horizontalTabStripView as? HorizontalTabStripView {
            strip.onAddTab = nil
            strip.onAddBrowser = nil
            strip.onAddMarkdown = nil
            strip.onAddStackedTerminal = nil
            strip.onSelectTab = nil
            strip.onCloseTab = nil
            strip.onSwapTabs = nil
        }

        searchQueryCancellable?.cancel()
        searchQueryCancellable = nil

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
    }

    func windowDidBecomeMain(_ notification: Notification) {
        // Ensure the terminal view has focus when the window becomes main.
        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let surfaceView = terminalSurfaceView {
            window?.makeFirstResponder(surfaceView)
        }
        injectedAgentDetectionEngine?.resumeTimingDetector()
    }

    func windowDidResignKey(_ notification: Notification) {
        injectedAgentDetectionEngine?.pauseTimingDetector()
    }

    // MARK: - Tab-to-Surface Mapping

    /// Returns the terminal surface view associated with the given tab.
    ///
    /// - Parameter tabID: The tab to look up.
    /// - Returns: The surface view, or nil if no mapping exists.
    func surfaceViewForTab(_ tabID: TabID) -> TerminalSurfaceView? {
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
    func handleTabSwitch(to tabID: TabID) {
        guard let targetSurfaceView = tabSurfaceViews[tabID] else { return }
        guard let container = terminalContainerView else { return }

        // Idempotent: skip if this tab is already displayed.
        if displayedTabID == tabID {
            refreshStatusBar()
            refreshTabStrip()
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
        } else {
            activeSplitView = nil
            targetSurfaceView.frame = container.bounds
            targetSurfaceView.autoresizingMask = [.width, .height]
            container.addSubview(targetSurfaceView, positioned: .below, relativeTo: nil)
        }

        // 3. Update active references.
        self.terminalSurfaceView = targetSurfaceView
        self.displayedTabID = tabID

        if let buffer = tabOutputBuffers[tabID] {
            terminalOutputBuffer = buffer
        }

        // 4. Notify libghostty of the surface size after re-adding to container.
        // Without this, the terminal renders at its old size until the user resizes
        // the window. This ensures the terminal fills the container immediately.
        if let surfaceID = tabSurfaceMap[tabID] {
            let bounds = container.bounds
            let cols = UInt16(max(1, bounds.width / 8))   // approximate cell width
            let rows = UInt16(max(1, bounds.height / 16)) // approximate cell height
            bridge.resize(surfaceID, to: TerminalSize(
                columns: cols,
                rows: rows,
                pixelWidth: UInt16(clamping: Int(bounds.width)),
                pixelHeight: UInt16(clamping: Int(bounds.height))
            ))
        }

        window?.makeFirstResponder(targetSurfaceView)
        targetSurfaceView.hideNotificationRing()

        refreshStatusBar()
        refreshTabStrip()
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
        terminalViewModel.zoomIn()
    }

    /// Decreases the terminal font size by one step. Wired to Cmd+- via the View menu.
    @objc func zoomOutAction(_ sender: Any?) {
        terminalViewModel.zoomOut()
    }

    /// Resets the terminal font size to the configured default. Wired to Cmd+0 via the View menu.
    @objc func resetZoomAction(_ sender: Any?) {
        terminalViewModel.resetZoom()
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
              let existingBridge = appDelegate.bridge else {
            NSLog("[MainWindowController] Cannot create new window: no bridge available")
            return
        }

        let newController = MainWindowController(
            bridge: existingBridge,
            configService: configService
        )
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
