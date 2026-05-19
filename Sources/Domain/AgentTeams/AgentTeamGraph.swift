// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamGraph.swift - Pure state graph for local agent team orchestration.

import Foundation

enum AgentTeamPermission: String, CaseIterable, Codable, Sendable, Equatable {
    case fileRead = "file-read"
    case fileWrite = "file-write"
    case network
    case exec
}

enum AgentTeamGraphError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownNode(String)
    case emptyNodeID
    case emptyFilePath

    var description: String {
        switch self {
        case .unknownNode(let nodeID):
            return "Unknown agent team graph node: \(nodeID)"
        case .emptyNodeID:
            return "Agent team graph node id cannot be empty"
        case .emptyFilePath:
            return "Touched file path cannot be empty"
        }
    }
}

struct AgentTeamGraphNode: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let provider: AgentTeamProvider
    var status: AgentTeamStatus
    var permissions: [AgentTeamPermission]
    var touchedFiles: [String]
    var updatedAt: Date
}

struct AgentTeamGraphEdge: Codable, Sendable, Equatable {
    let parentID: String
    let childID: String
}

struct AgentTeamGraph: Codable, Sendable, Equatable {
    let rootID: String
    private var nodeOrder: [String]
    private var nodesByID: [String: AgentTeamGraphNode]
    private(set) var edges: [AgentTeamGraphEdge]

    init(config: AgentTeamConfig, now: Date = Date()) {
        self.rootID = config.id
        let root = AgentTeamGraphNode(
            id: config.id,
            name: config.id,
            provider: config.provider,
            status: .starting,
            permissions: [],
            touchedFiles: [],
            updatedAt: now
        )
        let teammates = config.teammates.map { teammate in
            AgentTeamGraphNode(
                id: teammate.id,
                name: teammate.name,
                provider: config.provider,
                status: .starting,
                permissions: [],
                touchedFiles: [],
                updatedAt: now
            )
        }

        let allNodes = [root] + teammates
        self.nodeOrder = allNodes.map(\.id)
        self.nodesByID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
        self.edges = config.teammates.map { teammate in
            AgentTeamGraphEdge(parentID: config.id, childID: teammate.id)
        }
    }

    var nodes: [AgentTeamGraphNode] {
        nodeOrder.compactMap { nodesByID[$0] }
    }

    func node(id: String) -> AgentTeamGraphNode? {
        nodesByID[id]
    }

    @discardableResult
    mutating func linkSubagent(
        parentID: String? = nil,
        subagentID: String,
        name: String?,
        provider: AgentTeamProvider,
        status: AgentTeamStatus = .working,
        now: Date = Date()
    ) throws -> AgentTeamGraphNode {
        let normalizedID = subagentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw AgentTeamGraphError.emptyNodeID
        }

        let resolvedParentID = parentID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? rootID
        guard nodesByID[resolvedParentID] != nil else {
            throw AgentTeamGraphError.unknownNode(resolvedParentID)
        }

        let normalizedName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? normalizedID

        if var node = nodesByID[normalizedID] {
            node.status = status
            node.updatedAt = now
            nodesByID[normalizedID] = node
            linkEdgeIfNeeded(parentID: resolvedParentID, childID: normalizedID)
            return node
        }

        let node = AgentTeamGraphNode(
            id: normalizedID,
            name: normalizedName,
            provider: provider,
            status: status,
            permissions: [],
            touchedFiles: [],
            updatedAt: now
        )
        nodeOrder.append(normalizedID)
        nodesByID[normalizedID] = node
        linkEdgeIfNeeded(parentID: resolvedParentID, childID: normalizedID)
        return node
    }

    mutating func updateStatus(nodeID: String, status: AgentTeamStatus, now: Date = Date()) throws {
        try updateNode(nodeID: nodeID) { node in
            node.status = status
            node.updatedAt = now
        }
    }

    mutating func setPermissions(
        nodeID: String,
        permissions: [AgentTeamPermission],
        now: Date = Date()
    ) throws {
        try updateNode(nodeID: nodeID) { node in
            node.permissions = permissions
            node.updatedAt = now
        }
    }

    mutating func recordTouchedFile(nodeID: String, path: String, now: Date = Date()) throws {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw AgentTeamGraphError.emptyFilePath
        }

        try updateNode(nodeID: nodeID) { node in
            if !node.touchedFiles.contains(normalizedPath) {
                node.touchedFiles.append(normalizedPath)
                node.touchedFiles.sort()
            }
            node.updatedAt = now
        }
    }

    private mutating func linkEdgeIfNeeded(parentID: String, childID: String) {
        let edge = AgentTeamGraphEdge(parentID: parentID, childID: childID)
        if !edges.contains(edge) {
            edges.append(edge)
        }
    }

    private mutating func updateNode(
        nodeID: String,
        _ update: (inout AgentTeamGraphNode) -> Void
    ) throws {
        guard var node = nodesByID[nodeID] else {
            throw AgentTeamGraphError.unknownNode(nodeID)
        }
        update(&node)
        nodesByID[nodeID] = node
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
