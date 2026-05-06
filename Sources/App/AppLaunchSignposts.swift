// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLaunchSignposts.swift - Cold-start signposts for app launch analysis.

import Foundation
import CocxyShared
import os.signpost

/// App-owned launch phases that can be profiled independently from
/// LaunchServices, AppKit process startup, and CLI socket round trips.
enum AppLaunchStep: CaseIterable, Equatable, Hashable, Sendable {
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
        .windowWarmup,
        .crashRecovery,
        .sessionRestore,
        .configWatcher,
        .bundledFonts,
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
    ///
    /// Keep the first visual restore path together so a reopened window
    /// reaches its restored shell without artificial gaps between the
    /// scaffold, crash snapshot load, and session surface materialization.
    /// Secondary services stay one-per-turn after that first paint path.
    static let deferredWarmupRunLoopBatches: [[AppLaunchStep]] = [
        [.windowWarmup, .crashRecovery, .sessionRestore],
    ] + deferredWarmupSteps.dropFirst(3).map { [$0] }

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

struct AppLaunchTimingSnapshot: Equatable, Sendable {
    let durationsNanoseconds: [AppLaunchStep: UInt64]
    let pendingDeferredWarmupSteps: Int

    var recordedSteps: [AppLaunchStep] {
        AppLaunchStep.allCases.filter { durationsNanoseconds[$0] != nil }
    }

    var completedDeferredWarmupSteps: Int {
        max(0, AppLaunchStep.deferredWarmupSteps.count - pendingDeferredWarmupSteps)
    }

    var criticalPathNanoseconds: UInt64 {
        AppLaunchStep.criticalPathSteps.reduce(UInt64(0)) { total, step in
            total + (durationsNanoseconds[step] ?? 0)
        }
    }

    var slowestStep: (step: AppLaunchStep, durationNanoseconds: UInt64)? {
        recordedSteps
            .compactMap { step -> (AppLaunchStep, UInt64)? in
                guard let duration = durationsNanoseconds[step] else { return nil }
                return (step, duration)
            }
            .max { lhs, rhs in
                lhs.1 < rhs.1
            }
    }

    var slowestCriticalPathStep: (step: AppLaunchStep, durationNanoseconds: UInt64)? {
        AppLaunchStep.criticalPathSteps
            .compactMap { step -> (AppLaunchStep, UInt64)? in
                guard let duration = durationsNanoseconds[step] else { return nil }
                return (step, duration)
            }
            .max { lhs, rhs in
                lhs.1 < rhs.1
            }
    }

    func durationNanoseconds(for step: AppLaunchStep) -> UInt64? {
        durationsNanoseconds[step]
    }

    func statusFields() -> [String: String] {
        var fields: [String: String] = [
            "launch_status": pendingDeferredWarmupSteps == 0 ? "ready" : "warming",
            "launch_recorded_steps": "\(recordedSteps.count)",
            "launch_critical_path_ms": Self.formatMilliseconds(criticalPathNanoseconds),
            "launch_critical_path_budget_ms": Self.formatMilliseconds(
                UInt64(ColdStartBudget.internalCriticalPathBudgetMilliseconds * 1_000_000),
                trimIntegerFraction: true
            ),
            "launch_deferred_completed": "\(completedDeferredWarmupSteps)",
            "launch_deferred_pending": "\(pendingDeferredWarmupSteps)",
            "launch_deferred_total": "\(AppLaunchStep.deferredWarmupSteps.count)"
        ]

        if let slowestStep {
            fields["launch_slowest_step"] = slowestStep.step.label
            fields["launch_slowest_step_ms"] = Self.formatMilliseconds(slowestStep.durationNanoseconds)
        }
        if let slowestCriticalPathStep {
            fields["launch_critical_slowest_step"] = slowestCriticalPathStep.step.label
            fields["launch_critical_slowest_step_ms"] = Self.formatMilliseconds(
                slowestCriticalPathStep.durationNanoseconds
            )
        }
        return fields
    }

    private static func formatMilliseconds(
        _ nanoseconds: UInt64,
        trimIntegerFraction: Bool = false
    ) -> String {
        let milliseconds = Double(nanoseconds) / 1_000_000
        if trimIntegerFraction, milliseconds.rounded() == milliseconds {
            return String(format: "%.0f", milliseconds)
        }
        return String(format: "%.2f", milliseconds)
    }
}

private final class AppLaunchTimingStore: @unchecked Sendable {
    private let lock = NSLock()
    private var durationsNanoseconds: [AppLaunchStep: UInt64] = [:]

    func record(_ step: AppLaunchStep, durationNanoseconds: UInt64) {
        lock.lock()
        durationsNanoseconds[step, default: 0] += durationNanoseconds
        lock.unlock()
    }

    func snapshot(
        pendingDeferredWarmupBatches: [[AppLaunchStep]]
    ) -> AppLaunchTimingSnapshot {
        lock.lock()
        let durations = durationsNanoseconds
        lock.unlock()
        return AppLaunchTimingSnapshot(
            durationsNanoseconds: durations,
            pendingDeferredWarmupSteps: pendingDeferredWarmupBatches.reduce(0) { total, batch in
                total + batch.count
            }
        )
    }

    func reset() {
        lock.lock()
        durationsNanoseconds.removeAll()
        lock.unlock()
    }
}

enum AppLaunchTimingRecorder {
    private static let store = AppLaunchTimingStore()

    static func record(_ step: AppLaunchStep, durationNanoseconds: UInt64) {
        store.record(step, durationNanoseconds: durationNanoseconds)
    }

    static func snapshot(
        pendingDeferredWarmupBatches: [[AppLaunchStep]]
    ) -> AppLaunchTimingSnapshot {
        store.snapshot(pendingDeferredWarmupBatches: pendingDeferredWarmupBatches)
    }

    static func resetForTesting() {
        store.reset()
    }
}

enum AppLaunchSignposts {
    private static let log = OSLog(
        subsystem: "dev.cocxy.terminal",
        category: "cold-start"
    )

    @discardableResult
    static func measure<T>(_ step: AppLaunchStep, _ work: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        os_signpost(.begin, log: log, name: step.signpostName)
        defer {
            AppLaunchTimingRecorder.record(
                step,
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - start
            )
            os_signpost(.end, log: log, name: step.signpostName)
        }
        return try work()
    }
}
