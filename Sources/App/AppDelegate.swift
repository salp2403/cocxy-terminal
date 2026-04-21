// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate.swift - NSApplicationDelegate handling app lifecycle.

import AppKit
import Combine
import UserNotifications

/// Main application delegate for Cocxy Terminal.
///
/// Responsibilities:
/// - Initialize the terminal engine at launch.
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
///   -> Create CocxyCoreBridge
///   -> Initialize bridge with config
///   -> Initialize agent detection engine (before window!)
///   -> Create MainWindowController
///   -> Show window
///   -> Create terminal surface (engine already available)
///   -> Wire agent detection to window
///
/// applicationWillTerminate
///   -> Destroy terminal surface
///   -> MainWindowController = nil
///   -> Bridge = nil (deinit frees terminal resources)
/// ```
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// The terminal engine. Created during app launch.
    private(set) var bridge: (any TerminalEngine)?

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

    /// Shared cross-window tab router used by notifications and the dashboard.
    var windowTabRouter: WindowControllerTabRouter?

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

    /// Subscription for hot-reloading the periodic session auto-save timer
    /// when the `[sessions]` config changes.
    var sessionAutoSaveConfigCancellable: AnyCancellable?

    /// Subscription that reapplies `[keybindings]` onto the main menu
    /// whenever `ConfigService` publishes a new config snapshot.
    ///
    /// Installed by `startMenuKeybindingsObserver()` right after
    /// `setupMainMenu()` so menu shortcuts stay in sync with the editor
    /// without requiring an app restart.
    private var menuKeybindingsCancellable: AnyCancellable?

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

    /// Tracks git snapshots and touched files per agent hook session for the code review panel.
    var sessionDiffTracker: SessionDiffTrackerImpl?

    /// The agent detection engine for terminal output analysis.
    /// Internal setter: extensions (+AgentWiring) assign during engine init.
    var agentDetectionEngine: AgentDetectionEngineImpl?

    /// Per-surface agent state store introduced by the v0.1.71 refactor.
    ///
    /// Writers in `AppDelegate+AgentWiring` populate this store from
    /// detection-engine transitions and hook events so UI consumers can
    /// read split-scoped agent state without the previous tab-level
    /// aggregation. `Tab` keeps mirroring the same fields during the
    /// dual-write phase; the store becomes the sole source of truth in
    /// Fase 4 when the forwarding fields on `Tab` are retired.
    var agentStatePerSurfaceStore: AgentStatePerSurfaceStore?

    /// The port scanner for detecting active dev servers on localhost.
    /// Exposed for testing purposes.
    private(set) var portScanner: PortScannerImpl?

    /// The appearance observer for auto-switching dark/light themes.
    private(set) var appearanceObserver: AppearanceObserver?

    /// Menu bar status item showing agent count.
    private(set) var menuBarItem: MenuBarStatusItem?

    /// Central session registry for multi-window synchronization.
    /// Tracks all terminal sessions across all windows, enabling
    /// cross-window tab drag, synchronized badges, and shared agent state.
    private(set) var sessionRegistry: SessionRegistryImpl?

    /// Event bus for cross-window communication (theme sync, config
    /// reload, focus session). Created alongside the session registry.
    private(set) var windowEventBus: WindowEventBusImpl?

    /// Aggregates notification unread counts across all windows.
    /// Uses the session registry as its data source.
    private(set) var notificationAggregator: GlobalNotificationAggregatorImpl?

    /// Aggregates agent state across all windows. Used by the dashboard
    /// to show agents from all windows, not just the current one.
    private(set) var agentStateAggregator: AgentStateAggregatorImpl?

    /// Additional window controllers for multi-window support.
    /// Each entry retains a MainWindowController to prevent deallocation.
    /// Internal access so `MainWindowController.newWindowAction` can append.
    var additionalWindowControllers: [MainWindowController] = []

    /// Best-effort routing cache from Claude hook session IDs to Cocxy tabs.
    ///
    /// Hook events identify Claude sessions, not Cocxy tabs. In multi-window
    /// setups we bind the first resolved tab for a hook session and reuse that
    /// binding for later state changes, notifications, and dashboard/timeline
    /// presentation. This avoids repeatedly falling back to CWD matching.
    var hookSessionTabBindings: [String: TabID] = [:]

    /// Best-effort routing cache from hook/native semantic session IDs to
    /// the exact terminal surface that produced them.
    ///
    /// CocxyCore native semantic events are emitted per surface. Keeping
    /// this companion binding prevents a split tab with duplicate CWDs
    /// from routing all agent state to the tab's first surface.
    var hookSessionSurfaceBindings: [String: SurfaceID] = [:]

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

    /// The main config file watcher for hot-reload of config.toml.
    private var configWatcher: ConfigWatcher?

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

    /// Remote port scanner for detecting dev servers on SSH-connected hosts.
    /// Internal setter: extensions (+RemoteWorkspace) assign during setup.
    var remotePortScanner: RemotePortScanner?

    /// SSH tunnel manager shared across all windows.
    /// Internal setter: extensions (+RemoteWorkspace) assign during setup.
    var tunnelManager: SSHTunnelManager?

    /// SSH key manager shared across all windows.
    /// Internal setter: extensions (+RemoteWorkspace) assign during setup.
    var sshKeyManager: SSHKeyManager?

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
        BundledFontRegistry.ensureRegistered()
        themeEngine = ThemeEngineImpl()
        initializeConfigService()
        startConfigWatcher()
        initializeSessionManager()
        setupMainMenu()
        applyKeybindingsToMainMenu()
        startMenuKeybindingsObserver()
        initializeBridge()
        initializeAgentDetectionEngine()
        initializeSessionRegistry()
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
        startSessionAutoSaveIfNeeded()
        observeSessionAutoSaveConfigChanges()
        applyPlaceholderAppIcon()
        performFirstLaunchSetup()
        showWelcomeOnFirstLaunch()
        initializeMenuBarItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopSessionAutoSave()
        sessionAutoSaveConfigCancellable?.cancel()
        sessionAutoSaveConfigCancellable = nil
        menuKeybindingsCancellable?.cancel()
        menuKeybindingsCancellable = nil

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
        remotePortScanner?.stopScanning()
        remotePortScanner = nil
        remoteConnectionManager = nil
        remoteProfileStore = nil
        browserProfileManager = nil
        browserHistoryStore = nil
        browserBookmarkStore = nil
        sparkleUpdater = nil

        // Stop config watchers before services are torn down.
        configWatcher?.stopWatching()
        configWatcher = nil
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
        agentStateAggregator = nil
        notificationAggregator = nil
        windowEventBus = nil
        sessionRegistry = nil
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
        let allControllers = [windowController].compactMap { $0 } + additionalWindowControllers
        for controller in allControllers {
            controller.recoverTerminalRenderingAfterWake()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            if let wc = windowController, wc.window?.isVisible == true {
                wc.showWindow(nil)
            } else {
                if sessionRegistry == nil {
                    initializeSessionRegistry()
                }
                // Window was closed while the app kept running in the background.
                // Keep long-lived subsystems alive; recreating them here would
                // tear down app-wide Combine wiring (remote workspace, socket,
                // notifications, hot reload) and leave features half-disconnected.
                createMainWindow()
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

    /// Starts the config file watcher for hot-reload of config.toml.
    private func startConfigWatcher() {
        guard let service = configService else { return }
        let watcher = ConfigWatcher(
            configService: service,
            fileProvider: DiskConfigFileProvider()
        )
        watcher.startWatching()
        self.configWatcher = watcher
    }

    // MARK: - Menu Keybindings

    /// Overlays the current keybindings config onto the main menu.
    ///
    /// Called once after `setupMainMenu()` so the initial menu shortcuts
    /// reflect the user's `~/.config/cocxy/config.toml`. No-op when the
    /// main menu has not been installed yet (e.g., in unit-test fixtures).
    func applyKeybindingsToMainMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        let config = configService?.current.keybindings ?? .defaults
        MenuKeybindingsBinder.apply(config, to: mainMenu)
    }

    /// Subscribes to `ConfigService.configChangedPublisher` so menu shortcuts
    /// are refreshed whenever `~/.config/cocxy/config.toml` is edited.
    ///
    /// Drops the first emission (the initial value) because
    /// `applyKeybindingsToMainMenu()` already ran synchronously after
    /// `setupMainMenu()`. Without this, the menu would be rewritten twice
    /// at launch for no gain.
    func startMenuKeybindingsObserver() {
        guard let service = configService else { return }

        menuKeybindingsCancellable?.cancel()
        menuKeybindingsCancellable = service.configChangedPublisher
            .dropFirst()
            .map(\.keybindings)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keybindings in
                // `self` is captured weakly so the observer does not
                // outlive the delegate. Reading the instance in the
                // guard binds the lifetime and also satisfies the
                // compiler's unused-capture warning without a no-op
                // assignment. Binding is local-only — no instance
                // access is required beyond the guard, so we
                // intentionally do not touch `self` in the body.
                guard self != nil,
                      let mainMenu = NSApplication.shared.mainMenu else { return }
                MenuKeybindingsBinder.apply(keybindings, to: mainMenu)
            }
    }

    // MARK: - Session Registry Initialization

    /// Creates the central session registry for multi-window synchronization.
    ///
    /// The registry is a lightweight singleton that tracks session metadata
    /// across all windows. It must be created before any window so that
    /// `MainWindowController` can register sessions during tab creation.
    private func initializeSessionRegistry() {
        let registry = SessionRegistryImpl()
        sessionRegistry = registry
        windowEventBus = WindowEventBusImpl()
        notificationAggregator = GlobalNotificationAggregatorImpl(registry: registry)
        agentStateAggregator = AgentStateAggregatorImpl(registry: registry)
    }

    // MARK: - Bridge Initialization

    /// Initializes the terminal engine bridge.
    private func initializeBridge() {
        let newBridge: any TerminalEngine = CocxyCoreBridge()

        let fontFamily = configService?.current.appearance.fontFamily
            ?? AppearanceConfig.defaults.fontFamily
        let fontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize
        let theme = configService?.current.appearance.theme
            ?? AppearanceConfig.defaults.theme
        let shell = configService?.current.general.shell
            ?? GeneralConfig.defaults.shell

        // Resolve and apply the configured theme before the bridge is
        // initialized so `ThemeEngine.activeTheme` stays in lockstep
        // with the terminal palette from the first window frame. The
        // one-click light/dark toggle reads `activeTheme`; resolving a
        // palette without applying it leaves that toggle stuck on the
        // previous variant.
        let resolvedPalette: ThemePalette?
        if let engine = themeEngine, let resolved = try? engine.themeByName(theme) {
            try? engine.apply(themeName: resolved.metadata.name)
            resolvedPalette = resolved.palette
        } else {
            // Fall back to Catppuccin Mocha (the default).
            resolvedPalette = themeEngine?.activeTheme.palette
        }

        let paddingX = configService?.current.appearance.effectivePaddingX
            ?? AppearanceConfig.defaults.windowPadding
        let paddingY = configService?.current.appearance.effectivePaddingY
            ?? AppearanceConfig.defaults.windowPadding

        let config = TerminalEngineConfig(
            fontFamily: fontFamily,
            fontSize: fontSize,
            themeName: theme,
            shell: shell,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            themePalette: resolvedPalette,
            windowPaddingX: paddingX,
            windowPaddingY: paddingY,
            clipboardReadAccess: configService?.current.terminal.clipboardReadAccess
                ?? TerminalConfig.defaults.clipboardReadAccess,
            ligaturesEnabled: configService?.current.appearance.ligatures
                ?? AppearanceConfig.defaults.ligatures,
            fontThickenEnabled: configService?.current.appearance.fontThicken
                ?? AppearanceConfig.defaults.fontThicken,
            imageMemoryLimitBytes: UInt64(
                (configService?.current.terminal.imageMemoryLimitMB
                    ?? TerminalConfig.defaults.imageMemoryLimitMB) * 1024 * 1024
            ),
            imageFileTransferEnabled: configService?.current.terminal.imageFileTransfer
                ?? TerminalConfig.defaults.imageFileTransfer,
            sixelImagesEnabled: configService?.current.terminal.enableSixelImages
                ?? TerminalConfig.defaults.enableSixelImages,
            kittyImagesEnabled: configService?.current.terminal.enableKittyImages
                ?? TerminalConfig.defaults.enableKittyImages
        )

        do {
            try newBridge.initialize(config: config)
            self.bridge = newBridge
        } catch {
            NSLog("[AppDelegate] Failed to initialize terminal engine %@: %@",
                  String(describing: type(of: newBridge)),
                  String(describing: error))
            // The app can still show a window with an error state.
            // For now, we proceed without a bridge.
        }
    }

    // MARK: - Theme Switching

    /// Switches the terminal theme in place.
    ///
    /// CocxyCore applies theme changes without recreating surfaces, so existing
    /// tabs and windows keep their PTYs and visual state intact.
    ///
    /// - Parameter themeName: Display name of the target theme (e.g., "One Dark").
    private struct ThemeSwitchTabSnapshot {
        let id: TabID
        let title: String
        let workingDirectory: URL
    }

    func switchTheme(to themeName: String) {
        guard let windowController = windowController else { return }

        guard let engine = themeEngine else {
            NSLog("[AppDelegate] Theme switch requested before ThemeEngine was ready")
            return
        }

        guard let cocxyBridge = bridge as? CocxyCoreBridge else {
            NSLog("[AppDelegate] Theme switch requested before CocxyCore bridge was ready")
            return
        }

        do {
            try engine.apply(themeName: themeName)
        } catch {
            NSLog("[AppDelegate] Theme not found: %@", themeName)
            return
        }
        let theme = engine.activeTheme

        cocxyBridge.updateDefaults(
            themeName: theme.metadata.name,
            themePalette: theme.palette
        )
        applyCocxyCoreTheme(theme.palette, bridge: cocxyBridge)
        applyThemeUI(windowController, palette: theme.palette)
        windowController.syncAuroraDesignTheme(for: theme.metadata.variant)
        for controller in additionalWindowControllers {
            applyThemeUI(controller, palette: theme.palette)
            controller.syncAuroraDesignTheme(for: theme.metadata.variant)
        }
        if let config = configService?.current {
            let wasQuickTerminalVisible = quickTerminalController?.isVisible ?? false
            quickTerminalController?.setup(bridge: cocxyBridge, config: config)
            if wasQuickTerminalVisible {
                quickTerminalController?.show()
            }
        }

        // Broadcast theme change through the event bus so subscribers
        // (dashboard, plugins, future extensions) can react.
        windowEventBus?.broadcast(.themeChanged(themeName: theme.metadata.name))

        NSLog("[AppDelegate] Theme switched to: %@", theme.metadata.name)
    }

    func applyBridgeConfigurationChanges(from oldConfig: CocxyConfig?, to newConfig: CocxyConfig) {
        guard let cocxyBridge = bridge as? CocxyCoreBridge else { return }

        let resolvedTheme = try? themeEngine?.themeByName(newConfig.appearance.theme)
        cocxyBridge.updateDefaults(
            fontFamily: newConfig.appearance.fontFamily,
            fontSize: newConfig.appearance.fontSize,
            themeName: resolvedTheme?.metadata.name ?? newConfig.appearance.theme,
            themePalette: resolvedTheme?.palette,
            shell: newConfig.general.shell,
            windowPaddingX: newConfig.appearance.effectivePaddingX,
            windowPaddingY: newConfig.appearance.effectivePaddingY,
            clipboardReadAccess: newConfig.terminal.clipboardReadAccess,
            ligaturesEnabled: newConfig.appearance.ligatures,
            fontThickenEnabled: newConfig.appearance.fontThicken,
            imageMemoryLimitBytes: UInt64(newConfig.terminal.imageMemoryLimitMB) * 1024 * 1024,
            imageFileTransferEnabled: newConfig.terminal.imageFileTransfer,
            sixelImagesEnabled: newConfig.terminal.enableSixelImages,
            kittyImagesEnabled: newConfig.terminal.enableKittyImages
        )

        let fontChanged =
            oldConfig?.appearance.fontFamily != newConfig.appearance.fontFamily ||
            oldConfig?.appearance.fontSize != newConfig.appearance.fontSize
        let paddingChanged =
            oldConfig?.appearance.effectivePaddingX != newConfig.appearance.effectivePaddingX ||
            oldConfig?.appearance.effectivePaddingY != newConfig.appearance.effectivePaddingY
        let ligaturesChanged = oldConfig?.appearance.ligatures != newConfig.appearance.ligatures
        let fontThickenChanged = oldConfig?.appearance.fontThicken != newConfig.appearance.fontThicken
        let imageSettingsChanged =
            oldConfig?.terminal.imageMemoryLimitMB != newConfig.terminal.imageMemoryLimitMB ||
            oldConfig?.terminal.imageFileTransfer != newConfig.terminal.imageFileTransfer ||
            oldConfig?.terminal.enableSixelImages != newConfig.terminal.enableSixelImages ||
            oldConfig?.terminal.enableKittyImages != newConfig.terminal.enableKittyImages
        let themeChanged = oldConfig?.appearance.theme != newConfig.appearance.theme

        if fontChanged {
            cocxyBridge.applyFont(
                family: newConfig.appearance.fontFamily,
                size: newConfig.appearance.fontSize
            )
            // applyFont recreates the shaper; CocxyCore persists the thicken
            // flag on the Terminal struct and re-applies it to the new
            // shaper, so no extra call is needed unless the value also
            // changed in this diff.
            if fontThickenChanged {
                cocxyBridge.applyFontThickenEnabled(newConfig.appearance.fontThicken)
            }
        } else {
            if ligaturesChanged {
                cocxyBridge.applyLigaturesEnabled(newConfig.appearance.ligatures)
            }
            if fontThickenChanged {
                cocxyBridge.applyFontThickenEnabled(newConfig.appearance.fontThicken)
            }
        }

        if imageSettingsChanged {
            cocxyBridge.applyImageSettings(
                memoryLimitBytes: UInt64(newConfig.terminal.imageMemoryLimitMB) * 1024 * 1024,
                fileTransferEnabled: newConfig.terminal.imageFileTransfer,
                sixelEnabled: newConfig.terminal.enableSixelImages,
                kittyEnabled: newConfig.terminal.enableKittyImages
            )
        }

        if themeChanged {
            switchTheme(to: newConfig.appearance.theme)
        }

        if fontChanged || paddingChanged {
            refreshTerminalHostMetrics(using: newConfig)
        }
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

    private func createBridgeForTheme(_ themeName: String, palette: ThemePalette) -> (any TerminalEngine)? {
        let newBridge: any TerminalEngine = CocxyCoreBridge()
        let fontFamily = configService?.current.appearance.fontFamily
            ?? AppearanceConfig.defaults.fontFamily
        let fontSize = configService?.current.appearance.fontSize
            ?? AppearanceConfig.defaults.fontSize
        let shell = configService?.current.general.shell
            ?? GeneralConfig.defaults.shell

        let paddingX = configService?.current.appearance.effectivePaddingX
            ?? AppearanceConfig.defaults.windowPadding
        let paddingY = configService?.current.appearance.effectivePaddingY
            ?? AppearanceConfig.defaults.windowPadding

        let engineConfig = TerminalEngineConfig(
            fontFamily: fontFamily,
            fontSize: fontSize,
            themeName: themeName,
            shell: shell,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            themePalette: palette,
            windowPaddingX: paddingX,
            windowPaddingY: paddingY,
            clipboardReadAccess: configService?.current.terminal.clipboardReadAccess
                ?? TerminalConfig.defaults.clipboardReadAccess,
            ligaturesEnabled: configService?.current.appearance.ligatures
                ?? AppearanceConfig.defaults.ligatures,
            fontThickenEnabled: configService?.current.appearance.fontThicken
                ?? AppearanceConfig.defaults.fontThicken,
            imageMemoryLimitBytes: UInt64(
                (configService?.current.terminal.imageMemoryLimitMB
                    ?? TerminalConfig.defaults.imageMemoryLimitMB) * 1024 * 1024
            ),
            imageFileTransferEnabled: configService?.current.terminal.imageFileTransfer
                ?? TerminalConfig.defaults.imageFileTransfer,
            sixelImagesEnabled: configService?.current.terminal.enableSixelImages
                ?? TerminalConfig.defaults.enableSixelImages,
            kittyImagesEnabled: configService?.current.terminal.enableKittyImages
                ?? TerminalConfig.defaults.enableKittyImages
        )

        do {
            try newBridge.initialize(config: engineConfig)
        } catch {
            NSLog("[AppDelegate] Failed to initialize bridge for theme switch: %@",
                  String(describing: error))
            return nil
        }
        self.bridge = newBridge
        if let config = configService?.current {
            let wasQuickTerminalVisible = quickTerminalController?.isVisible ?? false
            quickTerminalController?.setup(bridge: newBridge, config: config)
            if wasQuickTerminalVisible {
                quickTerminalController?.show()
            }
        }
        return newBridge
    }

    private func recreateTabSurfaces(
        windowController wc: MainWindowController,
        bridge newBridge: any TerminalEngine,
        snapshots: [ThemeSwitchTabSnapshot]
    ) {
        wc.bridge = newBridge
        let tabs = wc.tabManager.tabs

        for (index, tab) in tabs.enumerated() {
            let snapshot = index < snapshots.count
                ? snapshots[index]
                : ThemeSwitchTabSnapshot(id: tab.id, title: tab.title, workingDirectory: tab.workingDirectory)

            let viewModel = TerminalViewModel(engine: newBridge)
            let configuredFontSize = configService?.current.appearance.fontSize
                ?? AppearanceConfig.defaults.fontSize
            viewModel.setDefaultFontSize(configuredFontSize)
            let surfaceView = CocxyCoreView(viewModel: viewModel)

            wc.tabViewModels[tab.id] = viewModel
            wc.tabSurfaceViews[tab.id] = surfaceView

            do {
                let surfaceID = try newBridge.createSurface(
                    in: surfaceView,
                    workingDirectory: snapshot.workingDirectory,
                    command: nil
                )
                viewModel.markRunning(surfaceID: surfaceID)
                surfaceView.configureSurfaceIfNeeded(bridge: newBridge, surfaceID: surfaceID)
                surfaceView.syncSizeWithTerminal()
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

    private func refreshTerminalHostMetrics(using config: CocxyConfig) {
        let allControllers = [windowController].compactMap { $0 } + additionalWindowControllers
        for controller in allControllers {
            controller.terminalViewModel.setDefaultFontSize(config.appearance.fontSize)
            for viewModel in controller.tabViewModels.values {
                viewModel.setDefaultFontSize(config.appearance.fontSize)
            }
            for viewModel in controller.splitViewModels.values {
                viewModel.setDefaultFontSize(config.appearance.fontSize)
            }
            for storedViewModels in controller.savedTabSplitViewModels.values {
                for viewModel in storedViewModels.values {
                    viewModel.setDefaultFontSize(config.appearance.fontSize)
                }
            }
            for surfaceView in controller.tabSurfaceViews.values {
                surfaceView.updateInteractionMetrics()
                surfaceView.requestImmediateRedraw()
            }
            for surfaceView in controller.splitSurfaceViews.values {
                surfaceView.updateInteractionMetrics()
                surfaceView.requestImmediateRedraw()
            }
        }

        if let bridge {
            let wasQuickTerminalVisible = quickTerminalController?.isVisible ?? false
            quickTerminalController?.setup(bridge: bridge, config: config)
            if wasQuickTerminalVisible {
                quickTerminalController?.show()
            }
        }
    }

    private func applyCocxyCoreTheme(
        _ palette: ThemePalette,
        bridge: CocxyCoreBridge
    ) {
        for surfaceID in bridge.allSurfaceIDs {
            bridge.applyTheme(palette, to: surfaceID)
        }

        let allControllers = [windowController].compactMap { $0 } + additionalWindowControllers
        for controller in allControllers {
            for surfaceView in controller.tabSurfaceViews.values {
                surfaceView.requestImmediateRedraw()
            }
            for surfaceView in controller.splitSurfaceViews.values {
                surfaceView.requestImmediateRedraw()
            }
        }
    }

    // MARK: - Window Setup

    /// Creates and displays the main application window.
    private func createMainWindow() {
        let shouldBootstrapSurface = !hasRestorableSessionOnLaunch()

        guard let controller = makeWindowController(registerInitialSession: shouldBootstrapSurface) else {
            // Bridge initialization failed. Show a placeholder window.
            createFallbackWindow()
            return
        }

        controller.showWindow(nil)
        if shouldBootstrapSurface {
            controller.window?.center()

            // Create the terminal surface after the window is visible.
            // The view needs a valid frame for Metal layer initialization.
            controller.createTerminalSurface()

            // Make the terminal view first responder for keyboard input.
            if let surfaceView = controller.terminalSurfaceView {
                controller.window?.makeFirstResponder(surfaceView)
            }
        }

        self.windowController = controller
    }

    // MARK: - Shared Window Wiring

    var allWindowControllers: [MainWindowController] {
        [windowController].compactMap { $0 } + additionalWindowControllers
    }

    func controllerContainingTab(_ tabID: TabID) -> MainWindowController? {
        allWindowControllers.first { $0.tabManager.tab(for: tabID) != nil }
    }

    /// Resolves the current per-surface agent state for a tab, or `.idle`
    /// if the tab is unknown.
    ///
    /// Cross-window helper used by AppleScript (`ScriptableTab.agentState`)
    /// and other scripting surfaces that only have a `TabID` in hand and
    /// need the resolved state the UI would render. Delegates to the
    /// owning `MainWindowController.resolveSurfaceAgentState` so the
    /// same priority chain (focused split > primary > any active >
    /// `.idle` fallback) feeds the scripting layer.
    func resolveScriptableAgentState(tabID: TabID) -> AgentState {
        guard let controller = controllerContainingTab(tabID) else {
            return .idle
        }
        return controller.resolveSurfaceAgentState(for: tabID).agentState
    }

    func controllerContainingSurface(_ surfaceID: SurfaceID) -> MainWindowController? {
        allWindowControllers.first { controller in
            controller.tabSurfaceMap.values.contains(surfaceID)
            || controller.savedTabSplitSurfaceViews.values.contains(where: { $0[surfaceID] != nil })
            || controller.splitSurfaceViews[surfaceID] != nil
        }
    }

    func controllerContainingWorkingDirectory(_ directory: String) -> MainWindowController? {
        resolvedWorkingDirectoryCandidate(for: directory)?.controller
    }

    func tabIDForWorkingDirectory(_ directory: String) -> TabID? {
        resolvedWorkingDirectoryCandidate(for: directory)?.tabID
    }

    func focusedWindowController() -> MainWindowController? {
        if let keyController = NSApp.keyWindow?.windowController as? MainWindowController {
            return keyController
        }
        return allWindowControllers.first(where: { $0.window?.isMainWindow == true }) ?? windowController
    }

    func bindHookSession(
        _ sessionID: String,
        to tabID: TabID,
        surfaceID: SurfaceID? = nil
    ) {
        hookSessionTabBindings[sessionID] = tabID
        if let surfaceID {
            hookSessionSurfaceBindings[sessionID] = surfaceID
        }
    }

    func unbindHookSession(_ sessionID: String) {
        hookSessionTabBindings.removeValue(forKey: sessionID)
        hookSessionSurfaceBindings.removeValue(forKey: sessionID)
    }

    func boundSurfaceIDForHookSession(_ sessionID: String?) -> SurfaceID? {
        guard let sessionID else { return nil }
        return hookSessionSurfaceBindings[sessionID]
    }

    func resolvedControllerAndTab(
        forHookSessionID sessionID: String?,
        cwd: String?
    ) -> (controller: MainWindowController, tabID: TabID)? {
        if let sessionID,
           let boundTabID = hookSessionTabBindings[sessionID],
           let boundController = controllerContainingTab(boundTabID) {
            return (boundController, boundTabID)
        }

        guard let cwd,
              let resolved = resolvedWorkingDirectoryCandidate(for: cwd) else {
            guard let sessionID,
                  let cwd,
                  let focusedController = focusedWindowController(),
                  let focusedTabID = focusedController.visibleTabID ?? focusedController.tabManager.activeTabID,
                  tabMatchesWorkingDirectory(focusedTabID, in: focusedController, directory: cwd) else {
                return nil
            }
            bindHookSession(sessionID, to: focusedTabID)
            return (focusedController, focusedTabID)
        }

        if let sessionID {
            bindHookSession(sessionID, to: resolved.tabID)
        }
        return resolved
    }

    func windowIDForTab(_ tabUUID: UUID) -> WindowID? {
        controllerContainingTab(TabID(rawValue: tabUUID))?.windowID
    }

    func windowIDForWorkingDirectory(_ directory: String) -> WindowID? {
        if let tabID = tabIDForWorkingDirectory(directory) {
            return controllerContainingTab(tabID)?.windowID
        }
        return controllerContainingWorkingDirectory(directory)?.windowID
    }

    func windowDisplayName(for windowID: WindowID?) -> String? {
        guard let windowID else { return nil }
        guard let index = allWindowControllers.firstIndex(where: { $0.windowID == windowID }) else {
            return nil
        }
        return "Window \(index + 1)"
    }

    private func resolvedWorkingDirectoryCandidate(
        for directory: String
    ) -> (controller: MainWindowController, tabID: TabID)? {
        // Both the hook side and the tab side go through the SAME
        // normalization (trim → file:// → resolveSymlinks → standardize)
        // so the strict equality below treats `/tmp` and `/private/tmp`
        // as the same canonical path. Without this, hooks from agents
        // that pre-resolve symlinks (Claude Code among them) would be
        // dropped against tabs whose CWD comes from the shell un-
        // resolved, and vice versa.
        let normalizedPath = normalizedWorkingDirectoryPath(directory)
        var matches: [(controller: MainWindowController, tabID: TabID)] = []
        var seenTabIDs = Set<TabID>()

        func appendMatch(controller: MainWindowController, tabID: TabID) {
            guard seenTabIDs.insert(tabID).inserted else { return }
            matches.append((controller, tabID))
        }

        for controller in allWindowControllers {
            for tab in controller.tabManager.tabs
            where HookPathNormalizer.normalize(tab.workingDirectory.path) == normalizedPath {
                appendMatch(controller: controller, tabID: tab.id)
            }

            for (surfaceID, workingDirectory) in controller.surfaceWorkingDirectories
            where HookPathNormalizer.normalize(workingDirectory.path) == normalizedPath {
                if let tabID = controller.tabID(for: surfaceID) {
                    appendMatch(controller: controller, tabID: tabID)
                }
            }
        }

        guard !matches.isEmpty else { return nil }
        if matches.count == 1 {
            return matches[0]
        }

        if let focusedController = focusedWindowController() {
            let focusedVisibleMatches = matches.filter {
                $0.controller === focusedController
                    && ($0.tabID == focusedController.visibleTabID
                        || $0.tabID == focusedController.tabManager.activeTabID)
            }
            if focusedVisibleMatches.count == 1 {
                return focusedVisibleMatches[0]
            }

            let focusedMatches = matches.filter { $0.controller === focusedController }
            if focusedMatches.count == 1 {
                return focusedMatches[0]
            }
        }

        let visibleMatches = matches.filter { $0.controller.visibleTabID == $0.tabID }
        if visibleMatches.count == 1 {
            return visibleMatches[0]
        }

        return Set(matches.map { $0.tabID }).count == 1 ? matches[0] : nil
    }

    private func normalizedWorkingDirectoryPath(_ directory: String) -> String {
        HookPathNormalizer.normalize(directory)
    }

    private func tabMatchesWorkingDirectory(
        _ tabID: TabID,
        in controller: MainWindowController,
        directory: String
    ) -> Bool {
        // Both sides of the comparison go through the same canonical
        // normalization so symlinked paths (e.g. /tmp ↔ /private/tmp)
        // resolve to the same value. See `resolvedWorkingDirectoryCandidate`
        // for the rationale.
        let normalizedPath = normalizedWorkingDirectoryPath(directory)

        if let tabPath = controller.tabManager.tab(for: tabID)?.workingDirectory.path,
           HookPathNormalizer.normalize(tabPath) == normalizedPath {
            return true
        }

        return controller.surfaceIDs(for: tabID).contains { surfaceID in
            guard let surfacePath = controller.surfaceWorkingDirectories[surfaceID]?.path else {
                return false
            }
            return HookPathNormalizer.normalize(surfacePath) == normalizedPath
        }
    }

    func configureSharedServices(
        for controller: MainWindowController,
        registerWindow: Bool = true
    ) {
        controller.injectedAgentDetectionEngine = agentDetectionEngine
        controller.injectedPerSurfaceStore = agentStatePerSurfaceStore
        controller.injectedSessionDiffTracker = sessionDiffTracker
        controller.injectedDashboardViewModel = agentDashboardViewModel
        controller.injectedTimelineStore = agentTimelineStore
        controller.injectedNotificationManager = notificationManager
        controller.windowEventBus = windowEventBus
        controller.notificationAggregator = notificationAggregator
        controller.portScanner = portScanner
        controller.remoteConnectionManager = remoteConnectionManager
        controller.remoteProfileStore = remoteProfileStore
        controller.tunnelManager = tunnelManager
        controller.sshKeyManager = sshKeyManager
        controller.remotePortScanner = remotePortScanner
        controller.browserProfileManager = browserProfileManager
        controller.browserHistoryStore = browserHistoryStore
        controller.browserBookmarkStore = browserBookmarkStore
        controller.sparkleUpdater = sparkleUpdater

        if let registry = sessionRegistry {
            controller.sessionRegistry = registry
            if registerWindow {
                registry.registerWindow(controller.windowID)
            }
        }

        if let manager = notificationManager {
            controller.tabBarViewModel?.setNotificationManager(manager)
        }

        if let quickSwitchController {
            controller.quickSwitchController = quickSwitchController
        }

        controller.timelineDispatcher.navigator = makeTimelineNavigator()

        // The Aurora chrome integration depends on the per-surface store
        // the block above injected. With every service in place we can
        // now honour `appearance.aurora-enabled` — a no-op when the flag
        // is off (default), and a one-shot install when it is on.
        controller.applyInitialAuroraChromeStateIfNeeded()
    }

    @discardableResult
    func registerSession(
        for tab: Tab,
        in controller: MainWindowController,
        sessionID: SessionID? = nil,
        titleOverride: String? = nil
    ) -> SessionID {
        let resolvedSessionID = sessionID
            ?? controller.tabSessionMap[tab.id]
            ?? SessionID()
        controller.tabSessionMap[tab.id] = resolvedSessionID

        let resolvedTitle = titleOverride ?? tab.displayTitle

        // Resolve the per-surface agent state for the registry entry
        // so it reflects the store rather than a tab-level snapshot.
        // Returns `.idle` with no detected agent when no surface of the
        // tab has an active entry yet.
        let resolved = controller.resolveSurfaceAgentState(for: tab.id)

        sessionRegistry?.registerSession(SessionEntry(
            sessionID: resolvedSessionID,
            ownerWindowID: controller.windowID,
            tabID: tab.id,
            title: resolvedTitle,
            workingDirectory: tab.workingDirectory,
            agentState: resolved.agentState,
            detectedAgentName: resolved.detectedAgent?.displayName,
            hasUnreadNotification: tab.hasUnreadNotification
        ))

        return resolvedSessionID
    }

    func makeWindowController(registerInitialSession: Bool) -> MainWindowController? {
        guard let bridge = bridge else { return nil }

        let controller = MainWindowController(
            bridge: bridge,
            configService: configService
        )
        configureSharedServices(for: controller, registerWindow: true)

        if registerInitialSession, let initialTab = controller.tabManager.tabs.first {
            registerSession(for: initialTab, in: controller)
        }

        return controller
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
        guard windowController != nil else { return }
        let config = configService?.current ?? .defaults

        // 1. Create a tab router adapter that delegates to the window controller.
        let tabRouter = windowTabRouter ?? WindowControllerTabRouter(appDelegate: self)
        self.windowTabRouter = tabRouter

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

        // 3b. Create the global notification aggregator. It reads unread
        // state from the session registry and provides cross-window counts.
        let notificationAggregator = self.notificationAggregator

        // 3c. Forward notification events to the session registry so other
        // windows can see unread state via the aggregator.
        if let registry = sessionRegistry {
            manager.notificationsPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak registry] notification in
                    guard let self, let registry else { return }
                    guard let wc = self.controllerContainingTab(notification.tabId) else { return }
                    let sessionID = wc.sessionIDForTab(notification.tabId)
                    registry.markUnread(sessionID)
                }
                .store(in: &hookCancellables)
        }

        // 4. Create the dock badge controller. When the global aggregator
        // exists, use it as the count source (aggregates all windows).
        // Fall back to the single manager for backwards compatibility.
        let badgeSource: any UnreadCountPublishing = notificationAggregator ?? manager
        let dockBadge = DockBadgeController(
            dockTile: SystemDockTile(),
            unreadCountSource: badgeSource,
            config: config
        )
        dockBadge.bind()
        self.dockBadgeController = dockBadge

        // 5. Inject the notification manager into the window controller
        // so OSC notifications are forwarded to the notification pipeline.
        for controller in allWindowControllers {
            controller.injectedNotificationManager = manager
            controller.notificationAggregator = notificationAggregator
            controller.tabBarViewModel?.setNotificationManager(manager)
        }

        // 6. Create the quick switch controller and wire to the window controller.
        let quickSwitch = QuickSwitchController(
            notificationManager: manager,
            tabActivator: tabRouter,
            tabNameProvider: { [weak self] tabID in
                self?.controllerContainingTab(tabID)?.tabManager.tab(for: tabID)?.displayTitle
            }
        )
        for controller in allWindowControllers {
            controller.quickSwitchController = quickSwitch
        }
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
                MainActor.assumeIsolated {
                    adapter?.handleNotificationClick(tabIdString: tabIdString)
                }
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
        for controller in allWindowControllers {
            controller.portScanner = scanner
            // The Aurora chrome may already be installed by the time
            // the port scanner comes online (launch order differs
            // between cold start and reopen). Re-wire the freshly
            // created scanner onto the Aurora controller so its
            // status bar mirrors the same port set as the classic
            // path. No-op when Aurora has never been installed.
            controller.auroraChromeController?.wirePortScanner(scanner)
        }
        scanner.startScanning(interval: 5.0)

        // Refresh status bar when ports change.
        scanner.portsChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.allWindowControllers.forEach { $0.refreshStatusBar() }
            }
            .store(in: &hookCancellables)
    }

    // MARK: - Appearance Observer

    /// Initializes the appearance observer for automatic dark/light theme switching.
    private func initializeAppearanceObserver() {
        let observer = AppearanceObserver()
        self.appearanceObserver = observer

        let config = configService?.current ?? .defaults
        let darkTheme = config.appearance.theme
        let lightTheme = config.appearance.lightTheme

        guard let engine = themeEngine else { return }
        observer.onThemeSwitchRequested = { [weak self] themeName in
            self?.switchTheme(to: themeName)
        }
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
        let delegateRef = WeakReference(self)
        let configServiceRef = WeakReference(configService)
        let sessionManagerRef = WeakReference(self.sessionManager)
        let liveConfigProvider: (@Sendable () -> CocxyConfig)?
        if configService != nil {
            liveConfigProvider = {
                syncOnMainActor {
                    configServiceRef.value?.current ?? .defaults
                }
            }
        } else {
            liveConfigProvider = nil
        }
        let focusedControllerProvider: @Sendable () -> MainWindowController? = {
            syncOnMainActor {
                delegateRef.value?.focusedWindowController()
                    ?? delegateRef.value?.windowController
            }
        }
        let handler = AppSocketCommandHandler(
            tabManager: windowController?.tabManager,
            hookEventReceiver: hookEventReceiver,
            browserViewModelProviderOverride: {
                syncOnMainActor {
                    delegateRef.value?.activeBrowserViewModelForCLI()
                }
            },
            tabCountProviderOverride: {
                syncOnMainActor {
                    delegateRef.value?.allWindowControllers.reduce(0) { partial, controller in
                        partial + controller.tabManager.tabs.count
                    } ?? 0
                }
            },
            tabInfoProviderOverride: {
                syncOnMainActor {
                    guard let delegate = delegateRef.value else { return [] }
                    return delegate.allWindowControllers.flatMap { controller in
                        controller.tabManager.tabs.map { tab in
                            (
                                id: tab.id.rawValue.uuidString,
                                title: tab.displayTitle,
                                isActive: tab.id == (controller.visibleTabID ?? controller.tabManager.activeTabID)
                            )
                        }
                    }
                }
            },
            tabFocusProviderOverride: { uuidString in
                guard let uuid = UUID(uuidString: uuidString) else { return false }
                return syncOnMainActor {
                    let tabID = TabID(rawValue: uuid)
                    if let router = delegateRef.value?.windowTabRouter {
                        guard delegateRef.value?.controllerContainingTab(tabID) != nil else { return false }
                        router.activateTab(id: tabID)
                        return true
                    }
                    return delegateRef.value?.controllerContainingTab(tabID)?.focusTab(id: tabID) ?? false
                }
            },
            tabCloseProviderOverride: { uuidString in
                guard let uuid = UUID(uuidString: uuidString) else { return .notFound }
                return syncOnMainActor {
                    let tabID = TabID(rawValue: uuid)
                    guard let controller = delegateRef.value?.controllerContainingTab(tabID) else {
                        return .notFound
                    }
                    guard let index = controller.tabManager.tabs.firstIndex(where: { $0.id == tabID }) else {
                        return .notFound
                    }
                    guard controller.tabManager.tabs.count > 1 else {
                        return .lastTabBlocked
                    }
                    guard !controller.tabManager.tabs[index].isPinned else {
                        return .pinnedBlocked
                    }

                    controller.closeTab(tabID)
                    return controller.tabManager.tabs.contains(where: { $0.id == tabID }) ? .unavailable : .closed
                }
            },
            tabCreateProviderOverride: { directoryPath in
                syncOnMainActor {
                    guard let controller = focusedControllerProvider() else { return nil }
                    let workingDirectory = directoryPath.map(URL.init(fileURLWithPath:))
                    controller.createTab(workingDirectory: workingDirectory)
                    guard let newTabID = controller.tabManager.activeTabID,
                          let tab = controller.tabManager.tab(for: newTabID) else {
                        return nil
                    }
                    return (id: newTabID.rawValue.uuidString, title: tab.displayTitle)
                }
            },
            tabRenameProviderOverride: { uuidString, newName in
                guard let uuid = UUID(uuidString: uuidString) else { return false }
                return syncOnMainActor {
                    let tabID = TabID(rawValue: uuid)
                    guard let controller = delegateRef.value?.controllerContainingTab(tabID) else { return false }
                    guard controller.tabManager.tab(for: tabID) != nil else { return false }
                    controller.tabManager.renameTab(id: tabID, newTitle: newName)
                    return true
                }
            },
            tabMoveProviderOverride: { uuidString, destinationIndex in
                guard let uuid = UUID(uuidString: uuidString) else { return false }
                return syncOnMainActor {
                    let tabID = TabID(rawValue: uuid)
                    guard let controller = delegateRef.value?.controllerContainingTab(tabID),
                          let fromIndex = controller.tabManager.tabs.firstIndex(where: { $0.id == tabID }),
                          destinationIndex >= 0,
                          destinationIndex < controller.tabManager.tabs.count else {
                        return false
                    }
                    controller.tabManager.moveTab(from: fromIndex, to: destinationIndex)
                    return true
                }
            },
            projectConfigProviderOverride: {
                syncOnMainActor {
                    guard let controller = focusedControllerProvider(),
                          let activeID = controller.visibleTabID ?? controller.tabManager.activeTabID,
                          let tab = controller.tabManager.tab(for: activeID),
                          let config = tab.projectConfig else {
                        return nil
                    }

                    var data: [String: String] = [:]
                    if let fontSize = config.fontSize {
                        data["font-size"] = String(fontSize)
                    }
                    if let padding = config.windowPadding {
                        data["window-padding"] = String(padding)
                    }
                    if let paddingX = config.windowPaddingX {
                        data["window-padding-x"] = String(paddingX)
                    }
                    if let paddingY = config.windowPaddingY {
                        data["window-padding-y"] = String(paddingY)
                    }
                    if let opacity = config.backgroundOpacity {
                        data["background-opacity"] = String(opacity)
                    }
                    if let blur = config.backgroundBlurRadius {
                        data["background-blur-radius"] = String(blur)
                    }
                    if let patterns = config.agentDetectionExtraPatterns {
                        data["agent-detection-extra-patterns"] = patterns.joined(separator: ", ")
                    }
                    if let keybindings = config.keybindingOverrides {
                        for (key, value) in keybindings {
                            data["keybinding.\(key)"] = value
                        }
                    }
                    return data
                }
            },
            configProvider: liveConfigProvider,
            statusDetailsProvider: {
                syncOnMainActor {
                    delegateRef.value?.runtimeStatusDetailsForCLI() ?? [:]
                }
            },
            themeEngineProvider: {
                if Thread.isMainThread {
                    return MainActor.assumeIsolated {
                        delegateRef.value?.themeEngine
                    }
                }
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        delegateRef.value?.themeEngine
                    }
                }
            },
            remoteConnectionManagerProvider: {
                if Thread.isMainThread {
                    return MainActor.assumeIsolated {
                        delegateRef.value?.remoteConnectionManager
                    }
                }
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        delegateRef.value?.remoteConnectionManager
                    }
                }
            },
            remoteProfileStoreProvider: {
                if Thread.isMainThread {
                    return MainActor.assumeIsolated {
                        delegateRef.value?.remoteProfileStore
                    }
                }
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        delegateRef.value?.remoteProfileStore
                    }
                }
            },
            pluginManagerProvider: {
                if Thread.isMainThread {
                    return MainActor.assumeIsolated {
                        delegateRef.value?.pluginManager
                    }
                }
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        delegateRef.value?.pluginManager
                    }
                }
            },
            notifyDispatcher: { title, body in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let manager = delegate.notificationManager else { return }
                    let tabId = focusedControllerProvider()?.visibleTabID
                        ?? focusedControllerProvider()?.tabManager.activeTabID
                        ?? TabID()
                    let notification = CocxyNotification(
                        type: .custom("cli"),
                        tabId: tabId,
                        title: title,
                        body: body
                    )
                    manager.notify(notification)
                }
            },
            // V3: Tab duplicate — create new tab with active tab's CWD.
            tabDuplicateProvider: {
                syncOnMainActor {
                    delegateRef.value?.duplicateFocusedTabForCLI()
                }
            },
            // V3: Tab pin — toggle pin on active or specific tab.
            tabPinProvider: { tabIDString in
                syncOnMainActor {
                    let manager: TabManager
                    if let idStr = tabIDString,
                       let uuid = UUID(uuidString: idStr),
                       let controller = delegateRef.value?.controllerContainingTab(TabID(rawValue: uuid)) {
                        manager = controller.tabManager
                    } else if let controller = focusedControllerProvider() {
                        manager = controller.tabManager
                    } else {
                        return nil
                    }
                    let targetID: TabID
                    if let idStr = tabIDString, let uuid = UUID(uuidString: idStr) {
                        targetID = TabID(rawValue: uuid)
                    } else if let activeID = manager.activeTabID {
                        targetID = activeID
                    } else {
                        return nil
                    }
                    manager.togglePin(id: targetID)
                    let isPinned = manager.tab(for: targetID)?.isPinned ?? false
                    return (id: targetID.rawValue.uuidString, isPinned: isPinned)
                }
            },
            // V3: Config reload — re-read config from disk.
            configReloadProvider: {
                syncOnMainActor {
                    guard let svc = delegateRef.value?.configService else { return false }
                    do {
                        try svc.reload()
                        return true
                    } catch {
                        return false
                    }
                }
            },
            // V3: Split info — list panes in active tab.
            splitInfoProvider: {
                syncOnMainActor {
                    guard let wc = focusedControllerProvider(),
                          let activeTabID = wc.tabManager.activeTabID else { return [] }
                    let sm = wc.tabSplitCoordinator.splitManager(for: activeTabID)
                    let leaves = sm.rootNode.allLeafIDs()
                    let focusedID = sm.focusedLeafID
                    return leaves.map { leaf in
                        (
                            leafID: leaf.leafID.uuidString,
                            terminalID: leaf.terminalID.uuidString,
                            isFocused: leaf.leafID == focusedID
                        )
                    }
                }
            },
            // V3: Split swap — exchange two panes by index.
            splitSwapProvider: { indexA, indexB in
                syncOnMainActor {
                    guard let wc = focusedControllerProvider(),
                          let activeTabID = wc.tabManager.activeTabID else { return false }
                    let sm = wc.tabSplitCoordinator.splitManager(for: activeTabID)
                    let leafCount = sm.rootNode.allLeafIDs().count
                    guard indexA >= 0, indexA < leafCount,
                          indexB >= 0, indexB < leafCount,
                          indexA != indexB else { return false }
                    sm.swapLeaves(at: indexA, with: indexB)
                    wc.rebuildSplitViewHierarchy(for: activeTabID)
                    return true
                }
            },
            splitSwapByDirectionProvider: { direction in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let navDirection = NavigationDirection(commandValue: direction) else { return false }
                    return delegate.swapSplit(in: navDirection)
                }
            },
            // V3: Split zoom — toggle zoom on focused pane.
            splitZoomProvider: {
                syncOnMainActor {
                    guard let wc = focusedControllerProvider(),
                          let activeTabID = wc.tabManager.activeTabID else { return (false, false) }
                    let sm = wc.tabSplitCoordinator.splitManager(for: activeTabID)
                    guard sm.rootNode.allLeafIDs().count > 1 else { return (false, false) }
                    sm.toggleZoom()
                    return (true, sm.isZoomed)
                }
            },
            // V3: Session manager.
            sessionManagerProvider: {
                sessionManagerRef.value
            },
            // V3: Session capture — snapshot current app state.
            sessionCaptureProvider: {
                syncOnMainActor {
                    delegateRef.value?.captureCurrentSession()
                }
            },
            // V3: Session restore — recreate tabs from saved session.
            sessionRestoreProvider: { name in
                syncOnMainActor {
                    delegateRef.value?.restoreSessionFromCLI(named: name) ?? false
                }
            },
            // V3: Notification manager.
            notificationManagerProvider: {
                if Thread.isMainThread {
                    return MainActor.assumeIsolated {
                        delegateRef.value?.notificationManager
                    }
                }
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        delegateRef.value?.notificationManager
                    }
                }
            },
            // V3: Capture pane — return terminal output buffer lines.
            capturePaneProvider: {
                syncOnMainActor {
                    focusedControllerProvider()?.terminalOutputBuffer.lines ?? []
                }
            },
            // V4: Dashboard toggle — show/hide dashboard panel.
            dashboardToggleProvider: {
                syncOnMainActor {
                    focusedControllerProvider()?.toggleDashboard()
                    return focusedControllerProvider()?.isDashboardVisible ?? false
                }
            },
            // V4: Dashboard status — session counts and visibility.
            dashboardStatusProvider: {
                syncOnMainActor {
                    let wc = focusedControllerProvider()
                    var data: [String: String] = [:]
                    data["visible"] = (wc?.isDashboardVisible ?? false) ? "true" : "false"
                    let sessions = wc?.dashboardViewModel?.sessions ?? []
                    data["session_count"] = "\(sessions.count)"
                    data["active_count"] = "\(sessions.filter { $0.state == .working }.count)"
                    data["error_count"] = "\(sessions.filter { $0.state == .error }.count)"
                    let totalSubagents = sessions.flatMap(\.subagents).count
                    data["subagent_count"] = "\(totalSubagents)"
                    let activeSubagents = sessions.flatMap(\.subagents).filter(\.isActive).count
                    data["active_subagent_count"] = "\(activeSubagents)"
                    let totalFiles = sessions.flatMap(\.filesTouched).count
                    data["total_files_touched"] = "\(totalFiles)"
                    let totalConflicts = sessions.flatMap(\.fileConflicts).count
                    data["file_conflicts"] = "\(totalConflicts)"
                    let totalTools = sessions.reduce(0) { $0 + $1.totalToolCalls }
                    data["total_tool_calls"] = "\(totalTools)"
                    let totalErrors = sessions.reduce(0) { $0 + $1.totalErrors }
                    data["total_errors"] = "\(totalErrors)"
                    return data
                }
            },
            reviewToggleProvider: {
                syncOnMainActor {
                    guard let wc = focusedControllerProvider() else { return false }
                    wc.toggleCodeReview()
                    return wc.isCodeReviewVisible
                }
            },
            reviewRefreshProvider: {
                syncOnMainActor {
                    focusedControllerProvider()?.refreshCodeReviewFromCLI()
                }
            },
            reviewSubmitProvider: {
                syncOnMainActor {
                    focusedControllerProvider()?.submitCodeReviewFromCLI()
                }
            },
            reviewStatsProvider: {
                syncOnMainActor {
                    guard let wc = focusedControllerProvider() else { return nil }
                    return wc.codeReviewStatsSnapshot()
                }
            },
            // V4: Timeline query — return events for a tab.
            timelineQueryProvider: { tabIDString in
                syncOnMainActor {
                    delegateRef.value?.timelineQuery(for: tabIDString)
                }
            },
            // V4: Timeline export — return serialized timeline data.
            timelineExportProvider: { tabIDString, format in
                syncOnMainActor {
                    delegateRef.value?.exportTimeline(for: tabIDString, format: format)
                }
            },
            // V4: Split create — add a new split pane.
            splitCreateProvider: { isVertical in
                syncOnMainActor {
                    guard let wc = focusedControllerProvider(),
                          let activeTabID = wc.tabManager.activeTabID else { return false }
                    let sm = wc.tabSplitCoordinator.splitManager(for: activeTabID)
                    let countBefore = sm.rootNode.allLeafIDs().count
                    guard countBefore < SplitManager.maxPaneCount else { return false }
                    if isVertical {
                        wc.splitVerticalAction(nil)
                    } else {
                        wc.splitHorizontalAction(nil)
                    }
                    return sm.rootNode.allLeafIDs().count > countBefore
                }
            },
            // V4: Split focus — focus a pane by DFS index.
            splitFocusProvider: { index in
                syncOnMainActor {
                    guard let wc = focusedControllerProvider(),
                          let activeTabID = wc.tabManager.activeTabID else { return false }
                    let sm = wc.tabSplitCoordinator.splitManager(for: activeTabID)
                    let leaves = sm.rootNode.allLeafIDs()
                    guard index >= 0, index < leaves.count else { return false }
                    sm.focusLeaf(id: leaves[index].leafID)
                    return true
                }
            },
            // V4: Split focus — focus neighboring pane by direction.
            splitFocusByDirectionProvider: { direction in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let navDirection = NavigationDirection(commandValue: direction) else { return false }
                    return delegate.focusSplit(in: navDirection)
                }
            },
            // V4: Split close — close the focused pane.
            splitCloseProvider: {
                syncOnMainActor {
                    guard let wc = focusedControllerProvider(),
                          let activeTabID = wc.tabManager.activeTabID else { return false }
                    let sm = wc.tabSplitCoordinator.splitManager(for: activeTabID)
                    guard sm.rootNode.allLeafIDs().count > 1 else { return false }
                    wc.closeSplitAction(nil)
                    return true
                }
            },
            // V4: Split resize — set ratio on a split node.
            splitResizeProvider: { splitIDStr, ratio in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let uuid = UUID(uuidString: splitIDStr) else { return false }
                    return delegate.setSplitRatio(splitID: uuid, ratio: ratio)
                }
            },
            // V4: Split resize — resize neighboring divider by direction and pixels.
            splitResizeByDirectionProvider: { direction, pixels in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let navDirection = NavigationDirection(commandValue: direction) else { return false }
                    return delegate.resizeSplit(in: navDirection, pixels: pixels)
                }
            },
            // V4: Search toggle — show/hide search bar.
            searchToggleProvider: {
                syncOnMainActor {
                    focusedControllerProvider()?.toggleSearchBar()
                }
            },
            // V4: Search query — return structured scrollback matches.
            searchProvider: { query, regex, caseSensitive, tabIDString in
                syncOnMainActor {
                    delegateRef.value?.searchScrollback(
                        query: query,
                        regex: regex,
                        caseSensitive: caseSensitive,
                        tabIDString: tabIDString
                    )
                }
            },
            // V4: Send text — write text to the active terminal's PTY.
            sendTextProvider: { text in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let bridge = delegate.bridge,
                          let wc = focusedControllerProvider(),
                          let surfaceView = wc.focusedSplitSurfaceView,
                          let surfaceID = surfaceView.terminalViewModel?.surfaceID else { return false }
                    bridge.sendText(text, to: surfaceID)
                    return true
                }
            },
            // V4: Send key — send a named key to the active terminal.
            sendKeyProvider: { keyName in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let bridge = delegate.bridge,
                          let wc = focusedControllerProvider(),
                          let surfaceView = wc.focusedSplitSurfaceView,
                          let surfaceID = surfaceView.terminalViewModel?.surfaceID else { return false }
                    let sequence: String?
                    switch keyName.lowercased() {
                    case "enter", "return":   sequence = "\r"
                    case "tab":               sequence = "\t"
                    case "escape", "esc":     sequence = "\u{1B}"
                    case "backspace", "bs":   sequence = "\u{7F}"
                    case "space":             sequence = " "
                    case "up":                sequence = "\u{1B}[A"
                    case "down":              sequence = "\u{1B}[B"
                    case "right":             sequence = "\u{1B}[C"
                    case "left":              sequence = "\u{1B}[D"
                    case "delete", "del":     sequence = "\u{1B}[3~"
                    case "home":              sequence = "\u{1B}[H"
                    case "end":               sequence = "\u{1B}[F"
                    case "pageup", "pgup":    sequence = "\u{1B}[5~"
                    case "pagedown", "pgdn":  sequence = "\u{1B}[6~"
                    case "insert", "ins":     sequence = "\u{1B}[2~"
                    case "ctrl-c":            sequence = "\u{03}"
                    case "ctrl-d":            sequence = "\u{04}"
                    case "ctrl-z":            sequence = "\u{1A}"
                    case "ctrl-l":            sequence = "\u{0C}"
                    case "ctrl-a":            sequence = "\u{01}"
                    case "ctrl-e":            sequence = "\u{05}"
                    case "ctrl-k":            sequence = "\u{0B}"
                    case "ctrl-u":            sequence = "\u{15}"
                    case "ctrl-w":            sequence = "\u{17}"
                    default:                  sequence = nil
                    }
                    guard let seq = sequence else { return false }
                    bridge.sendText(seq, to: surfaceID)
                    return true
                }
            },
            // V4: SSH — open SSH in a new tab.
            sshProvider: { destination, port, identityFile in
                syncOnMainActor {
                    guard let delegate = delegateRef.value,
                          let wc = focusedControllerProvider() else { return nil }
                    var sshArgs = ["ssh"]
                    if let port = port { sshArgs += ["-p", "\(port)"] }
                    if let identity = identityFile { sshArgs += ["-i", identity] }
                    sshArgs.append(destination)
                    let sshCommand = sshArgs.joined(separator: " ")

                    let newTab = wc.tabManager.addTab(
                        workingDirectory: FileManager.default.homeDirectoryForCurrentUser
                    )
                    wc.tabManager.renameTab(id: newTab.id, newTitle: destination)
                    wc.tabManager.setActive(id: newTab.id)

                    let targetTabID = newTab.id
                    Task { @MainActor [weak wc, weak delegate] in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard let bridge = delegate?.bridge,
                              let wc = wc,
                              wc.tabManager.activeTabID == targetTabID else { return }
                        let surfaceID = wc.activeTerminalSurfaceView?.terminalViewModel?.surfaceID
                        guard let sid = surfaceID else { return }
                        bridge.sendText("\(sshCommand)\r", to: sid)
                    }
                    return (id: newTab.id.rawValue.uuidString, title: destination)
                }
            },
            webStartProvider: { bind, port, token, maxConnections, fps in
                syncOnMainActor {
                    delegateRef.value?.startWebTerminalForCLI(
                        bindAddress: bind,
                        port: port,
                        token: token,
                        maxConnections: maxConnections,
                        maxFPS: fps
                    )
                }
            },
            webStopProvider: {
                syncOnMainActor {
                    delegateRef.value?.stopWebTerminalForCLI() ?? false
                }
            },
            webStatusProvider: {
                syncOnMainActor {
                    delegateRef.value?.webStatusForCLI()
                }
            },
            streamListProvider: {
                syncOnMainActor {
                    delegateRef.value?.streamListForCLI()
                }
            },
            streamCurrentProvider: { streamID in
                syncOnMainActor {
                    delegateRef.value?.setCurrentStreamForCLI(streamID)
                }
            },
            protocolCapabilitiesProvider: {
                syncOnMainActor {
                    delegateRef.value?.requestProtocolCapabilitiesForCLI()
                }
            },
            protocolViewportProvider: { requestID in
                syncOnMainActor {
                    delegateRef.value?.sendProtocolViewportForCLI(requestID: requestID)
                }
            },
            protocolSendProvider: { type, payload in
                syncOnMainActor {
                    delegateRef.value?.sendProtocolMessageForCLI(type: type, payload: payload)
                }
            },
            coreResetProvider: {
                syncOnMainActor {
                    delegateRef.value?.resetTerminalForCLI()
                }
            },
            coreSignalProvider: { signal in
                syncOnMainActor {
                    delegateRef.value?.sendSignalForCLI(signal)
                }
            },
            coreProcessProvider: {
                syncOnMainActor {
                    delegateRef.value?.processDiagnosticsForCLI()
                }
            },
            coreModesProvider: {
                syncOnMainActor {
                    delegateRef.value?.modeDiagnosticsForCLI()
                }
            },
            coreSearchProvider: {
                syncOnMainActor {
                    delegateRef.value?.searchDiagnosticsForCLI()
                }
            },
            coreLigaturesProvider: {
                syncOnMainActor {
                    delegateRef.value?.ligatureDiagnosticsForCLI()
                }
            },
            coreProtocolProvider: {
                syncOnMainActor {
                    delegateRef.value?.protocolDiagnosticsForCLI()
                }
            },
            coreSelectionProvider: {
                syncOnMainActor {
                    delegateRef.value?.selectionSnapshotForCLI()
                }
            },
            coreFontMetricsProvider: {
                syncOnMainActor {
                    delegateRef.value?.fontMetricsForCLI()
                }
            },
            corePreeditProvider: {
                syncOnMainActor {
                    delegateRef.value?.preeditSnapshotForCLI()
                }
            },
            coreSemanticProvider: { limit in
                syncOnMainActor {
                    delegateRef.value?.semanticSummaryForCLI(limit: limit)
                }
            },
            imageListProvider: {
                syncOnMainActor {
                    delegateRef.value?.listImagesForCLI()
                }
            },
            imageDeleteProvider: { imageID in
                syncOnMainActor {
                    delegateRef.value?.deleteImageForCLI(imageID)
                }
            },
            imageClearProvider: {
                syncOnMainActor {
                    delegateRef.value?.clearImagesForCLI()
                }
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
            MainActor.assumeIsolated {
                self?.socketServer?.restartIfNeeded()
            }
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
final class WindowControllerTabRouter: NotificationTabRouting, DashboardTabNavigating, TabActivating {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func activateTab(id: TabID) {
        guard let controller = appDelegate?.controllerContainingTab(id) else { return }
        controller.tabManager.setActive(id: id)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func focusTab(id: TabID) -> Bool {
        guard appDelegate?.controllerContainingTab(id) != nil else { return false }
        activateTab(id: id)
        return true
    }

    func setActive(id: TabID) {
        activateTab(id: id)
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
