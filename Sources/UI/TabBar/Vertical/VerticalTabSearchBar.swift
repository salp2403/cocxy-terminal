// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabSearchBar.swift - Search field for the Aurora vertical sidebar.

import SwiftUI

extension Design {

    struct VerticalTabSearchBar: View {
        @Binding var query: String
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Text("⌕")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
                TextField(Self.localizedPlaceholder(using: localizer), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textHigh.resolvedColor())
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.glassHighlight.resolvedColor())
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.glassBorder.resolvedColor(), lineWidth: 1)
                    )
            )
        }

        static func localizedPlaceholder(using localizer: AppLocalizer) -> String {
            localizer.string("verticalTab.search.placeholder", fallback: "Filter sessions...")
        }
    }
}
