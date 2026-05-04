// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginUpdatePicker.swift - Installed plugin update results.

import SwiftUI

struct PluginUpdatePicker: View {
    let updates: [PluginUpdateCandidate]
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onRefresh()
            } label: {
                Label(localized("plugins.checkUpdates", fallback: "Check Updates"), systemImage: "arrow.triangle.2.circlepath")
            }

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
