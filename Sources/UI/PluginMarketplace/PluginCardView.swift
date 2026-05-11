// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginCardView.swift - Compact plugin summary row.

import SwiftUI

struct PluginCardAction {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let perform: () -> Void
}

struct PluginCardView: View {
    let title: String
    let subtitle: String
    var detail: String?
    var capabilities: Set<PluginCapability> = []
    var signatureStatus: PluginSignatureStatus?
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    var primaryAction: PluginCardAction?
    var secondaryAction: PluginCardAction?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let signatureStatus {
                    PluginSignatureBadge(status: signatureStatus, localizer: localizer)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !capabilities.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(capabilities.map(\.rawValue).sorted(), id: \.self) { capability in
                            Text(capability)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            if let secondaryAction {
                Button(role: secondaryAction.role) {
                    secondaryAction.perform()
                } label: {
                    Label(secondaryAction.title, systemImage: secondaryAction.systemImage)
                }
            }

            if let primaryAction {
                Button(role: primaryAction.role) {
                    primaryAction.perform()
                } label: {
                    Label(primaryAction.title, systemImage: primaryAction.systemImage)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PluginSignatureBadge: View {
    let status: PluginSignatureStatus
    let localizer: AppLocalizer

    var body: some View {
        Label(status.localizedBadgeTitle(using: localizer), systemImage: status.badgeSystemImage)
            .font(.caption2)
            .foregroundStyle(status.badgeForegroundStyle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(status.localizedAccessibilityLabel(using: localizer))
    }
}

extension PluginSignatureStatus {
    static func inferred(from manifest: PluginManifest) -> PluginSignatureStatus {
        guard let signature = manifest.signature, !signature.value.isEmpty else {
            return .unsignedAllowed
        }
        return signature.signedArtifact() == nil ? .invalid : .presentButUnverified
    }

    func localizedBadgeTitle(using localizer: AppLocalizer) -> String {
        switch self {
        case .verified:
            return localizer.string("plugins.signature.verified", fallback: "Verified")
        case .unsignedAllowed:
            return localizer.string("plugins.signature.unsigned", fallback: "Unsigned")
        case .presentButUnverified:
            return localizer.string("plugins.signature.unverified", fallback: "Unverified")
        case .invalid:
            return localizer.string("plugins.signature.invalid", fallback: "Invalid signature")
        }
    }

    func localizedAccessibilityLabel(using localizer: AppLocalizer) -> String {
        switch self {
        case .verified:
            return localizer.string(
                "plugins.signature.accessibility.verified",
                fallback: "Plugin signature verified"
            )
        case .unsignedAllowed:
            return localizer.string(
                "plugins.signature.accessibility.unsigned",
                fallback: "Plugin is unsigned"
            )
        case .presentButUnverified:
            return localizer.string(
                "plugins.signature.accessibility.unverified",
                fallback: "Plugin signature is present but unverified"
            )
        case .invalid:
            return localizer.string(
                "plugins.signature.accessibility.invalid",
                fallback: "Plugin has an invalid signature"
            )
        }
    }

    var badgeSystemImage: String {
        switch self {
        case .verified:
            return "checkmark.seal"
        case .unsignedAllowed:
            return "exclamationmark.triangle"
        case .presentButUnverified:
            return "questionmark.diamond"
        case .invalid:
            return "xmark.seal"
        }
    }

    var badgeForegroundStyle: Color {
        switch self {
        case .verified:
            return .green
        case .unsignedAllowed:
            return .secondary
        case .presentButUnverified:
            return .orange
        case .invalid:
            return .red
        }
    }
}
