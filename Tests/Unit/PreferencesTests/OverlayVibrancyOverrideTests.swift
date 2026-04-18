// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OverlayVibrancyOverrideTests.swift - Tests that the transparency chrome
// theme override threads from MainWindowController to every on-demand
// SwiftUI overlay and hot-reloads when the config changes.

import AppKit
import Combine
import SwiftUI
import Testing
@testable import CocxyTerminal

// MARK: - Helpers

@MainActor
private func makeConfig(
    backgroundOpacity: Double,
    transparencyChromeTheme: TransparencyChromeTheme
) -> CocxyConfig {
    let appearance = AppearanceConfig(
        theme: "Catppuccin Mocha",
        lightTheme: "Catppuccin Latte",
        fontFamily: "JetBrainsMono Nerd Font Mono",
        fontSize: 14,
        tabPosition: .left,
        windowPadding: 8,
        windowPaddingX: nil,
        windowPaddingY: nil,
        ligatures: false,
        fontThicken: false,
        backgroundOpacity: backgroundOpacity,
        backgroundBlurRadius: 0,
        transparencyChromeTheme: transparencyChromeTheme
    )
    return CocxyConfig(
        general: .defaults,
        appearance: appearance,
        terminal: .defaults,
        agentDetection: .defaults,
        codeReview: .defaults,
        notifications: .defaults,
        quickTerminal: .defaults,
        keybindings: .defaults,
        sessions: .defaults
    )
}

private final class OverlayTestConfigProvider: ConfigFileProviding, @unchecked Sendable {
    private var stored: String?

    init(toml: String) {
        self.stored = toml
    }

    func readConfigFile() -> String? {
        stored
    }

    func writeConfigFile(_ content: String) throws {
        stored = content
    }
}

@MainActor
private func makeControllerWithConfig(_ config: CocxyConfig) throws -> (MainWindowController, ConfigService) {
    let appearance = config.appearance
    let toml = """
    [appearance]
    background-opacity = \(appearance.backgroundOpacity)
    transparency-chrome-theme = "\(appearance.transparencyChromeTheme.rawValue)"
    """
    let provider = OverlayTestConfigProvider(toml: toml)
    let service = ConfigService(fileProvider: provider)
    try service.reload()
    let bridge = MockTerminalEngine()
    let controller = MainWindowController(bridge: bridge, configService: service)
    controller.showWindow(nil)
    controller.applyEffectiveAppearance(service.current.appearance)
    return (controller, service)
}

// MARK: - Resolver

@Suite("MainWindowController — resolveVibrancyAppearanceOverride")
@MainActor
struct ResolveVibrancyOverrideTests {

    @Test
    func followSystemPreservesLegacyBehavior() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .followSystem
        )
        let (controller, _) = try makeControllerWithConfig(config)
        #expect(controller.resolveVibrancyAppearanceOverride() == nil)
    }

    @Test
    func lightResolvesToAqua() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .light
        )
        let (controller, _) = try makeControllerWithConfig(config)
        let override = controller.resolveVibrancyAppearanceOverride()
        #expect(override?.name == .aqua)
    }

    @Test
    func darkResolvesToDarkAqua() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(config)
        let override = controller.resolveVibrancyAppearanceOverride()
        #expect(override?.name == .darkAqua)
    }

    @Test
    func opaqueBackgroundCollapsesToNilEvenWhenThemeForced() throws {
        let config = makeConfig(
            backgroundOpacity: 1.0,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(config)
        #expect(controller.resolveVibrancyAppearanceOverride() == nil)
    }
}

// MARK: - Construction-time propagation

@Suite("Overlays receive vibrancy override from host")
@MainActor
struct OverlayVibrancyConstructionTests {

    @Test
    func commandPaletteReceivesOverrideFromHost() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(config)
        controller.toggleCommandPalette()

        let hostingView = try #require(controller.commandPaletteHostingView)
        #expect(hostingView.rootView.vibrancyAppearanceOverride?.name == .darkAqua)
    }

    @Test
    func notificationPanelReceivesOverrideFromHost() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .light
        )
        let (controller, _) = try makeControllerWithConfig(config)
        controller.toggleNotificationPanel()

        let hostingView = try #require(controller.notificationPanelHostingView)
        #expect(hostingView.rootView.vibrancyAppearanceOverride?.name == .aqua)
    }

    @Test
    func dashboardReceivesOverrideFromHost() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(config)
        controller.toggleDashboard()

        let hostingView = try #require(controller.dashboardHostingView)
        #expect(hostingView.rootView.vibrancyAppearanceOverride?.name == .darkAqua)
    }

    @Test
    func timelineReceivesOverrideFromHost() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .light
        )
        let (controller, _) = try makeControllerWithConfig(config)
        controller.toggleTimeline()

        let hostingView = try #require(
            controller.timelineHostingView as? NSHostingView<CocxyTerminal.TimelineView>
        )
        #expect(hostingView.rootView.vibrancyAppearanceOverride?.name == .aqua)
    }

    @Test
    func codeReviewReceivesOverrideFromHost() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(config)
        controller.toggleCodeReview()

        let hostingView = try #require(controller.codeReviewHostingView)
        #expect(hostingView.rootView.vibrancyAppearanceOverride?.name == .darkAqua)
    }

    @Test
    func browserReceivesOverrideFromHost() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(config)
        controller.toggleBrowser()

        let hostingView = try #require(controller.browserHostingView)
        #expect(hostingView.rootView.vibrancyAppearanceOverride?.name == .darkAqua)
    }

    @Test
    func searchBarReceivesOverrideFromHost() throws {
        let config = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(config)
        controller.toggleSearchBar()

        let hostingView = try #require(controller.searchBarHostingView)
        #expect(hostingView.rootView.vibrancyAppearanceOverride?.name == .darkAqua)
    }
}

