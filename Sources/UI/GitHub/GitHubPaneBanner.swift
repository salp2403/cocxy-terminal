// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneBanner.swift - Informational and error banners shown inside
// the GitHub pane. Follows the info/error separation the Code Review
// panel already enforces so the two chrome-docked panels stay visually
// consistent.

import SwiftUI
import AppKit

// MARK: - Banner kinds

/// Semantic classification used by the pane's banner renderer.
///
/// Keeps the styling decision table in one place: error banners use a
/// red tint and the warning glyph, info banners use a neutral tint so
/// recoverable states (no remote, sign-in needed, etc.) do not look
/// like bugs.
enum GitHubBannerKind: Equatable {
    case info
    case error

    var symbolName: String {
        switch self {
        case .info: return "info.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .info: return NSColor.secondaryLabelColor
        case .error: return NSColor.systemRed
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .info: return NSColor.systemBlue
        case .error: return NSColor.systemRed
        }
    }

    var accessibilityPrefix: String {
        switch self {
        case .info: return "Info"
        case .error: return "Error"
        }
    }
}

// MARK: - Banner view

/// Compact banner with a leading SF Symbol, a one-line message and an
/// optional primary action. Used for install-gh, sign-in,
/// not-a-git-repo, no-remote and rate-limit states.
struct GitHubPaneBanner: View {
    let message: String
    var kind: GitHubBannerKind = .info
    var actionTitle: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbolName)
                .foregroundColor(Color(nsColor: kind.tintColor))
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let onAction {
                    Button(actionTitle) { onAction() }
                        .buttonStyle(.link)
                        .font(.system(size: 12, weight: .medium))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: kind.backgroundColor).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Color(nsColor: kind.backgroundColor).opacity(0.25),
                    lineWidth: 0.5
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.accessibilityPrefix): \(message)")
    }
}
