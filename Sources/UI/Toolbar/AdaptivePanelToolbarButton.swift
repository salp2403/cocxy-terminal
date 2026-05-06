// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AdaptivePanelToolbarButton.swift - Compact toolbar controls for split panels.

import SwiftUI

struct AdaptivePanelToolbarPresentation: Equatable, Sendable {
    static let compactActionWidth: CGFloat = 380
    static let statusVisibleWidth: CGFloat = 300

    let usesCompactActions: Bool
    let showsStatus: Bool

    static func resolve(width: CGFloat) -> AdaptivePanelToolbarPresentation {
        AdaptivePanelToolbarPresentation(
            usesCompactActions: width < compactActionWidth,
            showsStatus: width >= statusVisibleWidth
        )
    }
}

struct AdaptivePanelToolbarButton: View {
    let title: String
    let systemImage: String
    let compact: Bool
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if compact {
                Image(systemName: systemImage)
                    .frame(width: 16, height: 16)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .controlSize(.small)
        .disabled(isDisabled)
        .help(title)
        .accessibilityLabel(title)
    }
}
