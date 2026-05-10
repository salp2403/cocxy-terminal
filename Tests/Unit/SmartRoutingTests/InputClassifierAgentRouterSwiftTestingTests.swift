// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyInputClassifier
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Input classifier agent routing")
struct InputClassifierAgentRouterSwiftTestingTests {

    @Test("natural language classification offers waiting agent without auto routing")
    func naturalLanguageClassificationOffersWaitingAgentWithoutAutoRouting() {
        let router = MockInputClassifierSmartRouter(sessions: [
            Self.makeSession(id: "working", state: .working),
            Self.makeSession(id: "waiting", state: .waitingForInput),
        ])
        let subject = InputClassifierAgentRouter(router: router)

        let route = subject.routeIfNeeded(
            classification: InputClassification(
                category: .naturalLanguage,
                confidence: 0.9,
                languageCode: "es",
                routingHint: .offerAgentRouting
            ),
            config: InputClassifierConfig.defaults
        )

        #expect(route?.agent.id == "waiting")
        #expect(route?.autoRouted == false)
        #expect(router.navigatedSessionIDs.isEmpty)
    }

    @Test("shell command classification does not offer agent route")
    func shellCommandClassificationDoesNotOfferAgentRoute() {
        let router = MockInputClassifierSmartRouter(sessions: [
            Self.makeSession(id: "waiting", state: .waitingForInput),
        ])
        let subject = InputClassifierAgentRouter(router: router)

        let route = subject.routeIfNeeded(
            classification: InputClassification(
                category: .shellCommand,
                confidence: 0.9,
                routingHint: .executeInShell
            ),
            config: InputClassifierConfig.defaults
        )

        #expect(route == nil)
        #expect(router.navigatedSessionIDs.isEmpty)
    }

    @Test("explicit auto route navigates to selected agent")
    func explicitAutoRouteNavigatesToSelectedAgent() {
        let router = MockInputClassifierSmartRouter(sessions: [
            Self.makeSession(id: "waiting", state: .waitingForInput),
        ])
        let subject = InputClassifierAgentRouter(router: router)

        let route = subject.routeIfNeeded(
            classification: InputClassification(
                category: .naturalLanguage,
                confidence: 0.9,
                languageCode: "en",
                routingHint: .offerAgentRouting
            ),
            config: InputClassifierConfig(
                enabled: true,
                dangerousCommandWarning: true,
                autoRouteNaturalLanguage: true,
                localeDetection: true,
                foundationModelsFallback: true
            )
        )

        #expect(route?.agent.id == "waiting")
        #expect(route?.autoRouted == true)
        #expect(router.navigatedSessionIDs == ["waiting"])
    }

    @Test("overlay view model stores pending route for UI consumption")
    func overlayViewModelStoresPendingRouteForUIConsumption() {
        let router = MockInputClassifierSmartRouter(sessions: [
            Self.makeSession(id: "waiting", state: .waitingForInput),
        ])
        let viewModel = SmartRoutingOverlayViewModel(router: router)

        viewModel.updateInputRoutingOffer(
            classification: InputClassification(
                category: .naturalLanguage,
                confidence: 0.9,
                languageCode: "es",
                routingHint: .offerAgentRouting
            ),
            config: InputClassifierConfig.defaults
        )

        #expect(viewModel.pendingInputRoute?.agent.id == "waiting")
        #expect(viewModel.pendingInputRoute?.autoRouted == false)
    }

    private static func makeSession(id: String, state: AgentDashboardState) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: "project",
            gitBranch: nil,
            agentName: "local-agent",
            state: state,
            lastActivity: nil,
            lastActivityTime: Date(timeIntervalSince1970: 1),
            tabId: UUID(),
            subagents: [],
            priority: .standard,
            model: nil
        )
    }
}

@MainActor
private final class MockInputClassifierSmartRouter: SmartAgentRouting {
    let sessions: [AgentSessionInfo]
    private(set) var navigatedSessionIDs: [String] = []

    init(sessions: [AgentSessionInfo]) {
        self.sessions = sessions
    }

    func agentsNeedingAttention() -> [AgentSessionInfo] {
        sessions.filter { [.error, .blocked, .waitingForInput].contains($0.state) }
    }

    func agents(withState state: AgentDashboardState) -> [AgentSessionInfo] {
        sessions.filter { $0.state == state }
    }

    func mostUrgentAgent() -> AgentSessionInfo? {
        agentsNeedingAttention().sorted { $0.state < $1.state }.first
    }

    func navigateToAgent(_ sessionId: String) {
        navigatedSessionIDs.append(sessionId)
    }
}
