// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// StatusBarView.swift - Bottom status bar with contextual workspace info.

import AppKit
import SwiftUI

// MARK: - Status Bar View

/// Bottom status bar that displays contextual workspace information.
///
/// Shows: user@hostname | git branch | active ports | agent activity summary.
/// Height: 24pt. Background: Crust with a subtle top border for depth.
struct StatusBarView: View {

    /// The current user and hostname (e.g., "user@MacBook").
    let hostname: String

    /// The git branch of the active tab, if any.
    let gitBranch: String?

    /// Whether the working tree has uncommitted changes.
    var gitDirty: Bool = false

    /// Summary of agent activity across all tabs.
    let agentSummary: AgentSummary

    /// Active development server ports detected on localhost.
    var activePorts: [DetectedPort] = []

    /// Active SSH session info for the focused tab, if any.
    var sshSession: SSHSessionInfo?

    /// Duration of the last completed command in seconds.
    var lastCommandDuration: TimeInterval?

    /// Exit code of the last command (0 = success).
    var lastCommandExitCode: Int?

    /// Whether a command is currently running.
    var isCommandRunning: Bool = false

    /// Whether to use vibrancy material instead of solid background.
    var useVibrancy: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: user@host
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))
                Text(hostname)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))
            .padding(.leading, 14)

            // Separator
            if gitBranch != nil || !activePorts.isEmpty {
                statusDivider
            }

            // Center: git branch
            if let branch = gitBranch {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.mauve))
                    Text(branch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext1))
                    if gitDirty {
                        Circle()
                            .fill(CocxyColors.swiftUI(CocxyColors.yellow))
                            .frame(width: 5, height: 5)
                    }
                }
            }

            // SSH session indicator
            if let ssh = sshSession {
                statusDivider
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.green))
                    Text(ssh.displayTitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.green))
                }
                .accessibilityLabel("SSH session: \(ssh.displayTitle)")
            }

            // Command duration badge
            if isCommandRunning {
                statusDivider
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .semibold))
                    Text("running...")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))
                .accessibilityLabel("Command running")
            } else if let duration = lastCommandDuration {
                statusDivider
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                    Text(CommandDurationFormatter.format(duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    if let exitCode = lastCommandExitCode, exitCode != 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(CocxyColors.swiftUI(CocxyColors.red))
                    }
                }
                .foregroundColor(
                    (lastCommandExitCode ?? 0) == 0
                        ? CocxyColors.swiftUI(CocxyColors.green)
                        : CocxyColors.swiftUI(CocxyColors.red)
                )
                .accessibilityLabel(
                    "Last command: \(CommandDurationFormatter.format(duration)), "
                    + "exit code \(lastCommandExitCode ?? 0)"
                )
            }

            Spacer()

            // Right: active dev server ports
            if !activePorts.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .medium))
                    ForEach(activePorts.prefix(3)) { port in
                        Text(verbatim: ":\(port.port)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    if activePorts.count > 3 {
                        Text(verbatim: "+\(activePorts.count - 3)")
                            .font(.system(size: 9, weight: .medium))
                    }
                }
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.teal))
                .padding(.trailing, 10)
            }

            // Keyboard shortcuts popover
            KeyboardShortcutsButton()
                .padding(.trailing, 6)

            if let liveAgentText = agentSummary.activeAgentText {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CocxyColors.swiftUI(agentSummary.activeAgentColor))
                        .frame(width: 6, height: 6)
                        .shadow(color: CocxyColors.swiftUI(agentSummary.activeAgentColor).opacity(0.45), radius: 3)
                    Text(liveAgentText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext1))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if agentSummary.activeToolCount > 0 {
                        AgentMetricPill(
                            value: "\(agentSummary.activeToolCount)t",
                            color: CocxyColors.swiftUI(CocxyColors.blue)
                        )
                    }
                    if agentSummary.activeErrorCount > 0 {
                        AgentMetricPill(
                            value: "\(agentSummary.activeErrorCount)e",
                            color: CocxyColors.swiftUI(CocxyColors.red)
                        )
                    }
                }
                .frame(maxWidth: 280, alignment: .trailing)
                .padding(.trailing, 8)
            }

            // Right: agent activity pills
            HStack(spacing: 6) {
                if agentSummary.working > 0 {
                    AgentCountPill(
                        count: agentSummary.working,
                        label: "working",
                        color: CocxyColors.swiftUI(CocxyColors.blue)
                    )
                }
                if agentSummary.waiting > 0 {
                    AgentCountPill(
                        count: agentSummary.waiting,
                        label: "waiting",
                        color: CocxyColors.swiftUI(CocxyColors.yellow)
                    )
                }
                if agentSummary.errors > 0 {
                    AgentCountPill(
                        count: agentSummary.errors,
                        label: "error",
                        color: CocxyColors.swiftUI(CocxyColors.red)
                    )
                }
            }
            .padding(.trailing, 14)
        }
        .frame(height: 24)
        .background {
            if useVibrancy {
                VisualEffectBackground(material: .headerView, blendingMode: .behindWindow)
            } else {
                Color(nsColor: CocxyColors.crust)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.surface0).opacity(0.4))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar")
    }

    /// Subtle vertical divider between status bar sections.
    private var statusDivider: some View {
        Rectangle()
            .fill(CocxyColors.swiftUI(CocxyColors.surface1).opacity(0.4))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 10)
    }
}

// MARK: - Agent Count Pill

/// Small pill showing agent count + label (e.g., "2 working").
private struct AgentCountPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text("\(count) \(label)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

private struct AgentMetricPill: View {
    let value: String
    let color: Color

    var body: some View {
        Text(value)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Agent Summary

/// Aggregated agent state counts across all tabs.
struct AgentSummary: Equatable {
    var working: Int = 0
    var waiting: Int = 0
    var errors: Int = 0
    var finished: Int = 0
    var activeAgentText: String?
    var activeAgentColor: NSColor = CocxyColors.overlay1
    var activeToolCount: Int = 0
    var activeErrorCount: Int = 0

    static let empty = AgentSummary()
}
