// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginManifestTests.swift - Tests for plugin manifest parsing.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Plugin Manifest Tests

@Suite("PluginManifestParser")
struct PluginManifestTests {

    // MARK: - TOML Parsing

    @Test func parseSimpleToml() {
        let toml = """
        name = "My Plugin"
        version = "1.0.0"
        author = "Developer"
        """

        let result = PluginManifestParser.parseToml(toml)

        #expect(result["name"] == "My Plugin")
        #expect(result["version"] == "1.0.0")
        #expect(result["author"] == "Developer")
    }

    @Test func parseTomlIgnoresComments() {
        let toml = """
        # This is a comment
        name = "test"
        # Another comment
        version = "0.1.0"
        """

        let result = PluginManifestParser.parseToml(toml)

        #expect(result.count == 2)
        #expect(result["name"] == "test")
    }

    @Test func parseTomlIgnoresSectionHeaders() {
        let toml = """
        [metadata]
        name = "test"
        [events]
        hook = "true"
        """

        let result = PluginManifestParser.parseToml(toml)

        #expect(result["name"] == "test")
        #expect(result["hook"] == "true")
    }

    @Test func parseTomlHandlesUnquotedValues() {
        let toml = """
        name = "quoted"
        count = 42
        enabled = true
        """

        let result = PluginManifestParser.parseToml(toml)

        #expect(result["name"] == "quoted")
        #expect(result["count"] == "42")
        #expect(result["enabled"] == "true")
    }

    @Test func parseTomlHandlesArrayValues() {
        let toml = """
        events = ["session-start", "agent-detected"]
        """

        let result = PluginManifestParser.parseToml(toml)

        #expect(result["events"] == "[\"session-start\", \"agent-detected\"]")
    }

    @Test func parseTomlHandlesEmptyInput() {
        let result = PluginManifestParser.parseToml("")
        #expect(result.isEmpty)
    }

    // MARK: - Plugin Events

    @Test func pluginEventScriptNames() {
        #expect(PluginEvent.sessionStart.scriptName == "on-session-start.sh")
        #expect(PluginEvent.agentDetected.scriptName == "on-agent-detected.sh")
        #expect(PluginEvent.commandComplete.scriptName == "on-command-complete.sh")
        #expect(PluginEvent.directoryChanged.scriptName == "on-directory-changed.sh")
    }

    @Test func allPluginEventsHaveScriptNames() {
        for event in PluginEvent.allCases {
            #expect(event.scriptName.hasPrefix("on-"))
            #expect(event.scriptName.hasSuffix(".sh"))
        }
    }

    // MARK: - Manifest Error Cases

    @Test func manifestRequiresNameField() {
        let toml = """
        version = "1.0.0"
        author = "Dev"
        """

        // Write to temp file.
        let tempDir = NSTemporaryDirectory() + "cocxy-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let manifestPath = "\(tempDir)/manifest.toml"
        try? toml.write(toFile: manifestPath, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        do {
            _ = try PluginManifestParser.parse(filePath: manifestPath, directoryPath: tempDir)
            Issue.record("Expected PluginManifestError.missingRequiredField")
        } catch let error as PluginManifestError {
            if case .missingRequiredField(let field) = error {
                #expect(field == "name")
            } else {
                Issue.record("Expected missingRequiredField, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func manifestParsesEvents() {
        let toml = """
        name = "test-plugin"
        version = "1.0.0"
        events = ["session-start", "agent-detected", "command-complete"]
        """

        let tempDir = NSTemporaryDirectory() + "cocxy-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let manifestPath = "\(tempDir)/manifest.toml"
        try? toml.write(toFile: manifestPath, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let manifest = try? PluginManifestParser.parse(
            filePath: manifestPath,
            directoryPath: tempDir
        )

        #expect(manifest != nil)
        #expect(manifest?.events.count == 3)
        #expect(manifest?.events.contains(.sessionStart) == true)
        #expect(manifest?.events.contains(.agentDetected) == true)
        #expect(manifest?.events.contains(.commandComplete) == true)
    }

    @Test func manifestUsesDirectoryNameAsID() {
        let toml = """
        name = "My Plugin"
        """

        let tempDir = NSTemporaryDirectory() + "my-cool-plugin"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let manifestPath = "\(tempDir)/manifest.toml"
        try? toml.write(toFile: manifestPath, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let manifest = try? PluginManifestParser.parse(
            filePath: manifestPath,
            directoryPath: tempDir
        )

        #expect(manifest?.id == "my-cool-plugin")
        #expect(manifest?.name == "My Plugin")
    }

    @Test func manifestFileNotFoundThrows() {
        do {
            _ = try PluginManifestParser.parse(
                filePath: "/nonexistent/manifest.toml",
                directoryPath: "/nonexistent"
            )
            Issue.record("Expected PluginManifestError.fileNotFound")
        } catch let error as PluginManifestError {
            if case .fileNotFound = error {
                // Expected.
            } else {
                Issue.record("Expected fileNotFound, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
