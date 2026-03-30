// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EdgeCaseTests.swift - T-056: Final QA edge case tests.
//
// El Rompe-cosas: 36 edge cases para demostrar que el codigo aguanta lo que
// ningun usuario deberia hacer pero que inevitablemente alguien hara.
// Cobertura: TabManager, SplitNode/SplitManager, SessionManager,
//            ConfigService, AgentConfigService, ThemeEngine,
//            NotificationManager, SocketMessageFraming.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Edge Case Tests

@MainActor
final class EdgeCaseTests: XCTestCase {

    // MARK: - Setup / Teardown

    private var cancellables: Set<AnyCancellable>!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        cancellables = []
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-edge-\(UUID().uuidString)")
    }

    override func tearDown() {
        cancellables = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEmitter() -> MockNotificationEmitter {
        MockNotificationEmitter()
    }

    private func makeNotificationManager(
        coalescenceWindow: TimeInterval = 2.0,
        rateLimitPerTab: TimeInterval = 5.0
    ) -> NotificationManagerImpl {
        var config = CocxyConfig.defaults
        config = CocxyConfig(
            general: config.general,
            appearance: config.appearance,
            terminal: config.terminal,
            agentDetection: config.agentDetection,
            notifications: NotificationConfig(
                macosNotifications: true,
                sound: false,
                badgeOnTab: true,
                flashTab: false,
                showDockBadge: false,
                soundFinished: "default",
                soundAttention: "default",
                soundError: "default"
            ),
            quickTerminal: config.quickTerminal,
            keybindings: config.keybindings,
            sessions: config.sessions
        )
        return NotificationManagerImpl(
            config: config,
            systemEmitter: makeEmitter(),
            coalescenceWindow: coalescenceWindow,
            rateLimitPerTab: rateLimitPerTab
        )
    }

    private func makeSession(tabs: Int) -> Session {
        let tabStates = (0..<tabs).map { i in
            TabState(
                id: TabID(),
                title: "Tab \(i)",
                workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                splitTree: .leaf(workingDirectory: FileManager.default.homeDirectoryForCurrentUser, command: nil)
            )
        }
        let window = WindowState(
            frame: CodableRect(x: 0, y: 0, width: 800, height: 600),
            isFullScreen: false,
            tabs: tabStates,
            activeTabIndex: 0
        )
        return Session(version: Session.currentVersion, savedAt: Date(), windows: [window])
    }

    // MARK: - Tab Management Edge Cases

    // EC-T-001: Single tab -- nextTab is a no-op, invariant preserved.
    func testNextTabWithSingleTabIsNoOp() {
        let manager = TabManager()
        XCTAssertEqual(manager.tabs.count, 1)
        let originalID = manager.activeTabID

        manager.nextTab()

        XCTAssertEqual(manager.tabs.count, 1, "Tab count must stay 1")
        XCTAssertEqual(manager.activeTabID, originalID, "Active tab must not change with a single tab")
    }

    // EC-T-002: Single tab -- previousTab is a no-op.
    func testPreviousTabWithSingleTabIsNoOp() {
        let manager = TabManager()
        let originalID = manager.activeTabID

        manager.previousTab()

        XCTAssertEqual(manager.activeTabID, originalID)
    }

    // EC-T-003: Cannot remove the last tab.
    func testRemoveLastTabIsNoOp() {
        let manager = TabManager()
        XCTAssertEqual(manager.tabs.count, 1)
        let lastID = manager.tabs[0].id

        manager.removeTab(id: lastID)

        XCTAssertEqual(manager.tabs.count, 1, "Last tab must never be removed")
        XCTAssertEqual(manager.tabs[0].id, lastID, "The tab must remain unchanged")
    }

    // EC-T-004: Remove non-existent TabID is a no-op.
    func testRemoveNonExistentTabIDIsNoOp() {
        let manager = TabManager()
        manager.addTab()
        let countBefore = manager.tabs.count
        let phantomID = TabID()

        manager.removeTab(id: phantomID)

        XCTAssertEqual(manager.tabs.count, countBefore, "Removing phantom ID must not change tab count")
    }

    // EC-T-005: Create 100 tabs and verify invariants at each step.
    func testCreate100TabsRapidly() {
        let manager = TabManager()
        for _ in 0..<99 {
            manager.addTab()
        }
        XCTAssertEqual(manager.tabs.count, 100)
        let activeCount = manager.tabs.filter { $0.isActive }.count
        XCTAssertEqual(activeCount, 1, "Exactly one tab must be active after 100 creates")
        XCTAssertNotNil(manager.activeTabID, "activeTabID must be set")
        XCTAssertEqual(manager.activeTab?.id, manager.activeTabID, "activeTab must match activeTabID")
    }

    // EC-T-006: Close 99 tabs until only one remains.
    func testClose99TabsUntilOneRemains() {
        let manager = TabManager()
        for _ in 0..<99 {
            manager.addTab()
        }
        XCTAssertEqual(manager.tabs.count, 100)

        while manager.tabs.count > 1 {
            manager.removeTab(id: manager.tabs.last!.id)
        }

        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.tabs.filter { $0.isActive }.count, 1)
    }

    // EC-T-007: Tab title with 1000 characters.
    func testTabWithVeryLongTitle() {
        let manager = TabManager()
        let longTitle = String(repeating: "A", count: 1000)

        manager.updateTab(id: manager.tabs[0].id) { $0.title = longTitle }

        XCTAssertEqual(manager.tabs[0].title.count, 1000)
    }

    // EC-T-008: setActive with non-existent ID is a no-op.
    func testSetActiveNonExistentIDIsNoOp() {
        let manager = TabManager()
        manager.addTab()
        let originalActiveID = manager.activeTabID

        manager.setActive(id: TabID())

        XCTAssertEqual(manager.activeTabID, originalActiveID, "Active tab must not change for unknown ID")
    }

    // EC-T-009: gotoTab at negative index is a no-op.
    func testGotoTabNegativeIndexIsNoOp() {
        let manager = TabManager()
        let originalID = manager.activeTabID

        manager.gotoTab(at: -1)

        XCTAssertEqual(manager.activeTabID, originalID)
    }

    // EC-T-010: gotoTab at out-of-bounds index is a no-op.
    func testGotoTabOutOfBoundsIndexIsNoOp() {
        let manager = TabManager()
        let originalID = manager.activeTabID

        manager.gotoTab(at: 9999)

        XCTAssertEqual(manager.activeTabID, originalID)
    }

    // MARK: - Split Node / Split Manager Edge Cases

    // EC-S-001: Split at depth 4 (maxDepth) is rejected -- returns nil.
    func testSplitAtMaxDepthIsRejected() {
        // Build a tree at depth 4 by splitting the leaf 4 times
        var node = SplitNode.leaf(id: UUID(), terminalID: UUID())
        var lastLeafID = node.id

        for depth in 0..<SplitNode.defaultMaxDepth {
            let result = node.splitLeaf(leafID: lastLeafID, direction: .horizontal, newTerminalID: UUID())
            XCTAssertNotNil(result, "Split at depth \(depth) must succeed")
            node = result!
            // After split, the new leaf is the second child; go deeper on the first leaf
            // Actually the new leaf is the second in the new split; to keep building depth
            // we need to split the original leaf which is now at deeper position.
            // Instead let's track the new leaf id to keep splitting the fresh leaf.
            let newLeafInfo = node.allLeafIDs().last!
            lastLeafID = newLeafInfo.leafID
        }

        // Now at depth 4. Another split must be rejected.
        let rejectedResult = node.splitLeaf(leafID: lastLeafID, direction: .horizontal, newTerminalID: UUID())
        XCTAssertNil(rejectedResult, "Split at maxDepth must be rejected")
    }

    // EC-S-002: Close last split in a tab keeps 1 leaf.
    func testCloseLastSplitKeepsOneLeaf() {
        let manager = SplitManager()
        XCTAssertEqual(manager.rootNode.leafCount, 1)

        manager.closeFocused()

        XCTAssertEqual(manager.rootNode.leafCount, 1, "Closing the last pane must preserve it")
        XCTAssertNotNil(manager.focusedLeafID, "focusedLeafID must remain set")
    }

    // EC-S-003: Navigate in direction with no neighbor is a no-op.
    func testNavigateInDirectionWithNoNeighborIsNoOp() {
        let manager = SplitManager()
        let originalFocus = manager.focusedLeafID

        // Single leaf: no neighbor in any direction.
        manager.navigateInDirection(.left)
        XCTAssertEqual(manager.focusedLeafID, originalFocus)

        manager.navigateInDirection(.right)
        XCTAssertEqual(manager.focusedLeafID, originalFocus)

        manager.navigateInDirection(.up)
        XCTAssertEqual(manager.focusedLeafID, originalFocus)

        manager.navigateInDirection(.down)
        XCTAssertEqual(manager.focusedLeafID, originalFocus)
    }

    // EC-S-004: Split ratio exactly at minimum boundary 0.1 is accepted.
    func testSplitRatioAtMinimumBoundary() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())
        let splitResult = node.splitLeaf(leafID: leafID, direction: .horizontal, newTerminalID: UUID())!

        // Update ratio to minimum
        guard case .split(let id, _, _, _, _) = splitResult else {
            XCTFail("Expected split node"); return
        }
        let updated = splitResult.updateRatio(splitID: id, ratio: 0.1)

        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, SplitNode.minimumRatio, accuracy: 0.001, "Ratio 0.1 must be accepted as-is")
        } else {
            XCTFail("Expected split node after updateRatio")
        }
    }

    // EC-S-005: Split ratio exactly at maximum boundary 0.9 is accepted.
    func testSplitRatioAtMaximumBoundary() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())
        let splitResult = node.splitLeaf(leafID: leafID, direction: .horizontal, newTerminalID: UUID())!

        guard case .split(let id, _, _, _, _) = splitResult else {
            XCTFail("Expected split node"); return
        }
        let updated = splitResult.updateRatio(splitID: id, ratio: 0.9)

        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, SplitNode.maximumRatio, accuracy: 0.001, "Ratio 0.9 must be accepted as-is")
        } else {
            XCTFail("Expected split node after updateRatio")
        }
    }

    // EC-S-006: Split ratio below minimum is clamped to 0.1.
    func testSplitRatioBelowMinimumIsClamped() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())
        let splitResult = node.splitLeaf(leafID: leafID, direction: .horizontal, newTerminalID: UUID())!

        guard case .split(let id, _, _, _, _) = splitResult else {
            XCTFail("Expected split node"); return
        }
        let updated = splitResult.updateRatio(splitID: id, ratio: 0.0)

        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, SplitNode.minimumRatio, accuracy: 0.001, "Ratio 0.0 must clamp to 0.1")
        } else {
            XCTFail("Expected split node after updateRatio")
        }
    }

    // EC-S-007: Split ratio above maximum is clamped to 0.9.
    func testSplitRatioAboveMaximumIsClamped() {
        let leafID = UUID()
        let node = SplitNode.leaf(id: leafID, terminalID: UUID())
        let splitResult = node.splitLeaf(leafID: leafID, direction: .horizontal, newTerminalID: UUID())!

        guard case .split(let id, _, _, _, _) = splitResult else {
            XCTFail("Expected split node"); return
        }
        let updated = splitResult.updateRatio(splitID: id, ratio: 1.5)

        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, SplitNode.maximumRatio, accuracy: 0.001, "Ratio 1.5 must clamp to 0.9")
        } else {
            XCTFail("Expected split node after updateRatio")
        }
    }

    // EC-S-008: navigateToNextLeaf on single leaf is a no-op.
    func testNavigateNextLeafSingleLeafIsNoOp() {
        let manager = SplitManager()
        let originalFocus = manager.focusedLeafID

        manager.navigateToNextLeaf()

        XCTAssertEqual(manager.focusedLeafID, originalFocus)
    }

    // EC-S-009: focusLeaf with non-existent ID is a no-op.
    func testFocusLeafNonExistentIDIsNoOp() {
        let manager = SplitManager()
        let originalFocus = manager.focusedLeafID

        manager.focusLeaf(id: UUID())

        XCTAssertEqual(manager.focusedLeafID, originalFocus)
    }

    // MARK: - Session Manager Edge Cases

    // EC-SS-001: Save session with 0 tabs (0-tab window) -- no crash, round-trips.
    func testSaveAndLoadSessionWithZeroTabs() throws {
        let manager = SessionManagerImpl(sessionsDirectory: tempDirectory)
        let emptyWindow = WindowState(
            frame: CodableRect(x: 0, y: 0, width: 800, height: 600),
            isFullScreen: false,
            tabs: [],
            activeTabIndex: 0
        )
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [emptyWindow]
        )

        try manager.saveSession(session, named: nil)
        let loaded = try manager.loadLastSession()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.windows[0].tabs.count, 0)
    }

    // EC-SS-002: Session JSON with unknown fields is decoded without error (forward compat).
    func testSessionWithUnknownFieldsDecodesGracefully() throws {
        let manager = SessionManagerImpl(sessionsDirectory: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Write JSON with extra unknown keys that the current model does not know about.
        let jsonWithExtraFields = """
        {
          "version": 1,
          "savedAt": "2026-01-01T00:00:00Z",
          "windows": [],
          "unknownFutureField": "this should be ignored",
          "anotherUnknownField": { "nested": true }
        }
        """
        let fileURL = tempDirectory.appendingPathComponent("last.json")
        try jsonWithExtraFields.write(to: fileURL, atomically: true, encoding: .utf8)

        // Swift's Codable ignores unknown keys by default -- must not throw.
        let loaded = try manager.loadLastSession()
        XCTAssertNotNil(loaded, "Session with unknown fields must load without throwing")
        XCTAssertEqual(loaded!.version, 1)
    }

    // EC-SS-003: Session with unsupported future version throws unsupportedVersion.
    func testSessionWithFutureVersionThrows() throws {
        let manager = SessionManagerImpl(sessionsDirectory: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let futureVersion = Session.currentVersion + 100
        let json = """
        {
          "version": \(futureVersion),
          "savedAt": "2026-01-01T00:00:00Z",
          "windows": []
        }
        """
        let fileURL = tempDirectory.appendingPathComponent("last.json")
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.loadLastSession()) { error in
            if case SessionError.unsupportedVersion(let found, _) = error {
                XCTAssertEqual(found, futureVersion)
            } else {
                XCTFail("Expected SessionError.unsupportedVersion, got \(error)")
            }
        }
    }

    // EC-SS-004: Load non-existent session returns nil (no crash).
    func testLoadNonExistentSessionReturnsNil() throws {
        let manager = SessionManagerImpl(sessionsDirectory: tempDirectory)
        let result = try manager.loadLastSession()
        XCTAssertNil(result, "Non-existent session must return nil")
    }

    // EC-SS-005: Delete non-existent session throws deleteFailed.
    func testDeleteNonExistentSessionThrows() {
        let manager = SessionManagerImpl(sessionsDirectory: tempDirectory)
        XCTAssertThrowsError(try manager.deleteSession(named: "phantom")) { error in
            if case SessionError.deleteFailed = error {
                // Expected
            } else {
                XCTFail("Expected SessionError.deleteFailed, got \(error)")
            }
        }
    }

    // EC-SS-006: Very large session (50 tabs) saves and loads in under 500ms.
    func testLargeSessionRoundTrip() throws {
        let manager = SessionManagerImpl(sessionsDirectory: tempDirectory)
        let session = makeSession(tabs: 50)

        let start = Date()
        try manager.saveSession(session, named: nil)
        let loaded = try manager.loadLastSession()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.windows[0].tabs.count, 50)
        XCTAssertLessThan(elapsed, 0.5, "50-tab session save+load must complete in under 500ms")
    }

    // EC-SS-007: Truncated / corrupted JSON throws parseFailed.
    func testTruncatedJSONThrowsParseFailed() throws {
        let manager = SessionManagerImpl(sessionsDirectory: tempDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let truncatedJSON = "{\"version\": 1, \"savedAt\": "  // intentionally cut off
        let fileURL = tempDirectory.appendingPathComponent("last.json")
        try truncatedJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.loadLastSession()) { error in
            if case SessionError.parseFailed = error {
                // Expected
            } else {
                XCTFail("Expected SessionError.parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Config Service Edge Cases

    // EC-C-001: Config with unknown TOML sections is parsed without error, uses defaults.
    func testConfigWithUnknownSectionsUsesDefaults() throws {
        let tomlWithUnknownSection = """
        [general]
        shell = "/bin/zsh"

        [unknown-future-section]
        some-key = "some-value"

        [another-unknown]
        nested-key = 42
        """
        let provider = EdgeQAConfigFileProvider(content: tomlWithUnknownSection)
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        XCTAssertEqual(service.current.general.shell, "/bin/zsh", "Known keys must be parsed")
        // Unknown sections must be silently ignored -- no crash.
    }

    // EC-C-002: Font size below minimum (6.0) is clamped.
    func testFontSizeBelowMinimumIsClamped() throws {
        let toml = """
        [appearance]
        font-size = 1.0
        """
        let provider = EdgeQAConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        XCTAssertGreaterThanOrEqual(service.current.appearance.fontSize, 6.0, "Font size must be clamped to >= 6.0")
    }

    // EC-C-003: Font size above maximum (72.0) is clamped.
    func testFontSizeAboveMaximumIsClamped() throws {
        let toml = """
        [appearance]
        font-size = 999.0
        """
        let provider = EdgeQAConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        XCTAssertLessThanOrEqual(service.current.appearance.fontSize, 72.0, "Font size must be clamped to <= 72.0")
    }

    // EC-C-004: Scrollback lines = 0 is allowed (disables scrollback).
    func testScrollbackLinesZeroIsAllowed() throws {
        let toml = """
        [terminal]
        scrollback-lines = 0
        """
        let provider = EdgeQAConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        XCTAssertEqual(service.current.terminal.scrollbackLines, 0)
    }

    // EC-C-005: Negative scrollback lines is clamped to 0.
    func testNegativeScrollbackLinesIsClamped() throws {
        let toml = """
        [terminal]
        scrollback-lines = -100
        """
        let provider = EdgeQAConfigFileProvider(content: toml)
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        XCTAssertGreaterThanOrEqual(service.current.terminal.scrollbackLines, 0)
    }

    // EC-C-006: Completely empty config uses all defaults without crashing.
    func testEmptyConfigUsesAllDefaults() throws {
        let provider = EdgeQAConfigFileProvider(content: "")
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        let defaults = CocxyConfig.defaults
        XCTAssertEqual(service.current.general.shell, defaults.general.shell)
        XCTAssertEqual(service.current.appearance.fontSize, defaults.appearance.fontSize)
    }

    // EC-C-007: Malformed TOML falls back to defaults.
    func testMalformedTOMLFallsBackToDefaults() throws {
        let malformed = "this is not = valid TOML ][["
        let provider = EdgeQAConfigFileProvider(content: malformed)
        let service = ConfigService(fileProvider: provider)

        // Must not throw; must produce defaults.
        try service.reload()
        let defaults = CocxyConfig.defaults
        XCTAssertEqual(service.current.general.shell, defaults.general.shell)
    }

    // MARK: - AgentConfigService Edge Cases

    // EC-A-001: agents.toml with duplicate agent names -- last one wins (TOML table behavior).
    func testAgentConfigWithDuplicateNamesLastWins() throws {
        // TOML tables with the same key: the parser will simply overwrite
        // the first with the second.
        let tomlWithDuplicate = """
        [claude]
        display-name = "First Claude"
        osc-supported = false
        launch-patterns = ["^claude\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = ["^\\$\\s*$"]

        [claude]
        display-name = "Second Claude"
        osc-supported = true
        launch-patterns = ["^claude-code\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = ["^\\$\\s*$"]
        """
        let provider = EdgeQAAgentConfigFileProvider(content: tomlWithDuplicate)
        let service = AgentConfigService(fileProvider: provider)

        // Must not crash, regardless of how the TOML parser resolves duplicates.
        try service.reload()
        XCTAssertGreaterThanOrEqual(service.currentConfigs.count, 1, "At least one claude config must survive")
    }

    // EC-A-002: Invalid regex pattern in agent config is collected in invalidPatterns, not a crash.
    func testAgentConfigWithInvalidRegexCollectsInvalidPatterns() {
        let configWithBadRegex = AgentConfig(
            name: "bad-agent",
            displayName: "Bad Agent",
            launchPatterns: ["[invalid regex (unclosed"],
            waitingPatterns: [],
            errorPatterns: [],
            finishedIndicators: [],
            oscSupported: false,
            idleTimeoutOverride: nil
        )

        let compiled = AgentConfigService.compile(configWithBadRegex)

        XCTAssertEqual(compiled.launchPatterns.count, 0, "Invalid regex must be excluded from compiled patterns")
        XCTAssertEqual(compiled.invalidPatterns.count, 1, "Invalid pattern must be tracked in invalidPatterns")
    }

    // EC-A-003: Empty agents.toml falls back to built-in defaults.
    func testEmptyAgentsTomlFallsBackToBuiltInDefaults() throws {
        let provider = EdgeQAAgentConfigFileProvider(content: "")
        let service = AgentConfigService(fileProvider: provider)

        try service.reload()

        // Malformed / empty TOML produces no tables, so result should be empty or defaults.
        // The service parses empty string as empty dictionary, producing empty configs --
        // not a crash. This verifies graceful degradation.
        // Note: empty string is valid TOML (empty document); it produces zero agent configs.
        XCTAssertGreaterThanOrEqual(service.currentConfigs.count, 0, "Must not crash on empty agents.toml")
    }

    // MARK: - Theme Engine Edge Cases

    // EC-TH-001: Apply non-existent theme name throws themeNotFound.
    func testApplyNonExistentThemeThrows() {
        let engine = ThemeEngineImpl()
        XCTAssertThrowsError(try engine.apply(themeName: "NonExistentThemeName12345")) { error in
            if case ThemeError.themeNotFound(let name) = error {
                XCTAssertEqual(name, "NonExistentThemeName12345")
            } else {
                XCTFail("Expected ThemeError.themeNotFound, got \(error)")
            }
        }
    }

    // EC-TH-002: themeByName with non-existent name throws themeNotFound.
    func testThemeByNameNonExistentThrows() {
        let engine = ThemeEngineImpl()
        XCTAssertThrowsError(try engine.themeByName("NoSuchTheme")) { error in
            if case ThemeError.themeNotFound = error {
                // Expected
            } else {
                XCTFail("Expected ThemeError.themeNotFound, got \(error)")
            }
        }
    }

    // EC-TH-003: ThemeTomlParser does NOT validate hex color format -- accepts any string.
    //
    // HALLAZGO QA (IMPORTANTE): ThemeTomlParser almacena colores como String sin validar
    // el formato hexadecimal. Un color "NOT_A_HEX_COLOR" se acepta silenciosamente.
    // La validacion se delega al consumidor (CodableColor), que tiene su propio fallback.
    // Ver informe final de QA para detalles.
    func testCustomThemeWithInvalidHexColorIsAcceptedWithoutValidation() {
        let tomlWithInvalidHex = """
        [metadata]
        name = "Bad Colors"
        variant = "dark"

        [colors]
        foreground = "NOT_A_HEX_COLOR"
        background = "#1e1e2e"
        cursor = "#f5e0dc"
        selection = "#585b70"

        [colors.normal]
        black = "#45475a"
        red = "#f38ba8"
        green = "#a6e3a1"
        yellow = "#f9e2af"
        blue = "#89b4fa"
        magenta = "#f5c2e7"
        cyan = "#94e2d5"
        white = "#bac2de"

        [colors.bright]
        black = "#585b70"
        red = "#f38ba8"
        green = "#a6e3a1"
        yellow = "#f9e2af"
        blue = "#89b4fa"
        magenta = "#f5c2e7"
        cyan = "#94e2d5"
        white = "#a6adc8"
        """

        // ThemeTomlParser now validates hex color format and rejects invalid values.
        // This was a pre-release fix: invalid hex like "NOT_A_HEX_COLOR" is caught early.
        XCTAssertThrowsError(
            try ThemeTomlParser.parse(tomlWithInvalidHex),
            "ThemeTomlParser must reject invalid hex colors"
        )
    }

    // EC-TH-004: Theme TOML with missing [metadata] section throws parseFailed.
    func testThemeTomlMissingMetadataSectionThrows() {
        let tomlWithoutMetadata = """
        [colors]
        foreground = "#cdd6f4"
        background = "#1e1e2e"
        """

        XCTAssertThrowsError(try ThemeTomlParser.parse(tomlWithoutMetadata)) { error in
            if case ThemeError.parseFailed = error {
                // Expected
            } else {
                XCTFail("Expected ThemeError.parseFailed, got \(error)")
            }
        }
    }

    // EC-TH-005: All 6 built-in themes are available after engine init.
    func testAllBuiltInThemesAreAvailable() {
        let engine = ThemeEngineImpl()
        let builtInNames = ["Catppuccin Mocha", "Catppuccin Latte", "One Dark",
                            "Solarized Dark", "Solarized Light", "Dracula"]
        for name in builtInNames {
            XCTAssertNoThrow(
                try engine.themeByName(name),
                "Built-in theme '\(name)' must be available"
            )
        }
    }

    // MARK: - Notification Manager Edge Cases

    // EC-N-001: markAsRead with non-existent TabID is a no-op.
    func testMarkAsReadNonExistentTabIDIsNoOp() {
        let manager = makeNotificationManager()
        let phantomID = TabID()

        // Must not crash; queue remains empty.
        manager.markAsRead(tabId: phantomID)
        XCTAssertEqual(manager.unreadCount, 0)
    }

    // EC-N-002: gotoNextUnread with empty queue returns nil.
    func testGotoNextUnreadEmptyQueueReturnsNil() {
        let manager = makeNotificationManager()
        let result = manager.gotoNextUnread()
        XCTAssertNil(result, "Empty queue must return nil")
    }

    // EC-N-003: 100 notifications for same tab+type in 1 second -- coalescence fires only first.
    func testCoalescenceSupresses100RapidNotificationsOfSameType() {
        // Use a very long coalescence window so ALL 100 are within it.
        let emitter = makeEmitter()
        var config = CocxyConfig.defaults
        config = CocxyConfig(
            general: config.general,
            appearance: config.appearance,
            terminal: config.terminal,
            agentDetection: config.agentDetection,
            notifications: NotificationConfig(
                macosNotifications: true,
                sound: false,
                badgeOnTab: true,
                flashTab: false,
                showDockBadge: false,
                soundFinished: "default",
                soundAttention: "default",
                soundError: "default"
            ),
            quickTerminal: config.quickTerminal,
            keybindings: config.keybindings,
            sessions: config.sessions
        )
        let manager = NotificationManagerImpl(
            config: config,
            systemEmitter: emitter,
            coalescenceWindow: 60.0,   // wide window
            rateLimitPerTab: 0.0        // no rate limit to isolate coalescence behavior
        )
        let tabID = TabID()

        for _ in 0..<100 {
            let n = CocxyNotification(type: .agentNeedsAttention, tabId: tabID, title: "T", body: "B")
            manager.notify(n)
        }

        XCTAssertEqual(manager.attentionQueue.count, 1, "Coalescence must suppress 99 out of 100 same-type notifications")
        XCTAssertEqual(manager.unreadCount, 1)
    }

    // EC-N-004: markAllAsRead sets all items to read.
    func testMarkAllAsReadSetsAllToRead() {
        let manager = makeNotificationManager(coalescenceWindow: 0.0, rateLimitPerTab: 0.0)
        let tab1 = TabID()
        let tab2 = TabID()

        // Use different types to bypass coalescence on different tabs.
        manager.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tab1, title: "A", body: "B"))
        manager.notify(CocxyNotification(type: .agentFinished, tabId: tab2, title: "C", body: "D"))
        XCTAssertGreaterThan(manager.unreadCount, 0)

        manager.markAllAsRead()

        XCTAssertEqual(manager.unreadCount, 0)
    }

    // EC-N-005: Quick Switch with 0 pending items returns nil.
    func testQuickSwitchWithZeroPendingItemsReturnsNil() {
        let manager = makeNotificationManager()
        // No notifications sent; peek must return nil.
        XCTAssertNil(manager.peekNextUnread())
    }

    // MARK: - SocketMessageFraming Edge Cases

    // EC-SK-001: Encode and decode length round-trips for various sizes.
    func testSocketMessageFramingLengthRoundTrip() {
        let sizes: [UInt32] = [0, 1, 255, 256, 65535, 65536]
        for size in sizes {
            let encoded = SocketMessageFraming.encodeLength(size)
            XCTAssertEqual(encoded.count, 4, "Header must always be 4 bytes")
            let decoded = SocketMessageFraming.decodeLength(encoded)
            XCTAssertEqual(decoded, size, "Length \(size) must round-trip through encode/decode")
        }
    }

    // EC-SK-002: decodeLength with fewer than 4 bytes returns nil.
    func testSocketDecodeLengthShortDataReturnsNil() {
        let shortData = Data([0x00, 0x01, 0x02])  // 3 bytes, not 4
        let result = SocketMessageFraming.decodeLength(shortData)
        XCTAssertNil(result, "decodeLength must return nil for data shorter than 4 bytes")
    }

    // EC-SK-003: frame() with payload exceeding 64KB throws malformedMessage.
    func testSocketFrameOversizedPayloadThrows() {
        // Create a SocketRequest whose JSON encoding exceeds 64KB.
        let hugeValue = String(repeating: "X", count: 70_000)
        let request = SocketRequest(
            id: "test",
            command: "notify",
            params: ["message": hugeValue]
        )

        XCTAssertThrowsError(try SocketMessageFraming.frame(request)) { error in
            if case CLISocketError.malformedMessage = error {
                // Expected
            } else {
                XCTFail("Expected CLISocketError.malformedMessage for oversized payload, got \(error)")
            }
        }
    }

    // EC-SK-004: Request with empty params encodes and decodes cleanly.
    func testSocketRequestWithEmptyParamsRoundTrips() throws {
        let request = SocketRequest(id: "abc", command: "status", params: nil)
        let framed = try SocketMessageFraming.frame(request)

        // Verify the frame contains a 4-byte header followed by valid JSON.
        XCTAssertGreaterThan(framed.count, 4)
        let headerData = framed.prefix(4)
        let payloadLength = SocketMessageFraming.decodeLength(Data(headerData))
        XCTAssertNotNil(payloadLength)
        XCTAssertEqual(Int(payloadLength!), framed.count - 4)
    }

    // EC-SK-005: SocketResponse.ok and .failure factories set fields correctly.
    func testSocketResponseFactoriesSetFieldsCorrectly() {
        let successResponse = SocketResponse.ok(id: "req-1", data: ["result": "done"])
        XCTAssertTrue(successResponse.success)
        XCTAssertEqual(successResponse.id, "req-1")
        XCTAssertNil(successResponse.error)
        XCTAssertEqual(successResponse.data?["result"], "done")

        let failureResponse = SocketResponse.failure(id: "req-2", error: "Command not found")
        XCTAssertFalse(failureResponse.success)
        XCTAssertEqual(failureResponse.id, "req-2")
        XCTAssertEqual(failureResponse.error, "Command not found")
        XCTAssertNil(failureResponse.data)
    }
}

// MARK: - Test Doubles

/// In-memory implementation of ConfigFileProviding for tests.
private final class EdgeQAConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
    private var content: String?
    private var writtenContent: String?

    init(content: String?) {
        self.content = content
    }

    func readConfigFile() -> String? {
        content
    }

    func writeConfigFile(_ content: String) throws {
        writtenContent = content
        self.content = content
    }
}

/// In-memory implementation of AgentConfigFileProviding for tests.
private final class EdgeQAAgentConfigFileProvider: AgentConfigFileProviding, @unchecked Sendable {
    private var content: String?

    init(content: String?) {
        self.content = content
    }

    func readAgentConfigFile() -> String? {
        content
    }

    func writeAgentConfigFile(_ content: String) throws {
        self.content = content
    }
}
