// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolRegistrySwiftTestingTests.swift - Phase F built-in tool catalog.

import Testing
@testable import CocxyTerminal

@Suite("AgentToolRegistry")
struct AgentToolRegistrySwiftTestingTests {

    @Test("built-in minimum registry exposes the 12 Phase F tools")
    func builtInMinimumRegistryExposesPhaseFTools() throws {
        let registry = AgentToolRegistry.minimumBuiltIns()

        #expect(registry.toolIDs == [
            "apply_diff",
            "ask_user",
            "git_diff",
            "git_status",
            "grep",
            "list_directory",
            "read_file",
            "read_lsp_diagnostics",
            "read_terminal_output",
            "run_command",
            "search_files",
            "write_file",
        ])
        #expect(registry.descriptor(for: "read_file")?.capability == .read)
        #expect(registry.descriptor(for: "write_file")?.capability == .write)
        #expect(registry.descriptor(for: "run_command")?.capability == .command)
        #expect(registry.descriptor(for: "ask_user")?.capability == .userInteraction)
    }

    @Test("registry rejects duplicate tool identifiers")
    func registryRejectsDuplicateToolIDs() {
        let descriptor = AgentToolDescriptor(
            id: "read_file",
            displayName: "Read File",
            description: "Read a file",
            capability: .read
        )

        #expect(throws: AgentToolRegistryError.duplicateToolID("read_file")) {
            _ = try AgentToolRegistry(descriptors: [descriptor, descriptor])
        }
    }

    @Test("registry normalizes tool identifiers and preserves descriptors sorted by id")
    func registryNormalizesToolIdentifiers() throws {
        let registry = try AgentToolRegistry(descriptors: [
            AgentToolDescriptor(id: "  Zed.Tool  ", displayName: "Zed", description: "Last", capability: .read),
            AgentToolDescriptor(id: "alpha.tool", displayName: "Alpha", description: "First", capability: .read),
        ])

        #expect(registry.toolIDs == ["alpha.tool", "zed.tool"])
        #expect(registry.descriptor(for: "ZED.TOOL")?.displayName == "Zed")
    }
}
