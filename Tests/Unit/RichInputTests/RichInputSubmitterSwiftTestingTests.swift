// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputSubmitterSwiftTestingTests.swift - Terminal rich input payload tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Rich input submitter")
struct RichInputSubmitterSwiftTestingTests {
    @Test("payload preserves prompt text when there are no attachments")
    func payloadPreservesPromptTextWithoutAttachments() {
        let payload = RichInputSubmitter.terminalPayload(
            text: "explain this",
            attachments: []
        )

        #expect(payload == "explain this")
    }

    @Test("payload sends escaped attachment paths before prompt text")
    func payloadSendsEscapedAttachmentPathsBeforePromptText() {
        let attachment = AgentImageAttachment(
            displayName: "Clipboard Image.png",
            mimeType: "image/png",
            filePath: "/tmp/Cocxy Clipboard Image.png",
            byteCount: 12,
            pixelWidth: 1,
            pixelHeight: 1
        )

        let payload = RichInputSubmitter.terminalPayload(
            text: "describe it",
            attachments: [attachment]
        )

        #expect(payload == "/tmp/Cocxy\\ Clipboard\\ Image.png\ndescribe it")
    }

    @Test("empty draft with attachments still submits file paths")
    func emptyDraftWithAttachmentsSubmitsFilePaths() {
        let first = AgentImageAttachment(
            displayName: "a.png",
            mimeType: "image/png",
            filePath: "/tmp/a.png",
            byteCount: 1,
            pixelWidth: 1,
            pixelHeight: 1
        )
        let second = AgentImageAttachment(
            displayName: "b.png",
            mimeType: "image/png",
            filePath: "/tmp/b.png",
            byteCount: 1,
            pixelWidth: 1,
            pixelHeight: 1
        )

        let payload = RichInputSubmitter.terminalPayload(text: "", attachments: [first, second])

        #expect(payload == "/tmp/a.png /tmp/b.png")
    }

    @MainActor
    @Test("composer view model stores and removes pasted image data")
    func composerViewModelStoresAndRemovesPastedImageData() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-rich-input-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let storage = AgentAttachmentStorage(rootDirectory: rootDirectory)
        let viewModel = RichInputComposerViewModel(attachmentStorage: storage)

        viewModel.attachImageData(Self.pngData, suggestedFilename: "from-notes.png")

        let attachment = try #require(viewModel.attachments.first)
        #expect(viewModel.canSubmit)
        #expect(attachment.displayName == "from-notes.png")
        #expect(FileManager.default.fileExists(atPath: attachment.filePath))

        viewModel.removeAttachment(id: attachment.id)

        #expect(viewModel.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: attachment.filePath))
    }

    @MainActor
    @Test("composer view model creates drafts preserving identity and attachments")
    func composerViewModelCreatesDraftsPreservingIdentityAndAttachments() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = RichInputDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            tabID: "tab-a",
            text: "old",
            attachments: [],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let attachment = AgentImageAttachment(
            displayName: "a.png",
            mimeType: "image/png",
            filePath: "/tmp/a.png",
            byteCount: 1,
            pixelWidth: 1,
            pixelHeight: 1
        )
        let viewModel = RichInputComposerViewModel(text: "new", attachments: [attachment])
        let now = Date(timeIntervalSince1970: 1_700_000_010)

        let draft = viewModel.draft(tabID: "tab-a", previous: previous, now: now)

        #expect(draft.id == previous.id)
        #expect(draft.createdAt == createdAt)
        #expect(draft.updatedAt == now)
        #expect(draft.text == "new")
        #expect(draft.attachments == [attachment])
        #expect(!draft.isEmpty)
    }

    @Test("draft store persists loads and deletes per tab")
    func draftStorePersistsLoadsAndDeletesPerTab() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-rich-drafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let store = RichInputDraftStore(rootDirectory: rootDirectory)
        let draft = RichInputDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000222")!,
            tabID: "tab/a",
            text: "line 1\nline 2",
            attachments: [
                AgentImageAttachment(
                    displayName: "clip.png",
                    mimeType: "image/png",
                    filePath: "/tmp/clip.png",
                    byteCount: 20,
                    pixelWidth: 2,
                    pixelHeight: 2,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_019)
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_020),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_021)
        )

        try store.save(draft)

        #expect(try store.load(tabID: "tab/a") == draft)
        #expect(FileManager.default.fileExists(atPath: store.fileURL(forTabID: "tab/a").path))

        store.delete(tabID: "tab/a")

        #expect(try store.load(tabID: "tab/a") == nil)
    }

    @Test("draft store sanitizes empty and path-like tab IDs")
    func draftStoreSanitizesTabIDs() {
        #expect(RichInputDraftStore.sanitizedTabID("") == "default")
        #expect(RichInputDraftStore.sanitizedTabID("../tab id") == "tab-id")
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
}
