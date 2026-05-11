// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CreateBranchSheet.swift - Branch creation sheet for Source Control.

import SwiftUI

struct CreateBranchSheet: View {
    let startPoint: String?
    var onCancel: () -> Void
    var onCreate: (String, String?) -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    @State private var branchName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizer.string("github.branchSheet.title", fallback: "Create Branch"))
                .font(.system(size: 15, weight: .semibold))

            TextField(
                localizer.string("github.branchSheet.name", fallback: "Branch name"),
                text: $branchName
            )
            .textFieldStyle(.roundedBorder)

            if let startPoint, !startPoint.isEmpty {
                Text(
                    String(
                        format: localizer.string(
                            "github.branchSheet.startPoint",
                            fallback: "Start point: %@"
                        ),
                        startPoint
                    )
                )
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button(localizer.string("common.cancel", fallback: "Cancel"), action: onCancel)
                Button(localizer.string("github.branchSheet.create", fallback: "Create")) {
                    onCreate(branchName, startPoint)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}
