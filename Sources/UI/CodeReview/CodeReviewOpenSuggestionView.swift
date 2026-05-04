// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewOpenSuggestionView.swift - Smart prompt for agent review discovery.

import AppKit
import SwiftUI

struct CodeReviewOpenSuggestionView: View {
    let fileCount: Int
    let agentCount: Int
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
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
                Text(
                    localized(
                        "codeReview.openSuggestion.title",
                        fallback: "Agent changes are ready to review"
                    )
                )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))

                Text(detailText)
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(localized("codeReview.openSuggestion.open", fallback: "Open Review")) {
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
            .help(localized("codeReview.openSuggestion.dismiss", fallback: "Not now"))
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
        .accessibilityLabel(
            localized(
                "codeReview.openSuggestion.title",
                fallback: "Agent changes are ready to review"
            )
        )
    }

    private var detailText: String {
        let files: String
        if fileCount > 0 {
            files = String(
                format: localized(
                    fileCount == 1
                        ? "codeReview.openSuggestion.files.one"
                        : "codeReview.openSuggestion.files.many",
                    fallback: fileCount == 1 ? "%d changed file" : "%d changed files"
                ),
                fileCount
            )
        } else {
            files = localized(
                "codeReview.openSuggestion.files.none",
                fallback: "new file activity"
            )
        }

        let agents: String
        if agentCount > 0 {
            agents = String(
                format: localized(
                    agentCount == 1
                        ? "codeReview.openSuggestion.agents.one"
                        : "codeReview.openSuggestion.agents.many",
                    fallback: agentCount == 1 ? " from %d active agent" : " from %d active agents"
                ),
                agentCount
            )
        } else {
            agents = ""
        }

        return String(
            format: localized(
                "codeReview.openSuggestion.detail",
                fallback: "%@%@. Open Code Review when you are ready."
            ),
            files,
            agents
        )
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
