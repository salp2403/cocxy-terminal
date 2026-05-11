// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputComposerView.swift - Terminal rich input composer overlay.

import SwiftUI

struct RichInputComposerView: View {
    @ObservedObject var viewModel: RichInputComposerViewModel
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    var panelWidth: CGFloat = 620

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.45)
            content
        }
        .frame(width: panelWidth)
        .glassPanelBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("richInput.accessibility", fallback: "Rich input composer"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(localized("richInput.title", fallback: "Rich Input"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { onCancel?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(localized("richInput.cancel", fallback: "Cancel"))
            .accessibilityLabel(localized("richInput.cancel", fallback: "Cancel"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentAttachmentBar(
                attachments: viewModel.attachments,
                onRemove: viewModel.removeAttachment(id:),
                localizer: localizer
            )

            ZStack(alignment: .topLeading) {
                AgentPromptComposerTextView(
                    text: $viewModel.text,
                    isEnabled: true,
                    onSubmit: { onSubmit?() },
                    onImageData: viewModel.attachImageData(_:suggestedFilename:),
                    onFileURLs: viewModel.attachFiles(_:)
                )
                .frame(minHeight: 104, maxHeight: 148)

                if viewModel.text.isEmpty {
                    Text(localized(
                        "richInput.placeholder",
                        fallback: "Write or paste a long prompt..."
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: CocxyColors.surface0).opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: CocxyColors.overlay0).opacity(0.45), lineWidth: 1)
            )

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: CocxyColors.yellow))
            }

            HStack(spacing: 8) {
                Spacer()
                Button(action: { onCancel?() }) {
                    Label(localized("richInput.cancel", fallback: "Cancel"), systemImage: "xmark")
                }
                .controlSize(.small)

                Button(action: { onSubmit?() }) {
                    Label(localized("richInput.send", fallback: "Send"), systemImage: "paperplane.fill")
                }
                .disabled(!viewModel.canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
