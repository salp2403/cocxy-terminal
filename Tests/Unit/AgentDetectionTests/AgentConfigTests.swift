// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentConfigTests.swift - Tests for AgentConfig model and AgentConfigService.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Agent Config Model Tests

/// Tests for the `AgentConfig` struct.
///
/// Covers:
/// - Codable round-trip encoding/decoding.
/// - Equatable conformance.
/// - All fields are correctly stored.

final class AgentConfigModelTests: XCTestCase {

    func testAgentConfigStoresAllFields() {
        let config = AgentConfig(
            name: "test-agent",
            displayName: "Test Agent",
            launchPatterns: ["^test\\b"],
            waitingPatterns: ["\\? "],
            errorPatterns: ["Error:"],
            finishedIndicators: ["^\\$\\s*$"],
            oscSupported: true,
            idleTimeoutOverride: 15.0
        )

        XCTAssertEqual(config.name, "test-agent")
        XCTAssertEqual(config.displayName, "Test Agent")
        XCTAssertEqual(config.launchPatterns, ["^test\\b"])
        XCTAssertEqual(config.waitingPatterns, ["\\? "])
        XCTAssertEqual(config.errorPatterns, ["Error:"])
        XCTAssertEqual(config.finishedIndicators, ["^\\$\\s*$"])
        XCTAssertTrue(config.oscSupported)
        XCTAssertEqual(config.idleTimeoutOverride, 15.0)
    }

