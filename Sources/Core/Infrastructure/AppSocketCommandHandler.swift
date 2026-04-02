// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler.swift - Production socket command dispatcher.

import AppKit
import Foundation

// MARK: - Version Constant

/// Single source of truth for the application version.
/// Reads from Info.plist at runtime (set by the release pipeline).
/// Falls back to "dev" for debug/test builds where no Info.plist exists.
enum CocxyVersion {
    static let current: String = {
        guard let bundleID = Bundle.main.bundleIdentifier,
              bundleID.contains("cocxy"),
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "dev"
        }
        return version
    }()
}

// MARK: - App Socket Command Handler

/// Production implementation of `SocketCommandHandling`.
///
/// Dispatches validated socket commands to the appropriate domain services.
/// Called from background threads; dispatches to main actor when needed
/// via closure providers that safely bridge the concurrency boundary.
///
/// ## Command Groups
///
/// 1. **Status & Tab listing** -- read-only queries (status, list-tabs).
/// 2. **Tab mutations** -- focus-tab, close-tab, new-tab, tab-rename, tab-move.
/// 3. **Config operations** -- config-get, config-set, config-path (disk I/O).
/// 4. **Theme operations** -- theme-list, theme-set.
/// 5. **Acknowledged commands** -- async UI actions that return immediately
///    (notify, split, dashboard, timeline, search, send, send-key, hooks).
///
/// Unknown commands are rejected with an error response.
///
/// - SeeAlso: `SocketCommandHandling` protocol
/// - SeeAlso: `CLICommandName` for the closed set of valid commands.
final class AppSocketCommandHandler: SocketCommandHandling, @unchecked Sendable {

    // MARK: - Dependencies

    /// Closure that returns the tab count from the main thread.
    private let tabCountProvider: @Sendable () -> Int

    /// Closure that returns tab info (id, title, isActive) from the main thread.
    private let tabInfoProvider: @Sendable () -> [(id: String, title: String, isActive: Bool)]

    /// Closure that focuses a tab by UUID string. Returns true if the tab was found.
    private let tabFocusProvider: @Sendable (String) -> Bool

    /// Closure that closes a tab by UUID string. Returns true if executed.
    private let tabCloseProvider: @Sendable (String) -> Bool

    /// Closure that creates a new tab with an optional working directory.
    /// Returns the new tab's (id, title) or nil if TabManager is unavailable.
    private let tabCreateProvider: @Sendable (String?) -> (id: String, title: String)?

    /// Closure that renames a tab. Params: (tabID, newName). Returns true on success.
    private let tabRenameProvider: @Sendable (String, String) -> Bool

    /// Closure that moves a tab. Params: (tabID, destinationIndex). Returns true on success.
    private let tabMoveProvider: @Sendable (String, Int) -> Bool

    /// Closure that reads the active tab's project config. Returns a dict of overrides or nil.
    private let projectConfigProvider: @Sendable () -> [String: String]?

    /// The hook event receiver for processing Claude Code hook events.
    private let hookEventReceiver: HookEventReceiverImpl?

    /// Closure that provides the browser view model for scriptable browser commands.
    /// Returns nil when no browser panel is open.
    private let browserViewModelProvider: @Sendable () -> BrowserViewModel?

    /// Closure that returns the current live configuration snapshot.
    /// Falls back to defaults when ConfigService is unavailable.
    private let configProvider: (@Sendable () -> CocxyConfig)?

    /// Provides the shared theme engine for theme-list and theme-set commands.
    /// Must be called from MainActor context.
    private let themeEngineProvider: (() -> ThemeEngineImpl?)?

    /// Provides the remote connection manager for remote workspace commands.
    private let remoteConnectionManagerProvider: (() -> RemoteConnectionManager?)?

    /// Provides the remote profile store for remote workspace queries.
    private let remoteProfileStoreProvider: (() -> (any RemoteProfileStoring)?)?

    /// Provides the plugin manager for plugin lifecycle commands.
    private let pluginManagerProvider: (() -> PluginManager?)?

    /// Dispatches a CLI notification through the notification pipeline.
    /// Called from `handleNotify(_:)` to deliver real notifications instead
    /// of silently returning "acknowledged".
    private let notifyDispatcher: @Sendable (String, String) -> Void

    // MARK: - V3 Command Providers

    /// Duplicates the active tab (creates new tab with same working directory).
    private let tabDuplicateProvider: (@Sendable () -> (id: String, title: String)?)?

    /// Toggles pin on a tab. Nil tabID = active tab. Returns (id, isPinned).
    private let tabPinProvider: (@Sendable (String?) -> (id: String, isPinned: Bool)?)?

    /// Reloads the configuration from disk. Returns true on success.
    private let configReloadProvider: (@Sendable () -> Bool)?

    /// Returns split pane info for the active tab.
    private let splitInfoProvider: (@Sendable () -> [(leafID: String, terminalID: String, isFocused: Bool)])?

    /// Swaps two panes by DFS index in the active tab. Returns true on success.
    private let splitSwapProvider: (@Sendable (Int, Int) -> Bool)?

    /// Toggles zoom on the focused pane. Returns (success, isZoomed).
    private let splitZoomProvider: (@Sendable () -> (success: Bool, isZoomed: Bool))?

    /// Provides the session manager for session CRUD operations.
    private let sessionManagerProvider: (() -> (any SessionManaging)?)?

    /// Captures the current application state as a Session snapshot.
    private let sessionCaptureProvider: (@Sendable () -> Session?)?

    /// Restores a session by name (nil = last). Returns true on success.
    private let sessionRestoreProvider: (@Sendable (String?) -> Bool)?

    /// Provides the notification manager for list/clear operations.
    private let notificationManagerProvider: (() -> NotificationManagerImpl?)?

    /// Returns the active pane's terminal output buffer content.
    private let capturePaneProvider: (@Sendable () -> [String])?

    // MARK: - Initialization

