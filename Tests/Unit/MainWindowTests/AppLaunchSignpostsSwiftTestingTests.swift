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
            "Plugins",
            "Socket server",
            "Quick terminal",
            "Appearance observer",
            "Remote workspace",
            "Browser Pro",
            "Auto update",
            "Session restore",
            "Session auto-save",
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
}
