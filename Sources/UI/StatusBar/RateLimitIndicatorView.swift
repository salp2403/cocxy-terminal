// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitIndicatorView.swift - SwiftUI pill rendering the active
// agent's local-only rate-limit snapshot in the status bar.

import SwiftUI

/// Status-bar pill that renders a `RateLimitSnapshot` as a small dot +
/// percent capsule with a hover tooltip.
///
/// The view is intentionally dumb: it draws whatever the parent passes
/// in. The polling timer, agent-tracking, and provider dispatch live in
/// `RateLimitProbeService`; the rendering rules (label and tooltip
/// strings) live in `RateLimitIndicatorFormatting`. The view only owns
/// the colour mapping for the three heat bands so the brand palette
/// can evolve in `CocxyColors` without rippling into the formatting
/// helper.
///
/// ## Visual layout
///
/// ```
/// ●  42%
/// ```
///
/// The dot is filled in the band colour (green / yellow / red); the
/// pill's background is the same colour at 15% opacity so the
/// indicator is legible under both light and dark chrome without
/// relying on a vibrancy material.
struct RateLimitIndicatorView: View {

    /// Snapshot the pill renders. Always non-nil — the parent decides
    /// whether to render the indicator at all (the status bar threads
    /// the optional from `RateLimitProbeService.snapshot` and elides
    /// the view entirely when it is `nil`).
    let snapshot: RateLimitSnapshot
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Self.color(for: snapshot.heatLevel))
                .frame(width: 6, height: 6)
            Text(RateLimitIndicatorFormatting.percentLabel(for: snapshot))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Self.color(for: snapshot.heatLevel).opacity(0.15))
        )
        .help(RateLimitIndicatorFormatting.tooltipText(for: snapshot))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.localizedAccessibilityLabel(for: snapshot, using: localizer))
        .accessibilityValue(RateLimitIndicatorFormatting.percentLabel(for: snapshot))
    }

    /// Maps the closed heat band to the brand palette. Internal so a
    /// future smoke / snapshot test can probe the colour without
    /// reflecting on `Color`.
    static func color(for level: RateLimitSnapshot.HeatLevel) -> Color {
        switch level {
        case .green:  return CocxyColors.swiftUI(CocxyColors.green)
        case .yellow: return CocxyColors.swiftUI(CocxyColors.yellow)
        case .red:    return CocxyColors.swiftUI(CocxyColors.red)
        }
    }

    static func localizedAccessibilityLabel(
        for snapshot: RateLimitSnapshot,
        using localizer: AppLocalizer
    ) -> String {
        String(
            format: localizer.string("statusBar.rateLimit.usage", fallback: "%@ usage"),
            RateLimitIndicatorFormatting.agentDisplayName(snapshot.agent)
        )
    }
}
