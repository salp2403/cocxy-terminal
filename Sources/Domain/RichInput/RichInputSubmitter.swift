// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputSubmitter.swift - Converts rich input drafts to terminal text.

import Foundation

enum RichInputSubmitter {
    static func terminalPayload(
        text: String,
        attachments: [AgentImageAttachment]
    ) -> String {
        let normalizedText = CocxyCoreView.normalizedTerminalPasteText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentPayload = FileDropPathFormatter.format(attachments.map(\.fileURL))

        switch (attachmentPayload.isEmpty, normalizedText.isEmpty) {
        case (true, true):
            return ""
        case (true, false):
            return normalizedText
        case (false, true):
            return attachmentPayload
        case (false, false):
            return "\(attachmentPayload)\n\(normalizedText)"
        }
    }
}
