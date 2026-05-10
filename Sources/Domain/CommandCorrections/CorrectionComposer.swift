// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct CorrectionComposer: CommandCorrectionProvider {
    public let providers: [any CommandCorrectionProvider]
    public let maxSuggestions: Int

    public init(
        providers: [any CommandCorrectionProvider],
        maxSuggestions: Int = 3
    ) {
        self.providers = providers
        self.maxSuggestions = max(1, maxSuggestions)
    }

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        var strongestBySuggestion: [String: CommandCorrection] = [:]

        for provider in providers {
            for correction in provider.corrections(for: context) where correction.suggestion != context.normalizedCommand {
                let key = correction.suggestion
                if let existing = strongestBySuggestion[key],
                   existing.confidence >= correction.confidence {
                    continue
                }
                strongestBySuggestion[key] = correction
            }
        }

        return strongestBySuggestion.values
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                let lhsRank = Self.sourcePriority(lhs.source)
                let rhsRank = Self.sourcePriority(rhs.source)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.suggestion < rhs.suggestion
            }
            .prefix(maxSuggestions)
            .map { $0 }
    }

    private static func sourcePriority(_ source: CommandCorrectionSource) -> Int {
        switch source {
        case .commonTypo: return 0
        case .shellHint: return 1
        case .pathHeuristic: return 2
        case .editDistance: return 3
        case .foundationModels: return 4
        case .agent: return 5
        }
    }
}

public struct CommandCorrectionEngine: CommandCorrectionProvider {
    private let composer: CorrectionComposer

    public init(composer: CorrectionComposer) {
        self.composer = composer
    }

    public static func localDefault(
        editDistanceThreshold: Int = 2,
        foundationModelsEnabled: Bool = true,
        agentFallback: Bool = false,
        maxSuggestions: Int = 3
    ) -> CommandCorrectionEngine {
        CommandCorrectionEngine(
            composer: CorrectionComposer(
                providers: [
                    CommonTypoCorrectionProvider(),
                    ShellHintCorrectionProvider(),
                    PathCorrectionProvider(),
                    EditDistanceCorrectionProvider(threshold: editDistanceThreshold),
                    FoundationModelsCorrectionProvider(isEnabled: foundationModelsEnabled),
                    AgentCorrectionProvider(isEnabled: agentFallback)
                ],
                maxSuggestions: maxSuggestions
            )
        )
    }

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        composer.corrections(for: context)
    }
}

public struct CommandCorrectionListener: Sendable {
    private let engine: CommandCorrectionEngine

    public init(engine: CommandCorrectionEngine) {
        self.engine = engine
    }

    public func suggestion(
        for execution: CommandExecutionSnapshot,
        enabled: Bool
    ) -> CommandCorrection? {
        guard enabled, execution.failed else { return nil }
        return engine.corrections(for: execution.context).first
    }
}
