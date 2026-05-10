// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLIIdentityCapabilitiesSwiftTestingTests.swift - Discovery CLI contract tests.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("CLI identity and capabilities discovery")
struct CLIIdentityCapabilitiesSwiftTestingTests {

    @Test("identify parses as a top-level command")
    func identifyParsesAsTopLevelCommand() throws {
        #expect(try CLIArgumentParser.parse(["identify"]) == .identify)
    }

    @Test("capabilities parses as a top-level command")
    func capabilitiesParsesAsTopLevelCommand() throws {
        #expect(try CLIArgumentParser.parse(["capabilities"]) == .capabilities)
    }

    @Test("identify returns JSON without requiring the app socket")
    func identifyReturnsJSONWithoutSocket() throws {
        let runner = CommandRunner(socketClient: SocketClient(socketPath: "/tmp/missing-cocxy.sock"))

        let result = runner.run(arguments: ["identify"])

        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        let object = try jsonObject(from: result.stdout)
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["name"] as? String == "cocxy")
        #expect(object["version"] as? String == CLIArgumentParser.version)
        #expect(object["bundleIdentifier"] as? String == "dev.cocxy.terminal")
        #expect(object["channel"] as? String == "stable")
        #expect(object["telemetry"] as? String == "none")
        let enabledFeatures = try #require(object["enabledFeatures"] as? [String])
        #expect(enabledFeatures.contains("terminal"))
        #expect(enabledFeatures.contains("local-cli"))
        #expect(enabledFeatures.contains("app-socket"))
    }

    @Test("capabilities returns supported feature JSON without requiring the app socket")
    func capabilitiesReturnsJSONWithoutSocket() throws {
        let runner = CommandRunner(socketClient: SocketClient(socketPath: "/tmp/missing-cocxy.sock"))

        let result = runner.run(arguments: ["capabilities"])

        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        let object = try jsonObject(from: result.stdout)
        #expect(object["schemaVersion"] as? Int == 2)
        let capabilities = try #require(object["capabilities"] as? [[String: Any]])
        #expect(capabilities.contains { $0["id"] as? String == "mcp" && $0["supported"] as? Bool == true })
        #expect(capabilities.contains { $0["id"] as? String == "lsp" && $0["supported"] as? Bool == true })
        #expect(capabilities.contains { $0["id"] as? String == "voice" && $0["supported"] as? Bool == true })
        #expect(capabilities.contains {
            $0["id"] as? String == "high-fidelity-clipboard"
                && $0["supported"] as? Bool == true
        })
        #expect(capabilities.contains { $0["id"] as? String == "vault" && $0["supported"] as? Bool == false })
    }

    @Test("help advertises discovery commands")
    func helpAdvertisesDiscoveryCommands() {
        let help = CLIArgumentParser.helpText()

        #expect(help.contains("cocxy identify"))
        #expect(help.contains("cocxy capabilities"))
    }

    private func jsonObject(from text: String) throws -> [String: Any] {
        let data = Data(text.utf8)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
