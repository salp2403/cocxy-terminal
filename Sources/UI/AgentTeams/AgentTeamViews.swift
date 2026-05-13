// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamViews.swift - SwiftUI surfaces for local agent teams.

import SwiftUI

struct AgentTeamSidebarBadge: View {
    let teammate: AgentTeammateState
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(teammate.name.prefix(2).uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if unreadCount > 0 {
                Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.92), in: Capsule())
                    .foregroundStyle(Color.white)
            }
        }
        .accessibilityLabel("\(teammate.name), \(teammate.status.rawValue)")
    }

    private var statusColor: Color {
        switch teammate.status {
        case .starting: return .blue
        case .working: return .green
        case .waiting: return .yellow
        case .finished: return .secondary
        case .error: return .red
        }
    }
}

struct AgentTeammateRowView: View {
    let teammate: AgentTeammateState
    let notifications: [AgentTeamNotification]

    var body: some View {
        HStack(spacing: 10) {
            AgentTeamSidebarBadge(teammate: teammate, unreadCount: notifications.count)
            VStack(alignment: .leading, spacing: 2) {
                Text(teammate.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(teammate.status.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AgentTeamPanelView: View {
    let coordinator: AgentTeamCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Agent Team")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(coordinator.config.teammates.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ForEach(coordinator.teammateStates) { teammate in
                AgentTeammateRowView(
                    teammate: teammate,
                    notifications: coordinator.notifications(for: teammate.id)
                )
            }
        }
        .padding(12)
    }
}

struct AgentTeamCreatorSheet: View {
    @Binding var teammates: String
    let onLaunch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Team")
                .font(.headline)
            TextField("Design, Build, Review", text: $teammates)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Launch", action: onLaunch)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 360)
    }
}

extension MainWindowController: AgentTeamPaneLaunching {
    func spawnAgentTeamPane(teammateID: String, sessionID: String, agentType: String) -> Bool {
        let before = panelContentViews.values.compactMap { $0 as? SubagentContentView }.count
        spawnSubagentPanel(
            subagentId: teammateID,
            sessionId: sessionID,
            agentType: agentType,
            targetTabId: visibleTabID?.rawValue ?? tabManager.activeTabID?.rawValue
        )
        let after = panelContentViews.values.compactMap { $0 as? SubagentContentView }.count
        return after > before || panelContentViews.values.contains { view in
            guard let subagentView = view as? SubagentContentView else { return false }
            return subagentView.subagentId == teammateID && subagentView.sessionId == sessionID
        }
    }
}
