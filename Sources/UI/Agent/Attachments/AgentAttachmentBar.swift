// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentAttachmentBar.swift - Image attachment previews for Agent Mode.

import AppKit
import SwiftUI

struct AgentAttachmentBar: View {
    let attachments: [AgentImageAttachment]
    let onRemove: (String) -> Void

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        attachmentChip(attachment)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 52)
        }
    }

    private func attachmentChip(_ attachment: AgentImageAttachment) -> some View {
        HStack(spacing: 8) {
            preview(for: attachment)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(attachment.pixelWidth)x\(attachment.pixelHeight)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 150, alignment: .leading)

            Button {
                onRemove(attachment.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .frame(width: 22, height: 22)
            .help("Remove image")
            .accessibilityLabel("Remove image")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: CocxyColors.overlay0).opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func preview(for attachment: AgentImageAttachment) -> some View {
        if let image = NSImage(contentsOf: attachment.fileURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .padding(8)
                .foregroundStyle(.secondary)
        }
    }
}
