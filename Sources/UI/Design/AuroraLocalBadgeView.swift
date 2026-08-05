// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraLocalBadgeView.swift - Privacy status badge for Aurora chrome.

import SwiftUI

extension Design {
    /// Privacy status badge used by the Aurora status bar's leftmost
    /// chip. Keep the copy scoped to telemetry, not execution locality:
    /// Cocxy supports explicit remote sessions, so "100% local" would
    /// overstate the runtime model whenever SSH features are active.
    struct LocalBadgeView: View {
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            let finished = AgentStateRole.finished.token.resolvedColor()
            HStack(spacing: Spacing.xxSmall) {
                Circle()
                    .fill(finished)
                    .frame(width: 6, height: 6)
                    .shadow(color: finished.opacity(0.7), radius: 3)
                Text(Self.localizedLabel(using: localizer))
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(finished)
            }
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(finished.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .strokeBorder(finished.opacity(0.35), lineWidth: 1)
                    )
            )
            .help(Self.localizedHelp(using: localizer))
            .accessibilityLabel(Self.localizedAccessibilityLabel(using: localizer))
        }

        static func localizedLabel(using localizer: AppLocalizer) -> String {
            localizer.string("auroraStatus.localBadge.label", fallback: "no telemetry")
        }

        static func localizedHelp(using localizer: AppLocalizer) -> String {
            localizer.string(
                "auroraStatus.localBadge.help",
                fallback: "No telemetry or tracking. Update checks only contact Cocxy's signed appcast."
            )
        }

        static func localizedAccessibilityLabel(using localizer: AppLocalizer) -> String {
            localizer.string(
                "auroraStatus.localBadge.accessibility",
                fallback: "No telemetry or tracking"
            )
        }
    }
}
