// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolRegistry.swift - Built-in Agent Mode tool catalog contracts.

import Foundation

/// Coarse permission category for an Agent Mode tool.
enum AgentToolCapability: String, Codable, Sendable, Equatable, CaseIterable {
    case read
    case write
    case command
    case userInteraction = "user-interaction"
}

/// Metadata for a tool the Agent loop may request.
struct AgentToolDescriptor: Codable, Sendable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let capability: AgentToolCapability

    init(
        id: String,
        displayName: String,
        description: String,
        capability: AgentToolCapability
    ) {
        self.id = Self.normalizedID(id)
        self.displayName = displayName
        self.description = description
        self.capability = capability
    }

    static func normalizedID(_ rawID: String) -> String {
        rawID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum AgentToolRegistryError: Error, Sendable, Equatable {
    case emptyToolID
    case duplicateToolID(String)
}

/// Immutable registry for Agent Mode tools.
struct AgentToolRegistry: Sendable, Equatable {
    private let descriptorsByID: [String: AgentToolDescriptor]

    init(descriptors: [AgentToolDescriptor]) throws {
        var next: [String: AgentToolDescriptor] = [:]

        for descriptor in descriptors {
            let id = AgentToolDescriptor.normalizedID(descriptor.id)
            guard !id.isEmpty else {
                throw AgentToolRegistryError.emptyToolID
            }
            guard next[id] == nil else {
                throw AgentToolRegistryError.duplicateToolID(id)
            }
            next[id] = AgentToolDescriptor(
                id: id,
                displayName: descriptor.displayName,
                description: descriptor.description,
                capability: descriptor.capability
            )
        }

        self.descriptorsByID = next
    }

    var descriptors: [AgentToolDescriptor] {
        descriptorsByID.values.sorted { $0.id < $1.id }
    }

    var toolIDs: [String] {
        descriptors.map(\.id)
    }

    func descriptor(for rawID: String) -> AgentToolDescriptor? {
        descriptorsByID[AgentToolDescriptor.normalizedID(rawID)]
    }

    static func minimumBuiltIns() -> AgentToolRegistry {
        do {
            return try AgentToolRegistry(descriptors: AgentBuiltInTools.minimumDescriptors)
        } catch {
            preconditionFailure("Built-in Agent tool registry is invalid: \(error)")
        }
    }
}

enum AgentBuiltInTools {
    static let minimumDescriptors: [AgentToolDescriptor] = [
        AgentToolDescriptor(
            id: "read_file",
            displayName: "Read File",
            description: "Read a repository file after path validation.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "write_file",
            displayName: "Write File",
            description: "Write a repository file through mandatory diff preview.",
            capability: .write
        ),
        AgentToolDescriptor(
            id: "apply_diff",
            displayName: "Apply Diff",
            description: "Apply a structured diff after user approval.",
            capability: .write
        ),
        AgentToolDescriptor(
            id: "list_directory",
            displayName: "List Directory",
            description: "List a directory while respecting workspace boundaries.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "search_files",
            displayName: "Search Files",
            description: "Find files by glob or fuzzy path query.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "grep",
            displayName: "Grep",
            description: "Search file contents with a local regex engine.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "run_command",
            displayName: "Run Command",
            description: "Run a shell command through the Agent permission gate.",
            capability: .command
        ),
        AgentToolDescriptor(
            id: "read_terminal_output",
            displayName: "Read Terminal Output",
            description: "Read the last clean command blocks from CocxyCore.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "git_status",
            displayName: "Git Status",
            description: "Read git status for the active repository.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "git_diff",
            displayName: "Git Diff",
            description: "Read git diff for the active repository.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "read_lsp_diagnostics",
            displayName: "Read LSP Diagnostics",
            description: "Read local language-server diagnostics already visible to Cocxy.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "ask_user",
            displayName: "Ask User",
            description: "Pause the Agent loop for an explicit user answer.",
            capability: .userInteraction
        ),
    ]
}