// MARK: - Hot-reload propagation

@Suite("Hot-reload propagates vibrancy override to live overlays")
@MainActor
struct OverlayVibrancyHotReloadTests {

    @Test
    func applyEffectiveAppearanceUpdatesLiveCommandPalette() throws {
        let initial = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .followSystem
        )
        let (controller, _) = try makeControllerWithConfig(initial)
        controller.toggleCommandPalette()

        let paletteHost = try #require(controller.commandPaletteHostingView)
        #expect(paletteHost.rootView.vibrancyAppearanceOverride == nil)

        let updated = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        controller.applyEffectiveAppearance(updated.appearance)

        let refreshedHost = try #require(controller.commandPaletteHostingView)
        #expect(refreshedHost.rootView.vibrancyAppearanceOverride?.name == .darkAqua)
    }

    @Test
    func applyEffectiveAppearanceUpdatesLiveDashboardAndTimeline() throws {
        let initial = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .light
        )
        let (controller, _) = try makeControllerWithConfig(initial)
        controller.toggleDashboard()
        controller.toggleTimeline()

        let updated = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        controller.applyEffectiveAppearance(updated.appearance)

        let dashboardHost = try #require(controller.dashboardHostingView)
        #expect(dashboardHost.rootView.vibrancyAppearanceOverride?.name == .darkAqua)

        let timelineHost = try #require(
            controller.timelineHostingView as? NSHostingView<CocxyTerminal.TimelineView>
        )
        #expect(timelineHost.rootView.vibrancyAppearanceOverride?.name == .darkAqua)
    }

    @Test
    func revertToFollowSystemClearsOverrideOnLiveOverlays() throws {
        let initial = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(initial)
        controller.toggleNotificationPanel()
        controller.toggleBrowser()

        let notificationHostBefore = try #require(controller.notificationPanelHostingView)
        #expect(notificationHostBefore.rootView.vibrancyAppearanceOverride?.name == .darkAqua)

        let cleared = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .followSystem
        )
        controller.applyEffectiveAppearance(cleared.appearance)

        let notificationHostAfter = try #require(controller.notificationPanelHostingView)
        #expect(notificationHostAfter.rootView.vibrancyAppearanceOverride == nil)

        let browserHost = try #require(controller.browserHostingView)
        #expect(browserHost.rootView.vibrancyAppearanceOverride == nil)
    }

    @Test
    func opaqueBackgroundOverridesIgnoredEvenForForcedTheme() throws {
        let initial = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .dark
        )
        let (controller, _) = try makeControllerWithConfig(initial)
        controller.toggleCommandPalette()

        let opaque = makeConfig(
            backgroundOpacity: 1.0,
            transparencyChromeTheme: .dark
        )
        controller.applyEffectiveAppearance(opaque.appearance)

        let paletteHost = try #require(controller.commandPaletteHostingView)
        #expect(paletteHost.rootView.vibrancyAppearanceOverride == nil)
    }

    @Test
    func followSystemDefaultPreservesLegacyBehavior() throws {
        let defaultConfig = makeConfig(
            backgroundOpacity: 0.85,
            transparencyChromeTheme: .followSystem
        )
        let (controller, _) = try makeControllerWithConfig(defaultConfig)

        controller.toggleCommandPalette()
        controller.toggleTimeline()
        controller.toggleNotificationPanel()

        let paletteHost = try #require(controller.commandPaletteHostingView)
        let timelineHost = try #require(
            controller.timelineHostingView as? NSHostingView<CocxyTerminal.TimelineView>
        )
        let notificationHost = try #require(controller.notificationPanelHostingView)

        #expect(paletteHost.rootView.vibrancyAppearanceOverride == nil)
        #expect(timelineHost.rootView.vibrancyAppearanceOverride == nil)
        #expect(notificationHost.rootView.vibrancyAppearanceOverride == nil)
    }
}

// MARK: - Subagent content view

@Suite("SubagentContentView threads vibrancy override")
@MainActor
struct SubagentContentViewVibrancyTests {

    @Test
    func initializerStoresOverride() {
        let vm = AgentDashboardViewModel()
        let override = NSAppearance(named: .darkAqua)
        let view = SubagentContentView(
            viewModel: vm,
            subagentId: "sub-1",
            sessionId: "sess-1",
            vibrancyAppearanceOverride: override
        )
        #expect(view.vibrancyAppearanceOverride?.name == .darkAqua)
    }

    @Test
    func initializerDefaultsToNil() {
        let vm = AgentDashboardViewModel()
        let view = SubagentContentView(
            viewModel: vm,
            subagentId: "sub-1",
            sessionId: "sess-1"
        )
        #expect(view.vibrancyAppearanceOverride == nil)
    }

    @Test
    func setVibrancyAppearanceOverrideUpdatesStoredValue() {
        let vm = AgentDashboardViewModel()
        let view = SubagentContentView(
            viewModel: vm,
            subagentId: "sub-1",
            sessionId: "sess-1"
        )
        #expect(view.vibrancyAppearanceOverride == nil)

        view.setVibrancyAppearanceOverride(NSAppearance(named: .aqua))
        #expect(view.vibrancyAppearanceOverride?.name == .aqua)

        view.setVibrancyAppearanceOverride(nil)
        #expect(view.vibrancyAppearanceOverride == nil)
    }
}
