// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentProgressOverlay.swift - Subtle progress pill shown during agent work.

import SwiftUI

// MARK: - Agent Progress Overlay

/// A translucent pill in the bottom-right corner of the terminal area
/// showing real-time agent progress (tool count, errors, duration).
///
/// Appears when an agent is actively working on the current tab.
/// Transparent to mouse events so terminal interaction is never blocked.
///
/// ## Visibility Rules
///
/// - Shown when the active tab's `agentState` is `.working` or `.launched`.
/// - Hidden when `agentState` is `.idle`, `.finished`, or `.error`.
/// - Updated by `MainWindowController` on tab switch and state changes.
struct AgentProgressOverlay: View {

    let agentName: String
    let toolCount: Int
    let errorCount: Int
    let durationText: String?

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: CocxyColors.blue))
                .frame(width: 6, height: 6)
                .opacity(isVisible ? 1.0 : 0.4)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isVisible
                )

            Text(agentName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            if toolCount > 0 {
                statLabel(
                    icon: "bolt.fill",
                    value: "\(toolCount)",
                    color: CocxyColors.blue
                )
            }

            if errorCount > 0 {
                statLabel(
                    icon: "exclamationmark.triangle.fill",
                    value: "\(errorCount)",
                    color: CocxyColors.red
                )
            }

            if let duration = durationText {
                statLabel(
                    icon: "clock",
                    value: duration,
                    color: CocxyColors.overlay1
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .onAppear { isVisible = true }
    }

    private func statLabel(icon: String, value: String, color: NSColor) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(verbatim: value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundColor(Color(nsColor: color))
    }
}
