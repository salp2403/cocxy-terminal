// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLaunchSignpostsSwiftTestingTests.swift - Cold-start signpost catalog coverage.

import Testing
@testable import CocxyTerminal

@Suite("App launch cold-start signposts")
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
        #expect(!AppLaunchStep.criticalPathSteps.contains(.bundledFonts))
        #expect(!AppLaunchStep.criticalPathSteps.contains(.remoteWorkspace))
        #expect(AppLaunchStep.deferredWarmupSteps.first == .bundledFonts)
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.windowWarmup))
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.sessionRestore))
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.bundledFonts))
        #expect(AppLaunchStep.deferredWarmupSteps.contains(.remoteWorkspace))
    }
}
