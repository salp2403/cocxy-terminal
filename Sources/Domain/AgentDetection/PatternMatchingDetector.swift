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

    /// The number of active entries currently stored in the circular window.
    private var recentLineWindowCount: Int = 0

    /// The next slot to overwrite in the circular window.
    private var nextWindowSlot: Int = 0

    /// Match history flags aligned with the circular window slot.
    private var launchMatchFlags: [[Bool]] = []
    private var waitingMatchFlags: [Bool]
    private var errorMatchFlags: [Bool]
    private var finishedMatchFlags: [Bool]

    /// Window match counts (sum of true values in flags above).
    private var launchMatchesInWindow: [Int] = []
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

    /// Incomplete UTF-8 bytes preserved across chunks.
    private var pendingUTF8Bytes: [UInt8] = []

    /// Exposed for tests: the number of lines in the circular buffer.
    var recentLineCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recentLineWindowCount
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
        self.waitingMatchFlags = Array(repeating: false, count: self.maxLineBuffer)
        self.errorMatchFlags = Array(repeating: false, count: self.maxLineBuffer)
        self.finishedMatchFlags = Array(repeating: false, count: self.maxLineBuffer)
        initializeLaunchBuffers(for: configs)
    }

    // MARK: - DetectionLayer

    func processBytes(_ data: Data) -> [DetectionSignal] {
        lock.lock()
        defer { lock.unlock() }

        if pendingLineFragment.isEmpty,
           pendingUTF8Bytes.isEmpty,
           data.last == 0x0A,
           !data.dropLast().contains(0x0A) {
            let lineData = data.dropLast()
            guard let line = decodeUTF8Text(lineData) else { return [] }
            return processLine(line)
        }

        guard let decoded = decodeBufferedUTF8(data) else { return [] }
        let text = decoded.text
        pendingUTF8Bytes = decoded.trailingBytes

        // Combine with any pending fragment from previous chunk
        let fullText: String
        if pendingLineFragment.isEmpty {
            fullText = text
        } else {
            fullText = pendingLineFragment + text
            pendingLineFragment = ""
        }

        var signals: [DetectionSignal] = []
        var lineStart = fullText.startIndex

        while let newlineIndex = fullText[lineStart...].firstIndex(of: "\n") {
            let lineSignals = processLine(fullText[lineStart..<newlineIndex])
            signals.append(contentsOf: lineSignals)
            lineStart = fullText.index(after: newlineIndex)
        }

        if lineStart < fullText.endIndex {
            pendingLineFragment = String(fullText[lineStart...])
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
        initializeLaunchBuffers(for: newConfigs)
    }

    // MARK: - Private

    /// Processes a single complete line and returns any signals.
    ///
    /// Uses a sliding window approach: match flags are aligned with the circular
    /// buffer. When a line scrolls out, its flag is removed and the window count
    /// decremented. Detection fires when the count within the window reaches the
    /// required threshold, regardless of whether matches are consecutive.
    private func processLine<S: StringProtocol>(_ line: S) -> [DetectionSignal] {
        let slot = nextWindowSlot
        if recentLineWindowCount >= maxLineBuffer {
            evictMatchFlags(at: slot)
        } else {
            recentLineWindowCount += 1
        }
        nextWindowSlot = (slot + 1) % maxLineBuffer

        let isBlankLine = line.allSatisfy { $0.isWhitespace }

        // Phase 1: Determine what matched across all configs.
        var launchMatchedIndex: Int?
        var waitingMatched = false
        var errorMatchedAgent: String?
        var finishedMatched = false

        if !isBlankLine {
            for (index, compiled) in configs.enumerated() {
                let agentName = compiled.config.name

                if launchMatchedIndex == nil &&
                   matchesAny(line: line, matchers: compiled.launchMatchers) {
                    launchMatchedIndex = index
                }

                if !waitingMatched &&
                   matchesAny(line: line, matchers: compiled.waitingMatchers) {
                    waitingMatched = true
                    lastWaitingAgent = agentName
                }

                if errorMatchedAgent == nil &&
                   matchesAny(line: line, matchers: compiled.errorMatchers) {
                    errorMatchedAgent = agentName
                    lastErrorAgent = agentName
                }

                if !finishedMatched &&
                   matchesAny(line: line, matchers: compiled.finishedMatchers) {
                    finishedMatched = true
                    lastFinishedAgent = agentName
                }
            }
        }

        // Phase 2: Append match flags to sliding window and update counts.
        appendLaunchFlags(matchedIndex: launchMatchedIndex, at: slot)
        writeCategoryFlag(matched: waitingMatched, at: slot, flags: &waitingMatchFlags,
                           count: &waitingMatchesInWindow)
        writeCategoryFlag(matched: errorMatchedAgent != nil, at: slot, flags: &errorMatchFlags,
                           count: &errorMatchesInWindow)
        writeCategoryFlag(matched: finishedMatched, at: slot, flags: &finishedMatchFlags,
                           count: &finishedMatchesInWindow)

        // Phase 3: Check thresholds and emit signals.
        var signals: [DetectionSignal] = []
        var timestamp: Date?

        // Launch: per-agent window count
        for (index, compiled) in configs.enumerated() {
            let agentName = compiled.config.name
            let windowCount = launchMatchesInWindow[index]

            guard windowCount >= requiredConsecutiveMatches else { continue }

            let cooldownKey = "\(agentName).launch"
            let lastEmission = lastEmissionByKey[cooldownKey] ?? .distantPast
            let now = emissionTimestamp(cachedIn: &timestamp)
            guard now.timeIntervalSince(lastEmission) >= cooldownInterval else { continue }

            signals.append(DetectionSignal(
                event: .agentDetected(name: agentName),
                confidence: 0.7,
                source: .pattern(name: agentName),
                timestamp: now
            ))
            lastEmissionByKey[cooldownKey] = now
            clearLaunchFlags(at: index)
        }

        // Waiting
        if waitingMatchesInWindow >= requiredConsecutiveMatches {
            let waitingAgent = lastWaitingAgent ?? "unknown"
            let cooldownKey = "\(waitingAgent).waiting"
            let lastEmission = lastEmissionByKey[cooldownKey] ?? .distantPast
            let now = emissionTimestamp(cachedIn: &timestamp)
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
            let now = emissionTimestamp(cachedIn: &timestamp)
            if now.timeIntervalSince(lastEmission) >= cooldownInterval {
                signals.append(DetectionSignal(
                    event: .errorDetected(message: String(line)),
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
            let now = emissionTimestamp(cachedIn: &timestamp)
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

    /// Evicts the flags currently stored in the slot that is about to be reused.
    private func evictMatchFlags(at slot: Int) {
        for index in launchMatchFlags.indices {
            let evicted = launchMatchFlags[index][slot]
            if evicted {
                launchMatchesInWindow[index] = max(0, launchMatchesInWindow[index] - 1)
            }
            launchMatchFlags[index][slot] = false
        }

        evictFlag(at: slot, flags: &waitingMatchFlags, count: &waitingMatchesInWindow)
        evictFlag(at: slot, flags: &errorMatchFlags, count: &errorMatchesInWindow)
        evictFlag(at: slot, flags: &finishedMatchFlags, count: &finishedMatchesInWindow)
    }

    /// Evicts the flag from a category slot and decrements count if needed.
    private func evictFlag(at slot: Int, flags: inout [Bool], count: inout Int) {
        guard flags.indices.contains(slot) else { return }
        let evicted = flags[slot]
        if evicted {
            count = max(0, count - 1)
        }
        flags[slot] = false
    }

    /// Writes launch match flags for all configured agents into the current slot.
    private func appendLaunchFlags(matchedIndex: Int?, at slot: Int) {
        for index in launchMatchFlags.indices {
            let didMatch = index == matchedIndex
            launchMatchFlags[index][slot] = didMatch
            if didMatch {
                launchMatchesInWindow[index] += 1
            }
        }
    }

    /// Writes a match flag for a non-launch category and updates its count.
    private func writeCategoryFlag(
        matched: Bool,
        at slot: Int,
        flags: inout [Bool],
        count: inout Int
    ) {
        flags[slot] = matched
        if matched {
            count += 1
        }
    }

    /// Clears all launch flags and window count for a specific agent after emission.
    private func clearLaunchFlags(at index: Int) {
        launchMatchFlags[index] = Array(repeating: false, count: maxLineBuffer)
        launchMatchesInWindow[index] = 0
    }

    /// Clears flags and count for a non-launch category after emission.
    private func clearCategoryFlags(flags: inout [Bool], count: inout Int) {
        flags = Array(repeating: false, count: maxLineBuffer)
        count = 0
    }

    /// Tests if a line matches any of the given compiled matchers.
    private func matchesAny<S: StringProtocol>(line: S, matchers: [CompiledPatternMatcher]) -> Bool {
        for matcher in matchers {
            if matcher.matches(line) {
                return true
            }
        }
        return false
    }

    /// Resets all sliding window state and cooldown timestamps.
    private func resetAllCounters() {
        recentLineWindowCount = 0
        nextWindowSlot = 0
        pendingLineFragment = ""
        pendingUTF8Bytes.removeAll(keepingCapacity: true)
        for index in launchMatchFlags.indices {
            launchMatchFlags[index] = Array(repeating: false, count: maxLineBuffer)
            launchMatchesInWindow[index] = 0
        }
        waitingMatchFlags = Array(repeating: false, count: maxLineBuffer)
        waitingMatchesInWindow = 0
        errorMatchFlags = Array(repeating: false, count: maxLineBuffer)
        errorMatchesInWindow = 0
        finishedMatchFlags = Array(repeating: false, count: maxLineBuffer)
        finishedMatchesInWindow = 0
        lastEmissionByKey.removeAll()
        lastWaitingAgent = nil
        lastErrorAgent = nil
        lastFinishedAgent = nil
    }

    private func initializeLaunchBuffers(for configs: [CompiledAgentConfig]) {
        launchMatchFlags = Array(
            repeating: Array(repeating: false, count: maxLineBuffer),
            count: configs.count
        )
        launchMatchesInWindow = Array(repeating: 0, count: configs.count)
    }

    private func emissionTimestamp(cachedIn timestamp: inout Date?) -> Date {
        if let timestamp {
            return timestamp
        }

        let now = Date()
        timestamp = now
        return now
    }

    private func decodeUTF8Text<C: Collection>(_ bytes: C) -> String?
    where C.Element == UInt8 {
        if bytes.allSatisfy({ $0 < 0x80 }) {
            return String(decoding: bytes, as: UTF8.self)
        }

        return String(data: Data(bytes), encoding: .utf8)
    }

    private func decodeBufferedUTF8(_ data: Data) -> (text: String, trailingBytes: [UInt8])? {
        let combinedBytes: [UInt8]
        if pendingUTF8Bytes.isEmpty {
            combinedBytes = Array(data)
        } else {
            combinedBytes = pendingUTF8Bytes + data
        }

        if combinedBytes.isEmpty {
            return ("", [])
        }

        if combinedBytes.allSatisfy({ $0 < 0x80 }) {
            return (String(decoding: combinedBytes, as: UTF8.self), [])
        }

        let maxTrailingBytes = min(3, combinedBytes.count)
        for trailingCount in 0...maxTrailingBytes {
            let prefixEnd = combinedBytes.count - trailingCount
            let prefix = combinedBytes[..<prefixEnd]
            guard let text = String(data: Data(prefix), encoding: .utf8) else {
                continue
            }

            let trailing = trailingCount > 0 ? Array(combinedBytes[prefixEnd...]) : []
            return (text, trailing)
        }

        return nil
    }
}
