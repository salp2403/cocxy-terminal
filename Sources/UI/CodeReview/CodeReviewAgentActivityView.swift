// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewAgentActivityView.swift - Live agent and subagent activity strip for Code Review.

import AppKit
import SwiftUI

struct CodeReviewAgentActivityView: View {
    let sessions: [AgentSessionInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Label("Live Agent Workstream", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))

                Spacer(minLength: 8)

                metric("\(sessions.count)", "agents", color: CocxyColors.blue)
                metric("\(subagentCount)", "subs", color: CocxyColors.mauve)
                metric("\(touchedFileCount)", "files", color: CocxyColors.green)
                if conflictCount > 0 {
                    metric("\(conflictCount)", "conflicts", color: CocxyColors.red)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(sessions) { session in
                        CodeReviewAgentSessionCard(session: session)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: CocxyColors.surface0).opacity(0.76),
                    Color(nsColor: CocxyColors.mantle).opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live agent workstream")
    }

    private var subagentCount: Int {
        sessions.reduce(0) { $0 + $1.subagents.count }
    }

    private var touchedFileCount: Int {
        Set(sessions.flatMap { $0.filesTouched.map(\.path) }).count
    }

    private var conflictCount: Int {
        Set(sessions.flatMap(\.fileConflicts)).count
    }

    private func metric(_ value: String, _ label: String, color: NSColor) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(nsColor: color))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(nsColor: color).opacity(0.12))
        )
    }
}

private struct CodeReviewAgentSessionCard: View {
    let session: AgentSessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                agentBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(agentName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(nsColor: CocxyColors.text))
                        .lineLimit(1)

                    Text("\(session.projectName) · \(stateLabel)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let lastActivityTime = session.lastActivityTime {
                    Text(relativeTime(lastActivityTime))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }
            }

            HStack(spacing: 6) {
                chip("\(session.totalToolCalls)", "tools", color: CocxyColors.sky)
                chip("\(session.filesTouched.count)", "files", color: CocxyColors.green)
                if session.totalErrors > 0 {
                    chip("\(session.totalErrors)", "errors", color: CocxyColors.red)
                }
                if !session.fileConflicts.isEmpty {
                    chip("\(session.fileConflicts.count)", "conflicts", color: CocxyColors.red)
                }
            }

            if let lastActivity = session.lastActivity, !lastActivity.isEmpty {
                Text(lastActivity)
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            subagentSection
            fileImpactSection
        }
        .padding(10)
        .frame(width: 280, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: CocxyColors.base).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: agentColor).opacity(0.36), lineWidth: 1)
        )
    }

    private var agentName: String {
        let trimmedName = session.agentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Agent" : trimmedName
    }

    private var agentBadge: some View {
        Text(agentInitials)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(nsColor: agentColor))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: agentColor).opacity(0.14))
            )
    }

    private var agentInitials: String {
        let lower = agentName.lowercased()
        if lower.contains("claude") { return "Cl" }
        if lower.contains("codex") { return "Co" }
        if lower.contains("gemini") { return "Ge" }
        return String(agentName.prefix(2)).capitalized
    }

    private var agentColor: NSColor {
        let lower = agentName.lowercased()
        if lower.contains("claude") { return CocxyColors.peach }
        if lower.contains("codex") { return CocxyColors.green }
        if lower.contains("gemini") { return CocxyColors.blue }
        return CocxyColors.mauve
    }

    private var stateLabel: String {
        switch session.state {
        case .working: return "working"
        case .waitingForInput: return "waiting"
        case .blocked: return "blocked"
        case .idle: return "idle"
        case .finished: return "finished"
        case .error: return "error"
        case .launching: return "launching"
        }
    }

    @ViewBuilder
    private var subagentSection: some View {
        if !session.subagents.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Subagents")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))

                ForEach(session.subagents.prefix(3)) { subagent in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(nsColor: color(for: subagent.state)))
                            .frame(width: 6, height: 6)
                        Text(subagent.type ?? subagent.id)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if subagent.toolUseCount > 0 {
                            Text("\(subagent.toolUseCount)t")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        }
                        if !subagent.touchedFilePaths.isEmpty {
                            Text("\(subagent.touchedFilePaths.count)f")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: CocxyColors.surface0).opacity(0.72))
                    )
                }

                if session.subagents.count > 3 {
                    Text("+\(session.subagents.count - 3) more subagents")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }
            }
        }
    }

    @ViewBuilder
    private var fileImpactSection: some View {
        if !session.filesTouched.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Touched files")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))

                ForEach(session.filesTouched.prefix(4), id: \.path) { impact in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(nsColor: CocxyColors.blue))
                        Text(impact.fileName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(operationSummary(impact.operations))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    }
                }
            }
        }
    }

    private func chip(_ value: String, _ label: String, color: NSColor) -> some View {
        Text("\(value) \(label)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(Color(nsColor: color))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(nsColor: color).opacity(0.10))
            )
    }

    private func color(for state: AgentDashboardState) -> NSColor {
        switch state {
        case .working: return CocxyColors.blue
        case .waitingForInput: return CocxyColors.yellow
        case .blocked, .error: return CocxyColors.red
        case .finished: return CocxyColors.green
        case .launching: return CocxyColors.mauve
        case .idle: return CocxyColors.overlay0
        }
    }

    private func operationSummary(_ operations: Set<FileImpact.FileOperation>) -> String {
        operations
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }
}
