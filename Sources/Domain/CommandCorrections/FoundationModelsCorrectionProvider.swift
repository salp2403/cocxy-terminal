// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct FoundationModelsCorrectionProvider: CommandCorrectionProvider {
    public let isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        guard isEnabled else { return [] }

        // The public provider is intentionally local-only. Until the
        // Foundation Models SDK is available to this package target, this
        // layer only exposes the stable hook point and never falls back to a
        // network request.
        return []
    }
}

public struct AgentCorrectionProvider: CommandCorrectionProvider {
    public typealias Resolver = @Sendable (CommandCorrectionContext) -> [CommandCorrection]

    private let isEnabled: Bool
    private let resolver: Resolver?

    public init(isEnabled: Bool = false, resolver: Resolver? = nil) {
        self.isEnabled = isEnabled
        self.resolver = resolver
    }

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        guard isEnabled, let resolver else { return [] }
        return resolver(context).map { correction in
            CommandCorrection(
                original: correction.original,
                suggestion: correction.suggestion,
                reason: correction.reason,
                confidence: correction.confidence,
                source: .agent
            )
        }
    }
}
