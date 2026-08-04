// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomeUnavailablePanelView.swift - Honest project home restoration failure state.

import SwiftUI

struct ProjectHomeUnavailablePanelView: View {
    let localizer: AppLocalizer
    var messageKey = "projectHome.unavailable.message"
    var messageFallback = "Project services are not ready for this restored panel."

    @Environment(\.designThemePalette) private var palette

    var messageText: String {
        localizer.string(messageKey, fallback: messageFallback)
    }

    func updatedLocalizer(_ localizer: AppLocalizer) -> Self {
        Self(
            localizer: localizer,
            messageKey: messageKey,
            messageFallback: messageFallback
        )
    }

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
            Text(messageText)
                .font(.system(size: 12))
                .foregroundStyle(palette.textMedium.resolvedColor())
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanelBackground()
        .environment(\.layoutDirection, localizer.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
