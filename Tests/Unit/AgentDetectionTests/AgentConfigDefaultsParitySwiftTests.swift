// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent config defaults parity")
struct AgentConfigDefaultsParitySwiftTests {

    @Test("bundled reference agents TOML matches generated defaults")
    func bundledReferenceAgentsTomlMatchesGeneratedDefaults() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundledDefaultsURL = repoRoot.appendingPathComponent("Resources/defaults/agents.toml")
        let bundledDefaults = try String(contentsOf: bundledDefaultsURL, encoding: .utf8)

        let service = AgentConfigService(
            fileProvider: InMemoryAgentConfigFileProvider(content: bundledDefaults)
        )
        try service.reload()

        let parsedBundledDefaults = service.agentConfigs().sorted { $0.name < $1.name }
        let generatedDefaults = AgentConfigService.defaultAgentConfigs().sorted { $0.name < $1.name }

        #expect(parsedBundledDefaults == generatedDefaults)
    }
}
