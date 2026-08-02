// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomeUnavailablePanelView.swift - Honest project home restoration failure state.

import SwiftUI

struct ProjectHomeUnavailablePanelView: View {
    let localizer: AppLocalizer
    var message: String? = nil

    @Environment(\.designThemePalette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(palette.accent.resolvedColor())
            Text(localizer.string(
                "projectHome.unavailable.title",
                fallback: "Project Home Unavailable"
            ))
                .font(.system(size: 16, weight: .semibold))
            Text(message ?? localizer.string(
                "projectHome.unavailable.message",
                fallback: "Project services are not ready for this restored panel."
            ))
                .font(.system(size: 12))
                .foregroundStyle(palette.textMedium.resolvedColor())
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.backgroundPrimary.resolvedColor())
    }
}