    func testAgentConfigCodableRoundTrip() throws {
        let original = AgentConfig(
            name: "claude",
            displayName: "Claude Code",
            launchPatterns: ["^claude\\b", "npx claude"],
            waitingPatterns: ["^\\? ", "\\(Y/n\\)"],
            errorPatterns: ["^Error:", "APIError"],
            finishedIndicators: ["^\\$\\s*$"],
            oscSupported: true,
            idleTimeoutOverride: 10.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentConfig.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testAgentConfigCodableRoundTripWithNilTimeout() throws {
        let original = AgentConfig(
            name: "codex",
            displayName: "Codex CLI",
            launchPatterns: ["^codex\\b"],
            waitingPatterns: ["\\? "],
            errorPatterns: ["Error:"],
            finishedIndicators: ["^\\$\\s*$"],
            oscSupported: false,
            idleTimeoutOverride: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentConfig.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertNil(decoded.idleTimeoutOverride)
    }

    func testAgentConfigEquality() {
        let configA = AgentConfig(
            name: "claude",
            displayName: "Claude Code",
            launchPatterns: ["^claude\\b"],
            waitingPatterns: [],
            errorPatterns: [],
            finishedIndicators: [],
            oscSupported: true,
            idleTimeoutOverride: nil
        )

        let configB = AgentConfig(
            name: "claude",
            displayName: "Claude Code",
            launchPatterns: ["^claude\\b"],
            waitingPatterns: [],
            errorPatterns: [],
            finishedIndicators: [],
            oscSupported: true,
            idleTimeoutOverride: nil
        )

        let configC = AgentConfig(
            name: "codex",
            displayName: "Codex CLI",
            launchPatterns: ["^codex\\b"],
            waitingPatterns: [],
            errorPatterns: [],
            finishedIndicators: [],
            oscSupported: false,
            idleTimeoutOverride: nil
        )

        XCTAssertEqual(configA, configB)
        XCTAssertNotEqual(configA, configC)
    }
}

// MARK: - Agent Config Service: Parse Full TOML

/// Tests for `AgentConfigService` parsing a complete agents.toml file.

final class AgentConfigServiceParseTests: XCTestCase {

    func testParseCompleteAgentsTomlReturnsSixAgents() throws {
        let toml = AgentConfigService.generateDefaultAgentsToml()
        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let configs = service.agentConfigs()
        XCTAssertEqual(configs.count, 6, "Default agents.toml must define exactly 6 agents")
    }

    func testParseCompleteAgentsTomlContainsAllExpectedAgents() throws {
        let toml = AgentConfigService.generateDefaultAgentsToml()
        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let names = service.agentConfigs().map { $0.name }.sorted()
        let expectedNames = ["aider", "claude", "codex", "gemini-cli", "kiro", "opencode"]
        XCTAssertEqual(names, expectedNames)
    }

    func testParseClaudeAgentHasCorrectProperties() throws {
        let toml = AgentConfigService.generateDefaultAgentsToml()
        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        guard let claude = service.agentConfig(named: "claude") else {
            XCTFail("Claude agent config must exist")
            return
        }

        XCTAssertEqual(claude.displayName, "Claude Code")
        XCTAssertTrue(claude.oscSupported)
        // 5 launch patterns: 3 direct command variants (^claude\b,
        // ^claude-code\b, npx claude) plus 2 banner-copy patterns
        // ("Claude Code v[0-9]" and "Claude (Max|Pro)") added in v0.1.53
        // to detect the launch when the user runs Claude Code without
        // typing the literal binary name (e.g., via a wrapper script).
        XCTAssertEqual(claude.launchPatterns.count, 5)
        XCTAssertEqual(claude.waitingPatterns.count, 5)
        XCTAssertEqual(claude.errorPatterns.count, 4)
        XCTAssertEqual(claude.finishedIndicators.count, 3)
        XCTAssertNil(claude.idleTimeoutOverride)
    }

    func testEachAgentHasNonEmptyPatterns() throws {
        let toml = AgentConfigService.generateDefaultAgentsToml()
        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        for config in service.agentConfigs() {
            XCTAssertFalse(
                config.launchPatterns.isEmpty,
                "\(config.name) must have at least one launch pattern"
            )
            XCTAssertFalse(
                config.errorPatterns.isEmpty,
                "\(config.name) must have at least one error pattern"
            )
            XCTAssertFalse(
                config.finishedIndicators.isEmpty,
                "\(config.name) must have at least one finished indicator"
            )
        }
    }
}

// MARK: - Agent Config Service: Regex Validation

/// Tests for regex compilation and invalid pattern handling.

final class AgentConfigServiceRegexTests: XCTestCase {

    func testValidPatternsCompileSuccessfully() {
        let config = AgentConfig(
            name: "test",
            displayName: "Test",
            launchPatterns: ["^claude\\b", "^codex\\b"],
            waitingPatterns: ["\\? ", "\\(Y/n\\)"],
            errorPatterns: ["^Error:"],
            finishedIndicators: ["^\\$\\s*$"],
            oscSupported: false,
            idleTimeoutOverride: nil
        )

        let compiled = AgentConfigService.compile(config)

        XCTAssertEqual(compiled.launchPatterns.count, 2)
        XCTAssertEqual(compiled.waitingPatterns.count, 2)
        XCTAssertEqual(compiled.errorPatterns.count, 1)
        XCTAssertEqual(compiled.finishedIndicators.count, 1)
        XCTAssertTrue(compiled.invalidPatterns.isEmpty)
    }

    func testInvalidPatternIsSkippedWithoutCrash() {
        let config = AgentConfig(
            name: "test",
            displayName: "Test",
            launchPatterns: ["^valid\\b", "[invalid(regex"],
            waitingPatterns: ["also valid"],
            errorPatterns: ["[broken"],
            finishedIndicators: ["^\\$\\s*$"],
            oscSupported: false,
            idleTimeoutOverride: nil
        )

        let compiled = AgentConfigService.compile(config)

        // Valid patterns should still compile
        XCTAssertEqual(compiled.launchPatterns.count, 1, "Only the valid launch pattern should compile")
        XCTAssertEqual(compiled.waitingPatterns.count, 1)
        XCTAssertEqual(compiled.finishedIndicators.count, 1)

        // Invalid patterns should be tracked
        XCTAssertEqual(compiled.invalidPatterns.count, 2, "Two invalid patterns should be tracked")
        XCTAssertTrue(compiled.invalidPatterns.contains("[invalid(regex"))
        XCTAssertTrue(compiled.invalidPatterns.contains("[broken"))
    }

    func testCompiledConfigPreservesOriginalConfig() {
        let config = AgentConfig(
            name: "claude",
            displayName: "Claude Code",
            launchPatterns: ["^claude\\b"],
            waitingPatterns: [],
            errorPatterns: [],
            finishedIndicators: [],
            oscSupported: true,
            idleTimeoutOverride: 10.0
        )

        let compiled = AgentConfigService.compile(config)
        XCTAssertEqual(compiled.config, config)
    }
}

// MARK: - Agent Config Service: Fallback to Defaults

/// Tests for default creation when the file does not exist.

final class AgentConfigServiceDefaultsTests: XCTestCase {

    func testMissingFileCreatesDefaultAndUsesDefaults() throws {
        let fileProvider = InMemoryAgentConfigFileProvider(content: nil)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertNotNil(
            fileProvider.writtenContent,
            "AgentConfigService must write a default agents.toml when none exists"
        )

        let configs = service.agentConfigs()
        XCTAssertEqual(configs.count, 6, "Default config must define 6 agents")
    }

    func testMalformedTomlFallsBackToDefaults() throws {
        let toml = "this is not valid toml {{ at all }}"

        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let configs = service.agentConfigs()
        XCTAssertEqual(configs.count, 6, "Malformed TOML must fall back to 6 default agents")
    }
}

// MARK: - Agent Config Service: Lookup by Name

/// Tests for `agentConfig(named:)` lookup.

final class AgentConfigServiceLookupTests: XCTestCase {

    func testAgentConfigNamedFindsExistingAgent() throws {
        let toml = AgentConfigService.generateDefaultAgentsToml()
        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let claude = service.agentConfig(named: "claude")
        XCTAssertNotNil(claude)
        XCTAssertEqual(claude?.displayName, "Claude Code")

        let aider = service.agentConfig(named: "aider")
        XCTAssertNotNil(aider)
        XCTAssertEqual(aider?.displayName, "Aider")
    }

    func testAgentConfigNamedReturnsNilForUnknownAgent() throws {
        let toml = AgentConfigService.generateDefaultAgentsToml()
        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let unknown = service.agentConfig(named: "nonexistent-agent")
        XCTAssertNil(unknown)
    }
}

// MARK: - Agent Config Service: Hot Reload

/// Tests for Combine publisher and hot-reload behavior.

final class AgentConfigServiceHotReloadTests: XCTestCase {

    func testReloadPublishesNewConfigsViaCombine() throws {
        let initialToml = """
        [claude]
        display-name = "Claude Code"
        osc-supported = true
        launch-patterns = ["^claude\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = []
        """

        let fileProvider = InMemoryAgentConfigFileProvider(content: initialToml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let expectation = expectation(description: "Config change published")
        var receivedConfigs: [CompiledAgentConfig]?
        var cancellables = Set<AnyCancellable>()

        service.configChangedPublisher
            .dropFirst() // Skip the current value
            .sink { configs in
                receivedConfigs = configs
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Change the file content and reload
        let updatedToml = """
        [claude]
        display-name = "Claude Code v2"
        osc-supported = true
        launch-patterns = ["^claude\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = []

        [aider]
        display-name = "Aider"
        osc-supported = false
        launch-patterns = ["^aider\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = []
        """

        fileProvider.content = updatedToml
        try service.reload()

        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedConfigs)
        XCTAssertEqual(receivedConfigs?.count, 2)
    }
}

// MARK: - Agent Config Service: Idle Timeout Override

/// Tests for the per-agent idle timeout override feature.

final class AgentConfigServiceIdleTimeoutTests: XCTestCase {

    func testIdleTimeoutOverrideParsedFromToml() throws {
        let toml = """
        [slow-agent]
        display-name = "Slow Agent"
        osc-supported = false
        launch-patterns = ["^slow\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = []
        idle-timeout-override = 30
        """

        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let config = service.agentConfig(named: "slow-agent")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.idleTimeoutOverride, 30.0)
    }

    func testMissingIdleTimeoutOverrideIsNil() throws {
        let toml = """
        [fast-agent]
        display-name = "Fast Agent"
        osc-supported = false
        launch-patterns = ["^fast\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = []
        """

        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let config = service.agentConfig(named: "fast-agent")
        XCTAssertNotNil(config)
        XCTAssertNil(config?.idleTimeoutOverride)
    }

    func testAiderDefaultConfigHasIdleTimeoutOverride() {
        let defaults = AgentConfigService.defaultAgentConfigs()
        guard let aider = defaults.first(where: { $0.name == "aider" }) else {
            XCTFail("Aider must exist in default agent configs")
            return
        }
        XCTAssertEqual(
            aider.idleTimeoutOverride, 10.0,
            "Aider debe tener un idle timeout de 10 segundos porque es un agente lento"
        )
    }

    func testGeminiCliDefaultConfigHasIdleTimeoutOverride() {
        let defaults = AgentConfigService.defaultAgentConfigs()
        guard let gemini = defaults.first(where: { $0.name == "gemini-cli" }) else {
            XCTFail("Gemini CLI must exist in default agent configs")
            return
        }
        XCTAssertEqual(
            gemini.idleTimeoutOverride, 8.0,
            "Gemini CLI debe tener un idle timeout de 8 segundos por su latencia inicial"
        )
    }

    func testClaudeDefaultConfigHasNoIdleTimeoutOverride() {
        let defaults = AgentConfigService.defaultAgentConfigs()
        guard let claude = defaults.first(where: { $0.name == "claude" }) else {
            XCTFail("Claude must exist in default agent configs")
            return
        }
        XCTAssertNil(
            claude.idleTimeoutOverride,
            "Claude no necesita override porque OSC es la fuente principal"
        )
    }
}

// MARK: - Agent Config Service: OSC Supported Flag

/// Tests for the OSC supported flag in agent configs.

final class AgentConfigServiceOscSupportedTests: XCTestCase {

    func testOscSupportedFlagParsedCorrectly() throws {
        let toml = """
        [osc-agent]
        display-name = "OSC Agent"
        osc-supported = true
        launch-patterns = ["^osc\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = []

        [no-osc-agent]
        display-name = "No OSC Agent"
        osc-supported = false
        launch-patterns = ["^noosc\\b"]
        waiting-patterns = []
        error-patterns = []
        finished-indicators = []
        """

        let fileProvider = InMemoryAgentConfigFileProvider(content: toml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let oscAgent = service.agentConfig(named: "osc-agent")
        XCTAssertTrue(oscAgent?.oscSupported ?? false)

        let noOscAgent = service.agentConfig(named: "no-osc-agent")
        XCTAssertFalse(noOscAgent?.oscSupported ?? true)
    }
}

// MARK: - Agent Config Service: Generated TOML Roundtrip

/// Tests that generated TOML can be parsed back correctly.

final class AgentConfigServiceTomlRoundtripTests: XCTestCase {

    func testGeneratedDefaultTomlCanBeParsedBack() throws {
        let generatedToml = AgentConfigService.generateDefaultAgentsToml()
        let fileProvider = InMemoryAgentConfigFileProvider(content: generatedToml)
        let service = AgentConfigService(fileProvider: fileProvider)
        try service.reload()

        let configs = service.agentConfigs()
        let defaults = AgentConfigService.defaultAgentConfigs()

        XCTAssertEqual(configs.count, defaults.count)

        for defaultConfig in defaults {
            guard let parsed = configs.first(where: { $0.name == defaultConfig.name }) else {
                XCTFail("Missing agent after roundtrip: \(defaultConfig.name)")
                continue
            }
            XCTAssertEqual(parsed.displayName, defaultConfig.displayName)
            XCTAssertEqual(parsed.oscSupported, defaultConfig.oscSupported)
            XCTAssertEqual(parsed.launchPatterns, defaultConfig.launchPatterns)
            XCTAssertEqual(parsed.waitingPatterns, defaultConfig.waitingPatterns)
            XCTAssertEqual(parsed.errorPatterns, defaultConfig.errorPatterns)
            XCTAssertEqual(parsed.finishedIndicators, defaultConfig.finishedIndicators)
            XCTAssertEqual(parsed.idleTimeoutOverride, defaultConfig.idleTimeoutOverride)
        }
    }
}

// MARK: - InMemoryAgentConfigFileProvider

/// A test double for `AgentConfigFileProviding` that holds content in memory.
///
/// Avoids filesystem access in unit tests, making them fast and deterministic.
final class InMemoryAgentConfigFileProvider: AgentConfigFileProviding, @unchecked Sendable {
    var content: String?
    private(set) var writtenContent: String?

    init(content: String?) {
        self.content = content
    }

    func readAgentConfigFile() -> String? {
        content
    }

    func writeAgentConfigFile(_ content: String) throws {
        writtenContent = content
    }
}
