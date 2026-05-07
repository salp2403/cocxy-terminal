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

struct AdaptiveEditorResultPanelLayout: Equatable, Sendable {
    static let verticalStackWidth: CGFloat = 700

    let stacksVertically: Bool

    static func resolve(width: CGFloat) -> AdaptiveEditorResultPanelLayout {
        AdaptiveEditorResultPanelLayout(
            stacksVertically: width < verticalStackWidth
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

struct AdaptivePanelToolbarStatusText: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isError ? .red : .secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

struct AdaptivePanelToolbarCloseButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .frame(width: 16, height: 16)
        }
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
    }
}
