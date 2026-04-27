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
}
