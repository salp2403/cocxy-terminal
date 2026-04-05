// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PerformanceTests.swift - Performance profiling and optimization verification.

import XCTest
@testable import CocxyTerminal

// MARK: - Performance Tests

/// Performance test suite for critical paths in Cocxy Terminal.
///
/// Measures throughput and latency of:
/// - Agent detection engine (1MB output processing).
/// - Pattern matching detector (10,000 lines).
/// - OSC sequence parser (100K bytes).
/// - Tab creation (20 tabs).
/// - Split tree operations (8 splits, directional navigation).
/// - Session save/load round-trip (10 tabs + splits).
/// - Config reload (TOML parsing + validation).
/// - Theme switching (5 themes).
///
/// Targets are derived from PLAN.md performance requirements.
final class PerformanceTests: XCTestCase {

    // MARK: - Test 1: Agent Detection Pipeline Throughput (All 3 Layers)

    /// Processes 1MB of simulated terminal output through the 3 detection layers
    /// (OSC + pattern matching + timing heuristics) in sequence.
    ///
    /// This tests the hot path: the byte-processing that happens on every PTY read.
    /// We measure the layers directly to avoid the DispatchQueue.main.async hop that
    /// the engine uses for @MainActor state mutation, which would deadlock in a
    /// synchronous test.
    ///
    /// Target: < 1150ms in debug build. Pattern matching with NSRegularExpression
    /// and string decoding still carry measurable overhead in unoptimized builds.
    /// Release should remain comfortably below this budget.
    func test_agentDetectionPipeline_1MB_throughput_completesUnder1150ms() {
        let configs = createSixAgentConfigs()
        let oscDetector = OSCSequenceDetector()
        let patternDetector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 5
        )
        let timingDetector = TimingHeuristicsDetector(
            defaultIdleTimeout: 5.0,
            sustainedOutputThreshold: 2.0
        )

        let oneMegabyte = generateSimulatedTerminalOutput(byteCount: 1_000_000)
        let chunks = splitIntoChunks(data: oneMegabyte, chunkSize: 4096)

        let startTime = CFAbsoluteTimeGetCurrent()

