// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PatternMatchingDetector.swift - Detection layer 2: Regex pattern matching.

import Foundation

// MARK: - Pattern Matching Detector

/// Detection layer 2 (medium confidence): Regex pattern matching on terminal output.
///
/// Uses `CompiledAgentConfig` from `AgentConfigService` to match the last N lines
/// of terminal output against launch, waiting, error, and finished patterns.
///
/// Implements sliding window hysteresis: requires N matches within the last
/// `maxLineBuffer` lines (not necessarily consecutive). This tolerates noise
/// lines intercalated between agent output lines. Combined with per-agent
/// cooldown to avoid rapid re-triggering.
///
/// - Thread safety: Uses a lock for all mutable state.
/// - SeeAlso: ADR-004 (Agent detection strategy)
final class PatternMatchingDetector: DetectionLayer, @unchecked Sendable {

    // MARK: - Category

    /// The type of pattern that matched a line.
    private enum MatchCategory: Equatable {
        case launch(agentName: String)
        case waiting
        case error(agentName: String)
        case finished
    }

    // MARK: - Properties

    private var configs: [CompiledAgentConfig]
    private let requiredConsecutiveMatches: Int
    private let cooldownInterval: TimeInterval
    private let maxLineBuffer: Int
    private let lock = NSLock()

    /// Circular buffer of recent lines.
    private var recentLines: [String] = []

    /// Match history flags aligned with recentLines circular buffer.
    /// Each Bool corresponds to a line in recentLines — true if that line matched.
    private var launchMatchFlags: [String: [Bool]] = [:]
    private var waitingMatchFlags: [Bool] = []
    private var errorMatchFlags: [Bool] = []
    private var finishedMatchFlags: [Bool] = []

    /// Window match counts (sum of true values in flags above).
    private var launchMatchesInWindow: [String: Int] = [:]
    private var waitingMatchesInWindow: Int = 0
    private var errorMatchesInWindow: Int = 0
    private var finishedMatchesInWindow: Int = 0

    /// Last emission time keyed by "agentName.category" for per-agent cooldown.
    private var lastEmissionByKey: [String: Date] = [:]

    /// Last agent name that matched each non-launch category. Used for the
    /// cooldown key when the threshold fires on a line that no longer matches
    /// (the threshold was reached from earlier lines in the sliding window).
    private var lastWaitingAgent: String?
    private var lastErrorAgent: String?
    private var lastFinishedAgent: String?

    /// Incomplete line buffer for handling data that doesn't end with newline.
    private var pendingLineFragment: String = ""

