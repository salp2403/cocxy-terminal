// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyCLILib

@Suite("CLIArgumentParser — tab config")
struct TabConfigCLIArgumentParserSwiftTestingTests {

    @Test("tab config save parses name plus optional theme and env overrides")
    func saveParsesOptions() throws {
        let parsed = try CLIArgumentParser.parse([
            "tab", "config", "save", "api",
            "--theme", "Nord",
            "--env", "API_URL=http://127.0.0.1:8080",
            "--env", "FEATURE_FLAG=true",
        ])

        #expect(parsed == .tabConfigSave(
            name: "api",
            command: nil,
            theme: "Nord",
            environment: [
                "API_URL": "http://127.0.0.1:8080",
                "FEATURE_FLAG": "true",
            ]
        ))
    }

    @Test("tab config open parses the saved config name")
    func openParsesName() throws {
        #expect(try CLIArgumentParser.parse(["tab", "config", "open", "api"]) == .tabConfigOpen(name: "api"))
    }

    @Test("tab config list and path parse")
    func listAndPathParse() throws {
        #expect(try CLIArgumentParser.parse(["tab", "config", "list"]) == .tabConfigList)
        #expect(try CLIArgumentParser.parse(["tab", "config", "path", "api"]) == .tabConfigPath(name: "api"))
    }

    @Test("tab config export parses a contained file name and force flag")
    func exportParsesOutputAndForce() throws {
        #expect(
            try CLIArgumentParser.parse([
                "tab", "config", "export", "api",
                "--output", "shared-api.toml",
                "--force",
            ]) == .tabConfigExport(
                name: "api",
                output: "shared-api.toml",
                force: true
            )
        )
    }

    @Test("tab config save rejects command-bearing socket configs")
    func saveRejectsStartupCommand() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse([
                "tab", "config", "save", "api",
                "--command", "npm run dev",
            ])
        }
    }

    @Test("tab config export rejects paths and hidden or ambiguous names", arguments: [
        "/tmp/shared-api.toml",
        "../shared-api.toml",
        "nested/shared-api.toml",
        "nested\\shared-api.toml",
        ".hidden.toml",
        "shared..api.toml",
        "shared-api.txt",
    ])
    func exportRejectsUnsafeFileName(_ output: String) {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse([
                "tab", "config", "export", "api",
                "--output", output,
            ])
        }
    }

    @Test("tab config save rejects malformed env pairs")
    func saveRejectsMalformedEnv() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse([
                "tab", "config", "save", "api",
                "--env", "MISSING_EQUALS",
            ])
        }
    }

    @Test("command runner builds socket requests with env key prefixes")
    func buildRequestUsesEnvKeyPrefixes() {
        let request = CommandRunner().buildRequest(from: .tabConfigSave(
            name: "api",
            command: nil,
            theme: "Nord",
            environment: ["API_URL": "http://127.0.0.1:8080"]
        ))

        #expect(request.command == "tab-config-save")
        #expect(request.params?["name"] == "api")
        #expect(request.params?["command"] == nil)
        #expect(request.params?["theme"] == "Nord")
        #expect(request.params?["env.API_URL"] == "http://127.0.0.1:8080")
    }

    @Test("command runner builds export socket requests")
    func buildExportRequest() {
        let request = CommandRunner().buildRequest(from: .tabConfigExport(
            name: "api",
            output: "shared-api.toml",
            force: true
        ))

        #expect(request.command == "tab-config-export")
        #expect(request.params?["name"] == "api")
        #expect(request.params?["output"] == "shared-api.toml")
        #expect(request.params?["force"] == "true")
    }
}
