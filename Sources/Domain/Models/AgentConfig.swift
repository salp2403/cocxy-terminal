// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentConfig.swift - Configuration model for AI agent detection patterns.

import Foundation

// MARK: - Compiled Pattern Matcher

/// Lightweight matcher used on the hot path before falling back to regex.
///
/// Most built-in agent patterns are simple literals or anchored prefixes.
/// Encoding them into cheaper checks avoids repeated `NSRegularExpression`
/// work for every terminal line while preserving regex fallback support for
/// user-defined or more complex patterns.
enum CompiledPatternMatcher: Sendable {
    case literal(String)
    case prefix(String)
    case prefixWord(String)
    case trimmedEquals(String)
    case orderedContains([String])
    case orderedContainsPrefix([String])
    case whitespaceSeparated([String])
    case whitespaceSeparatedPrefix([String])
    case regex(NSRegularExpression)

    func matches<S: StringProtocol>(_ line: S) -> Bool {
        switch self {
        case .literal(let needle):
            return line.contains(needle)
        case .prefix(let prefix):
            return line.hasPrefix(prefix)
        case .prefixWord(let prefix):
            guard line.hasPrefix(prefix),
                  let boundaryIndex = line.index(
                      line.startIndex,
                      offsetBy: prefix.count,
                      limitedBy: line.endIndex
                  ) else {
                return false
            }
            guard boundaryIndex < line.endIndex else { return true }
            guard let scalar = line[boundaryIndex].unicodeScalars.first else { return true }
            return !CharacterSet.alphanumerics.contains(scalar) && scalar != "_"
        case .trimmedEquals(let literal):
            return trimmedEquals(line, literal: literal)
        case .orderedContains(let segments):
            return matchesOrderedContains(line, segments: segments)
        case .orderedContainsPrefix(let segments):
            return matchesOrderedContainsPrefix(line, segments: segments)
        case .whitespaceSeparated(let segments):
            return matchesWhitespaceSeparated(line, segments: segments)
        case .whitespaceSeparatedPrefix(let segments):
            return matchesWhitespaceSeparatedPrefix(line, segments: segments)
        case .regex(let regex):
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    private func trimmedEquals<S: StringProtocol>(_ line: S, literal: String) -> Bool {
        var start = line.startIndex
        var end = line.endIndex

        while start < end, line[start].isWhitespace {
            start = line.index(after: start)
        }
        while start < end {
            let previous = line.index(before: end)
            guard line[previous].isWhitespace else { break }
            end = previous
        }

        return line[start..<end] == literal[...]
    }

    private func matchesOrderedContains<S: StringProtocol>(_ line: S, segments: [String]) -> Bool {
        guard !segments.isEmpty else { return false }

        var searchStart = line.startIndex
        for segment in segments {
            guard let range = line.range(of: segment, range: searchStart..<line.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }

        return true
    }

    private func matchesOrderedContainsPrefix<S: StringProtocol>(_ line: S, segments: [String]) -> Bool {
        guard let firstSegment = segments.first, line.hasPrefix(firstSegment) else { return false }

        var searchStart = line.index(line.startIndex, offsetBy: firstSegment.count)
        for segment in segments.dropFirst() {
            guard let range = line.range(of: segment, range: searchStart..<line.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }

        return true
    }

    private func matchesWhitespaceSeparated<S: StringProtocol>(_ line: S, segments: [String]) -> Bool {
        guard let firstSegment = segments.first, segments.count >= 2 else { return false }

        var searchStart = line.startIndex
        while let firstRange = line.range(of: firstSegment, range: searchStart..<line.endIndex) {
            var cursor = firstRange.upperBound
            var matched = true

            for segment in segments.dropFirst() {
                let whitespaceStart = cursor
                while cursor < line.endIndex, line[cursor].isWhitespace {
                    cursor = line.index(after: cursor)
                }

                if whitespaceStart == cursor || !line[cursor...].hasPrefix(segment) {
                    matched = false
                    break
                }

                cursor = line.index(cursor, offsetBy: segment.count)
            }

            if matched {
                return true
            }

            searchStart = firstRange.upperBound
        }

        return false
    }

    private func matchesWhitespaceSeparatedPrefix<S: StringProtocol>(
        _ line: S,
        segments: [String]
    ) -> Bool {
        guard let firstSegment = segments.first,
              segments.count >= 2,
              line.hasPrefix(firstSegment) else {
            return false
        }

        var cursor = line.index(line.startIndex, offsetBy: firstSegment.count)
        for segment in segments.dropFirst() {
            let whitespaceStart = cursor
            while cursor < line.endIndex, line[cursor].isWhitespace {
                cursor = line.index(after: cursor)
            }

            if whitespaceStart == cursor || !line[cursor...].hasPrefix(segment) {
                return false
            }

            cursor = line.index(cursor, offsetBy: segment.count)
        }

        return true
    }
}

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
    let launchMatchers: [CompiledPatternMatcher]

    /// Compiled waiting patterns (invalid source patterns are excluded).
    let waitingPatterns: [NSRegularExpression]
    let waitingMatchers: [CompiledPatternMatcher]

    /// Compiled error patterns (invalid source patterns are excluded).
    let errorPatterns: [NSRegularExpression]
    let errorMatchers: [CompiledPatternMatcher]

    /// Compiled finished indicators (invalid source patterns are excluded).
    let finishedIndicators: [NSRegularExpression]
    let finishedMatchers: [CompiledPatternMatcher]

    /// Patterns from the source config that failed to compile.
    let invalidPatterns: [String]
}
