// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CostTracker.swift - Provider/model token cost math with caller-supplied rates.

import Foundation

enum CostTracker {
    static func estimatedCostMicros(
        inputTokens: Int,
        outputTokens: Int,
        rate: TokenCostRate
    ) -> Int64 {
        roundedMicros(
            tokens: max(0, inputTokens),
            microsPerMillionTokens: rate.inputMicrosPerMillionTokens
        ) + roundedMicros(
            tokens: max(0, outputTokens),
            microsPerMillionTokens: rate.outputMicrosPerMillionTokens
        )
    }

    static func usageRecord(
        provider: String,
        model: String,
        sessionID: String?,
        project: ActivityProjectRef?,
        inputTokens: Int,
        outputTokens: Int,
        rate: TokenCostRate,
        timestamp: Date = Date()
    ) -> TokenUsageRecord {
        TokenUsageRecord(
            timestamp: timestamp,
            provider: provider,
            model: model,
            sessionID: sessionID,
            project: project,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostMicros: estimatedCostMicros(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                rate: rate
            )
        )
    }

    private static func roundedMicros(
        tokens: Int,
        microsPerMillionTokens: Int64
    ) -> Int64 {
        let safeTokens = Int64(max(0, tokens))
        let safeRate = max(0, microsPerMillionTokens)
        return (safeTokens * safeRate + 500_000) / 1_000_000
    }
}
