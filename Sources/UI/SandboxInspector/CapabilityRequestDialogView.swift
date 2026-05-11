// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CapabilityRequestDialogView.swift - User approval surface for plugin sandbox grants.

import SwiftUI

struct CapabilityRequestDialogView: View {
    let request: PluginCapabilityApprovalRequest
    let localizer: AppLocalizer
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                localizer.string("plugins.capabilityRequest.title", fallback: "Approve Plugin Capabilities"),
                systemImage: "shield.lefthalf.filled"
            )
            .font(.title3.weight(.semibold))

            Text(
                String(
                    format: localizer.string(
                        "plugins.capabilityRequest.message",
                        fallback: "%@ requests additional local permissions before it can be enabled."
                    ),
                    request.pluginName
                )
            )
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(request.capabilities, id: \.rawValue) { capability in
                    Label(
                        localizedCapability(capability),
                        systemImage: capability.systemImage
                    )
                    .font(.callout)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button(role: .cancel, action: onCancel) {
                    Text(localizer.string("common.cancel", fallback: "Cancel"))
                }
                Spacer()
                Button(action: onApprove) {
                    Label(
                        localizer.string("plugins.capabilityRequest.approve", fallback: "Approve and Enable"),
                        systemImage: "checkmark.shield"
                    )
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func localizedCapability(_ capability: PluginCapability) -> String {
        localizer.string(
            "sandboxInspector.capability.\(capability.rawValue)",
            fallback: capability.rawValue
        )
    }
}

private extension PluginCapability {
    var systemImage: String {
        switch self {
        case .filesystemRead:
            return "folder"
        case .filesystemWrite:
            return "square.and.pencil"
        case .environmentRead:
            return "list.bullet.rectangle"
        case .processSpawn:
            return "terminal"
        case .networkClient:
            return "network"
        }
    }
}
