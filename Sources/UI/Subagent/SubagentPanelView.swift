// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SubagentPanelView.swift - Live activity panel for a running subagent.

import SwiftUI

// MARK: - Subagent Panel View

/// A live panel showing a subagent's activity in real-time.
///
/// Displayed as an auto-created split when Claude Code spawns subagents.
/// Shows the agent type, state, tool activity feed, and stats.
/// Updates reactively via the dashboard ViewModel's `@Published sessions`.
///
/// This is Cocxy's answer to cmux's "native pane splits" for Agent Teams,
/// but with structured data instead of raw terminal output.
struct SubagentPanelView: View {

    @ObservedObject var viewModel: AgentDashboardViewModel
    let subagentId: String
    let sessionId: String
    var onClose: (() -> Void)?

    // MARK: - Computed Data

    private var session: AgentSessionInfo? {
        viewModel.sessions.first { $0.id == sessionId }
    }

    private var subagent: SubagentInfo? {
        session?.subagents.first { $0.id == subagentId }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
                .background(CocxyColors.swiftUI(CocxyColors.surface0))
            if let sub = subagent {
                contentArea(sub)
            } else {
                waitingView
            }
        }
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            stateCircle
            VStack(alignment: .leading, spacing: 1) {
                Text(subagent?.type ?? "Subagent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.text))
                Text(verbatim: subagent.map(Self.formatDuration) ?? "Starting...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay0))
            }
            Spacer()
            if let sub = subagent {
                statsChips(sub)
            }
            if let close = onClose {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
                }
                .buttonStyle(.plain)
                .help("Close panel")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(CocxyColors.swiftUI(CocxyColors.mantle))
    }

    private var stateCircle: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
    }

    private var stateColor: Color {
        guard let sub = subagent else {
            return CocxyColors.swiftUI(CocxyColors.overlay0)
        }
        switch sub.state {
        case .working:         return CocxyColors.swiftUI(CocxyColors.blue)
        case .finished:        return CocxyColors.swiftUI(CocxyColors.green)
        case .error:           return CocxyColors.swiftUI(CocxyColors.red)
        case .waitingForInput: return CocxyColors.swiftUI(CocxyColors.yellow)
        default:               return CocxyColors.swiftUI(CocxyColors.overlay0)
        }
    }

    private func statsChips(_ sub: SubagentInfo) -> some View {
        HStack(spacing: 6) {
            if sub.toolUseCount > 0 {
                chip(icon: "wrench", value: "\(sub.toolUseCount)", color: CocxyColors.overlay0)
            }
            if sub.errorCount > 0 {
                chip(icon: "exclamationmark.triangle", value: "\(sub.errorCount)", color: CocxyColors.red)
            }
            if !sub.touchedFilePaths.isEmpty {
                chip(icon: "doc", value: "\(sub.touchedFilePaths.count)", color: CocxyColors.overlay0)
            }
        }
    }

    private func chip(icon: String, value: String, color: NSColor) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(verbatim: value)
                .font(.system(size: 9, design: .monospaced))
        }
        .foregroundColor(CocxyColors.swiftUI(color))
    }

    // MARK: - Content

    private func contentArea(_ sub: SubagentInfo) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(sub.activities) { activity in
                    activityRow(activity)
                }
                if sub.activities.isEmpty {
                    Text(sub.lastActivity ?? "Running...")
                        .font(.system(size: 11))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func activityRow(_ activity: ToolActivity) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: Self.iconForTool(activity.toolName))
                .font(.system(size: 9))
                .foregroundColor(activity.isError
                    ? CocxyColors.swiftUI(CocxyColors.red)
                    : CocxyColors.swiftUI(CocxyColors.blue))
                .frame(width: 14)

            Text(activity.summary)
                .font(.system(size: 11))
                .foregroundColor(activity.isError
                    ? CocxyColors.swiftUI(CocxyColors.red)
                    : CocxyColors.swiftUI(CocxyColors.text))
                .lineLimit(2)

            Spacer()

            Text(Self.timeFormatter.string(from: activity.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay0))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private var waitingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
            Text("Agent starting...")
                .font(.system(size: 11))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
            Spacer()
        }
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func formatDuration(_ sub: SubagentInfo) -> String {
        let seconds = Int(sub.duration)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }

    static func iconForTool(_ toolName: String) -> String {
        let lower = toolName.lowercased()
        if lower.contains("read") { return "doc.text" }
        if lower.contains("write") || lower.contains("edit") { return "pencil" }
        if lower.contains("bash") { return "terminal" }
        if lower.contains("glob") || lower.contains("grep") { return "magnifyingglass" }
        if lower.contains("agent") { return "person.2" }
        if lower.contains("web") { return "globe" }
        return "wrench"
    }
}
