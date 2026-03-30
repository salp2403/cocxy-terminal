// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate.swift - NSApplicationDelegate handling app lifecycle.

import AppKit
import Combine
import UserNotifications

/// Main application delegate for Cocxy Terminal.
///
/// Responsibilities:
/// - Initialize the `GhosttyBridge` terminal engine at launch.
/// - Create and manage the main window via `MainWindowController`.
/// - Coordinate app lifecycle events (launch, terminate, activate).
/// - Trigger session save/restore at appropriate lifecycle points.
///
/// ## Extensions
///
/// Responsibilities are distributed across focused extension files:
/// - `+MenuSetup.swift` — Application menu bar construction.
/// - `+SessionManagement.swift` — Session persistence and restoration.
/// - `+AgentWiring.swift` — Agent detection engine setup and event wiring.
/// - `+RemoteWorkspace.swift` — Remote workspace service initialization.
/// - `+BrowserPro.swift` — Browser Pro service initialization.
///
/// This delegate is intentionally thin. Business logic belongs in services
/// and view models, not here.
///
/// ## Lifecycle
///
/// ```
/// applicationDidFinishLaunching
///   -> Create GhosttyBridge
///   -> Initialize bridge (config + ghostty_app)
///   -> Initialize agent detection engine (before window!)
///   -> Create MainWindowController
///   -> Show window
///   -> Create terminal surface (engine already available)
///   -> Wire agent detection to window
///
/// applicationWillTerminate
///   -> Destroy terminal surface
///   -> MainWindowController = nil
///   -> Bridge = nil (deinit frees ghostty_app + config)
/// ```
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// The terminal engine bridge. Created during app launch.
    /// Exposed for testing purposes.
    private(set) var bridge: GhosttyBridge?

    /// The main window controller. Created during app launch.
    /// Exposed for testing purposes.
    private(set) var windowController: MainWindowController?

    /// The configuration service. Created during app launch.
    /// Exposed for testing purposes.
    private(set) var configService: ConfigService?

    /// The macOS notification adapter. Created during app launch.
    /// Exposed for testing purposes.
    private(set) var notificationAdapter: MacOSNotificationAdapter?

    /// The notification manager. Created during app launch.
    /// Exposed for testing purposes.
    private(set) var notificationManager: NotificationManagerImpl?

    /// The dock badge controller. Created during app launch.
    /// Exposed for testing purposes.
    private(set) var dockBadgeController: DockBadgeController?

    /// The quick switch controller. Created during app launch.
    /// Exposed for testing purposes.
    private(set) var quickSwitchController: QuickSwitchController?

    /// The quick terminal controller. Created during app launch.
    /// Manages the global dropdown terminal panel and hotkey.
    /// Exposed for testing purposes.
    private(set) var quickTerminalController: QuickTerminalController?

    /// The shared theme engine. Created once and injected where needed
    /// to avoid redundant file system scanning.
    private(set) var themeEngine: ThemeEngineImpl?

    /// The session manager for persistence and restoration.
    /// Internal setter: extensions (+SessionManagement) assign during init.
    var sessionManager: SessionManagerImpl?

    /// The quick terminal view model for state management.
    /// Internal setter: extensions (+SessionManagement) assign during init.
    var quickTerminalViewModel: QuickTerminalViewModel?

    /// The socket server for CLI companion communication.
    /// Exposed for testing purposes.
    private(set) var socketServer: SocketServerImpl?

    /// Timer that periodically checks if the socket file still exists.
    /// If the file disappears (e.g., due to a race condition), the server
    /// is automatically restarted to restore hook connectivity.
    private var socketHealthTimer: Timer?

    /// The hook event receiver for Claude Code integration.
    /// Internal setter: extensions (+AgentWiring) assign during engine init.
    var hookEventReceiver: HookEventReceiverImpl?

    /// The agent detection engine for terminal output analysis.
    /// Internal setter: extensions (+AgentWiring) assign during engine init.
    var agentDetectionEngine: AgentDetectionEngineImpl?

    /// The port scanner for detecting active dev servers on localhost.
    /// Exposed for testing purposes.
    private(set) var portScanner: PortScannerImpl?

    /// The appearance observer for auto-switching dark/light themes.
    private(set) var appearanceObserver: AppearanceObserver?

    /// Menu bar status item showing agent count.
    private(set) var menuBarItem: MenuBarStatusItem?

    /// Additional window controllers for multi-window support.
    /// Each entry retains a MainWindowController to prevent deallocation.
    /// Internal access so `MainWindowController.newWindowAction` can append.
    var additionalWindowControllers: [MainWindowController] = []

    /// Cancellables for hook-to-engine wiring and agent-to-tab wiring.
    var hookCancellables = Set<AnyCancellable>()

    /// The timeline store for agent events. Created alongside the engine.
    /// Internal setter: extensions (+AgentWiring) assign during engine init.
    var agentTimelineStore: AgentTimelineStoreImpl?

    /// The dashboard ViewModel for agent sessions. Created alongside the engine.
    /// Internal setter: extensions (+AgentWiring) assign during engine init.
    var agentDashboardViewModel: AgentDashboardViewModel?

    /// The agent config service for agents.toml hot-reload.
    /// Internal setter: extensions (+AgentWiring) assign during engine init.
    var agentConfigService: AgentConfigService?

    /// The agent config file watcher for hot-reload.
    /// Internal setter: extensions (+AgentWiring) assign during engine init.
    var agentConfigWatcher: AgentConfigWatcher?

    // MARK: - Remote Workspace Properties

    /// Remote connection manager for SSH session orchestration.
    /// Internal setter: extensions (+RemoteWorkspace) assign during setup.
    var remoteConnectionManager: RemoteConnectionManager?

    /// Remote profile store for SSH connection profile persistence.
    /// Internal setter: extensions (+RemoteWorkspace) assign during setup.
    var remoteProfileStore: RemoteProfileStore?

    // MARK: - Plugin Properties

    /// Plugin manager for plugin lifecycle operations.
    var pluginManager: PluginManager?

    // MARK: - Browser Pro Properties

    /// Browser profile manager for multi-profile browsing.
    /// Internal setter: extensions (+BrowserPro) assign during setup.
    var browserProfileManager: BrowserProfileManager?

    /// Browser history store with full-text search.
    /// Internal setter: extensions (+BrowserPro) assign during setup.
    var browserHistoryStore: BrowserHistoryStoring?

    /// Browser bookmark store with tree structure.
    /// Internal setter: extensions (+BrowserPro) assign during setup.
    var browserBookmarkStore: BrowserBookmarkStoring?

    /// The Sparkle auto-update manager.
    /// Internal setter: extension (+AutoUpdate) assigns during setup.
    var sparkleUpdater: SparkleUpdater?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        themeEngine = ThemeEngineImpl()
        initializeConfigService()
        initializeSessionManager()
        setupMainMenu()
        initializeBridge()
        initializeAgentDetectionEngine()
        createMainWindow()
        wireAgentDetectionToWindow()
        initializeNotificationStack()
        wireAgentDetectionToNotifications()
        initializePortScanner()
        setupPlugins()
        initializeSocketServer()
        initializeQuickTerminal()
        initializeAppearanceObserver()
        setupRemoteWorkspace()
        setupBrowserPro()
        setupAutoUpdate()
        restoreSessionOnLaunch()
        applyPlaceholderAppIcon()
        performFirstLaunchSetup()
        showWelcomeOnFirstLaunch()
        initializeMenuBarItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save the current session synchronously before shutting down.
        saveSessionBeforeTermination()

        // Stop the appearance observer before tear down.
        appearanceObserver?.stopObserving()
        appearanceObserver = nil

        // Remove menu bar item.
        menuBarItem?.uninstall()
        menuBarItem = nil

        // Release plugins, remote workspace, browser, and update services.
        pluginManager = nil
        remoteConnectionManager = nil
        remoteProfileStore = nil
        browserProfileManager = nil
        browserHistoryStore = nil
        browserBookmarkStore = nil
        sparkleUpdater = nil

        // Stop the agent config watcher before services are torn down.
        agentConfigWatcher?.stopWatching()
        agentConfigWatcher = nil
        agentConfigService = nil

        // Stop the port scanner before other services are torn down.
        portScanner?.stopScanning()
        portScanner = nil

        // Stop the socket health check timer and server.
        socketHealthTimer?.invalidate()
        socketHealthTimer = nil
        socketServer?.stop()
        socketServer = nil

        // Tear down the quick terminal before the bridge is deallocated.
        quickTerminalController?.tearDown()
        quickTerminalController = nil

        // Destroy all terminal surfaces across all windows before the bridge
        // is deallocated. This includes split panes and additional windows.
        for additionalController in additionalWindowControllers {
            additionalController.destroyAllSurfaces()
        }
        additionalWindowControllers.removeAll()
        windowController?.destroyAllSurfaces()
        windowController = nil
        bridge = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit Cocxy Terminal?"
        alert.informativeText = "All terminal sessions will be closed."
        alert.alertStyle = .warning
        alert.icon = AppIconGenerator.generatePlaceholderIcon()
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The app stays alive even with no windows so the Quick Terminal
        // can respond to the global hotkey (Cmd+`).
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure the main window is visible when the app is activated
        // (e.g., via Dock click).
        windowController?.showWindow(nil)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            if let wc = windowController, wc.window?.isVisible == true {
                wc.showWindow(nil)
            } else {
                // Window was closed — recreate it.
                // Clear existing Combine subscriptions to prevent duplicate
                // subscribers accumulating on engine.stateChanged.
                hookCancellables.removeAll()

                // Stop the old socket server BEFORE creating a new one.
                // Without this, the old server's deinit runs after the new
                // server binds, and removeStaleSocketFile() deletes the
                // new server's socket file (race condition).
                socketServer?.stop()
                socketServer = nil

                createMainWindow()
                wireAgentDetectionToWindow()
                initializeNotificationStack()
                wireAgentDetectionToNotifications()
                initializeSocketServer()
            }
        }
        return true
    }

    // MARK: - Config Initialization

    /// Initializes the configuration service and loads config from disk.
    private func initializeConfigService() {
        let service = ConfigService()
        do {
            try service.reload()
        } catch {
            NSLog("[AppDelegate] Failed to load config: %@",
                  String(describing: error))
            // Continue with defaults -- ConfigService handles this gracefully.
        }
        self.configService = service
    }

    // MARK: - Bridge Initialization

    /// Initializes the GhosttyBridge with configuration from ConfigService.
    private func initializeBridge() {
        let newBridge = GhosttyBridge()

        let fontFamily = configService?.current.appearance.fontFamily
            ?? AppearanceConfig.defaults.fontFamily
        let fontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize
        let theme = configService?.current.appearance.theme
            ?? AppearanceConfig.defaults.theme
        let shell = configService?.current.general.shell
            ?? GeneralConfig.defaults.shell

        // Resolve the theme palette to pass to the terminal engine.
        let resolvedPalette: ThemePalette?
        if let resolved = try? themeEngine?.themeByName(theme) {
            resolvedPalette = resolved.palette
        } else {
            // Fall back to Catppuccin Mocha (the default).
            resolvedPalette = themeEngine?.activeTheme.palette
        }

        let config = TerminalEngineConfig(
            fontFamily: fontFamily,
            fontSize: fontSize,
            themeName: theme,
            shell: shell,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            themePalette: resolvedPalette
        )

        do {
            try newBridge.initialize(config: config)
            self.bridge = newBridge
        } catch {
            NSLog("[AppDelegate] Failed to initialize GhosttyBridge: %@",
                  String(describing: error))
            // The app can still show a window with an error state.
            // For now, we proceed without a bridge.
        }
    }

    // MARK: - Theme Switching

    /// Switches the terminal theme by recreating the bridge and all surfaces.
    ///
    /// This is the only way to change ghostty's color palette at runtime:
    /// the C API requires a fresh `ghostty_config` + `ghostty_app` pair.
    ///
    /// The method preserves the user's workspace state:
    /// 1. Captures each tab's working directory and title.
    /// 2. Destroys all surfaces and the old bridge.
    /// 3. Creates a new bridge with the target theme palette.
    /// 4. Recreates a surface for every tab at its saved working directory.
    /// 5. Restores the active tab and re-wires all handlers.
    ///
    /// Shell sessions restart — there is no way around this because ghostty
    /// owns the PTY and the PTY is bound to the surface.
    ///
    /// - Parameter themeName: Display name of the target theme (e.g., "One Dark").
    /// Snapshot of tab state captured before theme switch destroys surfaces.
    private struct ThemeSwitchTabSnapshot {
        let id: TabID
        let title: String
        let workingDirectory: URL
    }

    func switchTheme(to themeName: String) {
        guard let windowController = windowController else { return }

        // 1. Resolve the new theme palette.
        guard let theme = try? themeEngine?.themeByName(themeName) else {
            NSLog("[AppDelegate] Theme not found: %@", themeName)
            return
        }

        // 2. Capture state, destroy surfaces, rebuild with new theme.
        let (snapshots, activeIndex) = captureTabState(windowController)
        destroyAllSurfaces(windowController)

        guard let newBridge = createBridgeForTheme(themeName, palette: theme.palette) else {
            return
        }

        recreateTabSurfaces(
            windowController: windowController,
            bridge: newBridge,
            snapshots: snapshots
        )

        // 2b. Recreate surfaces for additional windows (Cmd+N windows).
        for controller in additionalWindowControllers {
            let (addSnapshots, _) = captureTabState(controller)
            recreateTabSurfaces(
                windowController: controller,
                bridge: newBridge,
                snapshots: addSnapshots
            )
            controller.bridge = newBridge
        }

        // 3. Restore focus and update UI.
        windowController.injectedAgentDetectionEngine = agentDetectionEngine
        restoreActiveTab(windowController, tabs: windowController.tabManager.tabs, activeIndex: activeIndex)
        applyThemeUI(windowController, palette: theme.palette)

        NSLog("[AppDelegate] Theme switched to: %@", themeName)
    }

    // MARK: - Theme Switch Helpers

    private func captureTabState(_ wc: MainWindowController) -> ([ThemeSwitchTabSnapshot], Int) {
        let activeIndex = wc.tabManager.tabs.firstIndex {
            $0.id == wc.tabManager.activeTabID
        } ?? 0

        let snapshots = wc.tabManager.tabs.map {
            ThemeSwitchTabSnapshot(id: $0.id, title: $0.title, workingDirectory: $0.workingDirectory)
        }
        return (snapshots, activeIndex)
    }

    private func destroyAllSurfaces(_ wc: MainWindowController) {
        wc.destroyAllSurfaces()
        for controller in additionalWindowControllers {
            controller.destroyAllSurfaces()
        }
        bridge = nil
    }

    private func createBridgeForTheme(_ themeName: String, palette: ThemePalette) -> GhosttyBridge? {
        let newBridge = GhosttyBridge()
        let fontFamily = configService?.current.appearance.fontFamily
            ?? AppearanceConfig.defaults.fontFamily
        let fontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize
        let shell = configService?.current.general.shell
            ?? GeneralConfig.defaults.shell

        let engineConfig = TerminalEngineConfig(
            fontFamily: fontFamily,
            fontSize: fontSize,
            themeName: themeName,
            shell: shell,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            themePalette: palette
        )

        do {
            try newBridge.initialize(config: engineConfig)
        } catch {
            NSLog("[AppDelegate] Failed to initialize bridge for theme switch: %@",
                  String(describing: error))
            return nil
        }
        self.bridge = newBridge
        return newBridge
    }

    private func recreateTabSurfaces(
        windowController wc: MainWindowController,
        bridge newBridge: GhosttyBridge,
        snapshots: [ThemeSwitchTabSnapshot]
    ) {
        wc.bridge = newBridge
        let tabs = wc.tabManager.tabs

        for (index, tab) in tabs.enumerated() {
            let snapshot = index < snapshots.count
                ? snapshots[index]
                : ThemeSwitchTabSnapshot(id: tab.id, title: tab.title, workingDirectory: tab.workingDirectory)

            let viewModel = TerminalViewModel(bridge: newBridge)
            let configuredFontSize = configService?.current.appearance.fontSize
                ?? AppearanceConfig.defaults.fontSize
            viewModel.setDefaultFontSize(configuredFontSize)
            let surfaceView = TerminalSurfaceView(viewModel: viewModel)

            wc.tabViewModels[tab.id] = viewModel
            wc.tabSurfaceViews[tab.id] = surfaceView

            do {
                let surfaceID = try newBridge.createSurface(
                    in: surfaceView,
                    workingDirectory: snapshot.workingDirectory,
                    command: nil
                )
                viewModel.markRunning(surfaceID: surfaceID)
                wc.tabSurfaceMap[tab.id] = surfaceID
                wc.wireHandlersForRestoredTab(tabID: tab.id, surfaceID: surfaceID)
            } catch {
                NSLog("[AppDelegate] Failed to create surface for tab %d during theme switch: %@",
                      index, String(describing: error))
            }

            wc.tabManager.updateTab(id: tab.id) { t in
                t.title = snapshot.title
            }
        }
    }

    private func restoreActiveTab(_ wc: MainWindowController, tabs: [Tab], activeIndex: Int) {
        let activeTab = tabs.indices.contains(activeIndex) ? tabs[activeIndex] : tabs.first
        if let tabID = activeTab?.id {
            wc.handleTabSwitch(to: tabID)
        }
    }

    private func applyThemeUI(_ wc: MainWindowController, palette: ThemePalette) {
        let backgroundColor = CodableColor(hex: palette.background).nsColor
        wc.window?.backgroundColor = backgroundColor
        wc.tabBarViewModel?.syncWithManager()
        wc.refreshStatusBar()

        if let appearance = configService?.current.appearance {
            wc.tabBarView?.setSidebarTransparent(appearance.backgroundOpacity < 1.0)
        }
    }

    // MARK: - Window Setup

    /// Creates and displays the main application window.
    private func createMainWindow() {
        guard let bridge = bridge else {
            // Bridge initialization failed. Show a placeholder window.
            createFallbackWindow()
            return
        }

        let controller = MainWindowController(
            bridge: bridge,
            configService: configService
        )
        // Inject the agent detection engine BEFORE creating the first
        // surface so the output handler captures a live reference.
        // Without this, the closure captures nil and terminal output
        // never reaches the detection system.
        controller.injectedAgentDetectionEngine = agentDetectionEngine

        controller.showWindow(nil)
        controller.window?.center()

        // Create the terminal surface after the window is visible.
        // The view needs a valid frame for Metal layer initialization.
        controller.createTerminalSurface()

        // Make the terminal view first responder for keyboard input.
        if let surfaceView = controller.terminalSurfaceView {
            controller.window?.makeFirstResponder(surfaceView)
        }

        self.windowController = controller
    }

    /// Creates a fallback window when the bridge failed to initialize.
    private func createFallbackWindow() {
        let windowRect = NSRect(x: 0, y: 0, width: 1200, height: 800)
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

        window.title = "Cocxy Terminal"
        window.minSize = NSSize(width: 320, height: 240)
        window.center()
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false

        let errorView = NSView(frame: windowRect)
        errorView.wantsLayer = true
        errorView.layer?.backgroundColor = CocxyColors.base.cgColor

        // Add error label.
        let label = NSTextField(labelWithString: "Terminal engine failed to initialize")
        label.textColor = CocxyColors.text
        label.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
        ])

        window.contentView = errorView
        window.makeKeyAndOrderFront(nil)
    }

    /// Exposes menu setup for testing without triggering full app launch.
    func setupMainMenuForTesting() {
        setupMainMenu()
    }

    // MARK: - Notification Stack Initialization

    /// Initializes the notification subsystem: adapter, manager, dock badge, quick switch.
    ///
    /// Called after the main window is created so we have a tab manager to wire into.
    private func initializeNotificationStack() {
        guard let windowController = windowController else { return }
        let config = configService?.current ?? .defaults

        // 1. Create a tab router adapter that delegates to the window controller.
        let tabRouter = WindowControllerTabRouter(windowController: windowController)

        // 2. Create the notification adapter (bridges to macOS notifications).
        let adapter = MacOSNotificationAdapter(
            notificationCenter: SystemNotificationCenter(),
            tabRouter: tabRouter,
            config: config
        )
        self.notificationAdapter = adapter

        // 3. Create the notification manager with the adapter as emitter.
        let manager = NotificationManagerImpl(
            config: config,
            systemEmitter: adapter
        )
        self.notificationManager = manager

        // 4. Create the dock badge controller and bind to the notification manager.
        let dockBadge = DockBadgeController(
            dockTile: SystemDockTile(),
            unreadCountSource: manager,
            config: config
        )
        dockBadge.bind()
        self.dockBadgeController = dockBadge

        // 5. Inject the notification manager into the window controller
        // so OSC notifications are forwarded to the notification pipeline.
        windowController.injectedNotificationManager = manager

        // 5b. Inject notification manager into the tab bar ViewModel so
        // each tab can display its unread notification count and preview.
        windowController.tabBarViewModel?.setNotificationManager(manager)

        // 6. Create the quick switch controller and wire to the window controller.
        let quickSwitch = QuickSwitchController(
            notificationManager: manager,
            tabActivator: windowController.tabManager
        )
        windowController.quickSwitchController = quickSwitch
        self.quickSwitchController = quickSwitch

        // 7. Install the notification center delegate so we receive
        // click events from macOS notifications.
        UNNotificationCenterBridge.shared.installDelegate()

        // 8. Observe notification clicks and route to the adapter.
        NotificationCenter.default.addObserver(
            forName: .cocxyNotificationClicked,
            object: nil,
            queue: .main
        ) { [weak adapter] note in
            if let tabIdString = note.userInfo?["tabId"] as? String {
                adapter?.handleNotificationClick(tabIdString: tabIdString)
            }
        }

        // 9. Request notification permissions.
        Task {
            await adapter.requestPermissionIfNeeded()
        }
    }

    // MARK: - Port Scanner Initialization

    /// Initializes the port scanner and wires it to the status bar.
    private func initializePortScanner() {
        let scanner = PortScannerImpl()
        self.portScanner = scanner
        windowController?.portScanner = scanner
        scanner.startScanning(interval: 5.0)

        // Refresh status bar when ports change.
        scanner.portsChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.windowController?.refreshStatusBar()
            }
            .store(in: &hookCancellables)
    }

    // MARK: - Appearance Observer

    /// Initializes the appearance observer for automatic dark/light theme switching.
    private func initializeAppearanceObserver() {
        let observer = AppearanceObserver()
        self.appearanceObserver = observer

        let darkTheme = configService?.current.appearance.theme ?? "catppuccin-mocha"
        let lightTheme = "Catppuccin Latte"

        guard let engine = themeEngine else { return }
        observer.startObserving(
            themeEngine: engine,
            darkTheme: darkTheme,
            lightTheme: lightTheme,
            autoSwitchEnabled: true
        )
    }

    // MARK: - Plugin Initialization

    /// Initializes the plugin manager and performs initial scan.
    private func setupPlugins() {
        let manager = PluginManager()
        manager.scanPlugins()
        self.pluginManager = manager
    }

    // MARK: - Socket Server Initialization

    /// Starts the CLI companion socket server and schedules a health check timer.
    private func initializeSocketServer() {
        let configService = self.configService
        let handler = AppSocketCommandHandler(
            tabManager: windowController?.tabManager,
            hookEventReceiver: hookEventReceiver,
            configProvider: configService.map { svc in { svc.current } },
            themeEngineProvider: { [weak self] in self?.themeEngine },
            remoteConnectionManagerProvider: { [weak self] in self?.remoteConnectionManager },
            remoteProfileStoreProvider: { [weak self] in self?.remoteProfileStore },
            pluginManagerProvider: { [weak self] in self?.pluginManager },
            notifyDispatcher: { [weak self] title, body in
                let work = {
                    MainActor.assumeIsolated {
                        guard let manager = self?.notificationManager else { return }
                        // Use the active tab as the source, or a sentinel tab ID.
                        let tabId = self?.windowController?.tabManager.activeTabID ?? TabID()
                        let notification = CocxyNotification(
                            type: .custom("cli"),
                            tabId: tabId,
                            title: title,
                            body: body
                        )
                        manager.notify(notification)
                    }
                }
                if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            }
        )

        let server = SocketServerImpl(commandHandler: handler)
        do {
            try server.start()
            self.socketServer = server
            startSocketHealthCheck()
        } catch {
            NSLog("[AppDelegate] Failed to start socket server: %@",
                  String(describing: error))
        }
    }

    /// Schedules a repeating timer that verifies the socket file exists.
    ///
    /// If the socket file disappears (e.g., external deletion or race
    /// condition), the server is automatically restarted. Runs every
    /// 30 seconds to balance responsiveness with overhead.
    private func startSocketHealthCheck() {
        socketHealthTimer?.invalidate()
        socketHealthTimer = Timer.scheduledTimer(
            withTimeInterval: 30.0,
            repeats: true
        ) { [weak self] _ in
            self?.socketServer?.restartIfNeeded()
        }
    }

    // MARK: - Quick Terminal Initialization

    /// Initializes the Quick Terminal controller with global hotkey.
    private func initializeQuickTerminal() {
        let config = configService?.current ?? .defaults
        guard config.quickTerminal.enabled else { return }

        let controller = QuickTerminalController()
        controller.setup(bridge: bridge, config: config)
        controller.registerHotkey()
        self.quickTerminalController = controller
    }

    // MARK: - Menu Bar Item

    /// Installs the macOS menu bar status item and wires it to agent state.
    private func initializeMenuBarItem() {
        let item = MenuBarStatusItem()
        item.install()
        item.onShowApp = {
            NSApp.activate(ignoringOtherApps: true)
        }
        item.onShowDashboard = { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.windowController?.toggleDashboard()
        }
        self.menuBarItem = item

        // Wire dashboard ViewModel to update menu bar when sessions change.
        agentDashboardViewModel?.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak item] sessions in
                let working = sessions.filter { $0.state == .working }.count
                let waiting = sessions.filter { $0.state == .waitingForInput }.count
                let errors = sessions.filter { $0.state == .error }.count
                // Only show active sessions (working/waiting) in the menu bar.
                // Error and finished sessions clutter the dropdown and make
                // "Show Dashboard" hard to reach.
                let activeSessions = sessions.filter {
                    $0.state == .working || $0.state == .waitingForInput
                }
                let summaries = activeSessions.prefix(5).map { session in
                    (
                        name: session.projectName,
                        state: session.state.rawValue,
                        activity: session.lastActivity
                    )
                }
                item?.updateAgentCount(
                    working: working,
                    waiting: waiting,
                    errors: errors,
                    sessions: summaries
                )
            }
            .store(in: &hookCancellables)
    }

    // MARK: - App Icon

    /// Applies the programmatic placeholder app icon.
    private func applyPlaceholderAppIcon() {
        NSApp.applicationIconImage = AppIconGenerator.generatePlaceholderIcon()
    }

    // MARK: - Welcome Overlay on First Launch

    /// Shows the Welcome overlay if this is the user's first launch.
    private func showWelcomeOnFirstLaunch() {
        let welcomeShownKey = "cocxy.welcomeShown"
        if !UserDefaults.standard.bool(forKey: welcomeShownKey) {
            windowController?.showWelcome()
            UserDefaults.standard.set(true, forKey: welcomeShownKey)
        }
    }
}

