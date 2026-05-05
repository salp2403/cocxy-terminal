// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceIndicator.swift - Compact Voice input status overlay.

import SwiftUI

struct VoiceIndicator: View {
    @ObservedObject var handler: VoiceTriggerHandler
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        if handler.isVisible {
            HStack(spacing: 8) {
                Image(systemName: handler.systemImageName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)

                Text(displayText)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(nsColor: CocxyColors.text))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: CocxyColors.surface0).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: CocxyColors.overlay0).opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.localizedAccessibilityLabel(using: localizer))
            .accessibilityValue(displayText)
        }
    }

    static func localizedAccessibilityLabel(using localizer: AppLocalizer) -> String {
        localizer.string("voice.indicator.accessibility", fallback: "Voice input")
    }

    private var iconColor: Color {
        switch handler.status {
        case .failed:
            return Color(nsColor: CocxyColors.red)
        case .completed:
            return Color(nsColor: CocxyColors.green)
        default:
            return Color(nsColor: CocxyColors.blue)
        }
    }

    private var displayText: String {
        handler.displayText(using: localizer)
    }
}
