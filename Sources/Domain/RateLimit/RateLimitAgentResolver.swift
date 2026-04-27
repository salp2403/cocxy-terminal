// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitAgentResolver.swift - Maps detected terminal agents to
// locally supported rate-limit providers.

import Foundation

/// Pure resolver that translates Cocxy's detected agent metadata into
/// the closed `RateLimitSnapshot.AgentKind` enum.
///
/// Agent detection stores canonical identifiers such as `claude-code`
/// plus display names intended for UI. The rate-limit subsystem only
/// needs to know whether a local provider exists for the visible agent,
/// so this resolver normalizes both fields and matches stable tokens
/// instead of depending on one exact spelling.
enum RateLimitAgentResolver {

    static func kind(for detectedAgent: DetectedAgent?) -> RateLimitSnapshot.AgentKind? {
        guard let detectedAgent else { return nil }
        return kind(name: detectedAgent.name, displayName: detectedAgent.displayName)
    }

    static func kind(name: String, displayName: String? = nil) -> RateLimitSnapshot.AgentKind? {
        let candidates = [name, displayName ?? ""]
            .map(normalizedIdentifier)
            .filter { !$0.isEmpty }

        if candidates.contains(where: { $0.contains("claude") }) { return .claude }
        if candidates.contains(where: { $0.contains("codex") }) { return .codex }
        if candidates.contains(where: { $0.contains("gemini") }) { return .gemini }
        if candidates.contains(where: { $0.contains("aider") }) { return .aider }
        return nil
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
