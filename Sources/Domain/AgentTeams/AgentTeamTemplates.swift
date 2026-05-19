// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamTemplates.swift - Reproducible local team templates.

import Foundation

struct AgentTeamTemplateRole: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let prompt: String
    let permissions: [AgentTeamPermission]

    init(
        id: String,
        name: String,
        prompt: String,
        permissions: [AgentTeamPermission] = []
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.permissions = permissions
    }
}

struct AgentTeamTemplate: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let summary: String
    let defaultProvider: AgentTeamProvider
    let roles: [AgentTeamTemplateRole]
}

enum AgentTeamTemplateError: Error, Equatable, Sendable, CustomStringConvertible {
    case duplicateTemplateID(String)
    case unknownTemplate(String)
    case emptyRoles(String)

    var description: String {
        switch self {
        case .duplicateTemplateID(let id):
            return "Duplicate agent team template id: \(id)"
        case .unknownTemplate(let id):
            return "Unknown agent team template: \(id)"
        case .emptyRoles(let id):
            return "Agent team template has no roles: \(id)"
        }
    }
}

struct AgentTeamTemplateCatalog: Codable, Sendable, Equatable {
    let templates: [AgentTeamTemplate]
    private let templatesByID: [String: AgentTeamTemplate]

    init(templates: [AgentTeamTemplate]) throws {
        var seenIDs: Set<String> = []
        var indexed: [String: AgentTeamTemplate] = [:]
        for template in templates {
            let id = AgentTeamConfig.slug(template.id)
            if seenIDs.contains(id) {
                throw AgentTeamTemplateError.duplicateTemplateID(id)
            }
            if template.roles.isEmpty {
                throw AgentTeamTemplateError.emptyRoles(id)
            }
            seenIDs.insert(id)
            indexed[id] = AgentTeamTemplate(
                id: id,
                name: template.name,
                summary: template.summary,
                defaultProvider: template.defaultProvider,
                roles: template.roles
            )
        }
        self.templates = templates.map { template in
            AgentTeamTemplate(
                id: AgentTeamConfig.slug(template.id),
                name: template.name,
                summary: template.summary,
                defaultProvider: template.defaultProvider,
                roles: template.roles
            )
        }
        self.templatesByID = indexed
    }

    private init(validatedTemplates templates: [AgentTeamTemplate]) {
        self.templates = templates
        self.templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
    }

    static let builtin = AgentTeamTemplateCatalog(validatedTemplates: [
        AgentTeamTemplate(
            id: "web-stack",
            name: "Web Stack",
            summary: "Frontend, backend, and tests for a web application.",
            defaultProvider: .codex,
            roles: [
                AgentTeamTemplateRole(
                    id: "frontend",
                    name: "Frontend",
                    prompt: "Own the UI implementation, accessibility, and browser-visible behavior.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
                AgentTeamTemplateRole(
                    id: "backend",
                    name: "Backend",
                    prompt: "Own the server, data contracts, validation, and integration boundaries.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
                AgentTeamTemplateRole(
                    id: "tests",
                    name: "Tests",
                    prompt: "Own focused regression coverage, smoke checks, and test triage.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
            ]
        ),
        AgentTeamTemplate(
            id: "data-pipeline",
            name: "Data Pipeline",
            summary: "ETL, validation, and monitoring workflow.",
            defaultProvider: .codex,
            roles: [
                AgentTeamTemplateRole(
                    id: "etl",
                    name: "ETL",
                    prompt: "Own ingestion, transformation, and idempotent pipeline behavior.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
                AgentTeamTemplateRole(
                    id: "validation",
                    name: "Validation",
                    prompt: "Own schema checks, data quality assertions, and fixture coverage.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
                AgentTeamTemplateRole(
                    id: "monitoring",
                    name: "Monitoring",
                    prompt: "Own operational signals, failure modes, and runbook-ready outputs.",
                    permissions: [.fileRead, .fileWrite]
                ),
            ]
        ),
        AgentTeamTemplate(
            id: "cli-tool",
            name: "CLI Tool",
            summary: "Core behavior, parser, and tests for a command-line tool.",
            defaultProvider: .codex,
            roles: [
                AgentTeamTemplateRole(
                    id: "core",
                    name: "Core",
                    prompt: "Own the core domain behavior and error model.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
                AgentTeamTemplateRole(
                    id: "parser",
                    name: "Parser",
                    prompt: "Own argument parsing, command contracts, and user-facing validation.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
                AgentTeamTemplateRole(
                    id: "tests",
                    name: "Tests",
                    prompt: "Own unit, integration, and smoke coverage for the CLI workflow.",
                    permissions: [.fileRead, .fileWrite, .exec]
                ),
            ]
        ),
    ])

    func template(id: String) -> AgentTeamTemplate? {
        templatesByID[AgentTeamConfig.slug(id)]
    }

    func makeConfig(
        templateID: String,
        teamID: String? = nil,
        provider: AgentTeamProvider? = nil
    ) throws -> AgentTeamConfig {
        let normalizedTemplateID = AgentTeamConfig.slug(templateID)
        guard let template = templatesByID[normalizedTemplateID] else {
            throw AgentTeamTemplateError.unknownTemplate(normalizedTemplateID)
        }
        guard !template.roles.isEmpty else {
            throw AgentTeamTemplateError.emptyRoles(normalizedTemplateID)
        }

        let normalizedTeamID = AgentTeamConfig.slug(teamID ?? template.id)
        var usedIDs: [String: Int] = [:]
        let teammates = template.roles.map { role -> AgentTeammateConfig in
            let roleSlug = AgentTeamConfig.slug(role.id.isEmpty ? role.name : role.id)
            let baseID = "\(normalizedTeamID)-\(roleSlug)"
            let next = (usedIDs[baseID] ?? 0) + 1
            usedIDs[baseID] = next
            let teammateID = next == 1 ? baseID : "\(baseID)-\(next)"
            return AgentTeammateConfig(id: teammateID, name: role.name, prompt: role.prompt)
        }

        return AgentTeamConfig(
            id: normalizedTeamID,
            provider: provider ?? template.defaultProvider,
            teammates: teammates
        )
    }
}
