// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskInboxEntry.swift - Unified project task inbox presentation contract.

import Foundation

enum TaskInboxEntryKind: String, Codable, CaseIterable, Equatable, Sendable {
    case fanOut = "fan-out"
    case queuedTask = "queue"
    case liveAgent = "live-agent"
    case handoff
}

struct TaskInboxStatus: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = trimmed.isEmpty ? "unknown" : trimmed
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var isTerminal: Bool {
        Self.terminalRawValues.contains(rawValue)
    }

    func localized(for kind: TaskInboxEntryKind, using localizer: AppLocalizer) -> String {
        let key: String
        switch kind {
        case .fanOut:
            key = "taskRun.status.\(rawValue)"
        case .queuedTask:
            key = "taskQueue.status.\(rawValue)"
        case .liveAgent, .handoff:
            let dashboardValue: String
            switch rawValue {
            case "launched": dashboardValue = "launching"
            case "waitingInput": dashboardValue = "waitingForInput"
            default: dashboardValue = rawValue
            }
            key = "agentDashboard.state.\(dashboardValue)"
        }
        return localizer.string(key, fallback: fallback)
    }

    private var fallback: String {
        switch rawValue {
        case "waitingForInput", "waitingInput": return "Waiting for input"
        case "retrying": return "Retrying"
        case "succeeded": return "Succeeded"
        case "cancelled": return "Cancelled"
        case "launching", "launched": return "Launching"
        case "promoting": return "Promoting"
        case "completed": return "Completed"
        default: return rawValue.capitalized
        }
    }

    private static let terminalRawValues: Set<String> = [
        "cancelled", "completed", "error", "failed", "finished", "succeeded",
    ]
}

enum TaskInboxTitleKind: String, Codable, Equatable, Sendable {
    case taskHandoff
}

struct TaskInboxNavigation: Equatable, Sendable {
    let windowID: WindowID?
    let tabID: TabID?
    let sessionID: String?

    init(windowID: WindowID? = nil, tabID: TabID? = nil, sessionID: String? = nil) {
        self.windowID = windowID
        self.tabID = tabID
        self.sessionID = sessionID
    }
}

struct TaskInboxEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: TaskInboxEntryKind
    let projectID: ProjectID
    let title: String
    let titleKind: TaskInboxTitleKind?
    let status: TaskInboxStatus
    let agents: [String]
    let worktreePaths: [String]
    let touchedFiles: [String]
    let updatedAt: Date

    /// Local routing metadata is deliberately excluded from the CLI JSON contract.
    let navigation: TaskInboxNavigation?

    init(
        id: String,
        kind: TaskInboxEntryKind,
        projectID: ProjectID,
        title: String,
        titleKind: TaskInboxTitleKind? = nil,
        status: TaskInboxStatus,
        agents: [String] = [],
        worktreePaths: [String] = [],
        touchedFiles: [String] = [],
        updatedAt: Date,
        navigation: TaskInboxNavigation? = nil
    ) {
        self.id = id
        self.kind = kind
        self.projectID = projectID
        self.title = title
        self.titleKind = titleKind
        self.status = status
        self.agents = agents
        self.worktreePaths = worktreePaths
        self.touchedFiles = touchedFiles
        self.updatedAt = updatedAt
        self.navigation = navigation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case projectID
        case title
        case titleKind
        case status
        case agents
        case worktreePaths
        case touchedFiles
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try container.decodeIfPresent(String.self, forKey: .id),
              let kind = try container.decodeIfPresent(TaskInboxEntryKind.self, forKey: .kind),
              let projectID = try container.decodeIfPresent(ProjectID.self, forKey: .projectID) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Task inbox identity is missing")
            )
        }
        self.init(
            id: id,
            kind: kind,
            projectID: projectID,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? id,
            titleKind: try container.decodeIfPresent(TaskInboxTitleKind.self, forKey: .titleKind),
            status: try container.decodeIfPresent(TaskInboxStatus.self, forKey: .status)
                ?? TaskInboxStatus(rawValue: "unknown"),
            agents: try container.decodeIfPresent([String].self, forKey: .agents) ?? [],
            worktreePaths: try container.decodeIfPresent([String].self, forKey: .worktreePaths) ?? [],
            touchedFiles: try container.decodeIfPresent([String].self, forKey: .touchedFiles) ?? [],
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(titleKind, forKey: .titleKind)
        try container.encode(status, forKey: .status)
        try container.encode(agents, forKey: .agents)
        try container.encode(worktreePaths, forKey: .worktreePaths)
        try container.encode(touchedFiles, forKey: .touchedFiles)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