    /// Exposed for tests: the number of lines in the circular buffer.
    var recentLineCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recentLines.count
    }

    // MARK: - Initialization

    /// Creates a PatternMatchingDetector with the given configuration.
    ///
    /// - Parameters:
    ///   - configs: Pre-compiled agent configurations with regex patterns.
    ///   - requiredConsecutiveMatches: How many matching lines within the sliding
    ///     window are needed before emitting a signal. Default 2 (hysteresis).
    ///     Matches do NOT need to be consecutive — noise lines between matches
    ///     are tolerated as long as all matches fall within the window.
    ///   - cooldownInterval: Minimum seconds between signals of the same category.
    ///     Default 1.0 second.
    ///   - maxLineBuffer: Size of the sliding window (in lines). Also controls
    ///     the maximum number of recent lines retained. Default 5.
    init(
        configs: [CompiledAgentConfig],
        requiredConsecutiveMatches: Int = 2,
        cooldownInterval: TimeInterval = 1.0,
        maxLineBuffer: Int = 5
    ) {
        self.configs = configs
        self.requiredConsecutiveMatches = max(1, requiredConsecutiveMatches)
        self.cooldownInterval = cooldownInterval
        self.maxLineBuffer = max(1, maxLineBuffer)
    }

    // MARK: - DetectionLayer

    func processBytes(_ data: Data) -> [DetectionSignal] {
        lock.lock()
        defer { lock.unlock() }

        guard let text = String(data: data, encoding: .utf8) else { return [] }

        // Combine with any pending fragment from previous chunk
        let fullText = pendingLineFragment + text
        pendingLineFragment = ""

        // Split into lines
        let lines = fullText.components(separatedBy: "\n")

        // If the data didn't end with a newline, the last element is a fragment
        if !text.hasSuffix("\n") && lines.count > 1 {
            pendingLineFragment = lines.last ?? ""
        } else if !text.hasSuffix("\n") && lines.count == 1 {
            pendingLineFragment = lines[0]
            return []
        }

        // Process complete lines (all except the pending fragment)
        let completeLineCount = text.hasSuffix("\n") ? lines.count : lines.count - 1
        var signals: [DetectionSignal] = []

        for i in 0..<completeLineCount {
            let line = lines[i]
            let lineSignals = processLine(line)
            signals.append(contentsOf: lineSignals)
        }

        return signals
    }

    // MARK: - Update Configs

    /// Updates the compiled agent configurations.
    ///
    /// Called when the user modifies agents.toml and the config is hot-reloaded.
    func updateConfigs(_ newConfigs: [CompiledAgentConfig]) {
        lock.lock()
        defer { lock.unlock() }
        configs = newConfigs
        resetAllCounters()
    }

    // MARK: - Private

    /// Processes a single complete line and returns any signals.
    ///
    /// Uses a sliding window approach: match flags are aligned with the circular
    /// buffer. When a line scrolls out, its flag is removed and the window count
    /// decremented. Detection fires when the count within the window reaches the
    /// required threshold, regardless of whether matches are consecutive.
    private func processLine(_ line: String) -> [DetectionSignal] {
        // Phase 0: Evict oldest entry from sliding window if buffer is full.
        if recentLines.count >= maxLineBuffer {
            evictOldestMatchFlags()
        }

        // Add to circular buffer.
        recentLines.append(line)
        if recentLines.count > maxLineBuffer {
            recentLines.removeFirst(recentLines.count - maxLineBuffer)
        }

        let isBlankLine = line.trimmingCharacters(in: .whitespaces).isEmpty

        // Phase 1: Determine what matched across all configs.
        var launchMatchedAgent: String?
        var waitingMatched = false
        var errorMatchedAgent: String?
        var finishedMatched = false

        if !isBlankLine {
            for compiled in configs {
                let agentName = compiled.config.name

                if launchMatchedAgent == nil &&
                   matchesAny(line: line, patterns: compiled.launchPatterns) {
                    launchMatchedAgent = agentName
                }

                if !waitingMatched &&
                   matchesAny(line: line, patterns: compiled.waitingPatterns) {
                    waitingMatched = true
                    lastWaitingAgent = agentName
                }

                if errorMatchedAgent == nil &&
                   matchesAny(line: line, patterns: compiled.errorPatterns) {
                    errorMatchedAgent = agentName
                    lastErrorAgent = agentName
                }

                if !finishedMatched &&
                   matchesAny(line: line, patterns: compiled.finishedIndicators) {
                    finishedMatched = true
                    lastFinishedAgent = agentName
                }
            }
        }

        // Phase 2: Append match flags to sliding window and update counts.
        appendLaunchFlags(matchedAgent: launchMatchedAgent)
        appendCategoryFlag(matched: waitingMatched, flags: &waitingMatchFlags,
                           count: &waitingMatchesInWindow)
        appendCategoryFlag(matched: errorMatchedAgent != nil, flags: &errorMatchFlags,
                           count: &errorMatchesInWindow)
        appendCategoryFlag(matched: finishedMatched, flags: &finishedMatchFlags,
                           count: &finishedMatchesInWindow)

        // Phase 3: Check thresholds and emit signals.
        var signals: [DetectionSignal] = []
        let now = Date()

        // Launch: per-agent window count
        for compiled in configs {
            let agentName = compiled.config.name
            let windowCount = launchMatchesInWindow[agentName] ?? 0

            guard windowCount >= requiredConsecutiveMatches else { continue }

            let cooldownKey = "\(agentName).launch"
            let lastEmission = lastEmissionByKey[cooldownKey] ?? .distantPast
            guard now.timeIntervalSince(lastEmission) >= cooldownInterval else { continue }

            signals.append(DetectionSignal(
                event: .agentDetected(name: agentName),
                confidence: 0.7,
                source: .pattern(name: agentName),
                timestamp: now
            ))
            lastEmissionByKey[cooldownKey] = now
            clearLaunchFlags(for: agentName)
        }

        // Waiting
        if waitingMatchesInWindow >= requiredConsecutiveMatches {
            let waitingAgent = lastWaitingAgent ?? "unknown"
            let cooldownKey = "\(waitingAgent).waiting"
            let lastEmission = lastEmissionByKey[cooldownKey] ?? .distantPast
            if now.timeIntervalSince(lastEmission) >= cooldownInterval {
                signals.append(DetectionSignal(
                    event: .promptDetected,
                    confidence: 0.7,
                    source: .pattern(name: waitingAgent),
                    timestamp: now
                ))
                lastEmissionByKey[cooldownKey] = now
                clearCategoryFlags(flags: &waitingMatchFlags, count: &waitingMatchesInWindow)
            }
        }

        // Error
        if errorMatchesInWindow >= requiredConsecutiveMatches {
            let errorAgent = lastErrorAgent ?? "unknown"
            let cooldownKey = "\(errorAgent).error"
            let lastEmission = lastEmissionByKey[cooldownKey] ?? .distantPast
            if now.timeIntervalSince(lastEmission) >= cooldownInterval {
                signals.append(DetectionSignal(
                    event: .errorDetected(message: line),
                    confidence: 0.7,
                    source: .pattern(name: errorAgent),
                    timestamp: now
                ))
                lastEmissionByKey[cooldownKey] = now
                clearCategoryFlags(flags: &errorMatchFlags, count: &errorMatchesInWindow)
            }
        }

        // Finished
        if finishedMatchesInWindow >= requiredConsecutiveMatches {
            let finishedAgent = lastFinishedAgent ?? "unknown"
            let cooldownKey = "\(finishedAgent).finished"
            let lastEmission = lastEmissionByKey[cooldownKey] ?? .distantPast
            if now.timeIntervalSince(lastEmission) >= cooldownInterval {
                signals.append(DetectionSignal(
                    event: .completionDetected,
                    confidence: 0.7,
                    source: .pattern(name: finishedAgent),
                    timestamp: now
                ))
                lastEmissionByKey[cooldownKey] = now
                clearCategoryFlags(flags: &finishedMatchFlags, count: &finishedMatchesInWindow)
            }
        }

        return signals
    }

    // MARK: - Sliding Window Helpers

    /// Evicts the oldest match flags when the buffer reaches capacity.
    private func evictOldestMatchFlags() {
        // Launch flags: per-agent eviction
        for agentName in launchMatchFlags.keys {
            guard var flags = launchMatchFlags[agentName], !flags.isEmpty else { continue }
            let evicted = flags.removeFirst()
            if evicted {
                launchMatchesInWindow[agentName] = max(0, (launchMatchesInWindow[agentName] ?? 0) - 1)
            }
            launchMatchFlags[agentName] = flags
        }

        evictOldestFlag(flags: &waitingMatchFlags, count: &waitingMatchesInWindow)
        evictOldestFlag(flags: &errorMatchFlags, count: &errorMatchesInWindow)
        evictOldestFlag(flags: &finishedMatchFlags, count: &finishedMatchesInWindow)
    }

    /// Evicts the oldest flag from a category and decrements count if needed.
    private func evictOldestFlag(flags: inout [Bool], count: inout Int) {
        guard !flags.isEmpty else { return }
        let evicted = flags.removeFirst()
        if evicted {
            count = max(0, count - 1)
        }
    }

    /// Appends launch match flags for all configured agents.
    private func appendLaunchFlags(matchedAgent: String?) {
        for compiled in configs {
            let agentName = compiled.config.name
            let didMatch = agentName == matchedAgent
            var flags = launchMatchFlags[agentName] ?? []
            flags.append(didMatch)
            launchMatchFlags[agentName] = flags
            if didMatch {
                launchMatchesInWindow[agentName] = (launchMatchesInWindow[agentName] ?? 0) + 1
            }
        }
    }

    /// Appends a match flag for a non-launch category and updates its count.
    private func appendCategoryFlag(matched: Bool, flags: inout [Bool], count: inout Int) {
        flags.append(matched)
        if matched {
            count += 1
        }
    }

    /// Clears all launch flags and window count for a specific agent after emission.
    private func clearLaunchFlags(for agentName: String) {
        let flagCount = launchMatchFlags[agentName]?.count ?? 0
        launchMatchFlags[agentName] = Array(repeating: false, count: flagCount)
        launchMatchesInWindow[agentName] = 0
    }

    /// Clears flags and count for a non-launch category after emission.
    private func clearCategoryFlags(flags: inout [Bool], count: inout Int) {
        flags = Array(repeating: false, count: flags.count)
        count = 0
    }

    /// Tests if a line matches any of the given compiled patterns.
    private func matchesAny(line: String, patterns: [NSRegularExpression]) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return patterns.contains { regex in
            regex.firstMatch(in: line, options: [], range: range) != nil
        }
    }

    /// Resets all sliding window state and cooldown timestamps.
    private func resetAllCounters() {
        recentLines.removeAll()
        pendingLineFragment = ""
        launchMatchFlags.removeAll()
        launchMatchesInWindow.removeAll()
        waitingMatchFlags.removeAll()
        waitingMatchesInWindow = 0
        errorMatchFlags.removeAll()
        errorMatchesInWindow = 0
        finishedMatchFlags.removeAll()
        finishedMatchesInWindow = 0
        lastEmissionByKey.removeAll()
        lastWaitingAgent = nil
        lastErrorAgent = nil
        lastFinishedAgent = nil
    }
}
