// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public enum InputClassificationCategory: String, Codable, Sendable, Equatable {
    case empty
    case shellCommand = "shell-command"
    case naturalLanguage = "natural-language"
    case dangerousCommand = "dangerous-command"
    case unknown
}

public enum InputClassificationRoutingHint: String, Codable, Sendable, Equatable {
    case ignore
    case executeInShell = "execute-in-shell"
    case offerAgentRouting = "offer-agent-routing"
    case requireConfirmation = "require-confirmation"
    case none
}

public enum DangerousCommandSeverity: String, Codable, Sendable, Equatable, Comparable {
    case low
    case medium
    case high
    case critical

    public static func < (lhs: DangerousCommandSeverity, rhs: DangerousCommandSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

public struct DangerousCommandMatch: Codable, Sendable, Equatable {
    public let severity: DangerousCommandSeverity
    public let reason: String
    public let matchedPattern: String
}

public struct InputClassification: Codable, Sendable, Equatable {
    public let category: InputClassificationCategory
    public let confidence: Double
    public let languageCode: String?
    public let dangerReason: String?
    public let dangerSeverity: DangerousCommandSeverity?
    public let shouldWarnBeforeExecution: Bool
    public let routingHint: InputClassificationRoutingHint
    public let suggestedCommand: String?

    public init(
        category: InputClassificationCategory,
        confidence: Double,
        languageCode: String? = nil,
        dangerReason: String? = nil,
        dangerSeverity: DangerousCommandSeverity? = nil,
        shouldWarnBeforeExecution: Bool = false,
        routingHint: InputClassificationRoutingHint = .none,
        suggestedCommand: String? = nil
    ) {
        self.category = category
        self.confidence = max(0, min(confidence, 1))
        self.languageCode = languageCode
        self.dangerReason = dangerReason
        self.dangerSeverity = dangerSeverity
        self.shouldWarnBeforeExecution = shouldWarnBeforeExecution
        self.routingHint = routingHint
        self.suggestedCommand = suggestedCommand
    }
}
