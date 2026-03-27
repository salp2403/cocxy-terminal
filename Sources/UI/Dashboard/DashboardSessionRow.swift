// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DashboardSessionRow.swift - Rich session row in the agent dashboard panel.

import SwiftUI

// MARK: - Dashboard Session Row

/// A single row in the dashboard panel representing one agent session.
///
/// Displays a rich, multi-line view of the agent's current activity:
/// - State indicator (colored circle with pulsing animation when working)
/// - Agent name + model badge
/// - Project name + git branch
/// - Current tool + file being worked on
/// - Subagent list with individual states
/// - Time since last activity
///
/// Click navigates to the associated tab via the ViewModel.
struct DashboardSessionRow: View {

    let session: AgentSessionInfo
    let onNavigate: () -> Void
    var onSetPriority: ((AgentPriority) -> Void)?

    @State private var isPulsing = false

    // MARK: - Body

    var body: some View {
        Button(action: onNavigate) {
            HStack(alignment: .top, spacing: 10) {
                stateIndicator
                VStack(alignment: .leading, spacing: 3) {
                    headerLine
                    if let activity = session.lastActivity, !activity.isEmpty {
                        activityLine(activity)
                    }
                    if !session.subagents.isEmpty {
                        subagentSection
                    }
                }
                Spacer(minLength: 4)
                timeLabel
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            isPulsing = session.state == .working
        }
        .onChange(of: session.state) {
            isPulsing = session.state == .working
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Activate to switch to this tab")
        .contextMenu {
            priorityMenu
        }
    }

    // MARK: - Priority Context Menu

    /// Right-click context menu for setting session priority (like Bobber).
    @ViewBuilder
    private var priorityMenu: some View {
        Button {
            onSetPriority?(.focus)
        } label: {
            Label("Focus", systemImage: "star.fill")
        }

        Button {
            onSetPriority?(.priority)
        } label: {
            Label("Priority", systemImage: "arrow.up.circle")
        }

        Button {
            onSetPriority?(.standard)
        } label: {
            Label("Standard", systemImage: "minus.circle")
        }

        Divider()

        Button(action: onNavigate) {
            Label("Go to Tab", systemImage: "arrow.right.square")
        }
    }

    // MARK: - State Indicator

    private var stateIndicator: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
            .shadow(color: stateColor.opacity(session.state == .working ? 0.6 : 0), radius: 4)
            .scaleEffect(isPulsing && session.state == .working ? 1.3 : 1.0)
            .animation(
                session.state == .working
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .padding(.top, 4)
    }

    // MARK: - Header Line (Name + Agent + Model)

    private var headerLine: some View {
        HStack(spacing: 5) {
            // Priority icon (only for Focus and Priority)
            if session.priority == .focus {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.yellow))
            } else if session.priority == .priority {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.peach))
            }

            Text(session.projectName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            if let agent = session.agentName, !agent.isEmpty {
                Text(agent)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(CocxyColors.swiftUI(CocxyColors.blue).opacity(0.15))
                    )
            }

            if let branch = session.gitBranch {
                Text(branch)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.mauve))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Activity Line (Tool + File)

    private func activityLine(_ activity: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: toolIcon(for: activity))
                .font(.system(size: 9))
                .foregroundColor(stateColor)
            Text(activity)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Subagent Section

    private var subagentSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(session.subagents) { sub in
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 7))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
                    Circle()
                        .fill(subagentColor(sub.state))
                        .frame(width: 5, height: 5)
                    Text(sub.type ?? "Subagent")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))
                    Text("(\(sub.id.prefix(8)))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay0))
                }
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Time Label

    private var timeLabel: some View {
        Group {
            if let activityTime = session.lastActivityTime {
                Text(relativeTimeString(from: activityTime))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private var stateColor: Color {
        switch session.state {
        case .working:         return CocxyColors.swiftUI(CocxyColors.blue)
        case .waitingForInput: return CocxyColors.swiftUI(CocxyColors.yellow)
        case .error:           return CocxyColors.swiftUI(CocxyColors.red)
        case .blocked:         return CocxyColors.swiftUI(CocxyColors.peach)
        case .finished:        return CocxyColors.swiftUI(CocxyColors.green)
        case .launching:       return CocxyColors.swiftUI(CocxyColors.blue)
        case .idle:            return CocxyColors.swiftUI(CocxyColors.overlay0)
        }
    }

    private func subagentColor(_ state: AgentDashboardState) -> Color {
        switch state {
        case .working: return CocxyColors.swiftUI(CocxyColors.blue)
        case .finished: return CocxyColors.swiftUI(CocxyColors.green)
        case .error: return CocxyColors.swiftUI(CocxyColors.red)
        default: return CocxyColors.swiftUI(CocxyColors.overlay0)
        }
    }

    private func toolIcon(for activity: String) -> String {
        let lower = activity.lowercased()
        if lower.hasPrefix("read") { return "doc.text" }
        if lower.hasPrefix("write") { return "square.and.pencil" }
        if lower.hasPrefix("edit") { return "pencil.line" }
        if lower.hasPrefix("bash") { return "terminal" }
        if lower.hasPrefix("glob") || lower.hasPrefix("grep") { return "magnifyingglass" }
        if lower.hasPrefix("agent") { return "person.2" }
        if lower.contains("error") { return "exclamationmark.triangle" }
        return "wrench"
    }

    private var accessibilityDescription: String {
        var parts = [session.projectName]
        if let agent = session.agentName { parts.append(agent) }
        if let branch = session.gitBranch { parts.append("branch \(branch)") }
        parts.append(DashboardStateIndicator.accessibilityLabel(for: session.state))
        if let activity = session.lastActivity { parts.append(activity) }
        if !session.subagents.isEmpty {
            parts.append("\(session.subagents.count) subagents")
        }
        return parts.joined(separator: ", ")
    }

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
