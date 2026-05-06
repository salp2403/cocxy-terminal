// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLaunchSignpostsSwiftTestingTests.swift - Cold-start signpost catalog coverage.

import Testing
@testable import CocxyTerminal

@Suite("App launch cold-start signposts", .serialized)
struct AppLaunchSignpostsSwiftTestingTests {

    @Test("catalog covers the launch phases called by AppDelegate")
    func catalogCoversExpectedLaunchPhases() {
        let labels = Set(AppLaunchStep.allCases.map(\.label))

        #expect(labels == [
            "Bundled fonts",
            "Theme engine",
            "Config service",
            "Config watcher",
            "Session manager",
            "Menu setup",
            "Keybindings",
            "Terminal bridge",
            "Agent detection engine",
            "Session registry",
            "Main window",
            "Agent wiring",
            "Notifications",
            "Port scanner",
            "Window warm-up",
            "Plugins",
            "Socket server",
            "Quick terminal",
            "Appearance observer",
            "Remote workspace",
            "Browser Pro",
            "Auto update",
            "Crash recovery",
            "Session restore",
            "Session auto-save",
            "Local backup",
            "App icon",
            "First launch setup",
            "Welcome",
            "Menu bar",
        ])
    }

    @Test("measure returns the wrapped value without changing control flow")
    func measureReturnsWrappedValue() {
        let value = AppLaunchSignposts.measure(.configService) { 42 }

        #expect(value == 42)
    }

    @Test("measure records app-owned launch step durations for local diagnostics")
    func measureRecordsLaunchStepDurations() {
        AppLaunchTimingRecorder.resetForTesting()

        let value = AppLaunchSignposts.measure(.configService) { 42 }
        let snapshot = AppLaunchTimingRecorder.snapshot(pendingDeferredWarmupBatches: [])

        #expect(value == 42)
        #expect(snapshot.recordedSteps.contains(.configService))
        #expect(snapshot.durationNanoseconds(for: .configService) != nil)
        #expect(snapshot.statusFields()["launch_critical_path_budget_ms"] == "50")
    }

    @Test("timing snapshot reports pending warmup and the slowest recorded launch step")
    func timingSnapshotReportsPendingWarmupAndSlowestStep() {
        AppLaunchTimingRecorder.resetForTesting()
        AppLaunchTimingRecorder.record(.configService, durationNanoseconds: 1_000_000)
        AppLaunchTimingRecorder.record(.mainWindow, durationNanoseconds: 3_500_000)
        AppLaunchTimingRecorder.record(.sessionRestore, durationNanoseconds: 5_000_000)

        let snapshot = AppLaunchTimingRecorder.snapshot(
            pendingDeferredWarmupBatches: [[.sessionRestore], [.plugins, .quickTerminal]]
        )
        let fields = snapshot.statusFields()

        #expect(snapshot.recordedSteps == [.configService, .mainWindow, .sessionRestore])
        #expect(snapshot.pendingDeferredWarmupSteps == 3)
        #expect(fields["launch_slowest_step"] == "Session restore")
        #expect(fields["launch_slowest_step_ms"] == "5.00")
        #expect(fields["launch_critical_slowest_step"] == "Main window")
        #expect(fields["launch_critical_slowest_step_ms"] == "3.50")
        #expect(fields["launch_deferred_pending"] == "3")
    }

    @Test("critical path and deferred warm-up partition the launch catalog")
    func launchStepPartitionsCoverCatalogExactlyOnce() {
        let critical = Set(AppLaunchStep.criticalPathSteps)
        let deferred = Set(AppLaunchStep.deferredWarmupSteps)

        #expect(critical.isDisjoint(with: deferred))
        #expect(critical.union(deferred) == Set(AppLaunchStep.allCases))
    }

    @Test("session restore and secondary services stay off the socket-ready critical path")
    func warmupWorkIsDeferredPastSocketReadiness() {
        #expect(AppLaunchStep.criticalPathSteps.last == .socketServer)
        #expect(!AppLaunchStep.criticalPathSteps.contains(.sessionRestore))
        #expect(!AppLaunchStep.criticalPathSteps.contains(.windowWarmup))
        #expect(!AppLaunchStep.criticalPathSteps.contains(.configWatcher))
        #expect(!AppLaunchStep.criticalPathSteps.contains(.bundledFonts))
        #expect(!AppLaunchStep.criticalPathSteps.contains(.remoteWorkspace))
        #expect(AppLaunchStep.deferredWarmupSteps.first == .windowWarmup)
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.windowWarmup))
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.sessionRestore))
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.configWatcher))
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.bundledFonts))
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.remoteWorkspace))
    }

    @Test("first visual warm-up batch reaches restored shell without extra run-loop gaps")
    func firstVisualWarmupBatchReachesRestoredShellWithoutExtraRunLoopGaps() {
        let batches = AppLaunchStep.deferredWarmupRunLoopBatches
        let flattened = batches.flatMap { $0 }

        #expect(flattened == AppLaunchStep.deferredWarmupSteps)
        #expect(batches.first == [.windowWarmup, .crashRecovery, .sessionRestore])
        #expect(batches.dropFirst().allSatisfy { $0.count == 1 })
        #expect(flattened.last == .menuBar)
    }

    @Test("window setup runs before bundled fonts so the first shell paints promptly")
    func windowWarmupRunsBeforeBundledFonts() throws {
        let steps = AppLaunchStep.deferredWarmupSteps

        let windowWarmup = try #require(steps.firstIndex(of: .windowWarmup))
        let bundledFonts = try #require(steps.firstIndex(of: .bundledFonts))

        #expect(windowWarmup < bundledFonts)
    }

    @Test("session restore precedes secondary services that do not paint the first shell")
    func sessionRestoreRunsBeforeNonVisualWarmup() throws {
        let steps = AppLaunchStep.deferredWarmupSteps

        let windowWarmup = try #require(steps.firstIndex(of: .windowWarmup))
        let crashRecovery = try #require(steps.firstIndex(of: .crashRecovery))
        let sessionRestore = try #require(steps.firstIndex(of: .sessionRestore))
        let configWatcher = try #require(steps.firstIndex(of: .configWatcher))
        let bundledFonts = try #require(steps.firstIndex(of: .bundledFonts))
        let menuSetup = try #require(steps.firstIndex(of: .menuSetup))
        let keybindings = try #require(steps.firstIndex(of: .keybindings))
        let plugins = try #require(steps.firstIndex(of: .plugins))
        let remoteWorkspace = try #require(steps.firstIndex(of: .remoteWorkspace))

        #expect(windowWarmup < sessionRestore)
        #expect(crashRecovery < sessionRestore)
        #expect(sessionRestore < configWatcher)
        #expect(sessionRestore < bundledFonts)
        #expect(sessionRestore < menuSetup)
        #expect(sessionRestore < keybindings)
        #expect(sessionRestore < plugins)
        #expect(sessionRestore < remoteWorkspace)
    }
}
