// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLaunchSignposts.swift - Cold-start signposts for app launch analysis.

import Foundation
import os.signpost

/// App-owned launch phases that can be profiled independently from
/// LaunchServices, AppKit process startup, and CLI socket round trips.
enum AppLaunchStep: CaseIterable, Equatable, Sendable {
    case bundledFonts
    case themeEngine
    case configService
    case configWatcher
    case sessionManager
    case menuSetup
    case keybindings
    case bridge
    case agentDetectionEngine
    case sessionRegistry
    case mainWindow
    case agentWiring
    case notifications
    case portScanner
    case windowWarmup
    case plugins
    case socketServer
    case quickTerminal
    case appearanceObserver
    case remoteWorkspace
    case browserPro
    case autoUpdate
    case crashRecovery
    case sessionRestore
    case autoSave
    case backup
    case appIcon
    case firstLaunch
    case welcome
    case menuBar

    var label: String {
        switch self {
        case .bundledFonts: return "Bundled fonts"
        case .themeEngine: return "Theme engine"
        case .configService: return "Config service"
        case .configWatcher: return "Config watcher"
        case .sessionManager: return "Session manager"
        case .menuSetup: return "Menu setup"
        case .keybindings: return "Keybindings"
        case .bridge: return "Terminal bridge"
        case .agentDetectionEngine: return "Agent detection engine"
        case .sessionRegistry: return "Session registry"
        case .mainWindow: return "Main window"
        case .agentWiring: return "Agent wiring"
        case .notifications: return "Notifications"
        case .portScanner: return "Port scanner"
        case .windowWarmup: return "Window warm-up"
        case .plugins: return "Plugins"
        case .socketServer: return "Socket server"
        case .quickTerminal: return "Quick terminal"
        case .appearanceObserver: return "Appearance observer"
        case .remoteWorkspace: return "Remote workspace"
        case .browserPro: return "Browser Pro"
        case .autoUpdate: return "Auto update"
        case .crashRecovery: return "Crash recovery"
        case .sessionRestore: return "Session restore"
        case .autoSave: return "Session auto-save"
        case .backup: return "Local backup"
        case .appIcon: return "App icon"
        case .firstLaunch: return "First launch setup"
        case .welcome: return "Welcome"
        case .menuBar: return "Menu bar"
        }
    }

    /// Launch phases that must complete before the CLI socket is ready.
    ///
    /// Keep this list minimal. Anything that can run after the first main
    /// run-loop turn belongs in `deferredWarmupSteps` so app launch remains
    /// responsive even when session restore or secondary services are slow.
    static let criticalPathSteps: [AppLaunchStep] = [
        .themeEngine,
        .configService,
        .configWatcher,
        .sessionManager,
        .bridge,
        .agentDetectionEngine,
        .sessionRegistry,
        .mainWindow,
        .agentWiring,
        .notifications,
        .socketServer,
    ]

    /// Launch phases that are required for full functionality but do not
    /// need to block socket readiness or the first visible window.
    static let deferredWarmupSteps: [AppLaunchStep] = [
        .bundledFonts,
        .windowWarmup,
        .crashRecovery,
        .sessionRestore,
        .menuSetup,
        .keybindings,
        .autoSave,
        .backup,
        .portScanner,
        .plugins,
        .quickTerminal,
        .appearanceObserver,
        .remoteWorkspace,
        .browserPro,
        .autoUpdate,
        .appIcon,
        .firstLaunch,
        .welcome,
        .menuBar,
    ]

    /// Warm-up work is intentionally sliced across main-run-loop turns.
    /// A single deferred block keeps socket readiness fast but can still
    /// make the first restored window feel frozen while restore, plugins,
    /// update checks and menu work run back-to-back.
    static let deferredWarmupRunLoopBatches: [[AppLaunchStep]] =
        deferredWarmupSteps.map { [$0] }

    var signpostName: StaticString {
        switch self {
        case .bundledFonts: return "Bundled fonts"
        case .themeEngine: return "Theme engine"
        case .configService: return "Config service"
        case .configWatcher: return "Config watcher"
        case .sessionManager: return "Session manager"
        case .menuSetup: return "Menu setup"
        case .keybindings: return "Keybindings"
        case .bridge: return "Terminal bridge"
        case .agentDetectionEngine: return "Agent detection engine"
        case .sessionRegistry: return "Session registry"
        case .mainWindow: return "Main window"
        case .agentWiring: return "Agent wiring"
        case .notifications: return "Notifications"
        case .portScanner: return "Port scanner"
        case .windowWarmup: return "Window warm-up"
        case .plugins: return "Plugins"
        case .socketServer: return "Socket server"
        case .quickTerminal: return "Quick terminal"
        case .appearanceObserver: return "Appearance observer"
        case .remoteWorkspace: return "Remote workspace"
        case .browserPro: return "Browser Pro"
        case .autoUpdate: return "Auto update"
        case .crashRecovery: return "Crash recovery"
        case .sessionRestore: return "Session restore"
        case .autoSave: return "Session auto-save"
        case .backup: return "Local backup"
        case .appIcon: return "App icon"
        case .firstLaunch: return "First launch setup"
        case .welcome: return "Welcome"
        case .menuBar: return "Menu bar"
        }
    }
}

enum AppLaunchSignposts {
    private static let log = OSLog(
        subsystem: "dev.cocxy.terminal",
        category: "cold-start"
    )

    @discardableResult
    static func measure<T>(_ step: AppLaunchStep, _ work: () throws -> T) rethrows -> T {
        os_signpost(.begin, log: log, name: step.signpostName)
        defer { os_signpost(.end, log: log, name: step.signpostName) }
        return try work()
    }
}
