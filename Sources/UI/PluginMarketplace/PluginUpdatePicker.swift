// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginUpdatePicker.swift - Installed plugin update results.

import SwiftUI

struct PluginUpdatePicker: View {
    let updates: [PluginUpdateCandidate]
    let isRefreshing: Bool
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onRefresh()
            } label: {
                HStack(spacing: 8) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(localized("plugins.checkUpdates", fallback: "Check Updates"))
                }
            }
            .disabled(isRefreshing)

            ForEach(updates) { update in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(update.pluginID)
                            .font(.headline)
                        Text("\(update.currentVersion) -> \(update.latestVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