    /// Creates an AppSocketCommandHandler with closure-based access to @MainActor services.
    ///
    /// Each closure provider safely bridges the concurrency boundary between
    /// the background socket thread and the main actor. The closures use the
    /// `MainActor.assumeIsolated` + `DispatchQueue.main.sync` pattern for
    /// safe cross-thread access to @MainActor-isolated properties.
    ///
    /// - Parameters:
    ///   - tabManager: The tab manager for tab operations. Nil when no window is open.
    ///   - hookEventReceiver: The hook event receiver for Layer 0 events.
    ///   - browserViewModel: The browser view model for scriptable browser commands.
    ///     Nil when no browser panel is available.
    init(
        tabManager: TabManager?,
        hookEventReceiver: HookEventReceiverImpl?,
        browserViewModel: BrowserViewModel? = nil,
        configProvider: (@Sendable () -> CocxyConfig)? = nil,
        themeEngineProvider: (() -> ThemeEngineImpl?)? = nil,
        remoteConnectionManagerProvider: (() -> RemoteConnectionManager?)? = nil,
        remoteProfileStoreProvider: (() -> (any RemoteProfileStoring)?)? = nil,
        pluginManagerProvider: (() -> PluginManager?)? = nil,
        notifyDispatcher: (@Sendable (String, String) -> Void)? = nil,
        tabDuplicateProvider: (@Sendable () -> (id: String, title: String)?)? = nil,
        tabPinProvider: (@Sendable (String?) -> (id: String, isPinned: Bool)?)? = nil,
        configReloadProvider: (@Sendable () -> Bool)? = nil,
        splitInfoProvider: (@Sendable () -> [(leafID: String, terminalID: String, isFocused: Bool)])? = nil,
        splitSwapProvider: (@Sendable (Int, Int) -> Bool)? = nil,
        splitZoomProvider: (@Sendable () -> (success: Bool, isZoomed: Bool))? = nil,
        sessionManagerProvider: (() -> (any SessionManaging)?)? = nil,
        sessionCaptureProvider: (@Sendable () -> Session?)? = nil,
        sessionRestoreProvider: (@Sendable (String?) -> Bool)? = nil,
        notificationManagerProvider: (() -> NotificationManagerImpl?)? = nil,
        capturePaneProvider: (@Sendable () -> [String])? = nil
    ) {
        self.configProvider = configProvider
        self.themeEngineProvider = themeEngineProvider
        self.remoteConnectionManagerProvider = remoteConnectionManagerProvider
        self.remoteProfileStoreProvider = remoteProfileStoreProvider
        self.pluginManagerProvider = pluginManagerProvider
        self.notifyDispatcher = notifyDispatcher ?? { _, _ in }
        self.tabDuplicateProvider = tabDuplicateProvider
        self.tabPinProvider = tabPinProvider
        self.configReloadProvider = configReloadProvider
        self.splitInfoProvider = splitInfoProvider
        self.splitSwapProvider = splitSwapProvider
        self.splitZoomProvider = splitZoomProvider
        self.sessionManagerProvider = sessionManagerProvider
        self.sessionCaptureProvider = sessionCaptureProvider
        self.sessionRestoreProvider = sessionRestoreProvider
        self.notificationManagerProvider = notificationManagerProvider
        self.capturePaneProvider = capturePaneProvider
        weak var weakTabManager = tabManager
        weak var weakBrowserVM = browserViewModel

        // -- Browser view model provider --
        self.browserViewModelProvider = {
            var vm: BrowserViewModel?
            let work = {
                MainActor.assumeIsolated {
                    vm = weakBrowserVM
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return vm
        }

        // -- Tab count provider (read-only) --
        self.tabCountProvider = {
            var count = 0
            let work = {
                MainActor.assumeIsolated {
                    count = weakTabManager?.tabs.count ?? 0
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return count
        }

        // -- Tab info provider (read-only) --
        self.tabInfoProvider = {
            var info: [(id: String, title: String, isActive: Bool)] = []
            let work = {
                MainActor.assumeIsolated {
                    guard let tabs = weakTabManager?.tabs else { return }
                    info = tabs.map { (
                        id: $0.id.rawValue.uuidString,
                        title: $0.title,
                        isActive: $0.isActive
                    )}
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return info
        }

        // -- Focus tab by UUID string --
        self.tabFocusProvider = { uuidString in
            guard let uuid = UUID(uuidString: uuidString) else { return false }
            var found = false
            let work = {
                MainActor.assumeIsolated {
                    guard let manager = weakTabManager else { return }
                    let tabID = TabID(rawValue: uuid)
                    guard manager.tabs.contains(where: { $0.id == tabID }) else { return }
                    manager.setActive(id: tabID)
                    found = true
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return found
        }

        // -- Close tab by UUID string --
        self.tabCloseProvider = { uuidString in
            guard let uuid = UUID(uuidString: uuidString) else { return false }
            var handled = false
            let work = {
                MainActor.assumeIsolated {
                    guard let manager = weakTabManager else { return }
                    let tabID = TabID(rawValue: uuid)
                    manager.removeTab(id: tabID)
                    handled = true
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return handled
        }

        // -- Create new tab with optional directory --
        self.tabCreateProvider = { directoryPath in
            var result: (id: String, title: String)?
            let work = {
                MainActor.assumeIsolated {
                    guard let manager = weakTabManager else { return }
                    let workingDirectory: URL
                    if let path = directoryPath {
                        workingDirectory = URL(fileURLWithPath: path)
                    } else {
                        workingDirectory = FileManager.default.homeDirectoryForCurrentUser
                    }
                    let newTab = manager.addTab(workingDirectory: workingDirectory)
                    result = (id: newTab.id.rawValue.uuidString, title: newTab.title)
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return result
        }

        // -- Rename tab by UUID string --
        self.tabRenameProvider = { uuidString, newName in
            guard let uuid = UUID(uuidString: uuidString) else { return false }
            var found = false
            let work = {
                MainActor.assumeIsolated {
                    guard let manager = weakTabManager else { return }
                    let tabID = TabID(rawValue: uuid)
                    guard manager.tabs.contains(where: { $0.id == tabID }) else { return }
                    manager.renameTab(id: tabID, newTitle: newName)
                    found = true
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return found
        }

        // -- Move tab to new position --
        self.tabMoveProvider = { uuidString, destinationIndex in
            guard let uuid = UUID(uuidString: uuidString) else { return false }
            var moved = false
            let work = {
                MainActor.assumeIsolated {
                    guard let manager = weakTabManager else { return }
                    let tabID = TabID(rawValue: uuid)
                    guard let fromIndex = manager.tabs.firstIndex(
                        where: { $0.id == tabID }
                    ) else { return }
                    guard destinationIndex >= 0,
                          destinationIndex < manager.tabs.count else { return }
                    manager.moveTab(from: fromIndex, to: destinationIndex)
                    moved = true
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return moved
        }

        // -- Project config from active tab (read-only) --
        self.projectConfigProvider = {
            var result: [String: String]?
            let work = {
                MainActor.assumeIsolated {
                    guard let manager = weakTabManager,
                          let activeID = manager.activeTabID,
                          let tab = manager.tab(for: activeID),
                          let config = tab.projectConfig else { return }

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
                    result = data
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }
            return result
        }

        self.hookEventReceiver = hookEventReceiver
    }

    // MARK: - SocketCommandHandling

    func handleCommand(_ request: SocketRequest) -> SocketResponse {
        guard let commandName = CLICommandName(rawValue: request.command) else {
            return .failure(id: request.id, error: "Unknown command: \(request.command)")
        }

        switch commandName {
        // Status & listing
        case .status:
            return handleStatus(request)
        case .listTabs:
            return handleListTabs(request)

        // Tab mutations
        case .focusTab:
            return handleFocusTab(request)
        case .closeTab:
            return handleCloseTab(request)
        case .newTab:
            return handleNewTab(request)
        case .tabRename:
            return handleTabRename(request)
        case .tabMove:
            return handleTabMove(request)

        // Config operations
        case .configGet:
            return handleConfigGet(request)
        case .configSet:
            return handleConfigSet(request)
        case .configPath:
            return handleConfigPath(request)
        case .configProject:
            return handleConfigProject(request)

        // Theme operations
        case .themeList:
            return handleThemeList(request)
        case .themeSet:
            return handleThemeSet(request)

        // Hook events
        case .hookEvent:
            return handleHookEvent(request)

        // Browser commands
        case .browserNavigate:
            return handleBrowserNavigate(request)
        case .browserBack:
            return handleBrowserBack(request)
        case .browserForward:
            return handleBrowserForward(request)
        case .browserReload:
            return handleBrowserReload(request)
        case .browserGetState:
            return handleBrowserGetState(request)
        case .browserEval:
            return handleBrowserEval(request)
        case .browserGetText:
            return handleBrowserGetText(request)
        case .browserListTabs:
            return handleBrowserListTabs(request)

        // Remote workspace commands
        case .remoteList:
            return handleRemoteList(request)
        case .remoteConnect:
            return handleRemoteConnect(request)
        case .remoteDisconnect:
            return handleRemoteDisconnect(request)
        case .remoteStatus:
            return handleRemoteStatus(request)
        case .remoteTunnels:
            return handleRemoteTunnels(request)

        // Plugin commands
        case .pluginList:
            return handlePluginList(request)
        case .pluginEnable:
            return handlePluginEnable(request)
        case .pluginDisable:
            return handlePluginDisable(request)

        // CLI notify: dispatch through the notification pipeline.
        case .notify:
            return handleNotify(request)

        // V3: Window management
        case .windowNew:
            return handleWindowNew(request)
        case .windowList:
            return handleWindowList(request)
        case .windowFocus:
            return handleWindowFocus(request)
        case .windowClose:
            return handleWindowClose(request)
        case .windowFullscreen:
            return handleWindowFullscreen(request)

        // V3: Session management
        case .sessionSave:
            return handleSessionSave(request)
        case .sessionRestore:
            return handleSessionRestore(request)
        case .sessionList:
            return handleSessionList(request)
        case .sessionDelete:
            return handleSessionDelete(request)

        // V3: Tab extended
        case .tabDuplicate:
            return handleTabDuplicate(request)
        case .tabPin:
            return handleTabPin(request)

        // V3: Config extended
        case .configList:
            return handleConfigList(request)
        case .configReload:
            return handleConfigReload(request)

        // V3: Split extended
        case .splitSwap:
            return handleSplitSwap(request)
        case .splitZoom:
            return handleSplitZoom(request)

        // V3: Output capture
        case .capturePane:
            return handleCapturePane(request)

        // V3: Notification CLI
        case .notificationList:
            return handleNotificationList(request)
        case .notificationClear:
            return handleNotificationClear(request)

        // Acknowledged commands (v2 UI actions — need window controller wiring)
        case .split,
             .splitList, .splitFocus, .splitClose, .splitResize,
             .dashboardShow, .dashboardHide, .dashboardToggle, .dashboardStatus,
             .timelineShow, .timelineExport,
             .search,
             .send, .sendKey,
             .hooks, .hookHandler:
            return .ok(id: request.id, data: ["status": "acknowledged"])
        }
    }

    // MARK: - Notify Handler

    /// Dispatches a CLI notification through the notification pipeline.
    ///
    /// Reads `title` and `message` from the request params. Falls back to
    /// "Cocxy" for the title and returns an error when no message is provided.
    private func handleNotify(_ request: SocketRequest) -> SocketResponse {
        let title = request.params?["title"] ?? "Cocxy"
        guard let message = request.params?["message"], !message.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: message")
        }

        notifyDispatcher(title, message)
        return .ok(id: request.id, data: ["status": "notification sent"])
    }

    // MARK: - Status & Listing Handlers

    /// Returns the application status including version and tab count.
    private func handleStatus(_ request: SocketRequest) -> SocketResponse {
        let tabCount = tabCountProvider()
        return .ok(id: request.id, data: [
            "status": "running",
            "version": CocxyVersion.current,
            "tabs": "\(tabCount)"
        ])
    }

    /// Returns a list of all open tabs with their IDs, titles, and active state.
    private func handleListTabs(_ request: SocketRequest) -> SocketResponse {
        let tabs = tabInfoProvider()
        var tabsInfo: [String: String] = [:]
        for (index, tab) in tabs.enumerated() {
            tabsInfo["tab_\(index)_id"] = tab.id
            tabsInfo["tab_\(index)_title"] = tab.title
            tabsInfo["tab_\(index)_active"] = tab.isActive ? "true" : "false"
        }
        tabsInfo["count"] = "\(tabs.count)"
        return .ok(id: request.id, data: tabsInfo)
    }

    // MARK: - Tab Mutation Handlers

    /// Focuses a tab by its UUID.
    ///
    /// Required params: `id` (UUID string).
    private func handleFocusTab(_ request: SocketRequest) -> SocketResponse {
        guard let tabIDString = request.params?["id"] else {
            return .failure(id: request.id, error: "Missing required param: id")
        }
        guard UUID(uuidString: tabIDString) != nil else {
            return .failure(id: request.id, error: "Invalid UUID format for param: id")
        }

        let found = tabFocusProvider(tabIDString)
        if found {
            return .ok(id: request.id, data: ["status": "focused"])
        } else {
            return .failure(id: request.id, error: "Tab not found or tab manager not available")
        }
    }

    /// Closes a tab by its UUID.
    ///
    /// Required params: `id` (UUID string).
    /// The last remaining tab cannot be closed (TabManager invariant).
    private func handleCloseTab(_ request: SocketRequest) -> SocketResponse {
        guard let tabIDString = request.params?["id"] else {
            return .failure(id: request.id, error: "Missing required param: id")
        }
        guard UUID(uuidString: tabIDString) != nil else {
            return .failure(id: request.id, error: "Invalid UUID format for param: id")
        }

        let handled = tabCloseProvider(tabIDString)
        if handled {
            return .ok(id: request.id, data: ["status": "closed"])
        } else {
            return .failure(id: request.id, error: "Tab manager not available")
        }
    }

    /// Creates a new tab with an optional working directory.
    ///
    /// Optional params: `dir` (filesystem path for the working directory).
    private func handleNewTab(_ request: SocketRequest) -> SocketResponse {
        let directoryPath = request.params?["dir"]

        // Validate directory exists if provided.
        if let path = directoryPath {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else {
                return .failure(id: request.id, error: "Directory does not exist: \(path)")
            }
        }

        guard let result = tabCreateProvider(directoryPath) else {
            return .failure(id: request.id, error: "Tab manager not available")
        }

        return .ok(id: request.id, data: [
            "status": "created",
            "id": result.id,
            "title": result.title
        ])
    }

    /// Renames a tab by its UUID.
    ///
    /// Required params: `id` (UUID string), `name` (new custom title).
    private func handleTabRename(_ request: SocketRequest) -> SocketResponse {
        guard let tabIDString = request.params?["id"] else {
            return .failure(id: request.id, error: "Missing required param: id")
        }
        guard let newName = request.params?["name"] else {
            return .failure(id: request.id, error: "Missing required param: name")
        }
        guard UUID(uuidString: tabIDString) != nil else {
            return .failure(id: request.id, error: "Invalid UUID format for param: id")
        }

        let found = tabRenameProvider(tabIDString, newName)
        if found {
            return .ok(id: request.id, data: ["status": "renamed"])
        } else {
            return .failure(id: request.id, error: "Tab not found or tab manager not available")
        }
    }

    /// Moves a tab to a new position in the tab list.
    ///
    /// Required params: `id` (UUID string), `position` (0-based destination index).
    private func handleTabMove(_ request: SocketRequest) -> SocketResponse {
        guard let tabIDString = request.params?["id"] else {
            return .failure(id: request.id, error: "Missing required param: id")
        }
        guard let positionString = request.params?["position"] else {
            return .failure(id: request.id, error: "Missing required param: position")
        }
        guard let position = Int(positionString) else {
            return .failure(id: request.id, error: "Invalid integer for param: position")
        }
        guard UUID(uuidString: tabIDString) != nil else {
            return .failure(id: request.id, error: "Invalid UUID format for param: id")
        }

        let moved = tabMoveProvider(tabIDString, position)
        if moved {
            return .ok(id: request.id, data: ["status": "moved"])
        } else {
            return .failure(id: request.id, error: "Tab not found or invalid position")
        }
    }

    // MARK: - Config Handlers

    /// Returns the active tab's project config overrides, or a message if none.
    ///
    /// No parameters required -- operates on the active tab.
    private func handleConfigProject(_ request: SocketRequest) -> SocketResponse {
        if let configData = projectConfigProvider() {
            return .ok(id: request.id, data: configData)
        } else {
            return .ok(id: request.id, data: ["status": "No project config (.cocxy.toml) found for active tab"])
        }
    }

    /// Returns the path to the configuration file.
    private func handleConfigPath(_ request: SocketRequest) -> SocketResponse {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homePath)/.config/cocxy/config.toml"
        return .ok(id: request.id, data: ["path": configPath])
    }

    /// Reads a configuration value by its dotted key path.
    ///
    /// Required params: `key` (dotted path like "appearance.theme").
    /// Reads from the default ConfigService snapshot to avoid file I/O races.
    private func handleConfigGet(_ request: SocketRequest) -> SocketResponse {
        guard let key = request.params?["key"] else {
            return .failure(id: request.id, error: "Missing required param: key")
        }

        let config = configProvider?() ?? CocxyConfig.defaults
        guard let value = resolveConfigValue(key: key, config: config) else {
            return .failure(id: request.id, error: "Unknown config key: \(key)")
        }

        return .ok(id: request.id, data: [
            "key": key,
            "value": value
        ])
    }

    /// Writes a configuration value by its dotted key path.
    ///
    /// Required params: `key` (dotted path), `value` (new value as string).
    /// Reads the current config file, updates the matching line, and writes back.
    private func handleConfigSet(_ request: SocketRequest) -> SocketResponse {
        guard let key = request.params?["key"] else {
            return .failure(id: request.id, error: "Missing required param: key")
        }
        guard let value = request.params?["value"] else {
            return .failure(id: request.id, error: "Missing required param: value")
        }

        // Reject values containing characters that could corrupt TOML structure.
        guard !value.contains("\n") && !value.contains("\r") && !value.contains("\"") else {
            return .failure(id: request.id, error: "Value must not contain newlines or double quotes")
        }

        // Validate key against known config keys.
        guard resolveConfigValue(key: key, config: CocxyConfig.defaults) != nil else {
            return .failure(id: request.id, error: "Unknown config key: \(key)")
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homePath)/.config/cocxy/config.toml"

        let existingContent = (try? String(contentsOfFile: configPath, encoding: .utf8))
            ?? ConfigService.generateDefaultToml()

        let updatedContent = updateTomlValue(
            in: existingContent,
            section: sectionFromKey(key),
            field: fieldFromKey(key),
            newValue: value
        )

        do {
            try updatedContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            return .failure(
                id: request.id,
                error: "Failed to write config: \(error.localizedDescription)"
            )
        }

        return .ok(id: request.id, data: [
            "status": "updated",
            "key": key,
            "value": value
        ])
    }

    // MARK: - Theme Handlers

    /// Returns the list of all available themes (built-in + custom).
    private func handleThemeList(_ request: SocketRequest) -> SocketResponse {
        var themes: [ThemeMetadata] = []
        let work = {
            MainActor.assumeIsolated {
                themes = self.themeEngineProvider?()?.availableThemes ?? []
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        var data: [String: String] = ["count": "\(themes.count)"]
        for (index, theme) in themes.enumerated() {
            data["theme_\(index)"] = theme.name
        }
        return .ok(id: request.id, data: data)
    }

    /// Applies a theme by name.
    ///
    /// Required params: `name` (theme display name or config name).
    /// Supports fuzzy matching (e.g., "catppuccin-mocha" matches "Catppuccin Mocha").
    private func handleThemeSet(_ request: SocketRequest) -> SocketResponse {
        guard let themeName = request.params?["name"] else {
            return .failure(id: request.id, error: "Missing required param: name")
        }

        var applied = false
        let work = {
            MainActor.assumeIsolated {
                guard let engine = self.themeEngineProvider?() else { return }
                do {
                    try engine.apply(themeName: themeName)
                    applied = true
                } catch {
                    // applied remains false
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        if applied {
            return .ok(id: request.id, data: [
                "status": "applied",
                "theme": themeName
            ])
        } else {
            return .failure(id: request.id, error: "Theme not found: \(themeName)")
        }
    }

    // MARK: - Hook Event Handler

    /// Forwards a hook event payload to the HookEventReceiver.
    ///
    /// Required params: `payload` (JSON string of the hook event).
    private func handleHookEvent(_ request: SocketRequest) -> SocketResponse {
        guard let receiver = hookEventReceiver else {
            return .failure(id: request.id, error: "Hook event receiver not initialized")
        }

        guard let payload = request.params?["payload"],
              let payloadData = payload.data(using: .utf8) else {
            return .failure(id: request.id, error: "Missing or invalid hook event payload")
        }

        let accepted = receiver.receiveRawJSON(payloadData)
        if accepted {
            return .ok(id: request.id, data: ["status": "accepted"])
        } else {
            return .failure(id: request.id, error: "Failed to parse hook event")
        }
    }

    // MARK: - Config Key Resolution

    /// Resolves a dotted config key to its current string value.
    ///
    /// Supports keys like "appearance.theme", "general.shell", "terminal.scrollback-lines".
    /// Returns nil for unknown keys.
    private func resolveConfigValue(key: String, config: CocxyConfig) -> String? {
        switch key {
        // General
        case "general.shell":
            return config.general.shell
        case "general.working-directory":
            return config.general.workingDirectory
        case "general.confirm-close-process":
            return "\(config.general.confirmCloseProcess)"

        // Appearance
        case "appearance.theme":
            return config.appearance.theme
        case "appearance.font-family":
            return config.appearance.fontFamily
        case "appearance.font-size":
            return "\(config.appearance.fontSize)"
        case "appearance.tab-position":
            return config.appearance.tabPosition.rawValue
        case "appearance.window-padding":
            return "\(config.appearance.windowPadding)"
        case "appearance.background-opacity":
            return "\(config.appearance.backgroundOpacity)"
        case "appearance.background-blur-radius":
            return "\(config.appearance.backgroundBlurRadius)"

        // Terminal
        case "terminal.scrollback-lines":
            return "\(config.terminal.scrollbackLines)"
        case "terminal.cursor-style":
            return config.terminal.cursorStyle.rawValue
        case "terminal.cursor-blink":
            return "\(config.terminal.cursorBlink)"
        case "terminal.cursor-opacity":
            return "\(config.terminal.cursorOpacity)"
        case "terminal.mouse-hide-while-typing":
            return "\(config.terminal.mouseHideWhileTyping)"
        case "terminal.copy-on-select":
            return "\(config.terminal.copyOnSelect)"
        case "terminal.clipboard-paste-protection":
            return "\(config.terminal.clipboardPasteProtection)"

        // Agent detection
        case "agent-detection.enabled":
            return "\(config.agentDetection.enabled)"
        case "agent-detection.osc-notifications":
            return "\(config.agentDetection.oscNotifications)"
        case "agent-detection.pattern-matching":
            return "\(config.agentDetection.patternMatching)"
        case "agent-detection.timing-heuristics":
            return "\(config.agentDetection.timingHeuristics)"
        case "agent-detection.idle-timeout-seconds":
            return "\(config.agentDetection.idleTimeoutSeconds)"

        // Notifications
        case "notifications.macos-notifications":
            return "\(config.notifications.macosNotifications)"
        case "notifications.sound":
            return "\(config.notifications.sound)"
        case "notifications.badge-on-tab":
            return "\(config.notifications.badgeOnTab)"
        case "notifications.flash-tab":
            return "\(config.notifications.flashTab)"
        case "notifications.show-dock-badge":
            return "\(config.notifications.showDockBadge)"
        case "notifications.sound-finished":
            return config.notifications.soundFinished
        case "notifications.sound-attention":
            return config.notifications.soundAttention
        case "notifications.sound-error":
            return config.notifications.soundError

        // Quick terminal
        case "quick-terminal.enabled":
            return "\(config.quickTerminal.enabled)"
        case "quick-terminal.hotkey":
            return config.quickTerminal.hotkey
        case "quick-terminal.position":
            return config.quickTerminal.position.rawValue
        case "quick-terminal.height-percentage":
            return "\(config.quickTerminal.heightPercentage)"
        case "quick-terminal.hide-on-deactivate":
            return "\(config.quickTerminal.hideOnDeactivate)"
        case "quick-terminal.working-directory":
            return config.quickTerminal.workingDirectory
        case "quick-terminal.animation-duration":
            return "\(config.quickTerminal.animationDuration)"
        case "quick-terminal.screen":
            return config.quickTerminal.screen.rawValue

        // Keybindings
        case "keybindings.new-tab":
            return config.keybindings.newTab
        case "keybindings.close-tab":
            return config.keybindings.closeTab
        case "keybindings.next-tab":
            return config.keybindings.nextTab
        case "keybindings.prev-tab":
            return config.keybindings.prevTab
        case "keybindings.split-vertical":
            return config.keybindings.splitVertical
        case "keybindings.split-horizontal":
            return config.keybindings.splitHorizontal
        case "keybindings.goto-attention":
            return config.keybindings.gotoAttention
        case "keybindings.toggle-quick-terminal":
            return config.keybindings.toggleQuickTerminal

        // Sessions
        case "sessions.auto-save":
            return "\(config.sessions.autoSave)"
        case "sessions.auto-save-interval":
            return "\(config.sessions.autoSaveInterval)"
        case "sessions.restore-on-launch":
            return "\(config.sessions.restoreOnLaunch)"

        default:
            return nil
        }
    }

    // MARK: - Browser Handlers

    /// Maximum allowed JavaScript evaluation script size in characters.
    private static let maxBrowserEvalLength = 10_000

    /// Navigates the embedded browser to a URL.
    ///
    /// Required params: `url` (the URL string to navigate to).
    private func handleBrowserNavigate(_ request: SocketRequest) -> SocketResponse {
        guard let urlString = request.params?["url"] else {
            return .failure(id: request.id, error: "Missing required param: url")
        }
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let work = {
            MainActor.assumeIsolated {
                viewModel.navigate(to: urlString)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: ["status": "navigated"])
    }

    /// Navigates the browser backward in history.
    private func handleBrowserBack(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let work = {
            MainActor.assumeIsolated {
                viewModel.goBack()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: ["status": "acknowledged"])
    }

    /// Navigates the browser forward in history.
    private func handleBrowserForward(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let work = {
            MainActor.assumeIsolated {
                viewModel.goForward()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: ["status": "acknowledged"])
    }

    /// Reloads the current browser page.
    private func handleBrowserReload(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let work = {
            MainActor.assumeIsolated {
                viewModel.reload()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: ["status": "acknowledged"])
    }

    /// Returns the current browser state (URL, title, loading, tabs).
    private func handleBrowserGetState(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        var state: [String: String] = [:]
        let work = {
            MainActor.assumeIsolated {
                state = viewModel.getState()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: state)
    }

    /// Evaluates JavaScript in the active browser tab.
    ///
    /// Required params: `script` (the JavaScript code, max 10,000 characters).
    ///
    /// The script is evaluated asynchronously by WKWebView; this returns
    /// immediately after dispatching. Results are not returned via socket
    /// (use `browser-get-text` for page content extraction).
    private func handleBrowserEval(_ request: SocketRequest) -> SocketResponse {
        guard let script = request.params?["script"] else {
            return .failure(id: request.id, error: "Missing required param: script")
        }
        guard script.count <= Self.maxBrowserEvalLength else {
            return .failure(
                id: request.id,
                error: "Script length \(script.count) exceeds maximum \(Self.maxBrowserEvalLength) characters"
            )
        }
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let work = {
            MainActor.assumeIsolated {
                viewModel.evaluateJavaScript(script)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: ["status": "evaluated"])
    }

    /// Gets the text content of the current page via `document.body.innerText`.
    ///
    /// Internally calls `evaluateJavaScript` with a fixed script.
    /// The result is dispatched asynchronously.
    private func handleBrowserGetText(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let work = {
            MainActor.assumeIsolated {
                viewModel.evaluateJavaScript("document.body.innerText")
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: ["status": "evaluated"])
    }

    /// Lists all open browser tabs.
    private func handleBrowserListTabs(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        var tabList: [[String: String]] = []
        let work = {
            MainActor.assumeIsolated {
                tabList = viewModel.getTabList()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        var data: [String: String] = ["count": "\(tabList.count)"]
        for (index, tab) in tabList.enumerated() {
            data["tab_\(index)_id"] = tab["id"] ?? ""
            data["tab_\(index)_url"] = tab["url"] ?? ""
            data["tab_\(index)_title"] = tab["title"] ?? ""
            data["tab_\(index)_active"] = tab["isActive"] ?? "false"
        }
        return .ok(id: request.id, data: data)
    }

    // MARK: - Plugin Handlers

    /// Lists all installed plugins with their enabled/disabled state.
    private func handlePluginList(_ request: SocketRequest) -> SocketResponse {
        var pluginData: [(id: String, name: String, enabled: Bool)] = []
        let work = {
            MainActor.assumeIsolated {
                guard let manager = self.pluginManagerProvider?() else { return }
                manager.scanPlugins()
                pluginData = manager.plugins.map { ($0.id, $0.manifest.name, $0.isEnabled) }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        var data: [String: String] = ["count": "\(pluginData.count)"]
        for (index, plugin) in pluginData.enumerated() {
            data["plugin_\(index)_id"] = plugin.id
            data["plugin_\(index)_name"] = plugin.name
            data["plugin_\(index)_enabled"] = plugin.enabled ? "true" : "false"
        }
        return .ok(id: request.id, data: data)
    }

    /// Enables a plugin by ID.
    private func handlePluginEnable(_ request: SocketRequest) -> SocketResponse {
        guard let pluginID = request.params?["id"] else {
            return .failure(id: request.id, error: "Usage: plugin-enable {\"id\": \"<plugin-id>\"}")
        }

        var resultMessage = ""
        let work = {
            MainActor.assumeIsolated {
                guard let manager = self.pluginManagerProvider?() else {
                    resultMessage = "Plugin manager not initialized"
                    return
                }
                do {
                    try manager.enablePlugin(id: pluginID)
                    resultMessage = "enabled"
                } catch {
                    resultMessage = "Failed: \(error)"
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        if resultMessage == "enabled" {
            return .ok(id: request.id, data: ["plugin": pluginID, "status": "enabled"])
        }
        return .failure(id: request.id, error: resultMessage)
    }

    /// Disables a plugin by ID.
    private func handlePluginDisable(_ request: SocketRequest) -> SocketResponse {
        guard let pluginID = request.params?["id"] else {
            return .failure(id: request.id, error: "Usage: plugin-disable {\"id\": \"<plugin-id>\"}")
        }

        var resultMessage = ""
        let work = {
            MainActor.assumeIsolated {
                guard let manager = self.pluginManagerProvider?() else {
                    resultMessage = "Plugin manager not initialized"
                    return
                }
                do {
                    try manager.disablePlugin(id: pluginID)
                    resultMessage = "disabled"
                } catch {
                    resultMessage = "Failed: \(error)"
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        if resultMessage == "disabled" {
            return .ok(id: request.id, data: ["plugin": pluginID, "status": "disabled"])
        }
        return .failure(id: request.id, error: resultMessage)
    }

    // MARK: - Remote Workspace Handlers

    /// Lists all saved remote connection profiles and their connection state.
    private func handleRemoteList(_ request: SocketRequest) -> SocketResponse {
        guard let profileStore = remoteProfileStoreProvider?() else {
            return .ok(id: request.id, data: ["count": "0"])
        }

        let profiles: [RemoteConnectionProfile]
        do {
            profiles = try profileStore.loadAll()
        } catch {
            return .failure(id: request.id, error: "Failed to load profiles")
        }

        // Read connection states from MainActor context.
        var connectionStates: [UUID: RemoteConnectionManager.ConnectionState] = [:]
        let work = {
            MainActor.assumeIsolated {
                if let manager = self.remoteConnectionManagerProvider?() {
                    connectionStates = manager.connections
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        var data: [String: String] = ["count": "\(profiles.count)"]
        for (index, profile) in profiles.enumerated() {
            data["profile_\(index)_id"] = profile.id.uuidString
            data["profile_\(index)_name"] = profile.name
            data["profile_\(index)_host"] = profile.displayTitle
            data["profile_\(index)_state"] = connectionStateString(
                connectionStates[profile.id] ?? .disconnected
            )
        }
        return .ok(id: request.id, data: data)
    }

    /// Connects to a remote profile by name or UUID.
    private func handleRemoteConnect(_ request: SocketRequest) -> SocketResponse {
        guard let identifier = request.params?["name"] else {
            return .failure(id: request.id, error: "Usage: remote-connect {\"name\": \"<name-or-uuid>\"}")
        }

        guard let profileStore = remoteProfileStoreProvider?() else {
            return .failure(id: request.id, error: "Remote workspace not initialized")
        }

        let profile: RemoteConnectionProfile?
        if let uuid = UUID(uuidString: identifier) {
            profile = (try? profileStore.loadAll())?.first { $0.id == uuid }
        } else {
            profile = try? profileStore.findByName(identifier)
        }

        guard let resolvedProfile = profile else {
            return .failure(id: request.id, error: "Profile not found: \(identifier)")
        }

        Task { @MainActor in
            guard let manager = self.remoteConnectionManagerProvider?() else { return }
            await manager.connect(profile: resolvedProfile)
        }

        return .ok(id: request.id, data: [
            "status": "connecting",
            "profile": resolvedProfile.name,
            "host": resolvedProfile.displayTitle,
        ])
    }

    /// Disconnects from a remote profile.
    private func handleRemoteDisconnect(_ request: SocketRequest) -> SocketResponse {
        guard let identifier = request.params?["name"] else {
            return .failure(id: request.id, error: "Usage: remote-disconnect {\"name\": \"<name-or-uuid>\"}")
        }

        guard let profileStore = remoteProfileStoreProvider?() else {
            return .failure(id: request.id, error: "Remote workspace not initialized")
        }

        let profile: RemoteConnectionProfile?
        if let uuid = UUID(uuidString: identifier) {
            profile = (try? profileStore.loadAll())?.first { $0.id == uuid }
        } else {
            profile = try? profileStore.findByName(identifier)
        }

        guard let resolvedProfile = profile else {
            return .failure(id: request.id, error: "Profile not found: \(identifier)")
        }

        Task { @MainActor in
            guard let manager = self.remoteConnectionManagerProvider?() else { return }
            await manager.disconnect(profileID: resolvedProfile.id)
        }

        return .ok(id: request.id, data: [
            "status": "disconnecting",
            "profile": resolvedProfile.name,
        ])
    }

    /// Returns connection status for all profiles or a specific one.
    private func handleRemoteStatus(_ request: SocketRequest) -> SocketResponse {
        var connectionStates: [UUID: RemoteConnectionManager.ConnectionState] = [:]
        var supportMap: [UUID: RemoteShellSupport] = [:]
        let work = {
            MainActor.assumeIsolated {
                if let manager = self.remoteConnectionManagerProvider?() {
                    connectionStates = manager.connections
                    supportMap = manager.remoteSupport
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        // If a specific profile is requested.
        if let identifier = request.params?["name"] {
            guard let profileStore = remoteProfileStoreProvider?() else {
                return .failure(id: request.id, error: "Remote workspace not initialized")
            }

            let profile: RemoteConnectionProfile?
            if let uuid = UUID(uuidString: identifier) {
                profile = (try? profileStore.loadAll())?.first { $0.id == uuid }
            } else {
                profile = try? profileStore.findByName(identifier)
            }

            guard let resolvedProfile = profile else {
                return .failure(id: request.id, error: "Profile not found: \(identifier)")
            }

            var data: [String: String] = [
                "name": resolvedProfile.name,
                "host": resolvedProfile.displayTitle,
                "state": connectionStateString(
                    connectionStates[resolvedProfile.id] ?? .disconnected
                ),
            ]

            if let support = supportMap[resolvedProfile.id] {
                data["remote_support"] = remoteShellSupportString(support)
            }

            return .ok(id: request.id, data: data)
        }

        // Return all connections.
        var data: [String: String] = ["count": "\(connectionStates.count)"]
        var index = 0
        for (profileID, state) in connectionStates {
            data["connection_\(index)_id"] = profileID.uuidString
            data["connection_\(index)_state"] = connectionStateString(state)
            index += 1
        }
        return .ok(id: request.id, data: data)
    }

    /// Lists active remote sessions across all connected profiles.
    private func handleRemoteTunnels(_ request: SocketRequest) -> SocketResponse {
        var tunnelData: [[String: String]] = []
        let work = {
            MainActor.assumeIsolated {
                guard let manager = self.remoteConnectionManagerProvider?() else { return }
                for (profileID, state) in manager.connections {
                    if case .connected = state {
                        let sessions = manager.savedSessionRecords(profileID: profileID)
                        for session in sessions {
                            tunnelData.append([
                                "profile_id": profileID.uuidString,
                                "session_name": session.sessionName,
                                "profile_title": session.profileDisplayTitle,
                            ])
                        }
                    }
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        var data: [String: String] = ["count": "\(tunnelData.count)"]
        for (index, tunnel) in tunnelData.enumerated() {
            for (key, value) in tunnel {
                data["tunnel_\(index)_\(key)"] = value
            }
        }
        return .ok(id: request.id, data: data)
    }

    // MARK: - Remote Helpers

    /// Converts a `ConnectionState` to a human-readable string.
    private func connectionStateString(
        _ state: RemoteConnectionManager.ConnectionState
    ) -> String {
        switch state {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected(let latencyMs):
            if let ms = latencyMs { return "connected (\(ms)ms)" }
            return "connected"
        case .reconnecting(let attempt): return "reconnecting (attempt \(attempt))"
        case .failed(let message): return "failed: \(message)"
        }
    }

    /// Converts a `RemoteShellSupport` to a human-readable string.
    private func remoteShellSupportString(_ support: RemoteShellSupport) -> String {
        switch support {
        case .tmux(let version): return "tmux (\(version))"
        case .screen: return "screen"
        case .none: return "none"
        }
    }

    // MARK: - V3 Window Management Handlers

    /// Creates a new tab (single-window architecture).
    ///
    /// Optional params: `dir` (working directory path).
    private func handleWindowNew(_ request: SocketRequest) -> SocketResponse {
        let directoryPath = request.params?["dir"]

        if let path = directoryPath {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else {
                return .failure(id: request.id, error: "Directory does not exist: \(path)")
            }
        }

        guard let result = tabCreateProvider(directoryPath) else {
            return .failure(id: request.id, error: "Tab manager not available")
        }

        return .ok(id: request.id, data: [
            "status": "created",
            "id": result.id,
            "title": result.title
        ])
    }

    /// Lists all visible application windows.
    private func handleWindowList(_ request: SocketRequest) -> SocketResponse {
        var windowData: [[String: String]] = []
        let work = {
            MainActor.assumeIsolated {
                for (index, window) in NSApplication.shared.windows.enumerated()
                    where window.isVisible {
                    let frame = window.frame
                    windowData.append([
                        "index": "\(index)",
                        "title": window.title,
                        "is_key": window.isKeyWindow ? "true" : "false",
                        "is_main": window.isMainWindow ? "true" : "false",
                        "is_fullscreen": window.styleMask.contains(.fullScreen)
                            ? "true" : "false",
                        "frame": "\(Int(frame.origin.x)),\(Int(frame.origin.y)),"
                            + "\(Int(frame.size.width)),\(Int(frame.size.height))"
                    ])
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        var data: [String: String] = ["count": "\(windowData.count)"]
        for (index, win) in windowData.enumerated() {
            for (key, value) in win {
                data["window_\(index)_\(key)"] = value
            }
        }
        return .ok(id: request.id, data: data)
    }

    /// Focuses a window by index or brings the main window to front.
    ///
    /// Optional params: `index` (0-based window index).
    private func handleWindowFocus(_ request: SocketRequest) -> SocketResponse {
        let indexString = request.params?["index"]
        var focused = false
        let work = {
            MainActor.assumeIsolated {
                let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible }
                if let indexStr = indexString, let index = Int(indexStr) {
                    guard index >= 0, index < visibleWindows.count else { return }
                    visibleWindows[index].makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    focused = true
                } else {
                    let target = visibleWindows.first(where: { $0.isMainWindow })
                        ?? visibleWindows.first
                    target?.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    focused = target != nil
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        if focused {
            return .ok(id: request.id, data: ["status": "focused"])
        }
        return .failure(id: request.id, error: "No visible window found")
    }

    /// Closes a window by index. Cannot close the last visible window.
    ///
    /// Required params: `index` (0-based window index).
    private func handleWindowClose(_ request: SocketRequest) -> SocketResponse {
        guard let indexStr = request.params?["index"],
              let index = Int(indexStr) else {
            return .failure(id: request.id, error: "Missing or invalid param: index")
        }

        var closed = false
        var errorMessage = ""
        let work = {
            MainActor.assumeIsolated {
                let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible }
                guard index >= 0, index < visibleWindows.count else {
                    errorMessage = "Window index out of range (0..<\(visibleWindows.count))"
                    return
                }
                guard visibleWindows.count > 1 else {
                    errorMessage = "Cannot close the last window"
                    return
                }
                visibleWindows[index].close()
                closed = true
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        if closed {
            return .ok(id: request.id, data: ["status": "closed"])
        }
        return .failure(id: request.id, error: errorMessage)
    }

    /// Toggles fullscreen on the key window.
    private func handleWindowFullscreen(_ request: SocketRequest) -> SocketResponse {
        var toggled = false
        var isFullScreen = false
        let work = {
            MainActor.assumeIsolated {
                guard let window = NSApplication.shared.keyWindow
                    ?? NSApplication.shared.mainWindow else { return }
                window.toggleFullScreen(nil)
                isFullScreen = window.styleMask.contains(.fullScreen)
                toggled = true
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        if toggled {
            return .ok(id: request.id, data: [
                "status": "toggled",
                "fullscreen": isFullScreen ? "true" : "false"
            ])
        }
        return .failure(id: request.id, error: "No window available")
    }

    // MARK: - V3 Session Management Handlers

    /// Saves the current session with an optional name.
    ///
    /// Optional params: `name` (session name; nil saves as "last").
    private func handleSessionSave(_ request: SocketRequest) -> SocketResponse {
        let name = request.params?["name"]

        guard let session = sessionCaptureProvider?() else {
            return .failure(id: request.id, error: "Session capture not available")
        }

        guard let sessionManager = sessionManagerProvider?() else {
            return .failure(id: request.id, error: "Session manager not available")
        }

        do {
            try sessionManager.saveSession(session, named: name)
            return .ok(id: request.id, data: [
                "status": "saved",
                "name": name ?? "last",
                "tabs": "\(session.windows.first?.tabs.count ?? 0)"
            ])
        } catch {
            return .failure(id: request.id, error: "Failed to save: \(error)")
        }
    }

    /// Restores a session by name or the last auto-saved session.
    ///
    /// Optional params: `name` (session name; nil restores last).
    private func handleSessionRestore(_ request: SocketRequest) -> SocketResponse {
        let name = request.params?["name"]

        // Try the full restore provider first (recreates tabs from session).
        if let restorer = sessionRestoreProvider {
            let restored = restorer(name)
            if restored {
                return .ok(id: request.id, data: [
                    "status": "restored",
                    "name": name ?? "last"
                ])
            }
            return .failure(id: request.id, error: "Failed to restore session: \(name ?? "last")")
        }

        // Fallback: load and return session data without UI restoration.
        guard let sessionManager = sessionManagerProvider?() else {
            return .failure(id: request.id, error: "Session manager not available")
        }

        let session: Session?
        do {
            if let name = name {
                session = try sessionManager.loadSession(named: name)
            } else {
                session = try sessionManager.loadLastSession()
            }
        } catch {
            return .failure(id: request.id, error: "Failed to load: \(error)")
        }

        guard let session = session,
              let windowState = session.windows.first else {
            return .failure(id: request.id, error: "Session not found: \(name ?? "last")")
        }

        let formatter = ISO8601DateFormatter()
        var data: [String: String] = [
            "status": "loaded",
            "name": name ?? "last",
            "tabs": "\(windowState.tabs.count)",
            "saved_at": formatter.string(from: session.savedAt)
        ]
        for (index, tab) in windowState.tabs.enumerated() {
            data["tab_\(index)_dir"] = tab.workingDirectory.path
            if let title = tab.title { data["tab_\(index)_title"] = title }
        }
        return .ok(id: request.id, data: data)
    }

    /// Lists all saved sessions with metadata.
    private func handleSessionList(_ request: SocketRequest) -> SocketResponse {
        guard let sessionManager = sessionManagerProvider?() else {
            return .failure(id: request.id, error: "Session manager not available")
        }

        let sessions = sessionManager.listSessions()
        let formatter = ISO8601DateFormatter()

        var data: [String: String] = ["count": "\(sessions.count)"]
        for (index, meta) in sessions.enumerated() {
            data["session_\(index)_name"] = meta.name
            data["session_\(index)_date"] = formatter.string(from: meta.savedAt)
            data["session_\(index)_windows"] = "\(meta.windowCount)"
            data["session_\(index)_tabs"] = "\(meta.tabCount)"
        }
        return .ok(id: request.id, data: data)
    }

    /// Deletes a saved session by name.
    ///
    /// Required params: `name`.
    private func handleSessionDelete(_ request: SocketRequest) -> SocketResponse {
        guard let name = request.params?["name"] else {
            return .failure(id: request.id, error: "Missing required param: name")
        }

        guard let sessionManager = sessionManagerProvider?() else {
            return .failure(id: request.id, error: "Session manager not available")
        }

        do {
            try sessionManager.deleteSession(named: name)
            return .ok(id: request.id, data: ["status": "deleted", "name": name])
        } catch {
            return .failure(id: request.id, error: "Failed to delete: \(error)")
        }
    }

    // MARK: - V3 Tab Extended Handlers

    /// Duplicates the active tab (new tab with same working directory).
    private func handleTabDuplicate(_ request: SocketRequest) -> SocketResponse {
        guard let provider = tabDuplicateProvider else {
            return .failure(id: request.id, error: "Tab duplicate not available")
        }

        guard let result = provider() else {
            return .failure(id: request.id, error: "No active tab to duplicate")
        }

        return .ok(id: request.id, data: [
            "status": "duplicated",
            "id": result.id,
            "title": result.title
        ])
    }

    /// Toggles pin on a tab.
    ///
    /// Optional params: `id` (tab UUID; nil = active tab).
    private func handleTabPin(_ request: SocketRequest) -> SocketResponse {
        guard let provider = tabPinProvider else {
            return .failure(id: request.id, error: "Tab pin not available")
        }

        let tabID = request.params?["id"]
        guard let result = provider(tabID) else {
            return .failure(id: request.id, error: "Tab not found or tab manager not available")
        }

        return .ok(id: request.id, data: [
            "status": result.isPinned ? "pinned" : "unpinned",
            "id": result.id
        ])
    }

    // MARK: - V3 Config Extended Handlers

    /// Lists all configuration keys and their current values.
    private func handleConfigList(_ request: SocketRequest) -> SocketResponse {
        let config = configProvider?() ?? CocxyConfig.defaults

        let keys = allConfigKeys
        var data: [String: String] = ["count": "\(keys.count)"]
        for key in keys {
            if let value = resolveConfigValue(key: key, config: config) {
                data[key] = value
            }
        }
        return .ok(id: request.id, data: data)
    }

    /// Reloads the configuration from disk.
    private func handleConfigReload(_ request: SocketRequest) -> SocketResponse {
        guard let reloader = configReloadProvider else {
            return .failure(id: request.id, error: "Config service not available")
        }

        let success = reloader()
        if success {
            return .ok(id: request.id, data: ["status": "reloaded"])
        }
        return .failure(id: request.id, error: "Failed to reload configuration")
    }

    // MARK: - V3 Split Extended Handlers

    /// Swaps two panes by their DFS indices.
    ///
    /// Required params: `indexA`, `indexB` (0-based pane indices).
    private func handleSplitSwap(_ request: SocketRequest) -> SocketResponse {
        guard let indexAStr = request.params?["indexA"],
              let indexBStr = request.params?["indexB"],
              let indexA = Int(indexAStr),
              let indexB = Int(indexBStr) else {
            return .failure(
                id: request.id,
                error: "Missing or invalid params: indexA, indexB (0-based pane indices)"
            )
        }

        guard let provider = splitSwapProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }

        let swapped = provider(indexA, indexB)
        if swapped {
            return .ok(id: request.id, data: [
                "status": "swapped",
                "indexA": "\(indexA)",
                "indexB": "\(indexB)"
            ])
        }
        return .failure(id: request.id, error: "Invalid pane indices or no splits active")
    }

    /// Toggles zoom on the focused pane.
    private func handleSplitZoom(_ request: SocketRequest) -> SocketResponse {
        guard let provider = splitZoomProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }

        let result = provider()
        if result.success {
            return .ok(id: request.id, data: [
                "status": result.isZoomed ? "zoomed" : "unzoomed"
            ])
        }
        return .failure(id: request.id, error: "No splits to zoom (single pane)")
    }

    // MARK: - V3 Output Capture Handler

    /// Captures the active pane's visible terminal content as text.
    ///
    /// Optional params: `lines` (max lines to return, default 500, max 10000).
    private func handleCapturePane(_ request: SocketRequest) -> SocketResponse {
        guard let provider = capturePaneProvider else {
            return .failure(id: request.id, error: "Terminal output buffer not available")
        }

        let maxLines: Int
        if let limitStr = request.params?["lines"], let limit = Int(limitStr) {
            maxLines = min(max(limit, 1), 10_000)
        } else {
            maxLines = 500
        }

        let allLines = provider()
        let lines = Array(allLines.suffix(maxLines))
        let content = lines.joined(separator: "\n")

        return .ok(id: request.id, data: [
            "status": "captured",
            "lines": "\(lines.count)",
            "content": content
        ])
    }

    // MARK: - V3 Notification CLI Handlers

    /// Lists recent notifications as structured data.
    private func handleNotificationList(_ request: SocketRequest) -> SocketResponse {
        guard let managerProvider = notificationManagerProvider else {
            return .failure(id: request.id, error: "Notification manager not available")
        }

        var notifications: [CocxyNotification] = []
        let work = {
            MainActor.assumeIsolated {
                guard let manager = managerProvider() else { return }
                notifications = manager.allNotifications()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        let formatter = ISO8601DateFormatter()
        var data: [String: String] = ["count": "\(notifications.count)"]
        for (index, notif) in notifications.enumerated() {
            data["notif_\(index)_id"] = notif.id.uuidString
            data["notif_\(index)_type"] = notificationTypeString(notif.type)
            data["notif_\(index)_title"] = notif.title
            data["notif_\(index)_body"] = notif.body
            data["notif_\(index)_timestamp"] = formatter.string(from: notif.timestamp)
            data["notif_\(index)_read"] = notif.isRead ? "true" : "false"
        }
        return .ok(id: request.id, data: data)
    }

    /// Clears the notification badge and marks all notifications as read.
    private func handleNotificationClear(_ request: SocketRequest) -> SocketResponse {
        guard let managerProvider = notificationManagerProvider else {
            return .failure(id: request.id, error: "Notification manager not available")
        }

        var remaining = 0
        let work = {
            MainActor.assumeIsolated {
                guard let manager = managerProvider() else { return }
                manager.markAllAsRead()
                remaining = manager.unreadCount
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync { work() } }

        return .ok(id: request.id, data: [
            "status": "cleared",
            "unread": "\(remaining)"
        ])
    }

    // MARK: - V3 Helpers

    /// All known configuration key paths for config-list enumeration.
    private var allConfigKeys: [String] {
        [
            "general.shell", "general.working-directory",
            "general.confirm-close-process",
            "appearance.theme", "appearance.font-family", "appearance.font-size",
            "appearance.tab-position", "appearance.window-padding",
            "appearance.background-opacity", "appearance.background-blur-radius",
            "terminal.scrollback-lines", "terminal.cursor-style",
            "terminal.cursor-blink", "terminal.cursor-opacity",
            "terminal.mouse-hide-while-typing", "terminal.copy-on-select",
            "terminal.clipboard-paste-protection",
            "agent-detection.enabled", "agent-detection.osc-notifications",
            "agent-detection.pattern-matching", "agent-detection.timing-heuristics",
            "agent-detection.idle-timeout-seconds",
            "notifications.macos-notifications", "notifications.sound",
            "notifications.badge-on-tab", "notifications.flash-tab",
            "notifications.show-dock-badge", "notifications.sound-finished",
            "notifications.sound-attention", "notifications.sound-error",
            "quick-terminal.enabled", "quick-terminal.hotkey",
            "quick-terminal.position", "quick-terminal.height-percentage",
            "quick-terminal.hide-on-deactivate", "quick-terminal.working-directory",
            "quick-terminal.animation-duration", "quick-terminal.screen",
            "keybindings.new-tab", "keybindings.close-tab",
            "keybindings.next-tab", "keybindings.prev-tab",
            "keybindings.split-vertical", "keybindings.split-horizontal",
            "keybindings.goto-attention", "keybindings.toggle-quick-terminal",
            "sessions.auto-save", "sessions.auto-save-interval",
            "sessions.restore-on-launch"
        ]
    }

    /// Converts a `NotificationType` to a CLI-friendly string.
    private func notificationTypeString(_ type: NotificationType) -> String {
        switch type {
        case .agentNeedsAttention: return "agent_needs_attention"
        case .agentError: return "agent_error"
        case .agentFinished: return "agent_finished"
        case .processExited(let code): return "process_exited_\(code)"
        case .custom(let name): return "custom_\(name)"
        }
    }

    // MARK: - TOML Helpers

    /// Extracts the TOML section name from a dotted key.
    private func sectionFromKey(_ key: String) -> String {
        let components = key.split(separator: ".", maxSplits: 1)
        return components.first.map(String.init) ?? ""
    }

    /// Extracts the TOML field name from a dotted key.
    private func fieldFromKey(_ key: String) -> String {
        let components = key.split(separator: ".", maxSplits: 1)
        return components.count > 1 ? String(components[1]) : ""
    }

    /// Updates a single value in a TOML string.
    ///
    /// Finds the line matching `field = ...` within the `[section]` block
    /// and replaces its value. Returns the original content if the field
    /// is not found (append is not attempted to avoid malformed TOML).
    private func updateTomlValue(
        in content: String,
        section: String,
        field: String,
        newValue: String
    ) -> String {
        var lines = content.components(separatedBy: "\n")
        var inTargetSection = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            // Detect section headers.
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionName = trimmed
                    .dropFirst()
                    .dropLast()
                    .trimmingCharacters(in: .whitespaces)
                inTargetSection = (sectionName == section)
                continue
            }

            // Update the matching field in the target section.
            if inTargetSection && trimmed.hasPrefix("\(field) =") {
                let quotedValue: String
                if newValue == "true" || newValue == "false" || Int(newValue) != nil
                    || Double(newValue) != nil {
                    quotedValue = newValue
                } else {
                    quotedValue = "\"\(newValue)\""
                }
                lines[index] = "\(field) = \(quotedValue)"
                break
            }
        }

        return lines.joined(separator: "\n")
    }
}
