// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TeamGraphView.swift - Agent team graph and feed surfaces.

import Foundation
import SwiftUI

struct AgentTeamGraphRowPresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let providerName: String
    let status: AgentTeamStatus
    let permissionSummary: String
    let touchedFileSummary: String
    let isRoot: Bool

    var accessibilityLabel: String {
        var parts = [name, providerName, status.rawValue]
        if permissionSummary != "none" {
            parts.append("permissions \(permissionSummary)")
        }
        if touchedFileSummary != "no files" {
            parts.append("\(touchedFileSummary) touched")
        }
        return parts.joined(separator: ", ")
    }
}

struct AgentTeamGraphPresentation: Equatable {
    let rows: [AgentTeamGraphRowPresentation]

    init(graph: AgentTeamGraph) {
        rows = graph.nodes.map { node in
            AgentTeamGraphRowPresentation(
                id: node.id,
                name: node.name,
                providerName: node.provider.displayName,
                status: node.status,
                permissionSummary: Self.permissionSummary(node.permissions),
                touchedFileSummary: Self.touchedFileSummary(node.touchedFiles),
                isRoot: node.id == graph.rootID
            )
        }
    }

    private static func permissionSummary(_ permissions: [AgentTeamPermission]) -> String {
        guard !permissions.isEmpty else { return "none" }
        return permissions.map(\.rawValue).joined(separator: ", ")
    }

    private static func touchedFileSummary(_ paths: [String]) -> String {
        switch paths.count {
        case 0:
            return "no files"
        case 1:
            return "1 file"
        default:
            return "\(paths.count) files"
        }
    }
}

struct AgentTeamFeedEventPresentation: Identifiable, Equatable {
    let id: String
    let teammateName: String
    let kind: AgentTeamFeedEventKind
    let message: String
    let metadataSummary: String

    var accessibilityLabel: String {
        [teammateName, kind.rawValue, message].joined(separator: ", ")
    }
}

struct AgentTeamFeedPresentation: Equatable {
    let rows: [AgentTeamFeedEventPresentation]

    init(
        feed: AgentTeamFeed,
        kind: AgentTeamFeedEventKind? = nil,
        query: String? = nil
    ) {
        rows = feed.events(kind: kind, matching: query).map { event in
            AgentTeamFeedEventPresentation(
                id: event.id.uuidString,
                teammateName: event.teammateName,
                kind: event.kind,
                message: event.message,
                metadataSummary: Self.metadataSummary(event.metadata)
            )
        }
    }

    private static func metadataSummary(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return "" }
        return metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "  ")
    }
}

struct TeamGraphView: View {
    let graph: AgentTeamGraph
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    private var presentation: AgentTeamGraphPresentation {
        AgentTeamGraphPresentation(graph: graph)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: localizer.string("agentTeams.graph.title", fallback: "Team Graph"),
                systemImage: "point.3.connected.trianglepath.dotted"
            )
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(presentation.rows) { row in
                    TeamGraphNodeRow(row: row)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("agentTeams.graph.accessibility", fallback: "Agent team graph"))
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
    }
}

private struct TeamGraphNodeRow: View {
    let row: AgentTeamGraphRowPresentation

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: row.isRoot ? 9 : 7, height: row.isRoot ? 9 : 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 11, weight: row.isRoot ? .semibold : .medium))
                        .lineLimit(1)
                    Text(row.providerName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(row.status.rawValue)
                    if row.permissionSummary != "none" {
                        Text(row.permissionSummary)
                    }
                    if row.touchedFileSummary != "no files" {
                        Text(row.touchedFileSummary)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(row.isRoot ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var statusColor: Color {
        switch row.status {
        case .starting:
            return .blue
        case .working:
            return .green
        case .waiting:
            return .yellow
        case .finished:
            return .secondary
        case .error:
            return .red
        }
    }
}

struct AgentTeamFeedView: View {
    let feed: AgentTeamFeed
    var kind: AgentTeamFeedEventKind?
    var query: String = ""
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    private var presentation: AgentTeamFeedPresentation {
        AgentTeamFeedPresentation(
            feed: feed,
            kind: kind,
            query: query
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: localizer.string("agentTeams.feed.title", fallback: "Agent Feed"),
                systemImage: "text.bubble"
            )
            if presentation.rows.isEmpty {
                Text(localizer.string("agentTeams.feed.empty", fallback: "No team events"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(presentation.rows) { row in
                        AgentTeamFeedEventRow(row: row)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("agentTeams.feed.accessibility", fallback: "Agent team feed"))
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
    }
}

private struct AgentTeamFeedEventRow: View {
    let row: AgentTeamFeedEventPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.teammateName)
                    .font(.system(size: 11, weight: .semibold))
                Text(row.kind.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(row.message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !row.metadataSummary.isEmpty {
                Text(row.metadataSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
