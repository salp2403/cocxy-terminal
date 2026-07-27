// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginInstallSheet.swift - Manual plugin install controls.

import SwiftUI

struct PluginInstallSheet: View {
    @Binding var urlText: String
    @Binding var replaceExisting: Bool
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    var isInstalling = false
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(localized("plugins.urlOrPath", fallback: "URL or local path"), text: $urlText)
                .textFieldStyle(.roundedBorder)
                .disabled(isInstalling)
            Toggle(localized("plugins.replaceExisting", fallback: "Replace existing"), isOn: $replaceExisting)
                .disabled(isInstalling)
            Button {
                onInstall()
            } label: {
                if isInstalling {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(localized("plugins.installing", fallback: "Installing..."))
                    }
                } else {
                    Label(
                        localized("plugins.install", fallback: "Install"),
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
            .frame(minWidth: 112)
            .disabled(
                isInstalling
                    || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
