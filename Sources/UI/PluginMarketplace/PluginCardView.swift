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
