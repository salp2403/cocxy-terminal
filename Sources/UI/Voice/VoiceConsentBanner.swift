// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceConsentBanner.swift - One-time local Voice acknowledgement UI.

import SwiftUI

@MainActor
final class VoiceConsentCoordinator {
    private(set) var presentationCount = 0

    func claimPresentation(for config: VoiceConfig) -> Bool {
        guard config.enabled,
              !config.consentPrompted,
              presentationCount == 0 else {
            return false
        }
        presentationCount = 1
        return true
    }
}

struct VoiceConsentBanner: View {
    let localizer: AppLocalizer
    let errorMessage: String?
    let onKeepEnabled: () -> Void
    let onDisable: () -> Void
    let onOpenPreferences: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: CocxyColors.blue))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color(nsColor: CocxyColors.blue).opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(Self.localizedTitle(using: localizer))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: CocxyColors.text))

                Text(Self.localizedMessage(using: localizer))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: CocxyColors.subtext0))
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: CocxyColors.red))
                }

                actionRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: CocxyColors.overlay0).opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.localizedTitle(using: localizer))
        .accessibilityHint(Self.localizedMessage(using: localizer))
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: onKeepEnabled) {
                Label(Self.localizedKeepEnabled(using: localizer), systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: CocxyColors.blue))

            Button(action: onDisable) {
                Label(Self.localizedDisable(using: localizer), systemImage: "mic.slash")
            }
            .buttonStyle(.bordered)

            Button(action: onOpenPreferences) {
                Label(
                    Self.localizedOpenPreferences(using: localizer),
                    systemImage: "slider.horizontal.3"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(nsColor: CocxyColors.subtext1))
        }
        .controlSize(.small)
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("voice.consent.title", fallback: "Voice dictation is on")
    }

    static func localizedMessage(using localizer: AppLocalizer) -> String {
        localizer.string(
            "voice.consent.message",
            fallback: "Processing is 100% on-device; nothing leaves your Mac. Keep it enabled?"
        )
    }

    static func localizedKeepEnabled(using localizer: AppLocalizer) -> String {
        localizer.string("voice.consent.keepEnabled", fallback: "Keep Enabled")
    }

    static func localizedDisable(using localizer: AppLocalizer) -> String {
        localizer.string("voice.consent.disable", fallback: "Disable")
    }

    static func localizedOpenPreferences(using localizer: AppLocalizer) -> String {
        localizer.string("voice.consent.openPreferences", fallback: "Voice Settings")
    }

    static func localizedSaveFailed(using localizer: AppLocalizer) -> String {
        localizer.string(
            "voice.consent.saveFailed",
            fallback: "This choice could not be saved. Try again."
        )
    }
}