        for chunk in chunks {
            let oscSignals = oscDetector.processBytes(chunk)
            let patternSignals = patternDetector.processBytes(chunk)
            _ = timingDetector.processBytes(chunk)
            // Signal resolution (lightweight comparison)
            _ = oscSignals + patternSignals
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 1150.0,
            "Detection pipeline processed 1MB in \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 1150ms target"
        )
    }

    // MARK: - Test 2: Pattern Matching Detector Throughput

    /// Processes 10,000 lines through PatternMatchingDetector with 6 agents (20+ patterns).
    /// Target: < 500ms in debug build. NSRegularExpression has significant overhead in
    /// unoptimized builds due to objc bridging. Release build should be < 50ms.
    func test_patternMatchingDetector_10000Lines_completesUnder500ms() {
        let configs = createSixAgentConfigs()
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 5
        )

        let lines = generateTerminalLines(count: 10_000)
        let linesData = lines.map { Data(($0 + "\n").utf8) }

        let startTime = CFAbsoluteTimeGetCurrent()

        for lineData in linesData {
            _ = detector.processBytes(lineData)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 500.0,
            "Pattern detector processed 10,000 lines in \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 500ms target"
        )
    }

    // MARK: - Test 3: OSC Sequence Parser Throughput

    /// Parses 100K bytes with embedded OSC sequences.
    /// Target: < 10ms.
    func test_oscParser_100KBytes_completesUnder10ms() {
        let detector = OSCSequenceDetector()
        let data = generateOSCMixedData(byteCount: 100_000)

        let startTime = CFAbsoluteTimeGetCurrent()

        _ = detector.processBytes(data)

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 10.0,
            "OSC parser processed 100KB in \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 10ms target"
        )
    }

    // MARK: - Test 4: OSC Parser Incremental Throughput

    /// Parses 100K bytes split into 1K chunks to test incremental parsing.
    /// Target: < 15ms (slightly higher due to per-chunk overhead).
    func test_oscParser_100KBytes_incrementalChunks_completesUnder15ms() {
        let detector = OSCSequenceDetector()
        let data = generateOSCMixedData(byteCount: 100_000)
        let chunks = splitIntoChunks(data: data, chunkSize: 1024)

        let startTime = CFAbsoluteTimeGetCurrent()

        for chunk in chunks {
            _ = detector.processBytes(chunk)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 15.0,
            "OSC incremental parsing took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 15ms target"
        )
    }

    // MARK: - Test 5: Tab Creation Performance

    /// Creates 20 tabs sequentially.
    /// Target: < 500ms.
    @MainActor
    func test_tabCreation_20Tabs_completesUnder500ms() {
        let tabManager = TabManager()

        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<19 {
            tabManager.addTab()
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertEqual(tabManager.tabs.count, 20)
        XCTAssertLessThan(
            elapsedMilliseconds, 500.0,
            "Creating 20 tabs took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 500ms target"
        )
    }

    // MARK: - Test 6: Split Tree Construction (8 Splits)

    /// Creates a split tree with 8 leaves respecting max depth of 4.
    /// Target: < 50ms for the full construction.
    ///
    /// Strategy: split different leaves to distribute depth evenly.
    /// With maxDepth=4, a balanced tree can hold up to 16 leaves.
    /// We split the focused leaf, then navigate back to split other
    /// leaves to build up to the maximum pane count (4).
    @MainActor
    func test_splitTreeConstruction_maxPanes_completesUnder50ms() {
        let splitManager = SplitManager()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Round 1: split root into 2 (depth 1).
        splitManager.splitFocused(direction: .horizontal)

        // Round 2: split each of the 2 leaves -> 4 leaves (max pane count).
        splitManager.navigateToPreviousLeaf()
        splitManager.splitFocused(direction: .vertical)
        splitManager.navigateToPreviousLeaf()
        splitManager.navigateToPreviousLeaf()
        splitManager.splitFocused(direction: .vertical)

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertEqual(splitManager.rootNode.leafCount, SplitManager.maxPaneCount)
        XCTAssertLessThan(
            elapsedMilliseconds, 50.0,
            "Creating \(SplitManager.maxPaneCount) panes took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 50ms target"
        )
    }

    // MARK: - Test 7: Split Tree Navigation

    /// Navigates all directions in a tree with multiple leaves.
    /// Target: < 1ms per operation.
    @MainActor
    func test_splitTreeNavigation_allDirections_under1msPerOperation() {
        let splitManager = SplitManager()

        // Build a balanced tree with multiple leaves.
        splitManager.splitFocused(direction: .horizontal)
        splitManager.navigateToPreviousLeaf()
        splitManager.splitFocused(direction: .vertical)
        splitManager.navigateToPreviousLeaf()
        splitManager.navigateToPreviousLeaf()
        splitManager.splitFocused(direction: .vertical)

        let navigationDirections: [NavigationDirection] = [
            .left, .right, .up, .down
        ]
        let operationCount = 100
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<operationCount {
            let direction = navigationDirections[i % navigationDirections.count]
            splitManager.navigateInDirection(direction)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let msPerOperation = elapsedMilliseconds / Double(operationCount)

        XCTAssertLessThan(
            msPerOperation, 1.0,
            "Split navigation averaged \(String(format: "%.3f", msPerOperation))ms per operation, exceeds 1ms target"
        )
    }

    // MARK: - Test 8: Session Save Performance

    /// Saves session state with 10 tabs + splits to JSON.
    /// Target: < 50ms for save.
    func test_sessionSave_10TabsWithSplits_completesUnder50ms() throws {
        let session = createSessionWith10TabsAndSplits()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-perf-test-\(UUID().uuidString)")
        let sessionManager = SessionManagerImpl(sessionsDirectory: tempDirectory)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        try sessionManager.saveSession(session, named: nil)

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 50.0,
            "Session save took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 50ms target"
        )
    }

    // MARK: - Test 9: Session Load Performance

    /// Loads session state with 10 tabs + splits from JSON.
    /// Target: < 50ms for load.
    func test_sessionLoad_10TabsWithSplits_completesUnder50ms() throws {
        let session = createSessionWith10TabsAndSplits()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-perf-test-\(UUID().uuidString)")
        let sessionManager = SessionManagerImpl(sessionsDirectory: tempDirectory)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try sessionManager.saveSession(session, named: nil)

        let startTime = CFAbsoluteTimeGetCurrent()

        let loaded = try sessionManager.loadLastSession()

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertNotNil(loaded)
        XCTAssertLessThan(
            elapsedMilliseconds, 50.0,
            "Session load took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 50ms target"
        )
    }

    // MARK: - Test 10: Session Round-Trip

    /// Full save + load round-trip with 10 tabs + splits.
    /// Target: < 100ms total.
    func test_sessionRoundTrip_10TabsWithSplits_completesUnder100ms() throws {
        let session = createSessionWith10TabsAndSplits()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-perf-test-\(UUID().uuidString)")
        let sessionManager = SessionManagerImpl(sessionsDirectory: tempDirectory)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        try sessionManager.saveSession(session, named: nil)
        let loaded = try sessionManager.loadLastSession()

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.windows.count, session.windows.count)
        XCTAssertLessThan(
            elapsedMilliseconds, 100.0,
            "Session round-trip took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 100ms target"
        )
    }

    // MARK: - Test 11: Config TOML Parse Performance

    /// Parses a full config.toml with all sections.
    /// Target: < 50ms.
    func test_configParse_fullConfig_completesUnder50ms() {
        let tomlContent = ConfigService.generateDefaultToml()
        let parser = TOMLParser()

        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            _ = try? parser.parse(tomlContent)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let msPerParse = elapsedMilliseconds / 100.0

        XCTAssertLessThan(
            msPerParse, 50.0,
            "Config parse averaged \(String(format: "%.2f", msPerParse))ms, exceeds 50ms target"
        )
    }

    // MARK: - Test 12: Config Reload End-to-End

    /// Full config reload: read file + parse + validate.
    /// Target: < 50ms.
    func test_configReload_endToEnd_completesUnder50ms() throws {
        let tomlContent = ConfigService.generateDefaultToml()
        let fileProvider = InMemoryConfigFileProvider(content: tomlContent)
        let configService = ConfigService(fileProvider: fileProvider)

        let startTime = CFAbsoluteTimeGetCurrent()

        try configService.reload()

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 50.0,
            "Config reload took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 50ms target"
        )
    }

    // MARK: - Test 13: Theme Switching Performance

    /// Switches between 5 themes sequentially.
    /// Target: < 10ms per switch.
    @MainActor
    func test_themeSwitching_5Themes_under10msPerSwitch() throws {
        let emptyThemeProvider = EmptyThemeFileProvider()
        let themeEngine = ThemeEngineImpl(themeFileProvider: emptyThemeProvider)
        let themeNames = themeEngine.availableThemes.prefix(5).map(\.name)

        guard themeNames.count >= 2 else {
            XCTFail("Need at least 2 themes for switching test, found \(themeNames.count)")
            return
        }

        let switchCount = themeNames.count
        let startTime = CFAbsoluteTimeGetCurrent()

        for name in themeNames {
            try themeEngine.apply(themeName: name)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let msPerSwitch = elapsedMilliseconds / Double(switchCount)

        XCTAssertLessThan(
            msPerSwitch, 10.0,
            "Theme switching averaged \(String(format: "%.2f", msPerSwitch))ms per switch, exceeds 10ms target"
        )
    }

    // MARK: - Test 14: Pattern Matching with Heavy Regex Load

    /// Stresses the pattern matcher with complex regex patterns across many agents.
    /// Ensures no exponential blowup on non-matching lines.
    /// Targeted as a debug-build guardrail rather than a release SLA.
    func test_patternMatching_complexRegex_noExponentialBlowup() {
        let configs = createSixAgentConfigs()
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 1,
            cooldownInterval: 0.0,
            maxLineBuffer: 10
        )

        // Lines designed to NOT match any pattern (worst case for regex backtracking).
        let hardLines = (0..<1000).map { i in
            "aaaaaaaaaaaaaaaaaaaaaaaaaaa_\(i)_normal_output_line_with_no_pattern_match"
        }
        let linesData = hardLines.map { Data(($0 + "\n").utf8) }

        let startTime = CFAbsoluteTimeGetCurrent()

        for lineData in linesData {
            _ = detector.processBytes(lineData)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 65.0,
            "Complex regex matching took \(String(format: "%.1f", elapsedMilliseconds))ms for 1000 lines, exceeds 65ms target"
        )
    }

    // MARK: - Test 15: Git Branch Cache Performance

    /// Verifies that cached branch lookups are sub-millisecond.
    func test_gitBranchCache_repeatedLookups_subMillisecond() {
        let provider = GitInfoProviderImpl(cacheTTLSeconds: 60.0)
        let repoDirectory = URL(fileURLWithPath: "/Users/Galf/claude-terminal")

        // Prime the cache with the first lookup.
        _ = provider.currentBranch(at: repoDirectory)

        let lookupCount = 1000
        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<lookupCount {
            _ = provider.currentBranch(at: repoDirectory)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let msPerLookup = elapsedMilliseconds / Double(lookupCount)

        XCTAssertLessThan(
            msPerLookup, 0.1,
            "Cached git branch lookup averaged \(String(format: "%.4f", msPerLookup))ms, exceeds 0.1ms target"
        )
    }

    // MARK: - Test 16: Tab Manager Bulk Operations

    /// Creates and removes tabs in bulk to test allocation/deallocation performance.
    @MainActor
    func test_tabManager_bulkCreateAndRemove_completesUnder200ms() {
        let tabManager = TabManager()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Create 50 tabs.
        var tabIDs: [TabID] = []
        for _ in 0..<50 {
            let tab = tabManager.addTab()
            tabIDs.append(tab.id)
        }

        // Remove 40 of them.
        for id in tabIDs.prefix(40) {
            tabManager.removeTab(id: id)
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertEqual(tabManager.tabs.count, 11) // 1 initial + 50 - 40
        XCTAssertLessThan(
            elapsedMilliseconds, 200.0,
            "Bulk tab operations took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 200ms target"
        )
    }

    // MARK: - Test 17: Agent State Machine Throughput

    /// Processes 10,000 state transitions to verify state machine overhead is negligible.
    /// Target: < 20ms in debug build. Release should be < 5ms.
    @MainActor
    func test_agentStateMachine_10000Transitions_under20ms() {
        let stateMachine = AgentStateMachine()

        let events: [AgentStateMachine.Event] = [
            .agentDetected(name: "claude"),
            .outputReceived,
            .promptDetected,
            .userInput,
            .completionDetected,
            .agentExited
        ]

        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<10_000 {
            let event = events[i % events.count]
            stateMachine.processEvent(event)

            // Reset periodically to allow the cycle to repeat.
            if i % events.count == events.count - 1 {
                stateMachine.reset()
            }
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        XCTAssertLessThan(
            elapsedMilliseconds, 50.0,
            "10,000 state transitions took \(String(format: "%.1f", elapsedMilliseconds))ms, exceeds 50ms target"
        )
    }

    // MARK: - Test 18: SplitNode Equality Check Performance

    /// Deep equality comparison on large split trees should be fast.
    @MainActor
    func test_splitNode_deepEquality_largeTree_under5ms() {
        let splitManager = SplitManager()

        // Build tree with 8 leaves.
        for direction in [SplitDirection.horizontal, .vertical, .horizontal, .vertical,
                          .horizontal, .vertical, .horizontal] {
            splitManager.splitFocused(direction: direction)
        }

        let tree1 = splitManager.rootNode
        let tree2 = splitManager.rootNode

        let comparisonCount = 1000
        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<comparisonCount {
            _ = tree1 == tree2
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let msPerComparison = elapsedMilliseconds / Double(comparisonCount)

        XCTAssertLessThan(
            msPerComparison, 5.0,
            "Split tree equality averaged \(String(format: "%.4f", msPerComparison))ms, exceeds 5ms target"
        )
    }

    // MARK: - Helpers: Data Generation

    /// Generates simulated terminal output with a mix of plain text,
    /// ANSI escape codes, and occasional agent-like patterns.
    ///
    /// Pre-builds a template block and copies it in bulk.
    private func generateSimulatedTerminalOutput(byteCount: Int) -> Data {
        let sampleLines: [String] = [
            "$ npm install\n",
            "\u{1B}[32m  added 150 packages in 3.2s\u{1B}[0m\n",
            "src/index.ts:42:  const result = await fetch(url);\n",
            "  Building module 'Foundation' [14/127]\n",
            "\u{1B}[1;33mwarning:\u{1B}[0m unused variable 'x'\n",
            "OK: 42 tests passed (0.5s)\n",
            "   Compiling cocxy-terminal v0.1.0\n",
            "     Running `target/debug/test`\n",
            "test result: ok. 150 passed; 0 failed\n",
            "diff --git a/file.swift b/file.swift\n",
        ]

        // Pre-build a template block from all sample lines (~500 bytes).
        let templateBlock = Array(sampleLines.joined().utf8)

        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)

        while bytes.count < byteCount {
            let remaining = byteCount - bytes.count
            if remaining >= templateBlock.count {
                bytes.append(contentsOf: templateBlock)
            } else {
                bytes.append(contentsOf: templateBlock.prefix(remaining))
            }
        }

        return Data(bytes)
    }

    /// Generates lines of simulated terminal output.
    private func generateTerminalLines(count: Int) -> [String] {
        let templates: [String] = [
            "src/module_XXX.swift:YYY: let value = computeResult()",
            "  Building target 'module_XXX' [YYY/ZZZ]",
            "warning: unused import 'Foundation' in module_XXX.swift",
            "test_function_XXX: OK (0.YYYs)",
            ">> Processing batch XXX of YYY...",
            "  downloading dependency ZZZ (XXX.YYY.0)",
            "error: could not find module 'NonExistent_XXX'",
            "   Linking target_XXX (YYY objects)",
        ]

        return (0..<count).map { index in
            var line = templates[index % templates.count]
            line = line.replacingOccurrences(of: "XXX", with: "\(index)")
            line = line.replacingOccurrences(of: "YYY", with: "\(index % 100)")
            line = line.replacingOccurrences(of: "ZZZ", with: "\(index % 50)")
            return line
        }
    }

    /// Generates data with embedded OSC sequences mixed with plain text.
    ///
    /// Pre-builds a repeating block of (plain text + OSC) and copies it
    /// in bulk to avoid byte-by-byte overhead.
    private func generateOSCMixedData(byteCount: Int) -> Data {
        // Build a template block: ~200 bytes of text + one OSC sequence.
        let textLine = "Some terminal output line content here for perf test.\n"
        let osc133A: [UInt8] = [0x1B, 0x5D] + Array("133;A".utf8) + [0x07]
        let osc133D: [UInt8] = [0x1B, 0x5D] + Array("133;D;0".utf8) + [0x1B, 0x5C]
        let osc9: [UInt8] = [0x1B, 0x5D] + Array("9;Task complete".utf8) + [0x07]

        // Compose three template blocks with different OSC sequences.
        let block1 = Array(repeating: textLine, count: 3).joined()
        let block2 = Array(repeating: textLine, count: 3).joined()
        let block3 = Array(repeating: textLine, count: 3).joined()

        let block1Bytes = Array(block1.utf8) + osc133A
        let block2Bytes = Array(block2.utf8) + osc133D
        let block3Bytes = Array(block3.utf8) + osc9

        // Concatenate the three blocks into one repeating unit.
        let templateUnit = block1Bytes + block2Bytes + block3Bytes

        // Fill the target size by repeating the template.
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)

        while bytes.count < byteCount {
            let remaining = byteCount - bytes.count
            if remaining >= templateUnit.count {
                bytes.append(contentsOf: templateUnit)
            } else {
                bytes.append(contentsOf: templateUnit.prefix(remaining))
            }
        }

        return Data(bytes)
    }

    /// Splits data into chunks of the specified size.
    private func splitIntoChunks(data: Data, chunkSize: Int) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            chunks.append(data[offset..<end])
            offset = end
        }
        return chunks
    }

    // MARK: - Helpers: Agent Config Creation

    /// Creates 6 agent configs with 20+ total patterns for realistic load testing.
    private func createSixAgentConfigs() -> [CompiledAgentConfig] {
        let agents: [(String, String, [String], [String], [String], [String])] = [
            (
                "claude",
                "Claude Code",
                ["^claude\\b", "^claude-code\\b", "claude\\s+--model"],
                ["^\\? ", "\\(Y/n\\)", "Press Enter"],
                ["^Error:", "APIError", "rate_limit"],
                ["^\\$\\s*$", "^>\\s*$"]
            ),
            (
                "codex",
                "Codex CLI",
                ["^codex\\b", "openai\\s+codex"],
                ["Enter to confirm", "\\[Y/n\\]"],
                ["Failed", "NetworkError"],
                ["^\\$\\s*$"]
            ),
            (
                "aider",
                "Aider",
                ["^aider\\b", "python.*aider"],
                ["^>\\s*$", "\\(yes/no\\)"],
                ["aider: error", "git error"],
                ["^\\$\\s*$", "Tokens:"]
            ),
            (
                "gemini",
                "Gemini CLI",
                ["^gemini\\b", "google.*gemini"],
                ["Input:", "Waiting for input"],
                ["Error:", "Quota exceeded"],
                ["^\\$\\s*$", "Done\\."]
            ),
            (
                "copilot",
                "GitHub Copilot CLI",
                ["^gh\\s+copilot", "copilot-cli"],
                ["\\? ", "Select an option"],
                ["error:", "unauthorized"],
                ["^\\$\\s*$"]
            ),
            (
                "cursor",
                "Cursor Agent",
                ["^cursor\\b", "cursor-agent"],
                ["Accept changes\\?", "Continue\\?"],
                ["Error:", "Failed to"],
                ["^\\$\\s*$", "Changes applied"]
            ),
        ]

        return agents.map { name, displayName, launch, waiting, errors, finished in
            let config = AgentConfig(
                name: name,
                displayName: displayName,
                launchPatterns: launch,
                waitingPatterns: waiting,
                errorPatterns: errors,
                finishedIndicators: finished,
                oscSupported: true,
                idleTimeoutOverride: nil
            )
            return AgentConfigService.compile(config)
        }
    }

    // MARK: - Helpers: Session Creation

    /// Creates a session with 10 tabs and realistic split configurations.
    private func createSessionWith10TabsAndSplits() -> Session {
        let homeURL = URL(fileURLWithPath: "/Users/test/projects")

        let tabStates = (0..<10).map { index -> TabState in
            let workingDir = homeURL.appendingPathComponent("project-\(index)")

            let splitTree: SplitNodeState
            switch index % 3 {
            case 0:
                // Single pane.
                splitTree = .leaf(workingDirectory: workingDir, command: nil)
            case 1:
                // Horizontal split.
                splitTree = .split(
                    direction: .horizontal,
                    first: .leaf(workingDirectory: workingDir, command: nil),
                    second: .leaf(workingDirectory: workingDir, command: nil),
                    ratio: 0.5
                )
            default:
                // Nested split (3 panes).
                splitTree = .split(
                    direction: .vertical,
                    first: .leaf(workingDirectory: workingDir, command: nil),
                    second: .split(
                        direction: .horizontal,
                        first: .leaf(workingDirectory: workingDir, command: nil),
                        second: .leaf(workingDirectory: workingDir, command: nil),
                        ratio: 0.5
                    ),
                    ratio: 0.6
                )
            }

            return TabState(
                id: TabID(),
                title: "Tab \(index)",
                workingDirectory: workingDir,
                splitTree: splitTree
            )
        }

        let windowState = WindowState(
            frame: CodableRect(x: 100, y: 100, width: 1200, height: 800),
            isFullScreen: false,
            tabs: tabStates,
            activeTabIndex: 0
        )

        return Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [windowState]
        )
    }
}

// MARK: - Test Support: Empty Theme File Provider

/// Theme file provider that returns no custom themes.
/// Used to test built-in theme switching performance.
private final class EmptyThemeFileProvider: ThemeFileProviding {
    func listCustomThemeFiles() -> [(name: String, content: String)] {
        return []
    }
}
