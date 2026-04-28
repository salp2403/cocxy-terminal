// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import XCTest
@testable import CocxyTerminal

@MainActor
final class RateLimitStatusBarWiringTests: XCTestCase {

    func testActiveRateLimitAgentKindFollowsResolvedTabAgent() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tab = controller.tabManager.tabs[0]
        seed(
            controller: controller,
            tabID: tab.id,
            state: .working,
            detectedAgent: DetectedAgent(
                name: "claude-code",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        )

        XCTAssertEqual(controller.activeRateLimitAgentKind(for: tab), .claude)
    }

    func testActiveRateLimitAgentKindReturnsNilForUnknownAgent() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tab = controller.tabManager.tabs[0]
        seed(
            controller: controller,
            tabID: tab.id,
            state: .working,
            detectedAgent: DetectedAgent(
                name: "unknown-tool",
                displayName: "Unknown Tool",
                launchCommand: "unknown-tool",
                startedAt: Date()
            )
        )

        XCTAssertNil(controller.activeRateLimitAgentKind(for: tab))
    }

    func testRefreshStatusBarSelectsProbeProviderForActiveAgent() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tab = controller.tabManager.tabs[0]
        seed(
            controller: controller,
            tabID: tab.id,
            state: .working,
            detectedAgent: DetectedAgent(
                name: "claude-code",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        )

        controller.refreshStatusBar()

        XCTAssertEqual(controller.rateLimitProbeService.currentAgent, .claude)
    }

    func testRefreshStatusBarSkipsProbeWhenIndicatorPreferenceDisabled() {
        // Even with a Claude agent active, when the user has turned off
        // the rate-limit indicator preference the wiring must clear the
        // probe's active agent so the pill stays hidden.
        let controller = makeControllerWithRateLimitIndicator(enabled: false)
        let tab = controller.tabManager.tabs[0]
        seed(
            controller: controller,
            tabID: tab.id,
            state: .working,
            detectedAgent: DetectedAgent(
                name: "claude-code",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        )

        controller.refreshStatusBar()

        XCTAssertNil(controller.rateLimitProbeService.currentAgent)
    }

    func testRefreshStatusBarUsesProbeWhenIndicatorPreferenceExplicitlyEnabled() {
        // Symmetric guard for the enabled side: an explicit `true` (not
        // just the implicit default) keeps the probe wiring active.
        let controller = makeControllerWithRateLimitIndicator(enabled: true)
        let tab = controller.tabManager.tabs[0]
        seed(
            controller: controller,
            tabID: tab.id,
            state: .working,
            detectedAgent: DetectedAgent(
                name: "claude-code",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            )
        )

        controller.refreshStatusBar()

        XCTAssertEqual(controller.rateLimitProbeService.currentAgent, .claude)
    }

    // MARK: - Helpers

    @discardableResult
    private func seed(
        controller: MainWindowController,
        tabID: TabID,
        state: AgentState,
        detectedAgent: DetectedAgent
    ) -> SurfaceID {
        if controller.injectedPerSurfaceStore == nil {
            controller.injectedPerSurfaceStore = AgentStatePerSurfaceStore()
        }
        let surfaceID = SurfaceID()
        controller.tabSurfaceMap[tabID] = surfaceID
        controller.injectedPerSurfaceStore?.update(surfaceID: surfaceID) {
            $0.agentState = state
            $0.detectedAgent = detectedAgent
        }
        return surfaceID
    }

    /// Builds a controller wired to a `ConfigService` whose appearance
    /// section has `rateLimitIndicatorEnabled` pinned to the supplied
    /// value. Anything else falls back to defaults so the controller
    /// behaves identically to the production path used by the simpler
    /// tests above.
    private func makeControllerWithRateLimitIndicator(enabled: Bool) -> MainWindowController {
        let toml = """
        [appearance]
        rate-limit-indicator-enabled = \(enabled)
        """
        let provider = InMemoryRateLimitConfigProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try? service.reload()
        return MainWindowController(bridge: MockTerminalEngine(), configService: service)
    }
}

/// Minimal in-memory provider used to seed `ConfigService` from a
/// hand-rolled TOML snippet without touching disk.
private final class InMemoryRateLimitConfigProvider: ConfigFileProviding, @unchecked Sendable {
    private var content: String?

    init(content: String?) {
        self.content = content
    }

    func readConfigFile() -> String? { content }

    func writeConfigFile(_ content: String) throws {
        self.content = content
    }
}
