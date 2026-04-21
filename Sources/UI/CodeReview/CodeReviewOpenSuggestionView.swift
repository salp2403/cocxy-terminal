// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewOpenSuggestionView.swift - Smart prompt for agent review discovery.

import AppKit
import SwiftUI

struct CodeReviewOpenSuggestionView: View {
    let fileCount: Int
    let agentCount: Int
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: CocxyColors.blue).opacity(0.16))
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.blue))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Agent changes are ready to review")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))

                Text(detailText)
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("Open Review") {
                onOpen()
            }
            .buttonStyle(.borderedProminent)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Not now")
        }
        .padding(12)
        .frame(width: 390)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: CocxyColors.mantle).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: CocxyColors.blue).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent changes are ready to review")
    }

    private var detailText: String {
        let files = fileCount > 0 ? "\(fileCount) changed file\(fileCount == 1 ? "" : "s")" : "new file activity"
        let agents = agentCount > 0 ? " from \(agentCount) active agent\(agentCount == 1 ? "" : "s")" : ""
        return "\(files)\(agents). Open Code Review when you are ready."
    }
}
