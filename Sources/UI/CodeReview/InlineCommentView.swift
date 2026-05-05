// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// InlineCommentView.swift - Composer and existing comments for a selected diff line.

import SwiftUI

struct InlineCommentView: View {
    let filePath: String
    let line: Int
    let existingComments: [ReviewComment]
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    let onRemove: (UUID) -> Void
    var responseTemplates: [PRReviewResponseTemplate] = PRReviewResponseTemplateCatalog.defaultTemplates
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    @State private var draftText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("codeReview.inlineComment.title", fallback: "Inline Comment"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(
                        String(
                            format: localized(
                                "codeReview.inlineComment.location",
                                fallback: "%@ · line %d"
                            ),
                            URL(fileURLWithPath: filePath).lastPathComponent,
                            line
                        )
                    )
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }
                Spacer()
                Button(localized("codeReview.inlineComment.cancel", fallback: "Cancel"), action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .accessibilityHint(
                        localized(
                            "codeReview.inlineComment.cancelHint",
                            fallback: "Close the inline comment composer"
                        )
                    )
            }

            if !existingComments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(existingComments) { comment in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 11))
                                .foregroundColor(Color(nsColor: CocxyColors.yellow))

                            Text(comment.body)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)

                            Spacer(minLength: 8)

                            Button {
                                onRemove(comment.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                            .help(localized("codeReview.inlineComment.remove", fallback: "Remove comment"))
                            .accessibilityLabel(
                                localized("codeReview.inlineComment.remove", fallback: "Remove comment")
                            )
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: CocxyColors.surface0))
                        )
                    }
                }
            }

            TextField(
                localized(
                    "codeReview.inlineComment.placeholder",
                    fallback: "Describe the change you want from the agent"
                ),
                text: $draftText,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: CocxyColors.base))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: CocxyColors.surface1), lineWidth: 1)
                )
                .onSubmit(submit)
                .accessibilityLabel(
                    localized(
                        "codeReview.inlineComment.draftAccessibility",
                        fallback: "Comment draft"
                    )
                )
                .accessibilityHint(
                    localized(
                        "codeReview.inlineComment.draftHint",
                        fallback: "Describe the change you want the agent to make"
                    )
                )

            HStack {
                Text(
                    localized(
                        "codeReview.inlineComment.keyboardHint",
                        fallback: "Enter to add, Cmd+Enter to submit all"
                    )
                )
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))

                Spacer()

                Menu {
                    ForEach(responseTemplates) { template in
                        Button(template.title(using: localizer)) {
                            draftText = PRReviewResponseTemplateCatalog.inserting(
                                templateBody: template.body(using: localizer),
                                into: draftText
                            )
                        }
                    }
                } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(responseTemplates.isEmpty)
                .help(localized("codeReview.inlineComment.templates.help", fallback: "Insert response template"))
                .accessibilityLabel(
                    localized("codeReview.inlineComment.templates.accessibility", fallback: "Insert response template")
                )

                Button(localized("codeReview.inlineComment.add", fallback: "Add Comment"), action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint(
                        localized(
                            "codeReview.inlineComment.addHint",
                            fallback: "Add this inline comment to the pending review feedback"
                        )
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: CocxyColors.mantle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: CocxyColors.surface1), lineWidth: 1)
        )
    }

    private func submit() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        draftText = ""
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
