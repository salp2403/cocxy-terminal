// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler.swift - Production socket command dispatcher.

import AppKit
import CocxyShared
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

enum AppSocketConfigTOMLUpdater {
    static func updateTomlValue(
        in content: String,
        section: String,
        field: String,
        newValue: String
    ) -> String {
        updateTomlValue(
            in: content,
            section: section,
            field: field,
            renderedValue: renderedScalarValue(newValue)
        )
    }

    static func updateTomlValue(
        in content: String,
        section: String,
        field: String,
        renderedValue: String
    ) -> String {
        let rendered = "\(field) = \(renderedValue)"
        var lines = content.components(separatedBy: "\n")
        var inTargetSection = false
        var sawTargetSection = false
        var insertIndex: Int?

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inTargetSection && insertIndex == nil {
                    insertIndex = index
                }

                let sectionName = trimmed
                    .dropFirst()
                    .dropLast()
                    .trimmingCharacters(in: .whitespaces)
                inTargetSection = (sectionName == section)
                if inTargetSection {
                    sawTargetSection = true
                    insertIndex = index + 1
                }
                continue
            }

            if inTargetSection {
                let matchesField = trimmed.hasPrefix("\(field) =")
                    || trimmed.hasPrefix("\(field)=")
                if matchesField {
                    lines[index] = rendered
                    return lines.joined(separator: "\n")
                }
                insertIndex = index + 1
            }
        }

        if sawTargetSection {
            lines.insert(rendered, at: insertIndex ?? lines.count)
            return lines.joined(separator: "\n")
        }

        if lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append("[\(section)]")
        lines.append(rendered)
        return lines.joined(separator: "\n")
    }

    static func renderedScalarValue(_ value: String) -> String {
        if value == "true" || value == "false" || Int(value) != nil || Double(value) != nil {
            return value
        }
        return "\"\(escapedStringValue(value))\""
    }

    static func renderedStringArrayValue(_ values: [String]) -> String {
        "[\(values.map { "\"\(escapedStringValue($0))\"" }.joined(separator: ", "))]"
    }

    private static func escapedStringValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum TabCloseOutcome: Sendable {
    case closed
    case lastTabBlocked
    case pinnedBlocked
    case notFound
    case unavailable
}

struct TimelineQueryResult: Sendable {
    let tabID: String?
    let sessionIDs: [String]
    let events: [TimelineEvent]
}

struct SearchCommandResult: Sendable {
    let tabID: String?
    let lineCount: Int
    let results: [SearchResult]
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

    /// Closure that closes a tab by UUID string and reports the exact outcome.
    private let tabCloseProvider: @Sendable (String) -> TabCloseOutcome

    /// Closure that creates a new tab with an optional working directory.
    /// Returns the new tab's (id, title) or nil if TabManager is unavailable.
    private let tabCreateProvider: @Sendable (String?) -> (id: String, title: String)?

    /// Closure that creates a tab with an optional per-tab engine preference.
    /// Existing callers use `tabCreateProvider`; CLI `new-tab --engine ...`
    /// goes through this path so daemon dogfood can be scoped to one tab.
    private let tabCreateWithEngineProvider: @Sendable (String?, String?) -> (id: String, title: String)?

    /// Closure that renames a tab. Params: (tabID, newName). Returns true on success.
    private let tabRenameProvider: @Sendable (String, String) -> Bool

    /// Closure that moves a tab. Params: (tabID, destinationIndex). Returns true on success.
    private let tabMoveProvider: @Sendable (String, Int) -> Bool

    /// Saves the focused tab as a reusable local TOML config.
    private let tabConfigSaveProvider: (@Sendable (
        _ name: String,
        _ command: String?,
        _ theme: String?,
        _ environment: [String: String]
    ) -> (name: String, path: String)?)?

    /// Opens a new tab from a reusable local TOML config.
    private let tabConfigOpenProvider: (@Sendable (_ name: String) -> (id: String, title: String, path: String)?)?

    /// Lists saved reusable tab config names.
    private let tabConfigListProvider: (@Sendable () -> [String]?)?

    /// Returns the TOML path for a saved reusable tab config.
    private let tabConfigPathProvider: (@Sendable (_ name: String) -> String?)?

    /// Exports a saved reusable tab config to a user-selected destination.
    private let tabConfigExportProvider: (@Sendable (
        _ name: String,
        _ output: String,
        _ overwrite: Bool
    ) -> (name: String, path: String)?)?

    /// Closure that reads the active tab's project config. Returns a dict of overrides or nil.
    private let projectConfigProvider: @Sendable () -> [String: String]?

    /// The hook event receiver for processing Claude Code hook events.
    private let hookEventReceiver: HookEventReceiverImpl?

