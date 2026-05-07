// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ContinuityCameraImportProvider.swift - AppKit import-from-device bridge.

import AppKit

enum ContinuityCameraImportProvider {
    static let supportedReturnTypes: [NSPasteboard.PasteboardType] =
        AgentPromptAttachmentPasteboardReader.supportedPasteboardTypes

    static func supports(returnType: NSPasteboard.PasteboardType?) -> Bool {
        guard let returnType else { return false }
        return supportedReturnTypes.contains(returnType)
    }

    static func suggestedFilename(for pasteboardFilename: String) -> String {
        let ext = URL(fileURLWithPath: pasteboardFilename).pathExtension
        return ext.isEmpty ? "continuity-camera.png" : "continuity-camera.\(ext)"
    }
}

@MainActor
final class ContinuityCameraImportResponderView: NSView {
    var onImportPasteboard: ((NSPasteboard) -> Bool)?

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        if ContinuityCameraImportProvider.supports(returnType: returnType) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc(readSelectionFromPasteboard:)
    func readSelectionFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        onImportPasteboard?(pasteboard) ?? false
    }
}
