// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyInputClassifier
import Foundation

struct InputClassifierAgentRoute: Equatable, Sendable {
    let classification: InputClassification
    let agent: AgentSessionInfo
    let autoRouted: Bool
}

@MainActor
final class InputClassifierAgentRouter {
    private let router: SmartAgentRouting

    init(router: SmartAgentRouting) {
        self.router = router
    }

    func routeIfNeeded(
        classification: InputClassification,
        config: InputClassifierConfig
    ) -> InputClassifierAgentRoute? {
        guard config.enabled else { return nil }
        guard classification.category == .naturalLanguage else { return nil }

        let candidate = router.agents(withState: .waitingForInput).first
            ?? router.mostUrgentAgent()
        guard let candidate else { return nil }

        if config.autoRouteNaturalLanguage {
            router.navigateToAgent(candidate.id)
        }

        return InputClassifierAgentRoute(
            classification: classification,
            agent: candidate,
            autoRouted: config.autoRouteNaturalLanguage
        )
    }
}
