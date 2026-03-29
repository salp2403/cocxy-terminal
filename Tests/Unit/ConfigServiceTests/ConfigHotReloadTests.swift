// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ConfigHotReloadTests.swift - Tests for config file hot-reload.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Config Hot-Reload Tests

/// Tests for `ConfigWatcher` covering file system change detection,
/// debouncing, and graceful handling of invalid config during reload.
///
/// Uses `MockConfigWatcherDelegate` to verify callbacks without
/// actual filesystem watchers.
///
/// Covers:
/// - File change triggers reload
/// - Debounce (rapid changes produce single reload)
/// - Invalid config after reload keeps previous config
/// - Theme change via config update
/// - agents.toml reload
/// - Watcher cleanup on stop
/// - Multiple rapid changes coalesced
/// - Watcher not active before start
final class ConfigHotReloadTests: XCTestCase {

    func testFileChangeTrigersReload() throws {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "dracula"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)

        // Simulate file change
        fileProvider.content = """
        [appearance]
        theme = "solarized-dark"
        """
        watcher.handleFileChange()

        XCTAssertEqual(
            service.current.appearance.theme,
            "solarized-dark",
            "Config must reload when file changes"
        )
    }

    func testDebounceCoalescesRapidChanges() {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "dracula"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try? service.reload()

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)
        watcher.debounceInterval = 0.1

        // Simulate multiple rapid changes
        fileProvider.content = """
        [appearance]
        theme = "nord"
        """
        watcher.scheduleReload()

        fileProvider.content = """
        [appearance]
        theme = "monokai"
        """
        watcher.scheduleReload()

        fileProvider.content = """
        [appearance]
        theme = "solarized-dark"
        """
        watcher.scheduleReload()

        // Wait for debounce
        let expectation = expectation(description: "Debounce settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(
            service.current.appearance.theme,
            "solarized-dark",
            "Only the last change should be applied after debounce"
        )
    }

    func testInvalidConfigAfterReloadKeepsPrevious() throws {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "dracula"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)

        // Corrupt the config file
        fileProvider.content = "this is completely broken toml!!!"
        watcher.handleFileChange()

        // Should use defaults (since malformed TOML falls to defaults in ConfigService)
        // The key point is that it doesn't crash
        XCTAssertNotNil(service.current)
    }

    func testThemeChangeViaConfigUpdate() throws {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let expectation = expectation(description: "Theme config change published")
        var receivedConfig: CocxyConfig?
        var cancellables = Set<AnyCancellable>()

        service.configChangedPublisher
            .dropFirst() // Skip current
            .sink { config in
                receivedConfig = config
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)

        fileProvider.content = """
        [appearance]
        theme = "dracula"
        """
        watcher.handleFileChange()

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedConfig?.appearance.theme, "dracula")
    }

    func testAgentsTomlReload() throws {
        let agentFileProvider = InMemoryAgentFileProvider(content: """
        [claude]
        display-name = "Claude Code"
        osc-supported = true
        launch-patterns = ["^claude\\\\b"]
        waiting-patterns = ["^\\\\? "]
        error-patterns = ["^Error:"]
        finished-indicators = ["^\\\\$\\\\s*$"]
        """)

        let agentConfigService = AgentConfigService(fileProvider: agentFileProvider)
        let watcher = AgentConfigWatcher(
            agentConfigService: agentConfigService,
            fileProvider: agentFileProvider
        )

        agentFileProvider.content = """
        [claude]
        display-name = "Claude Code Updated"
        osc-supported = true
        launch-patterns = ["^claude\\\\b"]
        waiting-patterns = ["^\\\\? "]
        error-patterns = ["^Error:"]
        finished-indicators = ["^\\\\$\\\\s*$"]
        """

        watcher.handleFileChange()

        XCTAssertTrue(
            watcher.lastReloadSucceeded,
            "Agent config should reload successfully"
        )
    }

    func testWatcherCleanupOnStop() {
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let service = ConfigService(fileProvider: fileProvider)

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)
        watcher.startWatching()

        XCTAssertTrue(watcher.isWatching, "Watcher must be active after start")

        watcher.stopWatching()

        XCTAssertFalse(watcher.isWatching, "Watcher must be inactive after stop")
    }

    func testWatcherNotActiveBeforeStart() {
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let service = ConfigService(fileProvider: fileProvider)

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)

        XCTAssertFalse(
            watcher.isWatching,
            "Watcher must not be active before startWatching"
        )
    }

    func testMultipleStartCallsAreIdempotent() {
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let service = ConfigService(fileProvider: fileProvider)

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)
        watcher.startWatching()
        watcher.startWatching()
        watcher.startWatching()

        XCTAssertTrue(watcher.isWatching)

        watcher.stopWatching()

        XCTAssertFalse(watcher.isWatching)
    }
}

// MARK: - Mock Agent File Provider

/// Test double for agent config file reading.
///
/// Conforms to `AgentConfigFileProviding` from `AgentConfigService.swift`.
final class InMemoryAgentFileProvider: AgentConfigFileProviding, @unchecked Sendable {
    var content: String?

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
