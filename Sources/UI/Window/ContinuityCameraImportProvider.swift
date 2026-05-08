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
    var terminalEventTargetProvider: (() -> TerminalHostView?)?

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

    override func keyDown(with event: NSEvent) {
        guard forwardTerminalEvent({ $0.keyDown(with: event) }) else {
            super.keyDown(with: event)
            return
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard forwardTerminalEvent({ $0.scrollWheel(with: event) }) else {
            super.scrollWheel(with: event)
            return
        }
    }

    private func forwardTerminalEvent(_ dispatch: (TerminalHostView) -> Void) -> Bool {
        guard let target = terminalEventTargetProvider?(),
              shouldForwardEvent(to: target) else { return false }
        dispatch(target)
        return true
    }

    private func shouldForwardEvent(to target: TerminalHostView) -> Bool {
        guard let firstResponderView = window?.firstResponder as? NSView else {
            return true
        }

        if firstResponderView === target || firstResponderView.isDescendant(of: target) {
            return false
        }

        return firstResponderView === self || target.isDescendant(of: firstResponderView)
    }
}
