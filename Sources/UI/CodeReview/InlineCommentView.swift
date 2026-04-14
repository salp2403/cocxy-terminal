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

    @State private var draftText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inline Comment")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(URL(fileURLWithPath: filePath).lastPathComponent) · line \(line)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .accessibilityHint("Close the inline comment composer")
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
                            .help("Remove comment")
                            .accessibilityLabel("Remove comment")
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: CocxyColors.surface0))
                        )
                    }
                }
            }

            TextField("Describe the change you want from the agent", text: $draftText, axis: .vertical)
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
                .accessibilityLabel("Comment draft")
                .accessibilityHint("Describe the change you want the agent to make")

            HStack {
                Text("Enter to add, Cmd+Enter to submit all")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))

                Spacer()

                Button("Add Comment", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Add this inline comment to the pending review feedback")
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
}