    /// Closure that provides the browser view model for scriptable browser commands.
    /// Returns nil when no browser panel is open.
    private let browserViewModelProvider: @Sendable () -> BrowserViewModel?
    /// Closure that provides or opens a browser view model for external navigation.
    /// Unlike the read-only provider above, this may create UI for `browser navigate`.
    private let browserNavigationViewModelProvider: @Sendable () -> BrowserViewModel?
    /// Routes browser import preview/run requests to the app-owned importer.
    private let browserImportProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))?

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

    /// Provides the decentralized plugin source store for marketplace commands.
    private let pluginSourceStoreProvider: () -> PluginSourceStore

    /// Provides the installer for plugin install/uninstall commands.
    private let pluginInstallerProvider: () -> PluginInstaller

    /// Provides persistent plugin sandbox capability grants.
    private let pluginCapabilityGrantStoreProvider: () -> PluginCapabilityGrantStore

    /// Provides the local skill registry for `cocxy skill list`.
    private let skillRegistryProvider: (@Sendable () -> SkillRegistry)?

    /// Provides the decentralized skill source store for marketplace commands.
    private let skillSourceStoreProvider: () -> SkillSourceStore

    /// Provides the installer for skill install/uninstall commands.
    private let skillInstallerProvider: () -> SkillMarketplaceInstaller

    /// Dispatches a CLI notification through the notification pipeline.
    /// Called from `handleNotify(_:)` to deliver real notifications instead
    /// of silently returning "acknowledged".
    private let notifyDispatcher: @Sendable (String, String) -> Void

    /// Provides extra status fields derived from the active CocxyCore surface.
    private let statusDetailsProvider: (@Sendable () -> [String: String])?

    // MARK: - V3 Command Providers

    /// Duplicates the active tab (creates new tab with same working directory).
    private let tabDuplicateProvider: (@Sendable () -> (id: String, title: String)?)?

    /// Toggles pin on a tab. Nil tabID = active tab. Returns (id, isPinned).
    private let tabPinProvider: (@Sendable (String?) -> (id: String, isPinned: Bool)?)?

    /// Reloads the configuration from disk. Returns true on success.
    private let configReloadProvider: (@Sendable () -> Bool)?

    /// Returns split pane info for the active tab.
    let splitInfoProvider: (@Sendable () -> [(leafID: String, terminalID: String, isFocused: Bool)])?

    /// Swaps two panes by DFS index in the active tab. Returns true on success.
    private let splitSwapProvider: (@Sendable (Int, Int) -> Bool)?

    /// Swaps the focused pane with an adjacent pane in a direction.
    private let splitSwapByDirectionProvider: (@Sendable (String) -> Bool)?

    /// Toggles zoom on the focused pane. Returns (success, isZoomed).
    private let splitZoomProvider: (@Sendable () -> (success: Bool, isZoomed: Bool))?

    /// Provides the session manager for session CRUD operations.
    private let sessionManagerProvider: (@Sendable () -> (any SessionManaging)?)?

    /// Captures the current application state as a Session snapshot.
    private let sessionCaptureProvider: (@Sendable () -> Session?)?

    /// Restores a session by name (nil = last). Returns true on success.
    private let sessionRestoreProvider: (@Sendable (String?) -> Bool)?

    /// Provides the notification manager for list/clear operations.
    private let notificationManagerProvider: (() -> NotificationManagerImpl?)?

    /// Returns the active pane's terminal output buffer content.
    private let capturePaneProvider: (@Sendable () -> [String])?

    // MARK: - V4 Command Providers (replacing acknowledged stubs)

    /// Toggles the dashboard panel. Returns true if visible after toggle.
    let dashboardToggleProvider: (@Sendable () -> Bool)?

    /// Returns dashboard status: isVisible, sessionCount, activeCount.
    let dashboardStatusProvider: (@Sendable () -> [String: String])?

    /// Toggles the code review panel and returns whether it is visible afterwards.
    let reviewToggleProvider: (@Sendable () -> Bool)?

    /// Refreshes the code review state and returns a lightweight snapshot.
    let reviewRefreshProvider: (@Sendable () -> [String: String]?)?

    /// Submits pending code review comments and returns submission metadata.
    let reviewSubmitProvider: (@Sendable () -> [String: String]?)?

    /// Returns current code review statistics.
    let reviewStatsProvider: (@Sendable () -> [String: String]?)?

    /// Queries timeline data, optionally scoped to a specific tab.
    let timelineQueryProvider: (@Sendable (String?) -> TimelineQueryResult?)?

    /// Exports timeline in the given format ("json" or "markdown"), optionally scoped to a tab.
    let timelineExportProvider: (@Sendable (String?, String) -> Data?)?

    /// Opens Rich Input for a tab ID. Returns false when the tab or composer is unavailable.
    let richInputShowProvider: (@Sendable (String) -> Bool)?

    /// Creates a split pane. Bool param = isVertical. Returns true on success.
    let splitCreateProvider: (@Sendable (Bool) -> Bool)?

    /// Focuses a split pane by DFS index. Returns true if found.
    let splitFocusProvider: (@Sendable (Int) -> Bool)?

    /// Focuses the adjacent split pane in a navigation direction.
    let splitFocusByDirectionProvider: (@Sendable (String) -> Bool)?

    /// Closes the focused split pane. Returns true on success.
    let splitCloseProvider: (@Sendable () -> Bool)?

    /// Resizes a split by setting ratio (0.1-0.9) on split ID. Returns true.
    let splitResizeProvider: (@Sendable (String, CGFloat) -> Bool)?

    /// Resizes the focused pane in a direction by pixel delta.
    let splitResizeByDirectionProvider: (@Sendable (String, CGFloat) -> Bool)?

    /// Toggles the search bar.
    let searchToggleProvider: (@Sendable () -> Void)?

    /// Searches the scrollback buffer and returns structured results.
    let searchProvider: (@Sendable (String, Bool, Bool, String?) -> SearchCommandResult?)?

    /// Sends text directly to the active terminal PTY.
    let sendTextProvider: (@Sendable (String) -> Bool)?

    /// Sends a named key event to the active terminal.
    let sendKeyProvider: (@Sendable (String) -> Bool)?

    /// Opens an SSH session in a new tab. Params: (destination, port?, identityFile?).
    let sshProvider: (@Sendable (String, Int?, String?) -> (id: String, title: String)?)?

    /// Handles every `cocxy worktree-*` CLI verb. The closure receives
    /// the verb kind ("add" / "list" / "remove" / "prune") plus a flat
    /// params dictionary the handler extracted from the socket
    /// request, and returns a boolean success flag along with a data
    /// dictionary. When `success == false`, the `data["error"]` value
    /// is surfaced as the socket-level error message.
    ///
    /// Synchronous by contract so the handler method can remain
    /// synchronous; the AppDelegate-side implementation bridges the
    /// async `WorktreeService` via a `DispatchSemaphore`, which is
    /// acceptable because the handler already runs on a background
    /// socket queue.
    let worktreeCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))?

    /// Routes `cocxy github-*` verbs through the AppDelegate-side
    /// bridge. Same sync `kind` + `params` shape as the worktree
    /// provider so both CLI surfaces share one mental model.
    let githubCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))?

    /// Routes `cocxy git-assistant-*` verbs through the AppDelegate-side
    /// bridge so generation can use app config, Keychain-backed provider
    /// secrets, and the active tab's repository.
    let gitAssistantCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))?

    /// Routes local agent-team CLI verbs through AppDelegate so the handler
    /// can create panes on the focused window without owning UI state.
    let agentTeamCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))?

    /// Starts a web terminal on the focused surface and returns status fields.
    let webStartProvider: (@Sendable (String, UInt16, String, UInt16, UInt32) -> [String: String]?)?

    /// Stops the focused surface's web terminal.
    let webStopProvider: (@Sendable () -> Bool)?

    /// Returns web-terminal status for the focused surface.
    let webStatusProvider: (@Sendable () -> [String: String]?)?

    /// Returns CocxyCore process streams for the focused surface.
    let streamListProvider: (@Sendable () -> [String: String]?)?

    /// Sets the current CocxyCore stream for the focused surface.
    let streamCurrentProvider: (@Sendable (UInt32) -> [String: String]?)?

    /// Requests a Protocol v2 capabilities exchange on the focused surface.
    let protocolCapabilitiesProvider: (@Sendable () -> [String: String]?)?

    /// Sends a Protocol v2 viewport payload on the focused surface.
    let protocolViewportProvider: (@Sendable (String?) -> [String: String]?)?

    /// Sends an explicit Protocol v2 message on the focused surface.
    let protocolSendProvider: (@Sendable (String, String) -> [String: String]?)?

    /// Resets the focused CocxyCore terminal surface.
    let coreResetProvider: (@Sendable () -> [String: String]?)?

    /// Sends a POSIX signal to the focused CocxyCore PTY child.
    let coreSignalProvider: (@Sendable (Int32) -> [String: String]?)?

    /// Returns the focused surface's PTY process diagnostics.
    let coreProcessProvider: (@Sendable () -> [String: String]?)?

    /// Returns the focused surface's terminal mode diagnostics.
    let coreModesProvider: (@Sendable () -> [String: String]?)?

    /// Returns the focused surface's search diagnostics.
    let coreSearchProvider: (@Sendable () -> [String: String]?)?

    /// Returns the focused surface's ligature diagnostics.
    let coreLigaturesProvider: (@Sendable () -> [String: String]?)?

    /// Returns the focused surface's protocol diagnostics.
    let coreProtocolProvider: (@Sendable () -> [String: String]?)?

    /// Returns the focused surface's current selection snapshot.
    let coreSelectionProvider: (@Sendable () -> [String: String]?)?

    /// Returns the focused surface's font metrics snapshot.
    let coreFontMetricsProvider: (@Sendable () -> [String: String]?)?

    /// Returns the focused surface's current preedit snapshot.
    let corePreeditProvider: (@Sendable () -> [String: String]?)?

    /// Returns semantic diagnostics and recent blocks for the focused surface.
    let coreSemanticProvider: (@Sendable (UInt32) -> [String: String]?)?

    /// Returns recent command-scoped blocks for the focused surface.
    let blockListProvider: (@Sendable (UInt32) -> [String: String]?)?

    /// Returns recent clean command-scoped output for the focused surface.
    let blockOutputsProvider: (@Sendable (UInt32) -> [String: String]?)?

    /// Copies one command block field to the pasteboard.
    let blockCopyProvider: (@Sendable (UInt64, String) -> [String: String]?)?

    /// Sends one command block's command back to the focused terminal.
    let blockRerunProvider: (@Sendable (UInt64) -> [String: String]?)?

    /// Returns stored inline images for the focused surface.
    let imageListProvider: (@Sendable () -> [String: String]?)?

    /// Deletes a specific inline image by ID for the focused surface.
    let imageDeleteProvider: (@Sendable (UInt32) -> [String: String]?)?

    /// Clears inline images for the focused surface.
    let imageClearProvider: (@Sendable () -> [String: String]?)?

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
        browserViewModelProviderOverride: (@Sendable () -> BrowserViewModel?)? = nil,
        browserNavigationViewModelProviderOverride: (@Sendable () -> BrowserViewModel?)? = nil,
        browserImportProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))? = nil,
        tabCountProviderOverride: (@Sendable () -> Int)? = nil,
        tabInfoProviderOverride: (@Sendable () -> [(id: String, title: String, isActive: Bool)])? = nil,
        tabFocusProviderOverride: (@Sendable (String) -> Bool)? = nil,
        tabCloseProviderOverride: (@Sendable (String) -> TabCloseOutcome)? = nil,
        tabCreateProviderOverride: (@Sendable (String?) -> (id: String, title: String)?)? = nil,
        tabCreateWithEngineProviderOverride: (@Sendable (String?, String?) -> (id: String, title: String)?)? = nil,
        tabRenameProviderOverride: (@Sendable (String, String) -> Bool)? = nil,
        tabMoveProviderOverride: (@Sendable (String, Int) -> Bool)? = nil,
        tabConfigSaveProvider: (@Sendable (
            _ name: String,
            _ command: String?,
            _ theme: String?,
            _ environment: [String: String]
        ) -> (name: String, path: String)?)? = nil,
        tabConfigOpenProvider: (@Sendable (_ name: String) -> (id: String, title: String, path: String)?)? = nil,
        tabConfigListProvider: (@Sendable () -> [String]?)? = nil,
        tabConfigPathProvider: (@Sendable (_ name: String) -> String?)? = nil,
        tabConfigExportProvider: (@Sendable (
            _ name: String,
            _ output: String,
            _ overwrite: Bool
        ) -> (name: String, path: String)?)? = nil,
        projectConfigProviderOverride: (@Sendable () -> [String: String]?)? = nil,
        configProvider: (@Sendable () -> CocxyConfig)? = nil,
        statusDetailsProvider: (@Sendable () -> [String: String])? = nil,
        themeEngineProvider: (() -> ThemeEngineImpl?)? = nil,
        remoteConnectionManagerProvider: (() -> RemoteConnectionManager?)? = nil,
        remoteProfileStoreProvider: (() -> (any RemoteProfileStoring)?)? = nil,
        pluginManagerProvider: (() -> PluginManager?)? = nil,
        pluginSourceStoreProvider: (() -> PluginSourceStore)? = nil,
        pluginInstallerProvider: (() -> PluginInstaller)? = nil,
        pluginCapabilityGrantStoreProvider: (() -> PluginCapabilityGrantStore)? = nil,
        skillRegistryProvider: (@Sendable () -> SkillRegistry)? = nil,
        skillSourceStoreProvider: (() -> SkillSourceStore)? = nil,
        skillInstallerProvider: (() -> SkillMarketplaceInstaller)? = nil,
        notifyDispatcher: (@Sendable (String, String) -> Void)? = nil,
        tabDuplicateProvider: (@Sendable () -> (id: String, title: String)?)? = nil,
        tabPinProvider: (@Sendable (String?) -> (id: String, isPinned: Bool)?)? = nil,
        configReloadProvider: (@Sendable () -> Bool)? = nil,
        splitInfoProvider: (@Sendable () -> [(leafID: String, terminalID: String, isFocused: Bool)])? = nil,
        splitSwapProvider: (@Sendable (Int, Int) -> Bool)? = nil,
        splitSwapByDirectionProvider: (@Sendable (String) -> Bool)? = nil,
        splitZoomProvider: (@Sendable () -> (success: Bool, isZoomed: Bool))? = nil,
        sessionManagerProvider: (@Sendable () -> (any SessionManaging)?)? = nil,
        sessionCaptureProvider: (@Sendable () -> Session?)? = nil,
        sessionRestoreProvider: (@Sendable (String?) -> Bool)? = nil,
        notificationManagerProvider: (() -> NotificationManagerImpl?)? = nil,
        capturePaneProvider: (@Sendable () -> [String])? = nil,
        // V4 providers
        dashboardToggleProvider: (@Sendable () -> Bool)? = nil,
        dashboardStatusProvider: (@Sendable () -> [String: String])? = nil,
        reviewToggleProvider: (@Sendable () -> Bool)? = nil,
        reviewRefreshProvider: (@Sendable () -> [String: String]?)? = nil,
        reviewSubmitProvider: (@Sendable () -> [String: String]?)? = nil,
        reviewStatsProvider: (@Sendable () -> [String: String]?)? = nil,
        timelineQueryProvider: (@Sendable (String?) -> TimelineQueryResult?)? = nil,
        timelineExportProvider: (@Sendable (String?, String) -> Data?)? = nil,
        richInputShowProvider: (@Sendable (String) -> Bool)? = nil,
        splitCreateProvider: (@Sendable (Bool) -> Bool)? = nil,
        splitFocusProvider: (@Sendable (Int) -> Bool)? = nil,
        splitFocusByDirectionProvider: (@Sendable (String) -> Bool)? = nil,
        splitCloseProvider: (@Sendable () -> Bool)? = nil,
        splitResizeProvider: (@Sendable (String, CGFloat) -> Bool)? = nil,
        splitResizeByDirectionProvider: (@Sendable (String, CGFloat) -> Bool)? = nil,
        searchToggleProvider: (@Sendable () -> Void)? = nil,
        searchProvider: (@Sendable (String, Bool, Bool, String?) -> SearchCommandResult?)? = nil,
        sendTextProvider: (@Sendable (String) -> Bool)? = nil,
        sendKeyProvider: (@Sendable (String) -> Bool)? = nil,
        sshProvider: (@Sendable (String, Int?, String?) -> (id: String, title: String)?)? = nil,
        webStartProvider: (@Sendable (String, UInt16, String, UInt16, UInt32) -> [String: String]?)? = nil,
        webStopProvider: (@Sendable () -> Bool)? = nil,
        webStatusProvider: (@Sendable () -> [String: String]?)? = nil,
        streamListProvider: (@Sendable () -> [String: String]?)? = nil,
        streamCurrentProvider: (@Sendable (UInt32) -> [String: String]?)? = nil,
        protocolCapabilitiesProvider: (@Sendable () -> [String: String]?)? = nil,
        protocolViewportProvider: (@Sendable (String?) -> [String: String]?)? = nil,
        protocolSendProvider: (@Sendable (String, String) -> [String: String]?)? = nil,
        coreResetProvider: (@Sendable () -> [String: String]?)? = nil,
        coreSignalProvider: (@Sendable (Int32) -> [String: String]?)? = nil,
        coreProcessProvider: (@Sendable () -> [String: String]?)? = nil,
        coreModesProvider: (@Sendable () -> [String: String]?)? = nil,
        coreSearchProvider: (@Sendable () -> [String: String]?)? = nil,
        coreLigaturesProvider: (@Sendable () -> [String: String]?)? = nil,
        coreProtocolProvider: (@Sendable () -> [String: String]?)? = nil,
        coreSelectionProvider: (@Sendable () -> [String: String]?)? = nil,
        coreFontMetricsProvider: (@Sendable () -> [String: String]?)? = nil,
        corePreeditProvider: (@Sendable () -> [String: String]?)? = nil,
        coreSemanticProvider: (@Sendable (UInt32) -> [String: String]?)? = nil,
        blockListProvider: (@Sendable (UInt32) -> [String: String]?)? = nil,
        blockOutputsProvider: (@Sendable (UInt32) -> [String: String]?)? = nil,
        blockCopyProvider: (@Sendable (UInt64, String) -> [String: String]?)? = nil,
        blockRerunProvider: (@Sendable (UInt64) -> [String: String]?)? = nil,
        imageListProvider: (@Sendable () -> [String: String]?)? = nil,
        imageDeleteProvider: (@Sendable (UInt32) -> [String: String]?)? = nil,
        imageClearProvider: (@Sendable () -> [String: String]?)? = nil,
        worktreeCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))? = nil,
        githubCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))? = nil,
        gitAssistantCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))? = nil,
        agentTeamCLIProvider: (@Sendable (String, [String: String]) -> (success: Bool, data: [String: String]))? = nil
    ) {
        self.configProvider = configProvider
        self.statusDetailsProvider = statusDetailsProvider
        self.themeEngineProvider = themeEngineProvider
        self.remoteConnectionManagerProvider = remoteConnectionManagerProvider
        self.remoteProfileStoreProvider = remoteProfileStoreProvider
        self.pluginManagerProvider = pluginManagerProvider
        self.pluginSourceStoreProvider = pluginSourceStoreProvider ?? { PluginSourceStore() }
        self.pluginInstallerProvider = pluginInstallerProvider ?? { PluginInstaller() }
        self.pluginCapabilityGrantStoreProvider = pluginCapabilityGrantStoreProvider
            ?? { PluginCapabilityGrantStore() }
        self.skillRegistryProvider = skillRegistryProvider
        self.skillSourceStoreProvider = skillSourceStoreProvider ?? { SkillSourceStore() }
        self.skillInstallerProvider = skillInstallerProvider ?? { SkillMarketplaceInstaller() }
        self.notifyDispatcher = notifyDispatcher ?? { _, _ in }
        self.tabDuplicateProvider = tabDuplicateProvider
        self.tabPinProvider = tabPinProvider
        self.tabConfigSaveProvider = tabConfigSaveProvider
        self.tabConfigOpenProvider = tabConfigOpenProvider
        self.tabConfigListProvider = tabConfigListProvider
        self.tabConfigPathProvider = tabConfigPathProvider
        self.tabConfigExportProvider = tabConfigExportProvider
        self.configReloadProvider = configReloadProvider
        self.splitInfoProvider = splitInfoProvider
        self.splitSwapProvider = splitSwapProvider
        self.splitSwapByDirectionProvider = splitSwapByDirectionProvider
        self.splitZoomProvider = splitZoomProvider
        self.sessionManagerProvider = sessionManagerProvider
        self.sessionCaptureProvider = sessionCaptureProvider
        self.sessionRestoreProvider = sessionRestoreProvider
        self.notificationManagerProvider = notificationManagerProvider
        self.capturePaneProvider = capturePaneProvider
        self.dashboardToggleProvider = dashboardToggleProvider
        self.dashboardStatusProvider = dashboardStatusProvider
        self.reviewToggleProvider = reviewToggleProvider
        self.reviewRefreshProvider = reviewRefreshProvider
        self.reviewSubmitProvider = reviewSubmitProvider
        self.reviewStatsProvider = reviewStatsProvider
        self.timelineQueryProvider = timelineQueryProvider
        self.timelineExportProvider = timelineExportProvider
        self.richInputShowProvider = richInputShowProvider
        self.splitCreateProvider = splitCreateProvider
        self.splitFocusProvider = splitFocusProvider
        self.splitFocusByDirectionProvider = splitFocusByDirectionProvider
        self.splitCloseProvider = splitCloseProvider
        self.splitResizeProvider = splitResizeProvider
        self.splitResizeByDirectionProvider = splitResizeByDirectionProvider
        self.searchToggleProvider = searchToggleProvider
        self.searchProvider = searchProvider
        self.sendTextProvider = sendTextProvider
        self.sendKeyProvider = sendKeyProvider
        self.sshProvider = sshProvider
        self.webStartProvider = webStartProvider
        self.webStopProvider = webStopProvider
        self.webStatusProvider = webStatusProvider
        self.streamListProvider = streamListProvider
        self.streamCurrentProvider = streamCurrentProvider
        self.protocolCapabilitiesProvider = protocolCapabilitiesProvider
        self.protocolViewportProvider = protocolViewportProvider
        self.protocolSendProvider = protocolSendProvider
        self.coreResetProvider = coreResetProvider
        self.coreSignalProvider = coreSignalProvider
        self.coreProcessProvider = coreProcessProvider
        self.coreModesProvider = coreModesProvider
        self.coreSearchProvider = coreSearchProvider
        self.coreLigaturesProvider = coreLigaturesProvider
        self.coreProtocolProvider = coreProtocolProvider
        self.coreSelectionProvider = coreSelectionProvider
        self.coreFontMetricsProvider = coreFontMetricsProvider
        self.corePreeditProvider = corePreeditProvider
        self.coreSemanticProvider = coreSemanticProvider
        self.blockListProvider = blockListProvider
        self.blockOutputsProvider = blockOutputsProvider
        self.blockCopyProvider = blockCopyProvider
        self.blockRerunProvider = blockRerunProvider
        self.imageListProvider = imageListProvider
        self.imageDeleteProvider = imageDeleteProvider
        self.imageClearProvider = imageClearProvider
        self.worktreeCLIProvider = worktreeCLIProvider
        self.githubCLIProvider = githubCLIProvider
        self.gitAssistantCLIProvider = gitAssistantCLIProvider
        self.agentTeamCLIProvider = agentTeamCLIProvider
        let tabManagerRef = WeakReference(tabManager)
        let browserViewModelRef = WeakReference(browserViewModel)

        // -- Browser view model provider --
        let resolvedBrowserViewModelProvider: @Sendable () -> BrowserViewModel?
        if let browserViewModelProviderOverride {
            resolvedBrowserViewModelProvider = browserViewModelProviderOverride
        } else {
            resolvedBrowserViewModelProvider = {
                if Thread.isMainThread {
                    return MainActor.assumeIsolated {
                        browserViewModelRef.value
                    }
                }
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        browserViewModelRef.value
                    }
                }
            }
        }
        self.browserViewModelProvider = resolvedBrowserViewModelProvider
        self.browserNavigationViewModelProvider = browserNavigationViewModelProviderOverride
            ?? resolvedBrowserViewModelProvider
        self.browserImportProvider = browserImportProvider

        // -- Tab count provider (read-only) --
        if let tabCountProviderOverride {
            self.tabCountProvider = tabCountProviderOverride
        } else {
            self.tabCountProvider = {
                syncOnMainActor {
                    tabManagerRef.value?.tabs.count ?? 0
                }
            }
        }

        // -- Tab info provider (read-only) --
        if let tabInfoProviderOverride {
            self.tabInfoProvider = tabInfoProviderOverride
        } else {
            self.tabInfoProvider = {
                syncOnMainActor {
                    guard let tabs = tabManagerRef.value?.tabs else { return [] }
                    return tabs.map { (
                        id: $0.id.rawValue.uuidString,
                        title: $0.title,
                        isActive: $0.isActive
                    )}
                }
            }
        }

        // -- Focus tab by UUID string --
        if let tabFocusProviderOverride {
            self.tabFocusProvider = tabFocusProviderOverride
        } else {
            self.tabFocusProvider = { uuidString in
                guard let uuid = UUID(uuidString: uuidString) else { return false }
                return syncOnMainActor {
                    guard let manager = tabManagerRef.value else { return false }
                    let tabID = TabID(rawValue: uuid)
                    guard manager.tabs.contains(where: { $0.id == tabID }) else { return false }
                    manager.setActive(id: tabID)
                    return true
                }
            }
        }

        // -- Close tab by UUID string --
        if let tabCloseProviderOverride {
            self.tabCloseProvider = tabCloseProviderOverride
        } else {
            self.tabCloseProvider = { uuidString in
                guard let uuid = UUID(uuidString: uuidString) else { return .notFound }
                return syncOnMainActor {
                    guard let manager = tabManagerRef.value else {
                        return .unavailable
                    }

                    let tabID = TabID(rawValue: uuid)
                    guard let index = manager.tabs.firstIndex(where: { $0.id == tabID }) else {
                        return .notFound
                    }
                    guard manager.tabs.count > 1 else {
                        return .lastTabBlocked
                    }
                    guard !manager.tabs[index].isPinned else {
                        return .pinnedBlocked
                    }

                    manager.removeTab(id: tabID)
                    return manager.tabs.contains(where: { $0.id == tabID }) ? .unavailable : .closed
                }
            }
        }

        // -- Create new tab with optional directory --
        if let tabCreateProviderOverride {
            self.tabCreateProvider = tabCreateProviderOverride
        } else {
            self.tabCreateProvider = { directoryPath in
                syncOnMainActor {
                    guard let manager = tabManagerRef.value else { return nil }
                    let workingDirectory: URL
                    if let path = directoryPath {
                        workingDirectory = URL(fileURLWithPath: path)
                    } else {
                        workingDirectory = FileManager.default.homeDirectoryForCurrentUser
                    }
                    let newTab = manager.addTab(workingDirectory: workingDirectory)
                    return (id: newTab.id.rawValue.uuidString, title: newTab.title)
                }
            }
        }
        if let tabCreateWithEngineProviderOverride {
            self.tabCreateWithEngineProvider = tabCreateWithEngineProviderOverride
        } else {
            self.tabCreateWithEngineProvider = { directoryPath, engineValue in
                syncOnMainActor {
                    guard let manager = tabManagerRef.value else { return nil }
                    let workingDirectory: URL
                    if let path = directoryPath {
                        workingDirectory = URL(fileURLWithPath: path)
                    } else {
                        workingDirectory = FileManager.default.homeDirectoryForCurrentUser
                    }
                    let preference = engineValue.flatMap(TerminalEnginePreference.init(cliValue:))
                    let newTab = manager.addTab(
                        workingDirectory: workingDirectory,
                        terminalEnginePreference: preference
                    )
                    return (id: newTab.id.rawValue.uuidString, title: newTab.title)
                }
            }
        }

        // -- Rename tab by UUID string --
        if let tabRenameProviderOverride {
            self.tabRenameProvider = tabRenameProviderOverride
        } else {
            self.tabRenameProvider = { uuidString, newName in
                guard let uuid = UUID(uuidString: uuidString) else { return false }
                return syncOnMainActor {
                    guard let manager = tabManagerRef.value else { return false }
                    let tabID = TabID(rawValue: uuid)
                    guard manager.tabs.contains(where: { $0.id == tabID }) else { return false }
                    manager.renameTab(id: tabID, newTitle: newName)
                    return true
                }
            }
        }

        // -- Move tab to new position --
        if let tabMoveProviderOverride {
            self.tabMoveProvider = tabMoveProviderOverride
        } else {
            self.tabMoveProvider = { uuidString, destinationIndex in
                guard let uuid = UUID(uuidString: uuidString) else { return false }
                return syncOnMainActor {
                    guard let manager = tabManagerRef.value else { return false }
                    let tabID = TabID(rawValue: uuid)
                    guard let fromIndex = manager.tabs.firstIndex(
                        where: { $0.id == tabID }
                    ) else { return false }
                    guard destinationIndex >= 0,
                          destinationIndex < manager.tabs.count else { return false }
                    manager.moveTab(from: fromIndex, to: destinationIndex)
                    return true
                }
            }
        }

        // -- Project config from active tab (read-only) --
        if let projectConfigProviderOverride {
            self.projectConfigProvider = projectConfigProviderOverride
        } else {
            self.projectConfigProvider = {
                syncOnMainActor {
                    guard let manager = tabManagerRef.value,
                          let activeID = manager.activeTabID,
                          let tab = manager.tab(for: activeID),
                          let config = tab.projectConfig else { return nil }

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
            }
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
        case .tabConfigSave:
            return handleTabConfigSave(request)
        case .tabConfigOpen:
            return handleTabConfigOpen(request)
        case .tabConfigList:
            return handleTabConfigList(request)
        case .tabConfigPath:
            return handleTabConfigPath(request)
        case .tabConfigExport:
            return handleTabConfigExport(request)

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
        case .browserSnapshot:
            return handleBrowserSnapshot(request)
        case .browserClick:
            return handleBrowserClick(request)
        case .browserFill:
            return handleBrowserFill(request)
        case .browserScreenshot:
            return handleBrowserScreenshot(request)
        case .browserConsole:
            return handleBrowserConsole(request)
        case .browserWait:
            return handleBrowserWait(request)
        case .browserCookiesList:
            return handleBrowserCookiesList(request)
        case .browserCookiesSet:
            return handleBrowserCookiesSet(request)
        case .browserCookiesDelete:
            return handleBrowserCookiesDelete(request)
        case .browserNetwork:
            return handleBrowserNetwork(request)
        case .browserImportPreview:
            return handleBrowserImport(kind: "preview", request: request)
        case .browserImportRun:
            return handleBrowserImport(kind: "run", request: request)
        case .agentTeamLaunch:
            return handleAgentTeam(kind: "launch", request: request)
        case .agentTeamList:
            return handleAgentTeam(kind: "list", request: request)
        case .agentTeamStop:
            return handleAgentTeam(kind: "stop", request: request)

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
        case .pluginSourceList:
            return handlePluginSourceList(request)
        case .pluginSourceAdd:
            return handlePluginSourceAdd(request)
        case .pluginInstall:
            return handlePluginInstall(request)
        case .pluginUninstall:
            return handlePluginUninstall(request)
        case .sandboxListGrants:
            return handleSandboxListGrants(request)
        case .sandboxRevoke:
            return handleSandboxRevoke(request)
        case .skillList:
            return handleSkillList(request)
        case .skillSourceList:
            return handleSkillSourceList(request)
        case .skillSourceAdd:
            return handleSkillSourceAdd(request)
        case .skillInstall:
            return handleSkillInstall(request)
        case .skillUninstall:
            return handleSkillUninstall(request)

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

        // Split management (v4)
        case .split:
            return handleSplitCreate(request)
        case .splitList:
            return handleSplitList(request)
        case .splitFocus:
            return handleSplitFocus(request)
        case .splitClose:
            return handleSplitClose(request)
        case .splitResize:
            return handleSplitResize(request)

        // Dashboard (v4)
        case .dashboardShow:
            return handleDashboardShow(request)
        case .dashboardHide:
            return handleDashboardHide(request)
        case .dashboardToggle:
            return handleDashboardToggle(request)
        case .dashboardStatus:
            return handleDashboardStatus(request)
        case .review:
            return handleReviewToggle(request)
        case .reviewRefresh:
            return handleReviewRefresh(request)
        case .reviewSubmit:
            return handleReviewSubmit(request)
        case .reviewStats:
            return handleReviewStats(request)
        case .reviewApprove:
            return handleGitHubCLI(kind: "review-approve", request: request)
        case .reviewRequestChanges:
            return handleGitHubCLI(kind: "review-request-changes", request: request)

        // Timeline (v4)
        case .timelineShow:
            return handleTimelineShow(request)
        case .timelineExport:
            return handleTimelineExport(request)

        // Rich Input (v4)
        case .richInputShow:
            return handleRichInputShow(request)

        // Search (v4)
        case .search:
            return handleSearch(request)

        // Terminal I/O (v4)
        case .send:
            return handleSend(request)
        case .sendKey:
            return handleSendKey(request)

        // Hook management (v4)
        case .hooks:
            return handleHooksList(request)
        case .hookHandler:
            return handleHookHandler(request)
        case .setupHooks:
            return .failure(
                id: request.id,
                error: "Command 'setup-hooks' must be run locally from the Cocxy CLI."
            )

        // SSH (v4)
        case .ssh:
            return handleSSH(request)

        // Worktree (v0.1.81)
        case .worktreeAdd:
            return handleWorktreeAdd(request)
        case .worktreeList:
            return handleWorktreeList(request)
        case .worktreeFocus:
            return handleWorktreeFocus(request)
        case .worktreeRemove:
            return handleWorktreeRemove(request)
        case .worktreePrune:
            return handleWorktreePrune(request)
        case .worktreeCleanupMerged:
            return handleWorktreeCleanupMerged(request)

        // GitHub pane (v0.1.84)
        case .githubStatus:
            return handleGitHubCLI(kind: "status", request: request)
        case .githubPRs:
            return handleGitHubCLI(kind: "prs", request: request)
        case .githubIssues:
            return handleGitHubCLI(kind: "issues", request: request)
        case .githubOpen:
            return handleGitHubCLI(kind: "open", request: request)
        case .githubRefresh:
            return handleGitHubCLI(kind: "refresh", request: request)
        case .githubPRMerge:
            return handleGitHubCLI(kind: "pr-merge", request: request)

        // Git Assistant
        case .gitAssistantCommitMessage:
            return handleGitAssistantCLI(kind: "commit-message", request: request)
        case .gitAssistantPRDraft:
            return handleGitAssistantCLI(kind: "pr-draft", request: request)
        case .gitAssistantReleaseNotes:
            return handleGitAssistantCLI(kind: "release-notes", request: request)

        // Web terminal (v5)
        case .webStart:
            return handleWebStart(request)
        case .webStop:
            return handleWebStop(request)
        case .webStatus:
            return handleWebStatus(request)
        case .streamList:
            return handleStreamList(request)
        case .streamCurrent:
            return handleStreamCurrent(request)
        case .protocolCapabilities:
            return handleProtocolCapabilities(request)
        case .protocolViewport:
            return handleProtocolViewport(request)
        case .protocolSend:
            return handleProtocolSend(request)
        case .coreReset:
            return handleCoreReset(request)
        case .coreSignal:
            return handleCoreSignal(request)
        case .coreProcess:
            return handleCoreProcess(request)
        case .coreModes:
            return handleCoreModes(request)
        case .coreSearch:
            return handleCoreSearch(request)
        case .coreLigatures:
            return handleCoreLigatures(request)
        case .coreProtocol:
            return handleCoreProtocol(request)
        case .coreSelection:
            return handleCoreSelection(request)
        case .coreFontMetrics:
            return handleCoreFontMetrics(request)
        case .corePreedit:
            return handleCorePreedit(request)
        case .coreSemantic:
            return handleCoreSemantic(request)
        case .blockList:
            return handleBlockList(request)
        case .blockOutputs:
            return handleBlockOutputs(request)
        case .blockCopy:
            return handleBlockCopy(request)
        case .blockRerun:
            return handleBlockRerun(request)
        case .imageList:
            return handleImageList(request)
        case .imageDelete:
            return handleImageDelete(request)
        case .imageClear:
            return handleImageClear(request)
        case .notebookImport:
            return handleNotebookImport(request)
        case .notebookExport:
            return handleNotebookExport(request)
        case .notebookExportHTML:
            return handleNotebookExportHTML(request)
        case .notebookTemplateList:
            return handleNotebookTemplateList(request)
        case .notebookTemplateCreate:
            return handleNotebookTemplateCreate(request)
        case .notebookRun:
            return handleNotebookRun(request)
        case .workflowRun:
            return handleWorkflowRun(request)
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
        var data: [String: String] = [
            "status": "running",
            "version": CocxyVersion.current,
            "tabs": "\(tabCount)"
        ]
        if let extra = statusDetailsProvider?() {
            for (key, value) in extra {
                data[key] = value
            }
        }
        return .ok(id: request.id, data: data)
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

        switch tabCloseProvider(tabIDString) {
        case .closed:
            return .ok(id: request.id, data: ["status": "closed"])
        case .lastTabBlocked:
            return .failure(id: request.id, error: "Cannot close the last remaining tab")
        case .pinnedBlocked:
            return .failure(id: request.id, error: "Cannot close a pinned tab")
        case .notFound:
            return .failure(id: request.id, error: "Tab not found")
        case .unavailable:
            return .failure(id: request.id, error: "Tab manager not available")
        }
    }

    /// Creates a new tab with an optional working directory.
    ///
    /// Optional params:
    /// - `dir` (filesystem path for the working directory)
    /// - `engine` (`system`, `in-process`, or `daemon`) for per-tab dogfood.
    private func handleNewTab(_ request: SocketRequest) -> SocketResponse {
        let directoryPath = request.params?["dir"]
        let enginePreference = request.params?["engine"]

        // Validate directory exists if provided.
        if let path = directoryPath {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else {
                return .failure(id: request.id, error: "Directory does not exist: \(path)")
            }
        }
        if let enginePreference,
           TerminalEnginePreference(cliValue: enginePreference) == nil {
            return .failure(
                id: request.id,
                error: "Invalid engine. Use system, in-process, or daemon"
            )
        }

        guard let result = tabCreateWithEngineProvider(directoryPath, enginePreference) else {
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

    /// Saves the focused tab to `~/.cocxy/tabs/<name>.toml`.
    ///
    /// Required params: `name`.
    /// Optional params: `command`, `theme`, and `env.<KEY>` entries.
    private func handleTabConfigSave(_ request: SocketRequest) -> SocketResponse {
        guard let provider = tabConfigSaveProvider else {
            return .failure(id: request.id, error: "Tab config save not available")
        }
        guard let name = request.params?["name"], !name.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: name")
        }

        let environment: [String: String]
        do {
            environment = try extractTabConfigEnvironment(from: request.params)
        } catch {
            return .failure(id: request.id, error: error.localizedDescription)
        }

        guard let result = provider(
            name,
            nonEmptyParam(request.params?["command"]),
            nonEmptyParam(request.params?["theme"]),
            environment
        ) else {
            return .failure(id: request.id, error: "Unable to save tab config")
        }

        return .ok(id: request.id, data: [
            "status": "saved",
            "name": result.name,
            "path": result.path,
        ])
    }

    /// Opens a new tab from a saved TOML config. The provider reloads the
    /// TOML from disk on every call so manual edits are picked up.
    private func handleTabConfigOpen(_ request: SocketRequest) -> SocketResponse {
        guard let provider = tabConfigOpenProvider else {
            return .failure(id: request.id, error: "Tab config open not available")
        }
        guard let name = request.params?["name"], !name.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: name")
        }
        guard let result = provider(name) else {
            return .failure(id: request.id, error: "Unable to open tab config")
        }
        return .ok(id: request.id, data: [
            "status": "opened",
            "name": name,
            "id": result.id,
            "title": result.title,
            "path": result.path,
        ])
    }

    private func handleTabConfigList(_ request: SocketRequest) -> SocketResponse {
        guard let names = tabConfigListProvider?() else {
            return .failure(id: request.id, error: "Tab config list not available")
        }
        var data: [String: String] = ["count": "\(names.count)"]
        for (index, name) in names.enumerated() {
            data["config_\(index)_name"] = name
        }
        return .ok(id: request.id, data: data)
    }

    private func handleTabConfigPath(_ request: SocketRequest) -> SocketResponse {
        guard let provider = tabConfigPathProvider else {
            return .failure(id: request.id, error: "Tab config path not available")
        }
        guard let name = request.params?["name"], !name.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: name")
        }
        guard let path = provider(name) else {
            return .failure(id: request.id, error: "Unable to resolve tab config path")
        }
        return .ok(id: request.id, data: ["name": name, "path": path])
    }

    private func handleTabConfigExport(_ request: SocketRequest) -> SocketResponse {
        guard let provider = tabConfigExportProvider else {
            return .failure(id: request.id, error: "Tab config export not available")
        }
        guard let name = request.params?["name"], !name.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: name")
        }
        guard let output = request.params?["output"], !output.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: output")
        }
        let overwrite = request.params?["force"] == "true"
        guard let result = provider(name, output, overwrite) else {
            return .failure(id: request.id, error: "Unable to export tab config")
        }
        return .ok(id: request.id, data: [
            "status": "exported",
            "name": result.name,
            "path": result.path,
        ])
    }

    private func extractTabConfigEnvironment(from params: [String: String]?) throws -> [String: String] {
        guard let params else { return [:] }
        var environment: [String: String] = [:]
        for (key, value) in params where key.hasPrefix("env.") {
            let envKey = String(key.dropFirst("env.".count))
            guard TabConfigTOMLCodec.isValidEnvironmentKey(envKey) else {
                throw TabConfigStoreError.invalidConfig("invalid env key \(envKey)")
            }
            environment[envKey] = value
        }
        return environment
    }

    private func nonEmptyParam(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
        guard !value.contains("\n") && !value.contains("\r") else {
            return .failure(id: request.id, error: "Value must not contain newlines")
        }

        // Validate key against known config keys.
        guard resolveConfigValue(key: key, config: CocxyConfig.defaults) != nil else {
            return .failure(id: request.id, error: "Unknown config key: \(key)")
        }
        guard let renderedValue = renderedConfigValue(key: key, rawValue: value) else {
            return .failure(id: request.id, error: "Invalid value for config key: \(key)")
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homePath)/.config/cocxy/config.toml"
        let configURL = URL(fileURLWithPath: configPath)

        let existingContent = (try? String(contentsOfFile: configPath, encoding: .utf8))
            ?? ConfigService.generateDefaultToml()

        let updatedContent = AppSocketConfigTOMLUpdater.updateTomlValue(
            in: existingContent,
            section: sectionFromKey(key),
            field: fieldFromKey(key),
            renderedValue: renderedValue
        )

        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try updatedContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            if let reload = configReloadProvider, reload() == false {
                return .failure(
                    id: request.id,
                    error: "Configuration was written but could not be reloaded"
                )
            }
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
        let themes: [ThemeMetadata]
        if Thread.isMainThread {
            themes = MainActor.assumeIsolated {
                self.themeEngineProvider?()?.availableThemes ?? []
            }
        } else {
            themes = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    self.themeEngineProvider?()?.availableThemes ?? []
                }
            }
        }

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

        let applied: Bool
        if Thread.isMainThread {
            applied = MainActor.assumeIsolated {
                guard let engine = self.themeEngineProvider?() else { return false }
                do {
                    try engine.apply(themeName: themeName)
                    return true
                } catch {
                    return false
                }
            }
        } else {
            applied = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let engine = self.themeEngineProvider?() else { return false }
                    do {
                        try engine.apply(themeName: themeName)
                        return true
                    } catch {
                        return false
                    }
                }
            }
        }

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
        case "appearance.ligatures":
            return "\(config.appearance.ligatures)"
        case "appearance.background-opacity":
            return "\(config.appearance.backgroundOpacity)"
        case "appearance.background-blur-radius":
            return "\(config.appearance.backgroundBlurRadius)"
        case "appearance.aurora-enabled":
            return "\(config.appearance.auroraEnabled)"
        case "appearance.rate-limit-indicator-enabled":
            return "\(config.appearance.rateLimitIndicatorEnabled)"
        case "appearance.quickswitch-mode":
            return config.appearance.quickSwitchMode.rawValue
        case "appearance.app-language":
            return config.appearance.appLanguage.rawValue

        // Rate limit
        case "rate-limit.enabled-providers":
            return config.rateLimit.enabledProviders.map(\.rawValue).joined(separator: ",")
        case "rate-limit.auto-detect":
            return "\(config.rateLimit.autoDetect)"
        case "rate-limit.oauth-refresh-interval-minutes":
            return "\(config.rateLimit.oauthRefreshIntervalMinutes)"

        // UX polish
        case "ux-polish.always-show-shortcut-hints":
            return "\(config.uxPolish.alwaysShowShortcutHints)"
        case "ux-polish.shortcut-hint-debug-overlay":
            return "\(config.uxPolish.shortcutHintDebugOverlay)"
        case "ux-polish.shortcut-hint-offset-x":
            return "\(config.uxPolish.shortcutHintOffsetX)"
        case "ux-polish.shortcut-hint-offset-y":
            return "\(config.uxPolish.shortcutHintOffsetY)"
        case "ux-polish.shortcut-hint-scale":
            return "\(config.uxPolish.shortcutHintScale)"

        // Command corrections
        case "command-corrections.enabled":
            return "\(config.commandCorrections.enabled)"
        case "command-corrections.edit-distance-threshold":
            return "\(config.commandCorrections.editDistanceThreshold)"
        case "command-corrections.foundation-models-enabled":
            return "\(config.commandCorrections.foundationModelsEnabled)"
        case "command-corrections.agent-fallback":
            return "\(config.commandCorrections.agentFallback)"
        case "command-corrections.auto-show-on-failure":
            return "\(config.commandCorrections.autoShowOnFailure)"
        case "command-corrections.show-confidence-badge":
            return "\(config.commandCorrections.showConfidenceBadge)"
        case "command-corrections.max-suggestions-shown":
            return "\(config.commandCorrections.maxSuggestionsShown)"

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
        case "terminal.clipboard-read-access":
            return config.terminal.clipboardReadAccess.rawValue
        case "terminal.image-memory-limit-mb":
            return "\(config.terminal.imageMemoryLimitMB)"
        case "terminal.image-file-transfer":
            return "\(config.terminal.imageFileTransfer)"
        case "terminal.enable-sixel-images":
            return "\(config.terminal.enableSixelImages)"
        case "terminal.enable-kitty-images":
            return "\(config.terminal.enableKittyImages)"
        case "terminal.enable-iterm2-images":
            return "\(config.terminal.enableITerm2Images)"
        case "terminal.image-disk-cache-directory":
            return config.terminal.imageDiskCacheDirectory
        case "terminal.image-disk-cache-limit-mb":
            return "\(config.terminal.imageDiskCacheLimitMB)"

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

        // Worktree
        case "worktree.enabled":
            return "\(config.worktree.enabled)"
        case "worktree.base-path":
            return config.worktree.basePath
        case "worktree.branch-template":
            return config.worktree.branchTemplate
        case "worktree.base-ref":
            return config.worktree.baseRef
        case "worktree.on-close":
            return config.worktree.onClose.rawValue
        case "worktree.open-in-new-tab":
            return "\(config.worktree.openInNewTab)"
        case "worktree.id-length":
            return "\(config.worktree.idLength)"
        case "worktree.inherit-project-config":
            return "\(config.worktree.inheritProjectConfig)"
        case "worktree.show-badge":
            return "\(config.worktree.showBadge)"

        // Experimental
        case "experimental.pip-enabled":
            return "\(config.experimental.pipEnabled)"
        case "experimental.pty-daemon":
            return "\(config.experimental.ptyDaemonEnabled)"

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

        // Notes
        case "notes.enabled":
            return "\(config.notes.enabled)"
        case "notes.format":
            return config.notes.format.rawValue
        case "notes.search-engine":
            return config.notes.searchEngine.rawValue
        case "notes.storage-dir":
            return config.notes.storageDir
        case "notes.shortcut":
            return config.notes.shortcut
        case "notes.auto-save":
            return "\(config.notes.autoSave)"
        case "notes.auto-save-interval-seconds":
            return "\(config.notes.autoSaveIntervalSeconds)"

        // Completions
        case "completions.inline-ai":
            return "\(config.completions.inlineAIEnabled)"
        case "completions.provider":
            return config.completions.provider.rawValue
        case "completions.idle-delay-seconds":
            return "\(config.completions.idleDelaySeconds)"
        case "completions.max-context-utf16-length":
            return "\(config.completions.maxContextUTF16Length)"
        case "completions.enabled-languages":
            return config.completions.enabledLanguageIDs.joined(separator: ",")

        default:
            return nil
        }
    }

    private func renderedConfigValue(key: String, rawValue: String) -> String? {
        switch key {
        case "appearance.app-language":
            guard let language = AppLanguage.normalized(rawValue) else { return nil }
            return AppSocketConfigTOMLUpdater.renderedScalarValue(language.rawValue)
        case "ux-polish.always-show-shortcut-hints",
             "ux-polish.shortcut-hint-debug-overlay":
            guard let value = normalizedConfigBool(rawValue) else { return nil }
            return value
        case "command-corrections.enabled",
             "command-corrections.foundation-models-enabled",
             "command-corrections.agent-fallback",
             "command-corrections.auto-show-on-failure",
             "command-corrections.show-confidence-badge":
            guard let value = normalizedConfigBool(rawValue) else { return nil }
            return value
        case "command-corrections.edit-distance-threshold":
            guard let value = Int(rawValue),
                  (CommandCorrectionsConfig.minEditDistanceThreshold...CommandCorrectionsConfig.maxEditDistanceThreshold)
                    .contains(value)
            else { return nil }
            return "\(value)"
        case "command-corrections.max-suggestions-shown":
            guard let value = Int(rawValue),
                  (CommandCorrectionsConfig.minSuggestionsShown...CommandCorrectionsConfig.maxSuggestionsShownLimit)
                    .contains(value)
            else { return nil }
            return "\(value)"
        case "completions.inline-ai":
            guard let value = normalizedConfigBool(rawValue) else { return nil }
            return value
        case "completions.provider":
            guard CompletionProviderKind(rawValue: rawValue) != nil else { return nil }
            return AppSocketConfigTOMLUpdater.renderedScalarValue(rawValue)
        case "completions.enabled-languages":
            let normalized = CompletionConfig(
                enabledLanguageIDs: parsedStringListConfigValue(rawValue)
            ).enabledLanguageIDs
            return AppSocketConfigTOMLUpdater.renderedStringArrayValue(normalized)
        case "rate-limit.enabled-providers":
            let providers = parsedStringListConfigValue(rawValue)
                .compactMap { RateLimitSnapshot.AgentKind(rawValue: $0) }
            let normalized = RateLimitConfig.normalizedProviders(providers)
            guard !normalized.isEmpty else { return nil }
            return AppSocketConfigTOMLUpdater.renderedStringArrayValue(normalized.map(\.rawValue))
        case "rate-limit.auto-detect":
            guard let value = normalizedConfigBool(rawValue) else { return nil }
            return value
        case "rate-limit.oauth-refresh-interval-minutes":
            guard let value = Int(rawValue),
                  value == RateLimitConfig.clampedRefreshInterval(value) else {
                return nil
            }
            return "\(value)"
        default:
            return AppSocketConfigTOMLUpdater.renderedScalarValue(rawValue)
        }
    }

    private func normalizedConfigBool(_ rawValue: String) -> String? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true": return "true"
        case "false": return "false"
        default: return nil
        }
    }

    private func parsedStringListConfigValue(_ rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let inner: String
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            inner = String(trimmed.dropFirst().dropLast())
        } else {
            inner = trimmed
        }

        return inner
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { component in
                component.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .map { component in
                guard component.count >= 2 else { return component }
                let first = component.first
                let last = component.last
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    return String(component.dropFirst().dropLast())
                }
                return component
            }
            .filter { !$0.isEmpty }
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
        guard let viewModel = browserNavigationViewModelProvider() else {
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

        let state: [String: String]
        if Thread.isMainThread {
            state = MainActor.assumeIsolated {
                viewModel.getState()
            }
        } else {
            state = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    viewModel.getState()
                }
            }
        }

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

        let result = browserScriptResult(
            viewModel: viewModel,
            script: script,
            requiresBridge: false
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }

        var data = ["status": "evaluated"]
        if let value = result.value, !value.isEmpty {
            data["result"] = value
        }
        return .ok(id: request.id, data: data)
    }

    /// Gets the text content of the current page via `document.body.innerText`.
    ///
    /// Internally calls `evaluateJavaScript` with a fixed script.
    /// The result is dispatched asynchronously.
    private func handleBrowserGetText(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let result = browserScriptResult(
            viewModel: viewModel,
            script: "document.body.innerText",
            requiresBridge: false
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }

        var data = ["status": "evaluated"]
        if let value = result.value, !value.isEmpty {
            data["text"] = value
        }
        return .ok(id: request.id, data: data)
    }

    /// Lists all open browser tabs.
    private func handleBrowserListTabs(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let tabList: [[String: String]]
        if Thread.isMainThread {
            tabList = MainActor.assumeIsolated {
                viewModel.getTabList()
            }
        } else {
            tabList = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    viewModel.getTabList()
                }
            }
        }

        var data: [String: String] = ["count": "\(tabList.count)"]
        for (index, tab) in tabList.enumerated() {
            data["tab_\(index)_id"] = tab["id"] ?? ""
            data["tab_\(index)_url"] = tab["url"] ?? ""
            data["tab_\(index)_title"] = tab["title"] ?? ""
            data["tab_\(index)_active"] = tab["isActive"] ?? "false"
        }
        return .ok(id: request.id, data: data)
    }

    private func handleBrowserSnapshot(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }
        let result = browserScriptResult(
            viewModel: viewModel,
            script: Self.browserSnapshotScript,
            requiresBridge: true
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }
        return .ok(id: request.id, data: [
            "status": "captured",
            "snapshot": result.value ?? "[]"
        ])
    }

    private func handleBrowserClick(_ request: SocketRequest) -> SocketResponse {
        guard let ref = request.params?["ref"], Self.isValidBrowserRef(ref) else {
            return .failure(id: request.id, error: "Missing or invalid required param: ref")
        }
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }
        let result = browserScriptResult(
            viewModel: viewModel,
            script: Self.browserClickScript(ref: ref),
            requiresBridge: true
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }
        let status = result.value == "not-found" ? "not-found" : "clicked"
        return .ok(id: request.id, data: ["status": status, "ref": ref])
    }

    private func handleBrowserFill(_ request: SocketRequest) -> SocketResponse {
        guard let ref = request.params?["ref"], Self.isValidBrowserRef(ref) else {
            return .failure(id: request.id, error: "Missing or invalid required param: ref")
        }
        guard let text = request.params?["text"] else {
            return .failure(id: request.id, error: "Missing required param: text")
        }
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }
        let result = browserScriptResult(
            viewModel: viewModel,
            script: Self.browserFillScript(ref: ref, text: text),
            requiresBridge: true
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }
        let status = result.value == "not-found" ? "not-found" : "filled"
        return .ok(id: request.id, data: ["status": status, "ref": ref])
    }

    private func handleBrowserScreenshot(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }
        let outputPath = request.params?["output"]
        let result = viewModel.automationBridge.captureScreenshot(outputPath: outputPath, timeout: 3)
            ?? .failure("Browser page is not ready for screenshot capture")
        switch result {
        case .dataURL(let dataURL, let byteCount):
            return .ok(id: request.id, data: [
                "status": "captured",
                "dataURL": dataURL,
                "bytes": "\(byteCount)"
            ])
        case .file(let path, let byteCount):
            return .ok(id: request.id, data: [
                "status": "captured",
                "path": path,
                "bytes": "\(byteCount)"
            ])
        case .failure(let error):
            return .failure(id: request.id, error: error)
        }
    }

    private func handleBrowserConsole(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }
        let entries: [BrowserConsoleSnapshotEntry]
        if Thread.isMainThread {
            entries = MainActor.assumeIsolated { viewModel.consoleSnapshotEntries }
        } else {
            entries = DispatchQueue.main.sync {
                MainActor.assumeIsolated { viewModel.consoleSnapshotEntries }
            }
        }
        var data: [String: String] = ["count": "\(entries.count)"]
        for (index, entry) in entries.enumerated() {
            data["entry_\(index)_level"] = entry.level
            data["entry_\(index)_message"] = entry.message
            data["entry_\(index)_timestamp"] = ISO8601DateFormatter().string(from: entry.timestamp)
        }
        return .ok(id: request.id, data: data)
    }

    private func handleBrowserWait(_ request: SocketRequest) -> SocketResponse {
        guard let selector = request.params?["selector"], !selector.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: selector")
        }
        guard selector.count <= 1_024 else {
            return .failure(id: request.id, error: "Selector exceeds maximum 1024 characters")
        }
        let timeoutMilliseconds = min(max(Int(request.params?["timeout"] ?? "") ?? 5_000, 0), 30_000)
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMilliseconds) / 1_000)
        let script = Self.browserWaitScript(selector: selector)
        repeat {
            let result = browserScriptResult(
                viewModel: viewModel,
                script: script,
                requiresBridge: true,
                timeout: 1
            )
            if let error = result.error {
                return .failure(id: request.id, error: error)
            }
            if result.value == "found" {
                return .ok(id: request.id, data: ["status": "found", "selector": selector])
            }
            if timeoutMilliseconds == 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline

        return .ok(id: request.id, data: ["status": "timeout", "selector": selector])
    }

    private func handleBrowserCookiesList(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }
        let result = browserScriptResult(
            viewModel: viewModel,
            script: "document.cookie",
            requiresBridge: true
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }

        let domainFilter = request.params?["domain"]?.lowercased()
        let pairs = Self.cookiePairs(from: result.value ?? "")
        var data: [String: String] = ["count": "\(pairs.count)"]
        if let domainFilter, !domainFilter.isEmpty {
            data["domain"] = domainFilter
        }
        for (index, pair) in pairs.enumerated() {
            data["cookie_\(index)_name"] = pair.name
            data["cookie_\(index)_value"] = pair.value
        }
        return .ok(id: request.id, data: data)
    }

    private func handleBrowserCookiesSet(_ request: SocketRequest) -> SocketResponse {
        guard let name = request.params?["name"], !name.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: name")
        }
        guard let value = request.params?["value"] else {
            return .failure(id: request.id, error: "Missing required param: value")
        }
        guard Self.isSafeCookieName(name) else {
            return .failure(id: request.id, error: "Invalid cookie name")
        }
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let result = browserScriptResult(
            viewModel: viewModel,
            script: Self.browserSetCookieScript(
                name: name,
                value: value,
                path: request.params?["path"],
                domain: request.params?["domain"],
                secure: request.params?["secure"] == "true",
                sameSite: request.params?["same-site"],
                maxAge: request.params?["max-age"].flatMap(Int.init)
            ),
            requiresBridge: true
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }
        return .ok(id: request.id, data: ["status": "set", "name": name])
    }

    private func handleBrowserCookiesDelete(_ request: SocketRequest) -> SocketResponse {
        guard let name = request.params?["name"], !name.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: name")
        }
        guard Self.isSafeCookieName(name) else {
            return .failure(id: request.id, error: "Invalid cookie name")
        }
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }

        let result = browserScriptResult(
            viewModel: viewModel,
            script: Self.browserDeleteCookieScript(
                name: name,
                path: request.params?["path"],
                domain: request.params?["domain"]
            ),
            requiresBridge: true
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }
        return .ok(id: request.id, data: ["status": "deleted", "name": name])
    }

    private func handleBrowserNetwork(_ request: SocketRequest) -> SocketResponse {
        guard let viewModel = browserViewModelProvider() else {
            return .failure(id: request.id, error: "Browser panel not available")
        }
        let result = browserScriptResult(
            viewModel: viewModel,
            script: Self.browserNetworkScript,
            requiresBridge: true
        )
        if let error = result.error {
            return .failure(id: request.id, error: error)
        }
        let entries = Self.browserNetworkEntries(
            from: result.value ?? "[]",
            filter: request.params?["filter"],
            tail: request.params?["tail"].flatMap(Int.init)
        )
        var data: [String: String] = ["count": "\(entries.count)"]
        for (index, entry) in entries.enumerated() {
            data["entry_\(index)_url"] = entry.url
            data["entry_\(index)_method"] = entry.method
            data["entry_\(index)_initiatorType"] = entry.initiatorType
            data["entry_\(index)_duration"] = Self.browserNumberString(entry.duration)
            data["entry_\(index)_transferSize"] = "\(entry.transferSize)"
        }
        return .ok(id: request.id, data: data)
    }

    private func handleBrowserImport(kind: String, request: SocketRequest) -> SocketResponse {
        guard let provider = browserImportProvider else {
            return .failure(id: request.id, error: "Browser import is not available in this build.")
        }
        let result = provider(kind, request.params ?? [:])
        if result.success {
            return .ok(id: request.id, data: result.data)
        }
        return .failure(
            id: request.id,
            error: result.data["error"] ?? "Browser import \(kind) failed"
        )
    }

    private func browserScriptResult(
        viewModel: BrowserViewModel,
        script: String,
        requiresBridge: Bool,
        timeout: TimeInterval = 3
    ) -> BrowserScriptEvaluationResult {
        if let result = viewModel.automationBridge.evaluate(script: script, timeout: timeout) {
            return result
        }
        guard !requiresBridge else {
            return .failure("Browser page is not ready for synchronous automation")
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                viewModel.evaluateJavaScript(script)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    viewModel.evaluateJavaScript(script)
                }
            }
        }
        return .success("")
    }

    private static func isValidBrowserRef(_ ref: String) -> Bool {
        guard !ref.isEmpty, ref.count <= 64 else { return false }
        return ref.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    private static func browserClickScript(ref: String) -> String {
        """
        (function() {
            const element = document.querySelector('[data-cocxy-ref=\"\(ref)\"]');
            if (!element) { return 'not-found'; }
            element.scrollIntoView({block: 'center', inline: 'center'});
            element.click();
            return 'clicked';
        })();
        """
    }

    private static func browserFillScript(ref: String, text: String) -> String {
        let escapedText = javaScriptStringLiteral(text)
        return """
        (function() {
            const element = document.querySelector('[data-cocxy-ref=\"\(ref)\"]');
            if (!element) { return 'not-found'; }
            element.scrollIntoView({block: 'center', inline: 'center'});
            if (element.isContentEditable) {
                element.textContent = \(escapedText);
            } else {
                element.value = \(escapedText);
            }
            element.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: \(escapedText)}));
            element.dispatchEvent(new Event('change', {bubbles: true}));
            return 'filled';
        })();
        """
    }

    private static func browserWaitScript(selector: String) -> String {
        let escapedSelector = javaScriptStringLiteral(selector)
        return """
        (function() {
            try {
                return document.querySelector(\(escapedSelector)) ? 'found' : 'missing';
            } catch (error) {
                return 'missing';
            }
        })();
        """
    }

    private static func browserSetCookieScript(
        name: String,
        value: String,
        path: String?,
        domain: String?,
        secure: Bool,
        sameSite: String?,
        maxAge: Int?
    ) -> String {
        let cookie = cookieAssignment(
            name: name,
            value: value,
            path: path,
            domain: domain,
            secure: secure,
            sameSite: sameSite,
            maxAge: maxAge
        )
        return """
        (function() {
            document.cookie = \(javaScriptStringLiteral(cookie));
            return 'ok';
        })();
        """
    }

    private static func browserDeleteCookieScript(name: String, path: String?, domain: String?) -> String {
        let cookie = cookieAssignment(
            name: name,
            value: "",
            path: path,
            domain: domain,
            secure: false,
            sameSite: nil,
            maxAge: 0
        )
        return """
        (function() {
            document.cookie = \(javaScriptStringLiteral(cookie));
            return 'ok';
        })();
        """
    }

    private static func cookieAssignment(
        name: String,
        value: String,
        path: String?,
        domain: String?,
        secure: Bool,
        sameSite: String?,
        maxAge: Int?
    ) -> String {
        var parts = ["\(name)=\(value)"]
        if let path, !path.isEmpty { parts.append("Path=\(path)") }
        if let domain, !domain.isEmpty { parts.append("Domain=\(domain)") }
        if let maxAge { parts.append("Max-Age=\(maxAge)") }
        if secure { parts.append("Secure") }
        if let sameSite, !sameSite.isEmpty { parts.append("SameSite=\(sameSite)") }
        return parts.joined(separator: "; ")
    }

    private static func isSafeCookieName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 256 else { return false }
        return !name.contains { character in
            character == "=" || character == ";" || character.isWhitespace || character.isNewline
        }
    }

    private static func cookiePairs(from cookieString: String) -> [(name: String, value: String)] {
        cookieString
            .split(separator: ";", omittingEmptySubsequences: true)
            .compactMap { rawPair -> (name: String, value: String)? in
                let pair = rawPair.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = pair.firstIndex(of: "=") else { return nil }
                let name = String(pair[..<separator])
                let value = String(pair[pair.index(after: separator)...])
                guard !name.isEmpty else { return nil }
                return (name, value)
            }
    }

    private struct BrowserNetworkEntry {
        let url: String
        let method: String
        let initiatorType: String
        let duration: Double
        let transferSize: Int
    }

    private static var browserNetworkScript: String {
        """
        (function() {
            const entries = performance.getEntriesByType('resource').map(function(entry) {
                const initiatorType = entry.initiatorType || 'other';
                return {
                    url: entry.name || '',
                    method: (initiatorType === 'fetch' || initiatorType === 'xmlhttprequest') ? 'XHR' : 'GET',
                    initiatorType: initiatorType,
                    duration: entry.duration || 0,
                    transferSize: entry.transferSize || 0
                };
            });
            return JSON.stringify(entries);
        })();
        """
    }

    private static func browserNetworkEntries(
        from jsonString: String,
        filter: String?,
        tail: Int?
    ) -> [BrowserNetworkEntry] {
        guard let data = jsonString.data(using: .utf8),
              let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let normalizedFilter = filter?.lowercased()
        var entries = rawEntries.compactMap { raw -> BrowserNetworkEntry? in
            let url = (raw["url"] ?? raw["name"]) as? String ?? ""
            guard !url.isEmpty else { return nil }
            let method = raw["method"] as? String
                ?? (((raw["initiatorType"] as? String) == "fetch"
                    || (raw["initiatorType"] as? String) == "xmlhttprequest") ? "XHR" : "GET")
            let initiatorType = raw["initiatorType"] as? String ?? "other"
            let duration = raw["duration"] as? Double
                ?? (raw["duration"] as? Int).map(Double.init)
                ?? 0
            let transferSize = raw["transferSize"] as? Int
                ?? (raw["transferSize"] as? Double).map(Int.init)
                ?? 0
            return BrowserNetworkEntry(
                url: url,
                method: method,
                initiatorType: initiatorType,
                duration: duration,
                transferSize: transferSize
            )
        }
        if let normalizedFilter, !normalizedFilter.isEmpty {
            entries = entries.filter {
                $0.url.lowercased().contains(normalizedFilter)
                    || $0.method.lowercased().contains(normalizedFilter)
                    || $0.initiatorType.lowercased().contains(normalizedFilter)
            }
        }
        if let tail, tail > 0, entries.count > tail {
            entries = Array(entries.suffix(tail))
        }
        return entries
    }

    private static func browserNumberString(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.3f", value)
    }

    private static var browserSnapshotScript: String {
        """
        (function() {
            const selector = [
                'a[href]',
                'button',
                'input',
                'textarea',
                'select',
                '[role]',
                '[tabindex]',
                '[contenteditable="true"]'
            ].join(',');
            const visible = (element) => {
                const rect = element.getBoundingClientRect();
                const style = window.getComputedStyle(element);
                return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
            };
            const textFor = (element) => {
                return (
                    element.getAttribute('aria-label') ||
                    element.getAttribute('title') ||
                    element.innerText ||
                    element.value ||
                    element.getAttribute('placeholder') ||
                    ''
                ).trim().slice(0, 160);
            };
            const nodes = Array.from(document.querySelectorAll(selector)).filter(visible).slice(0, 500);
            return JSON.stringify(nodes.map((element, index) => {
                const cocxyRef = element.getAttribute('data-cocxy-ref') || `e${index + 1}`;
                element.setAttribute('data-cocxy-ref', cocxyRef);
                const rect = element.getBoundingClientRect();
                return {
                    ref: cocxyRef,
                    role: element.getAttribute('role') || element.tagName.toLowerCase(),
                    name: textFor(element),
                    x: Math.round(rect.x),
                    y: Math.round(rect.y),
                    width: Math.round(rect.width),
                    height: Math.round(rect.height)
                };
            }));
        })();
        """
    }

    private static func javaScriptStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        guard let data,
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "''"
        }
        return String(encoded.dropFirst().dropLast())
    }

    // MARK: - Plugin Handlers

    /// Lists all installed plugins with their enabled/disabled state.
    private func handlePluginList(_ request: SocketRequest) -> SocketResponse {
        let pluginData: [(id: String, name: String, enabled: Bool)]
        if Thread.isMainThread {
            pluginData = MainActor.assumeIsolated {
                guard let manager = self.pluginManagerProvider?() else { return [] }
                manager.scanPlugins()
                return manager.plugins.map { ($0.id, $0.manifest.name, $0.isEnabled) }
            }
        } else {
            pluginData = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let manager = self.pluginManagerProvider?() else { return [] }
                    manager.scanPlugins()
                    return manager.plugins.map { ($0.id, $0.manifest.name, $0.isEnabled) }
                }
            }
        }

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

        let resultMessage: String
        if Thread.isMainThread {
            resultMessage = MainActor.assumeIsolated {
                guard let manager = self.pluginManagerProvider?() else {
                    return "Plugin manager not initialized"
                }
                do {
                    try manager.enablePlugin(id: pluginID)
                    return "enabled"
                } catch {
                    return "Failed: \(error)"
                }
            }
        } else {
            resultMessage = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let manager = self.pluginManagerProvider?() else {
                        return "Plugin manager not initialized"
                    }
                    do {
                        try manager.enablePlugin(id: pluginID)
                        return "enabled"
                    } catch {
                        return "Failed: \(error)"
                    }
                }
            }
        }

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

        let resultMessage: String
        if Thread.isMainThread {
            resultMessage = MainActor.assumeIsolated {
                guard let manager = self.pluginManagerProvider?() else {
                    return "Plugin manager not initialized"
                }
                do {
                    try manager.disablePlugin(id: pluginID)
                    return "disabled"
                } catch {
                    return "Failed: \(error)"
                }
            }
        } else {
            resultMessage = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let manager = self.pluginManagerProvider?() else {
                        return "Plugin manager not initialized"
                    }
                    do {
                        try manager.disablePlugin(id: pluginID)
                        return "disabled"
                    } catch {
                        return "Failed: \(error)"
                    }
                }
            }
        }

        if resultMessage == "disabled" {
            return .ok(id: request.id, data: ["plugin": pluginID, "status": "disabled"])
        }
        return .failure(id: request.id, error: resultMessage)
    }

    /// Lists decentralized plugin source URLs configured on this Mac.
    private func handlePluginSourceList(_ request: SocketRequest) -> SocketResponse {
        do {
            let sources = try pluginSourceStoreProvider().load()
            var data: [String: String] = ["count": "\(sources.count)"]
            for (index, source) in sources.enumerated() {
                data["source_\(index)_id"] = source.id
                data["source_\(index)_url"] = source.url.absoluteString
                if let displayName = source.displayName {
                    data["source_\(index)_name"] = displayName
                }
            }
            return .ok(id: request.id, data: data)
        } catch {
            return .failure(id: request.id, error: "Failed to load plugin sources: \(error)")
        }
    }

    /// Adds a decentralized plugin source URL.
    private func handlePluginSourceAdd(_ request: SocketRequest) -> SocketResponse {
        guard let rawURL = request.params?["url"],
              let url = makePluginSourceURL(rawURL)
        else {
            return .failure(id: request.id, error: "Usage: plugin-source-add {\"url\": \"<url>\"}")
        }

        do {
            try pluginSourceStoreProvider().add(
                PluginSource(
                    url: url,
                    displayName: request.params?["name"]
                )
            )
            return .ok(id: request.id, data: ["url": url.absoluteString, "status": "added"])
        } catch {
            return .failure(id: request.id, error: "Failed to add plugin source: \(error)")
        }
    }

    /// Installs a plugin from a decentralized source URL or local repository path.
    private func handlePluginInstall(_ request: SocketRequest) -> SocketResponse {
        guard let rawURL = request.params?["url"],
              let url = makePluginSourceURL(rawURL)
        else {
            return .failure(id: request.id, error: "Usage: plugin-install {\"url\": \"<url-or-path>\"}")
        }

        let replace = request.params?["replace"] == "true"
        do {
            let receipt = try pluginInstallerProvider().install(from: url, replaceExisting: replace)
            refreshPluginManager()
            return .ok(
                id: request.id,
                data: [
                    "plugin": receipt.pluginID,
                    "path": receipt.installedURL.path,
                    "signature": String(describing: receipt.signatureStatus),
                    "status": "installed",
                ]
            )
        } catch {
            return .failure(id: request.id, error: "Failed to install plugin: \(error)")
        }
    }

    /// Uninstalls a local plugin by ID.
    private func handlePluginUninstall(_ request: SocketRequest) -> SocketResponse {
        guard let pluginID = request.params?["id"] else {
            return .failure(id: request.id, error: "Usage: plugin-uninstall {\"id\": \"<plugin-id>\"}")
        }

        do {
            try pluginInstallerProvider().uninstall(id: pluginID)
            refreshPluginManager()
            return .ok(id: request.id, data: ["plugin": pluginID, "status": "uninstalled"])
        } catch {
            return .failure(id: request.id, error: "Failed to uninstall plugin: \(error)")
        }
    }

    /// Lists persisted sandbox capability grants for one plugin.
    private func handleSandboxListGrants(_ request: SocketRequest) -> SocketResponse {
        guard let pluginID = request.params?["plugin"], !pluginID.isEmpty else {
            return .failure(
                id: request.id,
                error: "Usage: sandbox-list-grants {\"plugin\": \"<plugin-id>\"}"
            )
        }

        do {
            let grants = try pluginCapabilityGrantStoreProvider().grants(for: pluginID)
            let formatter = ISO8601DateFormatter()
            var data: [String: String] = [
                "plugin": pluginID,
                "count": "\(grants.count)",
            ]
            for (index, grant) in grants.enumerated() {
                data["grant_\(index)_capability"] = grant.capability.rawValue
                data["grant_\(index)_granted_at"] = formatter.string(from: grant.grantedAt)
                if let reason = grant.reason, !reason.isEmpty {
                    data["grant_\(index)_reason"] = reason
                }
            }
            return .ok(id: request.id, data: data)
        } catch {
            return .failure(id: request.id, error: "Failed to list sandbox grants: \(error)")
        }
    }

    /// Revokes one persisted sandbox capability grant for a plugin.
    private func handleSandboxRevoke(_ request: SocketRequest) -> SocketResponse {
        guard let pluginID = request.params?["plugin"], !pluginID.isEmpty else {
            return .failure(
                id: request.id,
                error: "Usage: sandbox-revoke {\"plugin\": \"<plugin-id>\", \"capability\": \"<capability>\"}"
            )
        }
        guard let rawCapability = request.params?["capability"], !rawCapability.isEmpty else {
            return .failure(
                id: request.id,
                error: "Usage: sandbox-revoke {\"plugin\": \"<plugin-id>\", \"capability\": \"<capability>\"}"
            )
        }
        guard let capability = PluginCapability(rawValue: rawCapability) else {
            return .failure(id: request.id, error: "Unknown plugin capability: \(rawCapability)")
        }

        do {
            try pluginCapabilityGrantStoreProvider().revoke(capability, for: pluginID)
            return .ok(id: request.id, data: [
                "plugin": pluginID,
                "capability": capability.rawValue,
                "status": "revoked",
            ])
        } catch {
            return .failure(id: request.id, error: "Failed to revoke sandbox grant: \(error)")
        }
    }

    private func makePluginSourceURL(_ rawValue: String) -> URL? {
        PluginSourceURLResolver.resolve(rawValue)
    }

    private func refreshPluginManager() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.pluginManagerProvider?()?.scanPlugins()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    self.pluginManagerProvider?()?.scanPlugins()
                }
            }
        }
    }

    // MARK: - Skill Handlers

    private func handleSkillList(_ request: SocketRequest) -> SocketResponse {
        let registry = skillRegistryProvider?() ?? SkillRegistry.localDefault()
        do {
            let skills = try registry.loadSkills()
            let snapshot = SkillListSnapshot(skills: skills)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            guard let content = String(data: data, encoding: .utf8) else {
                return .failure(id: request.id, error: "Failed to encode skill list")
            }
            return .ok(id: request.id, data: ["content": content])
        } catch {
            return .failure(id: request.id, error: "Failed to load skills: \(error.localizedDescription)")
        }
    }

    /// Lists decentralized skill source URLs configured on this Mac.
    private func handleSkillSourceList(_ request: SocketRequest) -> SocketResponse {
        do {
            let sources = try skillSourceStoreProvider().load()
            var data: [String: String] = ["count": "\(sources.count)"]
            for (index, source) in sources.enumerated() {
                data["source_\(index)_id"] = source.id
                data["source_\(index)_url"] = source.url.absoluteString
                if let displayName = source.displayName {
                    data["source_\(index)_name"] = displayName
                }
            }
            return .ok(id: request.id, data: data)
        } catch {
            return .failure(id: request.id, error: "Failed to load skill sources: \(error)")
        }
    }

    /// Adds a decentralized skill source URL.
    private func handleSkillSourceAdd(_ request: SocketRequest) -> SocketResponse {
        guard let rawURL = request.params?["url"],
              let url = PluginSourceURLResolver.resolve(rawURL)
        else {
            return .failure(id: request.id, error: "Usage: skill-source-add {\"url\": \"<url>\"}")
        }

        do {
            try skillSourceStoreProvider().add(
                SkillMarketplaceSource(
                    url: url,
                    displayName: request.params?["name"]
                )
            )
            return .ok(id: request.id, data: ["url": url.absoluteString, "status": "added"])
        } catch {
            return .failure(id: request.id, error: "Failed to add skill source: \(error)")
        }
    }

    /// Installs a skill from a decentralized source URL or local repository path.
    private func handleSkillInstall(_ request: SocketRequest) -> SocketResponse {
        guard let rawURL = request.params?["url"],
              let url = PluginSourceURLResolver.resolve(rawURL)
        else {
            return .failure(id: request.id, error: "Usage: skill-install {\"url\": \"<url-or-path>\"}")
        }

        let replace = request.params?["replace"] == "true"
        do {
            let receipt = try skillInstallerProvider().install(from: url, replaceExisting: replace)
            return .ok(
                id: request.id,
                data: [
                    "skill": receipt.skillID,
                    "path": receipt.installedURL.path,
                    "status": "installed",
                ]
            )
        } catch {
            return .failure(id: request.id, error: "Failed to install skill: \(error)")
        }
    }

    /// Uninstalls a local skill by ID.
    private func handleSkillUninstall(_ request: SocketRequest) -> SocketResponse {
        guard let skillID = request.params?["id"] else {
            return .failure(id: request.id, error: "Usage: skill-uninstall {\"id\": \"<skill-id>\"}")
        }

        do {
            try skillInstallerProvider().uninstall(id: skillID)
            return .ok(id: request.id, data: ["skill": skillID, "status": "uninstalled"])
        } catch {
            return .failure(id: request.id, error: "Failed to uninstall skill: \(error)")
        }
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
        let connectionStates: [UUID: RemoteConnectionManager.ConnectionState]
        if Thread.isMainThread {
            connectionStates = MainActor.assumeIsolated {
                if let manager = self.remoteConnectionManagerProvider?() {
                    return manager.connections
                }
                return [:]
            }
        } else {
            connectionStates = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    if let manager = self.remoteConnectionManagerProvider?() {
                        return manager.connections
                    }
                    return [:]
                }
            }
        }

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
        let stateSnapshot: (
            connectionStates: [UUID: RemoteConnectionManager.ConnectionState],
            supportMap: [UUID: RemoteShellSupport]
        )
        if Thread.isMainThread {
            stateSnapshot = MainActor.assumeIsolated {
                if let manager = self.remoteConnectionManagerProvider?() {
                    return (manager.connections, manager.remoteSupport)
                }
                return ([:], [:])
            }
        } else {
            stateSnapshot = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    if let manager = self.remoteConnectionManagerProvider?() {
                        return (manager.connections, manager.remoteSupport)
                    }
                    return ([:], [:])
                }
            }
        }
        let connectionStates = stateSnapshot.connectionStates
        let supportMap = stateSnapshot.supportMap

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
        let tunnelData: [[String: String]]
        if Thread.isMainThread {
            tunnelData = MainActor.assumeIsolated {
                guard let manager = self.remoteConnectionManagerProvider?() else { return [] }
                var tunnels: [[String: String]] = []
                for (profileID, state) in manager.connections {
                    if case .connected = state {
                        let sessions = manager.savedSessionRecords(profileID: profileID)
                        for session in sessions {
                            tunnels.append([
                                "profile_id": profileID.uuidString,
                                "session_name": session.sessionName,
                                "profile_title": session.profileDisplayTitle,
                            ])
                        }
                    }
                }
                return tunnels
            }
        } else {
            tunnelData = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let manager = self.remoteConnectionManagerProvider?() else { return [] }
                    var tunnels: [[String: String]] = []
                    for (profileID, state) in manager.connections {
                        if case .connected = state {
                            let sessions = manager.savedSessionRecords(profileID: profileID)
                            for session in sessions {
                                tunnels.append([
                                    "profile_id": profileID.uuidString,
                                    "session_name": session.sessionName,
                                    "profile_title": session.profileDisplayTitle,
                                ])
                            }
                        }
                    }
                    return tunnels
                }
            }
        }

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
    /// Optional params: `dir` (working directory path), `engine` (per-tab engine preference).
    private func handleWindowNew(_ request: SocketRequest) -> SocketResponse {
        let directoryPath = request.params?["dir"]
        let enginePreference = request.params?["engine"]

        if let path = directoryPath {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else {
                return .failure(id: request.id, error: "Directory does not exist: \(path)")
            }
        }
        if let enginePreference,
           TerminalEnginePreference(cliValue: enginePreference) == nil {
            return .failure(
                id: request.id,
                error: "Invalid engine. Use system, in-process, or daemon"
            )
        }

        guard let result = tabCreateWithEngineProvider(directoryPath, enginePreference) else {
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
        let windowData: [[String: String]]
        if Thread.isMainThread {
            windowData = MainActor.assumeIsolated {
                var windowsData: [[String: String]] = []
                for (index, window) in NSApplication.shared.windows.enumerated()
                    where window.isVisible {
                    let frame = window.frame
                    windowsData.append([
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
                return windowsData
            }
        } else {
            windowData = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    var windowsData: [[String: String]] = []
                    for (index, window) in NSApplication.shared.windows.enumerated()
                        where window.isVisible {
                        let frame = window.frame
                        windowsData.append([
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
                    return windowsData
                }
            }
        }

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
        let focused: Bool
        if Thread.isMainThread {
            focused = MainActor.assumeIsolated {
                let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible }
                if let indexStr = indexString, let index = Int(indexStr) {
                    guard index >= 0, index < visibleWindows.count else { return false }
                    visibleWindows[index].makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    return true
                } else {
                    let target = visibleWindows.first(where: { $0.isMainWindow })
                        ?? visibleWindows.first
                    target?.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    return target != nil
                }
            }
        } else {
            focused = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible }
                    if let indexStr = indexString, let index = Int(indexStr) {
                        guard index >= 0, index < visibleWindows.count else { return false }
                        visibleWindows[index].makeKeyAndOrderFront(nil)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        return true
                    } else {
                        let target = visibleWindows.first(where: { $0.isMainWindow })
                            ?? visibleWindows.first
                        target?.makeKeyAndOrderFront(nil)
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        return target != nil
                    }
                }
            }
        }

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

        let closeResult: (closed: Bool, errorMessage: String)
        if Thread.isMainThread {
            closeResult = MainActor.assumeIsolated {
                let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible }
                guard index >= 0, index < visibleWindows.count else {
                    return (false, "Window index out of range (0..<\(visibleWindows.count))")
                }
                guard visibleWindows.count > 1 else {
                    return (false, "Cannot close the last window")
                }
                visibleWindows[index].close()
                return (true, "")
            }
        } else {
            closeResult = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible }
                    guard index >= 0, index < visibleWindows.count else {
                        return (false, "Window index out of range (0..<\(visibleWindows.count))")
                    }
                    guard visibleWindows.count > 1 else {
                        return (false, "Cannot close the last window")
                    }
                    visibleWindows[index].close()
                    return (true, "")
                }
            }
        }

        if closeResult.closed {
            return .ok(id: request.id, data: ["status": "closed"])
        }
        return .failure(id: request.id, error: closeResult.errorMessage)
    }

    /// Toggles fullscreen on the key window.
    private func handleWindowFullscreen(_ request: SocketRequest) -> SocketResponse {
        let fullscreenResult: (toggled: Bool, isFullScreen: Bool)
        if Thread.isMainThread {
            fullscreenResult = MainActor.assumeIsolated {
                guard let window = NSApplication.shared.keyWindow
                    ?? NSApplication.shared.mainWindow else { return (false, false) }
                // toggleFullScreen is animated — styleMask updates AFTER the animation.
                // Report the INVERTED current state as the target state.
                let willBeFullScreen = !window.styleMask.contains(.fullScreen)
                window.toggleFullScreen(nil)
                return (true, willBeFullScreen)
            }
        } else {
            fullscreenResult = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let window = NSApplication.shared.keyWindow
                        ?? NSApplication.shared.mainWindow else { return (false, false) }
                    let willBeFullScreen = !window.styleMask.contains(.fullScreen)
                    window.toggleFullScreen(nil)
                    return (true, willBeFullScreen)
                }
            }
        }

        if fullscreenResult.toggled {
            return .ok(id: request.id, data: [
                "status": "toggled",
                "fullscreen": fullscreenResult.isFullScreen ? "true" : "false"
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

    /// Deletes a saved session by name, or deletes the unnamed auto-save
    /// session when `name` is omitted.
    private func handleSessionDelete(_ request: SocketRequest) -> SocketResponse {
        guard let sessionManager = sessionManagerProvider?() else {
            return .failure(id: request.id, error: "Session manager not available")
        }

        let name = request.params?["name"]

        do {
            try sessionManager.deleteSession(named: name)
            return .ok(id: request.id, data: [
                "status": "deleted",
                "name": name ?? "last",
            ])
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
        let filter = request.params?["filter"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let keys: [String]
        if let filter, !filter.isEmpty {
            keys = allConfigKeys.filter { $0.lowercased().hasPrefix(filter) }
        } else {
            keys = allConfigKeys
        }
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
        if let indexAStr = request.params?["indexA"],
           let indexBStr = request.params?["indexB"],
           let indexA = Int(indexAStr),
           let indexB = Int(indexBStr) {
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

        guard let direction = request.params?["direction"],
              NavigationDirection(commandValue: direction) != nil else {
            return .failure(
                id: request.id,
                error: "Missing or invalid params: indexA/indexB or direction (left|right|up|down)"
            )
        }
        guard let provider = splitSwapByDirectionProvider else {
            return .failure(id: request.id, error: "Split manager not available")
        }

        if provider(direction.lowercased()) {
            return .ok(id: request.id, data: [
                "status": "swapped",
                "direction": direction.lowercased()
            ])
        }
        return .failure(id: request.id, error: "No pane exists in that direction")
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

        let notifications: [CocxyNotification]
        if Thread.isMainThread {
            notifications = MainActor.assumeIsolated {
                guard let manager = managerProvider() else { return [] }
                return manager.allNotifications()
            }
        } else {
            notifications = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let manager = managerProvider() else { return [] }
                    return manager.allNotifications()
                }
            }
        }

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

        let remaining: Int
        if Thread.isMainThread {
            remaining = MainActor.assumeIsolated {
                guard let manager = managerProvider() else { return 0 }
                manager.markAllAsRead()
                return manager.unreadCount
            }
        } else {
            remaining = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let manager = managerProvider() else { return 0 }
                    manager.markAllAsRead()
                    return manager.unreadCount
                }
            }
        }

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
            "appearance.tab-position", "appearance.window-padding", "appearance.ligatures",
            "appearance.background-opacity", "appearance.background-blur-radius",
            "appearance.aurora-enabled", "appearance.rate-limit-indicator-enabled",
            "appearance.quickswitch-mode", "appearance.app-language",
            "rate-limit.enabled-providers", "rate-limit.auto-detect",
            "rate-limit.oauth-refresh-interval-minutes",
            "ux-polish.always-show-shortcut-hints", "ux-polish.shortcut-hint-debug-overlay",
            "ux-polish.shortcut-hint-offset-x", "ux-polish.shortcut-hint-offset-y",
            "ux-polish.shortcut-hint-scale",
            "command-corrections.enabled", "command-corrections.edit-distance-threshold",
            "command-corrections.foundation-models-enabled", "command-corrections.agent-fallback",
            "command-corrections.auto-show-on-failure", "command-corrections.show-confidence-badge",
            "command-corrections.max-suggestions-shown",
            "terminal.scrollback-lines", "terminal.cursor-style",
            "terminal.cursor-blink", "terminal.cursor-opacity",
            "terminal.mouse-hide-while-typing", "terminal.copy-on-select",
            "terminal.clipboard-paste-protection", "terminal.clipboard-read-access",
            "terminal.image-memory-limit-mb", "terminal.image-file-transfer",
            "terminal.enable-sixel-images", "terminal.enable-kitty-images",
            "terminal.enable-iterm2-images", "terminal.image-disk-cache-directory",
            "terminal.image-disk-cache-limit-mb",
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
            "worktree.enabled", "worktree.base-path", "worktree.branch-template",
            "worktree.base-ref", "worktree.on-close", "worktree.open-in-new-tab",
            "worktree.id-length", "worktree.inherit-project-config",
            "worktree.show-badge",
            "experimental.pip-enabled", "experimental.pty-daemon",
            "keybindings.new-tab", "keybindings.close-tab",
            "keybindings.next-tab", "keybindings.prev-tab",
            "keybindings.split-vertical", "keybindings.split-horizontal",
            "keybindings.goto-attention", "keybindings.toggle-quick-terminal",
            "sessions.auto-save", "sessions.auto-save-interval",
            "sessions.restore-on-launch",
            "notes.enabled", "notes.format", "notes.search-engine",
            "notes.storage-dir", "notes.shortcut", "notes.auto-save",
            "notes.auto-save-interval-seconds",
            "completions.inline-ai", "completions.provider",
            "completions.idle-delay-seconds",
            "completions.max-context-utf16-length",
            "completions.enabled-languages"
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

    // MARK: - Notebook Conversion

    private func handleNotebookImport(_ request: SocketRequest) -> SocketResponse {
        handleNotebookConversion(
            request,
            operationName: "imported",
            summaryPrefix: "Imported notebook to"
        ) { inputURL, outputURL in
            let data = try Data(contentsOf: inputURL)
            let notebook = try JupyterNotebookCodec.importDocument(from: data)
            let rendered = NotebookMarkdownCodec.render(notebook)
            try rendered.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    private func handleNotebookExport(_ request: SocketRequest) -> SocketResponse {
        handleNotebookConversion(
            request,
            operationName: "exported",
            summaryPrefix: "Exported notebook to"
        ) { inputURL, outputURL in
            let source = try String(contentsOf: inputURL, encoding: .utf8)
            let notebook = NotebookDocument.parseMarkdown(source)
            let data = try JupyterNotebookCodec.exportData(from: notebook)
            try data.write(to: outputURL, options: [.atomic])
        }
    }

    private func handleNotebookExportHTML(_ request: SocketRequest) -> SocketResponse {
        handleNotebookConversion(
            request,
            operationName: "exported-html",
            summaryPrefix: "Exported notebook HTML to"
        ) { inputURL, outputURL in
            let source = try String(contentsOf: inputURL, encoding: .utf8)
            let notebook = NotebookDocument.parseMarkdown(source)
            let html = NotebookHTMLExporter.render(notebook)
            try html.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    private func handleNotebookTemplateList(_ request: SocketRequest) -> SocketResponse {
        let templates = NotebookTemplateCatalog.builtInTemplates
        return .ok(id: request.id, data: [
            "status": "listed",
            "count": "\(templates.count)",
            "templates": templates.map(\.id).joined(separator: ","),
            "titles": templates.map(\.title).joined(separator: "|"),
            "summaries": templates.map(\.summary).joined(separator: "|")
        ])
    }

    private func handleNotebookTemplateCreate(_ request: SocketRequest) -> SocketResponse {
        guard let templateID = request.params?["template"], !templateID.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: template")
        }
        guard let outputPath = request.params?["output"], !outputPath.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: output")
        }
        guard let template = NotebookTemplateCatalog.template(id: templateID) else {
            return .failure(id: request.id, error: "Unknown notebook template: \(templateID)")
        }

        let outputURL = fileURL(fromCLIPath: outputPath)
        let force = request.params?["force"] == "true"
        if !force, FileManager.default.fileExists(atPath: outputURL.path) {
            return .failure(
                id: request.id,
                error: "Output file already exists: \(outputURL.path). Re-run with --force to replace it."
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try NotebookMarkdownCodec.render(template.document).write(
                to: outputURL,
                atomically: true,
                encoding: .utf8
            )
            return .ok(id: request.id, data: [
                "status": "created",
                "template": template.id,
                "output": outputURL.path,
                "summary": "Created notebook from template \(template.id) at \(outputURL.path)."
            ])
        } catch {
            return .failure(
                id: request.id,
                error: "Notebook template creation failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleNotebookRun(_ request: SocketRequest) -> SocketResponse {
        guard let inputPath = request.params?["input"], !inputPath.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: input")
        }

        let inputURL = fileURL(fromCLIPath: inputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return .failure(id: request.id, error: "Input file does not exist: \(inputURL.path)")
        }

        let outputURL = request.params?["output"].flatMap { outputPath -> URL? in
            guard !outputPath.isEmpty else { return nil }
            return fileURL(fromCLIPath: outputPath)
        } ?? inputURL

        let workingDirectory = request.params?["cwd"].flatMap { cwd -> URL? in
            guard !cwd.isEmpty else { return nil }
            return fileURL(fromCLIPath: cwd)
        } ?? inputURL.deletingLastPathComponent()

        guard directoryExists(at: workingDirectory) else {
            return .failure(
                id: request.id,
                error: "Working directory does not exist: \(workingDirectory.path)"
            )
        }

        let timeoutSeconds: TimeInterval?
        if let rawTimeout = request.params?["timeout"], !rawTimeout.isEmpty {
            guard let parsedTimeout = Double(rawTimeout), parsedTimeout > 0 else {
                return .failure(id: request.id, error: "Timeout must be a positive number of seconds.")
            }
            timeoutSeconds = parsedTimeout
        } else {
            timeoutSeconds = nil
        }

        let stopOnFailure = request.params?["continue-on-failure"] != "true"
        let sandbox: NotebookSandboxPolicy
        if let rawSandbox = request.params?["sandbox"], !rawSandbox.isEmpty {
            guard let parsedSandbox = NotebookSandboxPolicy(rawValue: rawSandbox) else {
                return .failure(
                    id: request.id,
                    error: "Sandbox must be one of: workspace, none."
                )
            }
            sandbox = parsedSandbox
        } else {
            sandbox = .workspace
        }

        do {
            let source = try String(contentsOf: inputURL, encoding: .utf8)
            let notebook = NotebookDocument.parseMarkdown(source)
            let summary = try NotebookExecutor().execute(
                notebook,
                workingDirectory: workingDirectory,
                timeoutSeconds: timeoutSeconds ?? 60,
                sandbox: sandbox,
                stopOnFailure: stopOnFailure
            )
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try NotebookMarkdownCodec.render(summary.document).write(
                to: outputURL,
                atomically: true,
                encoding: .utf8
            )

            let failedResult = summary.results.first { !$0.succeeded }
            let status = failedResult == nil ? "completed" : "failed"
            var data = [
                "status": status,
                "input": inputURL.path,
                "output": outputURL.path,
                "sandbox": sandbox.rawValue,
                "executed-cells": "\(summary.executedCellIndices.count)",
                "summary": notebookRunSummary(
                    executedCells: summary.executedCellIndices.count,
                    failedCellIndex: failedResult?.cellIndex
                )
            ]
            if let failedResult {
                data["failed-cell-index"] = "\(failedResult.cellIndex)"
                data["exit-code"] = "\(failedResult.exitCode)"
            }
            return .ok(id: request.id, data: data)
        } catch {
            return .failure(
                id: request.id,
                error: "Notebook execution failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleWorkflowRun(_ request: SocketRequest) -> SocketResponse {
        guard let inputPath = request.params?["input"], !inputPath.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: input")
        }

        let inputURL = fileURL(fromCLIPath: inputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return .failure(id: request.id, error: "Input file does not exist: \(inputURL.path)")
        }

        let workspaceRoot = request.params?["cwd"].flatMap { cwd -> URL? in
            guard !cwd.isEmpty else { return nil }
            return fileURL(fromCLIPath: cwd)
        } ?? inputURL.deletingLastPathComponent()

        guard directoryExists(at: workspaceRoot) else {
            return .failure(
                id: request.id,
                error: "Working directory does not exist: \(workspaceRoot.path)"
            )
        }

        do {
            let source = try String(contentsOf: inputURL, encoding: .utf8)
            let workflow = try WorkflowTOMLCodec.parse(source)
            let summary = try WorkflowExecutor().execute(workflow, workspaceRoot: workspaceRoot)
            var data = [
                "status": workflowStatusString(summary.status),
                "workflow": summary.workflowID,
                "steps": "\(summary.results.count)",
                "stdout": socketPreview(summary.results.map(\.stdout).joined()),
                "stderr": socketPreview(summary.results.map(\.stderr).joined()),
                "summary": workflowRunSummary(summary)
            ]
            if case .failed(let stepID, let exitCode) = summary.status {
                data["failed-step"] = stepID
                data["exit-code"] = "\(exitCode)"
            }
            return .ok(id: request.id, data: data)
        } catch {
            return .failure(
                id: request.id,
                error: "Workflow execution failed: \(error.localizedDescription)"
            )
        }
    }

    private func notebookRunSummary(executedCells: Int, failedCellIndex: Int?) -> String {
        let noun = executedCells == 1 ? "cell" : "cells"
        if let failedCellIndex {
            return "Notebook execution failed at cell \(failedCellIndex) after \(executedCells) \(noun)."
        }
        return "Executed \(executedCells) notebook \(noun)."
    }

    private func workflowStatusString(_ status: WorkflowExecutionStatus) -> String {
        switch status {
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        }
    }

    private func workflowRunSummary(_ summary: WorkflowExecutionSummary) -> String {
        let noun = summary.results.count == 1 ? "step" : "steps"
        switch summary.status {
        case .completed:
            return "Workflow \(summary.workflowID) completed after \(summary.results.count) \(noun)."
        case .failed(let stepID, let exitCode):
            return "Workflow \(summary.workflowID) failed at step \(stepID) with exit code \(exitCode)."
        }
    }

    private func handleNotebookConversion(
        _ request: SocketRequest,
        operationName: String,
        summaryPrefix: String,
        convert: (URL, URL) throws -> Void
    ) -> SocketResponse {
        guard let inputPath = request.params?["input"], !inputPath.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: input")
        }
        guard let outputPath = request.params?["output"], !outputPath.isEmpty else {
            return .failure(id: request.id, error: "Missing required param: output")
        }

        let inputURL = fileURL(fromCLIPath: inputPath)
        let outputURL = fileURL(fromCLIPath: outputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return .failure(id: request.id, error: "Input file does not exist: \(inputURL.path)")
        }

        let force = request.params?["force"] == "true"
        if !force, FileManager.default.fileExists(atPath: outputURL.path) {
            return .failure(
                id: request.id,
                error: "Output file already exists: \(outputURL.path). Re-run with --force to replace it."
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try convert(inputURL, outputURL)
            return .ok(id: request.id, data: [
                "status": operationName,
                "input": inputURL.path,
                "output": outputURL.path,
                "summary": "\(summaryPrefix) \(outputURL.path)."
            ])
        } catch {
            return .failure(
                id: request.id,
                error: "Notebook conversion failed: \(error.localizedDescription)"
            )
        }
    }

    private func fileURL(fromCLIPath path: String) -> URL {
        let expandedPath: String
        if path == "~" {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser.path
        } else if path.hasPrefix("~/") {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .path
        } else {
            expandedPath = path
        }
        return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func socketPreview(_ value: String, maxCharacters: Int = 8_192) -> String {
        guard value.count > maxCharacters else { return value }
        return String(value.prefix(maxCharacters)) + "\n[truncated]\n"
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

    // MARK: - Worktree (v0.1.81)

    /// Routes `cocxy worktree-add` to the injected provider. Payload
    /// keys match the flag names accepted by the CLI so the
    /// AppDelegate-side implementation can work from a flat dictionary
    /// without reparsing the socket request.
    private func handleWorktreeAdd(_ request: SocketRequest) -> SocketResponse {
        runWorktreeProvider(kind: "add", request: request)
    }

    /// Routes `cocxy worktree-list`. The provider returns a JSON
    /// payload under `data["entries"]` so the CLI can pretty-print it
    /// without the handler having to deserialise anything.
    private func handleWorktreeList(_ request: SocketRequest) -> SocketResponse {
        runWorktreeProvider(kind: "list", request: request)
    }

    /// Routes `cocxy worktree-focus`. The provider resolves the
    /// worktree id through the manifest, focuses an attached tab when
    /// one exists, or opens a new tab at the worktree root otherwise.
    private func handleWorktreeFocus(_ request: SocketRequest) -> SocketResponse {
        runWorktreeProvider(kind: "focus", request: request)
    }

    /// Routes `cocxy worktree-remove`. The id is required; `force`
    /// defaults to `false` when absent so a dirty worktree is refused
    /// by default — matching the `on-close = keep` safety stance.
    private func handleWorktreeRemove(_ request: SocketRequest) -> SocketResponse {
        runWorktreeProvider(kind: "remove", request: request)
    }

    /// Routes `cocxy worktree-prune`. No params; the provider returns
    /// the list of removed ids under `data["pruned"]`.
    private func handleWorktreePrune(_ request: SocketRequest) -> SocketResponse {
        runWorktreeProvider(kind: "prune", request: request)
    }

    /// Routes merged-worktree cleanup through the same provider used by
    /// the interactive Worktree UI. `dry-run=true` returns counts without
    /// deleting anything; the default path performs the preflight then
    /// removes only clean merged worktrees.
    private func handleWorktreeCleanupMerged(_ request: SocketRequest) -> SocketResponse {
        runWorktreeProvider(kind: "cleanup-merged", request: request)
    }

    /// Shared dispatch used by every worktree verb. Keeping the four
    /// handler methods thin makes the CLI-parity test easy to read
    /// and removes any chance of one verb accidentally calling another
    /// verb's provider.
    private func runWorktreeProvider(
        kind: String,
        request: SocketRequest
    ) -> SocketResponse {
        guard let provider = worktreeCLIProvider else {
            return .failure(
                id: request.id,
                error: "Worktree CLI is not yet wired in this build."
            )
        }
        let result = provider(kind, request.params ?? [:])
        if result.success {
            return .ok(id: request.id, data: result.data)
        }
        let message = result.data["error"]
            ?? "Worktree \(kind) failed"
        return .failure(id: request.id, error: message)
    }

    /// Shared dispatch used by every `github-*` verb. Mirrors the
    /// worktree handler so both CLI surfaces share a single audit
    /// trail. The AppDelegate-side bridge is responsible for routing
    /// `kind` into the matching `GitHubService` call.
    func handleGitHubCLI(kind: String, request: SocketRequest) -> SocketResponse {
        guard let provider = githubCLIProvider else {
            return .failure(
                id: request.id,
                error: "GitHub CLI is not yet wired in this build."
            )
        }
        let result = provider(kind, request.params ?? [:])
        if result.success {
            return .ok(id: request.id, data: result.data)
        }
        let message = result.data["error"]
            ?? "GitHub \(kind) failed"
        return .failure(id: request.id, error: message)
    }

    /// Shared dispatch used by every `git-assistant-*` verb. The
    /// AppDelegate-side bridge owns provider construction and Git diff
    /// collection so the socket handler remains a pure router.
    func handleGitAssistantCLI(kind: String, request: SocketRequest) -> SocketResponse {
        guard let provider = gitAssistantCLIProvider else {
            return .failure(
                id: request.id,
                error: "Git Assistant CLI is not yet wired in this build."
            )
        }
        let result = provider(kind, request.params ?? [:])
        if result.success {
            return .ok(id: request.id, data: result.data)
        }
        let message = result.data["error"]
            ?? "Git Assistant \(kind) failed"
        return .failure(id: request.id, error: message)
    }
}
