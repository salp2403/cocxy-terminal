// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputComposerViewModel.swift - Local terminal rich input composer state.

import AppKit
import Foundation

@MainActor
final class RichInputComposerViewModel: ObservableObject {
    @Published var text: String
    @Published private(set) var attachments: [AgentImageAttachment]
    @Published private(set) var errorMessage: String?

    private let imageProcessor: AgentImageProcessor
    private let attachmentStore: RichInputAttachmentStore
    private let snippetExpander: RichInputSnippetExpander

    init(
        text: String = "",
        attachments: [AgentImageAttachment] = [],
        imageProcessor: AgentImageProcessor = AgentImageProcessor(),
        attachmentStore: RichInputAttachmentStore = RichInputAttachmentStore(),
        snippetExpander: RichInputSnippetExpander = RichInputSnippetExpander()
    ) {
        self.text = text
        self.attachments = attachments
        self.imageProcessor = imageProcessor
        self.attachmentStore = attachmentStore
        self.snippetExpander = snippetExpander
    }

    convenience init(
        draft: RichInputDraft,
        imageProcessor: AgentImageProcessor = AgentImageProcessor(),
        attachmentStore: RichInputAttachmentStore = RichInputAttachmentStore(),
        snippetExpander: RichInputSnippetExpander = RichInputSnippetExpander()
    ) {
        self.init(
            text: draft.text,
            attachments: draft.attachments,
            imageProcessor: imageProcessor,
            attachmentStore: attachmentStore,
            snippetExpander: snippetExpander
        )
    }

    var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    func attachImageData(_ data: Data, suggestedFilename: String?) {
        do {
            let processed = try imageProcessor.process(data: data)
            let attachment = try attachmentStore.store(processed, originalFilename: suggestedFilename)
            attachments.append(attachment)
            errorMessage = nil
        } catch {
            errorMessage = Self.localizedImageAttachmentFailed
        }
    }

    func attachFiles(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            do {
                let processed = try imageProcessor.process(fileURL: url)
                let attachment = try attachmentStore.store(
                    processed,
                    originalFilename: url.lastPathComponent
                )
                attachments.append(attachment)
                errorMessage = nil
            } catch {
                errorMessage = Self.localizedImageAttachmentFailed
            }
        }
    }

    func removeAttachment(id: String) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = attachments.remove(at: index)
        attachmentStore.remove(attachment)
    }

    func terminalPayload() -> String {
        RichInputSubmitter.terminalPayload(text: text, attachments: attachments)
    }

    func terminalPayload(
        imageTransportMode: RichInputImageTransportMode
    ) -> RichInputTerminalPayload {
        RichInputSubmitter.terminalPayloadData(
            text: text,
            attachments: attachments,
            imageTransportMode: imageTransportMode
        )
    }

    func expandSnippet(in text: String, selectedRange: NSRange) -> RichInputTextEdit? {
        snippetExpander.expandSnippet(in: text, selectedRange: selectedRange)
    }

    func draft(tabID: String, previous: RichInputDraft? = nil, now: Date = Date()) -> RichInputDraft {
        RichInputDraft(
            id: previous?.id ?? UUID(),
            tabID: tabID,
            text: text,
            attachments: attachments,
            createdAt: previous?.createdAt ?? now,
            updatedAt: now
        )
    }

    private static var localizedImageAttachmentFailed: String {
        "Unable to attach image."
    }
}
