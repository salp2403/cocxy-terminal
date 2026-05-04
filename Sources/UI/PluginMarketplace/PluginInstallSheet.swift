// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginInstallSheet.swift - Manual plugin install controls.

import SwiftUI

struct PluginInstallSheet: View {
    @Binding var urlText: String
    @Binding var replaceExisting: Bool
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(localized("plugins.urlOrPath", fallback: "URL or local path"), text: $urlText)
                .textFieldStyle(.roundedBorder)
            Toggle(localized("plugins.replaceExisting", fallback: "Replace existing"), isOn: $replaceExisting)
            Button {
                onInstall()
            } label: {
                Label(localized("plugins.install", fallback: "Install"), systemImage: "square.and.arrow.down")
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