// MARK: - Window Controller Tab Router

/// Bridges `NotificationTabRouting` to `MainWindowController`.
///
/// Routes notification click actions to the correct tab by delegating
/// to the window controller's tab manager.
@MainActor
final class WindowControllerTabRouter: NotificationTabRouting {
    private weak var windowController: MainWindowController?

    init(windowController: MainWindowController) {
        self.windowController = windowController
    }

    func activateTab(id: TabID) {
        windowController?.tabManager.setActive(id: id)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - System Dock Tile

/// Production implementation of `DockTileProviding` that wraps `NSApp.dockTile`.
@MainActor
final class SystemDockTile: DockTileProviding {
    func setBadgeLabel(_ label: String?) {
        NSApp.dockTile.badgeLabel = label
    }
}

// MARK: - System Notification Center

/// Production implementation of `NotificationCenterProviding` that wraps
/// `UNUserNotificationCenter`.
@MainActor
final class SystemNotificationCenter: NotificationCenterProviding {
    func requestAuthorization(options: NotificationAuthorizationOptions) async -> Bool {
        do {
            let center = _getUNUserNotificationCenter()
            var unOptions: UInt = 0
            if options.contains(.alert) { unOptions |= 1 << 0 }
            if options.contains(.sound) { unOptions |= 1 << 1 }
            if options.contains(.badge) { unOptions |= 1 << 2 }
            return try await center.requestAuthorization(rawOptions: unOptions)
        } catch {
            NSLog("[SystemNotificationCenter] Authorization request failed: %@",
                  String(describing: error))
            return false
        }
    }

    func add(_ request: NotificationRequestSnapshot) {
        let center = _getUNUserNotificationCenter()
        center.addNotification(
            identifier: request.identifier,
            title: request.title,
            body: request.body,
            categoryIdentifier: request.categoryIdentifier,
            userInfo: request.userInfo,
            hasSound: request.hasSound,
            soundName: request.soundName
        )
    }

    /// Returns a bridge to UNUserNotificationCenter.
    /// Isolated here so the rest of the codebase does not import UserNotifications.
    private func _getUNUserNotificationCenter() -> UNNotificationCenterBridge {
        UNNotificationCenterBridge.shared
    }
}

// MARK: - UNNotificationCenter Bridge

/// Thin wrapper around UNUserNotificationCenter to keep the import localized.
///
/// This class is the ONLY place in the codebase that imports UserNotifications.
/// Everything else uses our protocol abstractions.
@MainActor
final class UNNotificationCenterBridge: NSObject {
    static let shared = UNNotificationCenterBridge()

    func requestAuthorization(rawOptions: UInt) async throws -> Bool {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[UNNotificationCenterBridge] Skipping authorization: no bundle identifier (running outside .app bundle)")
            return false
        }
        let center = UNUserNotificationCenter.current()
        let options = UNAuthorizationOptions(rawValue: rawOptions)
        return try await center.requestAuthorization(options: options)
    }

    func addNotification(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        userInfo: [String: String],
        hasSound: Bool,
        soundName: String = "default"
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo
        if hasSound {
            if soundName == "default" {
                content.sound = .default
            } else {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
            }
        }

        guard Bundle.main.bundleIdentifier != nil else {
            // Debug builds without a .app bundle cannot use UNUserNotificationCenter.
            // Skip system notifications entirely — the in-app notification panel
            // still works and provides the same information without annoying sounds.
            #if DEBUG
            NSLog("[UNNotificationCenterBridge] Skipping notification (no bundle): %@ — %@", title, body)
            #endif
            return
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[UNNotificationCenterBridge] Failed to schedule notification: %@",
                      String(describing: error))
            }
        }
    }

    /// Sets this bridge as the notification center delegate so we
    /// receive notification click events.
    func installDelegate() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = self
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension UNNotificationCenterBridge: @preconcurrency UNUserNotificationCenterDelegate {

    /// Called when the user clicks on a delivered notification.
    ///
    /// Extracts the tab ID from userInfo and routes to the notification
    /// adapter which activates the correct tab.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let tabIdString = userInfo["tabId"] as? String {
            NotificationCenter.default.post(
                name: .cocxyNotificationClicked,
                object: nil,
                userInfo: ["tabId": tabIdString]
            )
        }
        completionHandler()
    }

    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - Notification Click Routing

extension Notification.Name {
    /// Posted when the user clicks a macOS notification from Cocxy.
    static let cocxyNotificationClicked = Notification.Name("cocxyNotificationClicked")
}
