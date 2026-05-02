// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MCPPreferencesSwiftTestingTests.swift - Preferences coverage for mcp.json editing.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - MCP config editing")
@MainActor
struct MCPPreferencesSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(_ content: String? = nil) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    @Test("init loads user MCP config and exposes server preview")
    func initLoadsUserMCPConfigAndPreview() throws {
        let configURL = try makeTemporaryMCPConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try """
        {
          "mcpServers": {
            "github": {
              "name": "GitHub",
              "command": "github-mcp-server",
              "args": ["--stdio"],
              "enabled": true
            },
            "docs": {
              "url": "http://127.0.0.1:8765/mcp",
              "enabled": false
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let viewModel = PreferencesViewModel(
            config: .defaults,
            fileProvider: InMemoryProvider(),
            mcpConfigURL: configURL
        )

        #expect(viewModel.mcpConfigPath == configURL.path)
        #expect(viewModel.mcpConfiguredServers.map(\.id) == ["docs", "github"])
        #expect(viewModel.mcpServerSummary(for: viewModel.mcpConfiguredServers[0]) == "Disabled HTTP")
        #expect(viewModel.mcpServerSummary(for: viewModel.mcpConfiguredServers[1]) == "Enabled stdio")
        #expect(viewModel.hasUnsavedMCPConfigChanges == false)
        #expect(viewModel.hasUnsavedChanges == false)
    }

    @Test("saving MCP config validates and writes mcp.json separately from config TOML")
    func savingMCPConfigValidatesAndWritesJSON() throws {
        let configURL = try makeTemporaryMCPConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        let provider = InMemoryProvider()
        let viewModel = PreferencesViewModel(
            config: .defaults,
            fileProvider: provider,
            mcpConfigURL: configURL
        )

        viewModel.mcpConfigText = """
        {
          "mcpServers": {
            "local": {
              "command": "local-mcp-server",
              "args": ["--stdio"],
              "env": {
                "SAFE_MODE": "1"
              }
            }
          }
        }
        """

        #expect(viewModel.hasUnsavedMCPConfigChanges == true)
        #expect(viewModel.hasUnsavedChanges == true)

        try viewModel.saveMCPConfig()

        let written = try String(contentsOf: configURL, encoding: .utf8)
        #expect(written.contains("\"local\""))
        #expect(written.contains("\"SAFE_MODE\""))
        #expect(provider.content == nil)
        #expect(viewModel.mcpConfiguredServers.map(\.id) == ["local"])
        #expect(viewModel.hasUnsavedMCPConfigChanges == false)
        #expect(viewModel.hasUnsavedChanges == false)
    }

    @Test("main preferences save also persists dirty MCP config after validation")
    func mainSavePersistsDirtyMCPConfig() throws {
        let configURL = try makeTemporaryMCPConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        let provider = InMemoryProvider()
        let viewModel = PreferencesViewModel(
            config: .defaults,
            fileProvider: provider,
            mcpConfigURL: configURL
        )
        viewModel.shell = "/bin/bash"
        viewModel.mcpConfigText = """
        {
          "mcpServers": {
            "local": {
              "command": "local-mcp-server"
            }
          }
        }
        """

        try viewModel.save()

        #expect(provider.content?.contains("shell = \"/bin/bash\"") == true)
        #expect(try String(contentsOf: configURL, encoding: .utf8).contains("\"local\""))
        #expect(viewModel.hasUnsavedChanges == false)
    }

    @Test("invalid MCP draft blocks save without overwriting existing config")
    func invalidMCPDraftBlocksSaveWithoutOverwrite() throws {
        let configURL = try makeTemporaryMCPConfigURL()
        defer { try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent()) }
        try """
        {
          "mcpServers": {
            "valid": {
              "command": "valid-server"
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let viewModel = PreferencesViewModel(
            config: .defaults,
            fileProvider: InMemoryProvider(),
            mcpConfigURL: configURL
        )

        viewModel.mcpConfigText = "{ \"mcpServers\": { \"Bad Server\": { \"command\": \"bad\" } } }"

        #expect(throws: MCPServerConfigError.invalidServerID("Bad Server")) {
            try viewModel.saveMCPConfig()
        }
        let written = try String(contentsOf: configURL, encoding: .utf8)
        #expect(written.contains("\"valid\""))
        #expect(written.contains("\"Bad Server\"") == false)
        #expect(viewModel.hasUnsavedMCPConfigChanges == true)
    }
}

private func makeTemporaryMCPConfigURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-mcp-prefs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("mcp.json")
}
