// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskHandoffProviderCatalog.swift - Deterministic handoff destination ordering.

import Foundation

enum TaskHandoffProviderCatalog {
    static func resolveCurrentProvider(
        detectedAgent: DetectedAgent?
    ) -> AgentTeamProvider? {
        guard let detectedAgent else { return nil }
        return AgentTeamProvider.resolve(named: detectedAgent.name)
            ?? AgentTeamProvider.resolve(named: detectedAgent.displayName)
    }

    static func destinations(
        currentProvider: AgentTeamProvider?,
        availableProviders: [AgentTeamProvider]
    ) -> [AgentTeamProvider] {
        var seen = Set<AgentTeamProvider>()
        let candidates = availableProviders.filter { provider in
            provider != currentProvider && seen.insert(provider).inserted
        }
        let preferredProvider: AgentTeamProvider?
        switch currentProvider {
        case .claudeCode:
            preferredProvider = .codex
        case .codex:
            preferredProvider = .claudeCode
        default:
            preferredProvider = nil
        }

        return candidates.sorted { lhs, rhs in
            if lhs == preferredProvider { return true }
            if rhs == preferredProvider { return false }
            let displayOrder = lhs.displayName.localizedCaseInsensitiveCompare(
                rhs.displayName
            )
            if displayOrder != .orderedSame {
                return displayOrder == .orderedAscending
            }
            return lhs.rawValue < rhs.rawValue
        }
    }
}
