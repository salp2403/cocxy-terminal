// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputSubmitter.swift - Converts rich input drafts to terminal text.

import Foundation

enum RichInputImageTransportMode: Sendable, Equatable {
    case filePaths
    case osc1337InlineFile
}

struct RichInputTerminalPayload: Sendable, Equatable {
    let text: String
    let requiresRawControlSequences: Bool

    var isEmpty: Bool {
        text.isEmpty
    }
}

enum RichInputSubmitter {
    static func terminalPayload(
        text: String,
        attachments: [AgentImageAttachment]
    ) -> String {
        terminalPayloadData(text: text, attachments: attachments).text
    }

    static func terminalPayloadData(
        text: String,
        attachments: [AgentImageAttachment],
        imageTransportMode: RichInputImageTransportMode = .filePaths
    ) -> RichInputTerminalPayload {
        let normalizedText = CocxyCoreView.normalizedTerminalPasteText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentPayload = attachmentPayload(
            for: attachments,
            imageTransportMode: imageTransportMode
        )

        switch (attachmentPayload.text.isEmpty, normalizedText.isEmpty) {
        case (true, true):
            return RichInputTerminalPayload(text: "", requiresRawControlSequences: false)
        case (true, false):
            return RichInputTerminalPayload(
                text: normalizedText,
                requiresRawControlSequences: false
            )
        case (false, true):
            return attachmentPayload
        case (false, false):
            return RichInputTerminalPayload(
                text: "\(attachmentPayload.text)\n\(normalizedText)",
                requiresRawControlSequences: attachmentPayload.requiresRawControlSequences
            )
        }
    }

    private static func attachmentPayload(
        for attachments: [AgentImageAttachment],
        imageTransportMode: RichInputImageTransportMode
    ) -> RichInputTerminalPayload {
        guard !attachments.isEmpty else {
            return RichInputTerminalPayload(text: "", requiresRawControlSequences: false)
        }

        switch imageTransportMode {
        case .filePaths:
            return RichInputTerminalPayload(
                text: FileDropPathFormatter.format(attachments.map(\.fileURL)),
                requiresRawControlSequences: false
            )
        case .osc1337InlineFile:
            var containsRawControlSequences = false
            let parts = attachments.compactMap { attachment -> String? in
                if let sequence = osc1337InlineFileSequence(for: attachment) {
                    containsRawControlSequences = true
                    return sequence
                }
                let fallback = FileDropPathFormatter.format([attachment.fileURL])
                return fallback.isEmpty ? nil : fallback
            }
            return RichInputTerminalPayload(
                text: parts.joined(separator: "\n"),
                requiresRawControlSequences: containsRawControlSequences
            )
        }
    }

    private static func osc1337InlineFileSequence(for attachment: AgentImageAttachment) -> String? {
        guard let imageData = try? Data(contentsOf: attachment.fileURL),
              !imageData.isEmpty,
              let encodedName = attachment.displayName.data(using: .utf8)?.base64EncodedString()
        else {
            return nil
        }

        let encodedImage = imageData.base64EncodedString()
        return "\u{001B}]1337;File=name=\(encodedName);size=\(imageData.count);inline=1:\(encodedImage)\u{0007}"
    }
}
