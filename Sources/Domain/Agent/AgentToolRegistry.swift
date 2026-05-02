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
    let inputSchema: AgentToolInputSchema

    init(
        id: String,
        displayName: String,
        description: String,
        capability: AgentToolCapability,
        inputSchema: AgentToolInputSchema = .empty
    ) {
        self.id = Self.normalizedID(id)
        self.displayName = displayName
        self.description = description
        self.capability = capability
        self.inputSchema = inputSchema
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case description
        case capability
        case inputSchema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = Self.normalizedID(try container.decode(String.self, forKey: .id))
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.description = try container.decode(String.self, forKey: .description)
        self.capability = try container.decode(AgentToolCapability.self, forKey: .capability)
        self.inputSchema = try container.decodeIfPresent(
            AgentToolInputSchema.self,
            forKey: .inputSchema
        ) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(capability, forKey: .capability)
        try container.encode(inputSchema, forKey: .inputSchema)
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
                capability: descriptor.capability,
                inputSchema: descriptor.inputSchema
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
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "path": AgentToolInputProperty(.string, description: "Repository-relative file path to read."),
                ],
                required: ["path"]
            )
        ),
        AgentToolDescriptor(
            id: "write_file",
            displayName: "Write File",
            description: "Write a repository file through mandatory diff preview.",
            capability: .write,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "path": AgentToolInputProperty(.string, description: "Repository-relative file path to write."),
                    "content": AgentToolInputProperty(.string, description: "Complete UTF-8 file contents to write."),
                    "create": AgentToolInputProperty(.boolean, description: "Whether a missing target file may be created."),
                ],
                required: ["path", "content"]
            )
        ),
        AgentToolDescriptor(
            id: "apply_diff",
            displayName: "Apply Diff",
            description: "Apply a structured diff after user approval.",
            capability: .write,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "path": AgentToolInputProperty(.string, description: "Repository-relative file path to modify."),
                    "oldText": AgentToolInputProperty(.string, description: "Exact existing text to replace once."),
                    "newText": AgentToolInputProperty(.string, description: "Replacement text, which may be empty."),
                ],
                required: ["path", "oldText", "newText"]
            )
        ),
        AgentToolDescriptor(
            id: "list_directory",
            displayName: "List Directory",
            description: "List a directory while respecting workspace boundaries.",
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "path": AgentToolInputProperty(.string, description: "Repository-relative directory path. Defaults to the workspace root."),
                ]
            )
        ),
        AgentToolDescriptor(
            id: "search_files",
            displayName: "Search Files",
            description: "Find files by glob or fuzzy path query.",
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "pattern": AgentToolInputProperty(.string, description: "Glob pattern or file-name pattern to match."),
                    "limit": AgentToolInputProperty(.number, description: "Maximum number of paths to return."),
                ],
                required: ["pattern"]
            )
        ),
        AgentToolDescriptor(
            id: "search_codebase",
            displayName: "Search Codebase",
            description: "Search the local codebase with lexical fallback when semantic indexing is unavailable.",
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "query": AgentToolInputProperty(.string, description: "Natural-language or keyword query to search locally."),
                    "path": AgentToolInputProperty(.string, description: "Optional repository-relative directory scope."),
                    "limit": AgentToolInputProperty(.number, description: "Maximum number of results to return."),
                ],
                required: ["query"]
            )
        ),
        AgentToolDescriptor(
            id: "list_skills",
            displayName: "List Skills",
            description: "List local built-in, user, and project skills available to the agent.",
            capability: .read
        ),
        AgentToolDescriptor(
            id: "use_skill",
            displayName: "Use Skill",
            description: "Load one local skill and return its reusable instructions.",
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "id": AgentToolInputProperty(.string, description: "Skill identifier to load."),
                ],
                required: ["id"]
            )
        ),
        AgentToolDescriptor(
            id: "grep",
            displayName: "Grep",
            description: "Search file contents with a local regex engine.",
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "pattern": AgentToolInputProperty(.string, description: "Regular expression to search for."),
                    "path": AgentToolInputProperty(.string, description: "Repository-relative directory path. Defaults to the workspace root."),
                    "caseSensitive": AgentToolInputProperty(.boolean, description: "Whether matching should be case-sensitive."),
                    "limit": AgentToolInputProperty(.number, description: "Maximum number of matches to return."),
                ],
                required: ["pattern"]
            )
        ),
        AgentToolDescriptor(
            id: "run_command",
            displayName: "Run Command",
            description: "Run a shell command through the Agent permission gate.",
            capability: .command,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "command": AgentToolInputProperty(.string, description: "Shell command to run after policy and approval checks."),
                    "cwd": AgentToolInputProperty(.string, description: "Repository-relative working directory. Defaults to the workspace root."),
                    "timeoutSeconds": AgentToolInputProperty(.number, description: "Command timeout in seconds."),
                ],
                required: ["command"]
            )
        ),
        AgentToolDescriptor(
            id: "read_terminal_output",
            displayName: "Read Terminal Output",
            description: "Read the last clean command blocks from CocxyCore.",
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "limit": AgentToolInputProperty(.number, description: "Maximum number of recent command blocks to read."),
                ]
            )
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
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "path": AgentToolInputProperty(.string, description: "Optional repository-relative path to diff."),
                ]
            )
        ),
        AgentToolDescriptor(
            id: "read_lsp_diagnostics",
            displayName: "Read LSP Diagnostics",
            description: "Read local language-server diagnostics already visible to Cocxy.",
            capability: .read,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "limit": AgentToolInputProperty(.number, description: "Maximum number of diagnostics to return."),
                ]
            )
        ),
        AgentToolDescriptor(
            id: "ask_user",
            displayName: "Ask User",
            description: "Pause the Agent loop for an explicit user answer.",
            capability: .userInteraction,
            inputSchema: AgentToolInputSchema(
                properties: [
                    "prompt": AgentToolInputProperty(.string, description: "Question to show the user before the agent continues."),
                ],
                required: ["prompt"]
            )
        ),
    ]
}
