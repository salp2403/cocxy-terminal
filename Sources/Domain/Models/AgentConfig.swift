// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentConfig.swift - Configuration model for AI agent detection patterns.

import Foundation

// MARK: - Agent Config

/// Configuration for detecting a specific AI agent in terminal output.
///
/// Each agent has a set of regex patterns that the detection engine uses
/// to identify launch commands, waiting prompts, errors, and completion.
/// Patterns are loaded from `~/.config/cocxy/agents.toml` and compiled
/// into `NSRegularExpression` instances for efficient matching.
///
/// - SeeAlso: ADR-004 (Agent detection strategy)
/// - SeeAlso: `AgentConfigService`
struct AgentConfig: Codable, Equatable, Sendable {
    /// Short identifier used as the TOML table key (e.g., "claude").
    let name: String

    /// Human-readable name shown in the UI (e.g., "Claude Code").
    let displayName: String

    /// Regex patterns for detecting the agent launch command.
    let launchPatterns: [String]

    /// Regex patterns for detecting input prompts (agent waiting for user).
    let waitingPatterns: [String]

    /// Regex patterns for detecting error output.
    let errorPatterns: [String]

    /// Patterns indicating the agent has finished its task.
    let finishedIndicators: [String]

    /// Whether this agent supports OSC notification sequences.
    let oscSupported: Bool

    /// Per-agent idle timeout override in seconds.
    /// When `nil`, the global `idle-timeout-seconds` from config.toml applies.
    let idleTimeoutOverride: TimeInterval?
}

// MARK: - Compiled Agent Config

/// Pre-compiled version of `AgentConfig` with cached `NSRegularExpression` instances.
///
/// Regex compilation is expensive. This struct is created once when the config
/// is loaded and reused for every pattern match operation. Invalid patterns
/// are silently skipped with a warning logged.
struct CompiledAgentConfig: Sendable {
    /// The original configuration this was compiled from.
    let config: AgentConfig

    /// Compiled launch patterns (invalid source patterns are excluded).
    let launchPatterns: [NSRegularExpression]

    /// Compiled waiting patterns (invalid source patterns are excluded).
    let waitingPatterns: [NSRegularExpression]

    /// Compiled error patterns (invalid source patterns are excluded).
    let errorPatterns: [NSRegularExpression]

    /// Compiled finished indicators (invalid source patterns are excluded).
    let finishedIndicators: [NSRegularExpression]

    /// Patterns from the source config that failed to compile.
    let invalidPatterns: [String]
}
