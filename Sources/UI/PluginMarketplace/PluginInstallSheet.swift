// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginInstallSheet.swift - Manual plugin install controls.

import SwiftUI

struct PluginInstallSheet: View {
    @Binding var urlText: String
    @Binding var replaceExisting: Bool
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("URL or local path", text: $urlText)
                .textFieldStyle(.roundedBorder)
            Toggle("Replace existing", isOn: $replaceExisting)
            Button {
                onInstall()
            } label: {
                Label("Install", systemImage: "square.and.arrow.down")
            }
        }
    }
}
