// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPromptComposerTextView.swift - AppKit prompt input with image paste/drop support.

import AppKit
import SwiftUI

struct AgentPromptTextEdit: Equatable {
    let text: String
    let selectedRange: NSRange
}

struct AgentPromptComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let onSubmit: () -> Void
    var onTab: ((String, NSRange) -> AgentPromptTextEdit?)? = nil
    let onImageData: (Data, String?) -> Void
    let onFileURLs: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AgentPromptNSTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.registerForDraggedTypes(AgentPromptNSTextView.supportedPasteboardTypes)
        textView.onSubmit = onSubmit
        textView.onTab = onTab
        textView.onTextChanged = { context.coordinator.parent.text = $0 }
        textView.onImageData = onImageData
        textView.onFileURLs = onFileURLs

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? AgentPromptNSTextView else { return }
        textView.onSubmit = onSubmit
        textView.onTab = onTab
        textView.onTextChanged = { context.coordinator.parent.text = $0 }
        textView.onImageData = onImageData
        textView.onFileURLs = onFileURLs
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .secondaryLabelColor

        if textView.string != text {
            context.coordinator.isApplyingExternalUpdate = true
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selectedRange.location, (text as NSString).length),
                length: 0
            ))
            context.coordinator.isApplyingExternalUpdate = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentPromptComposerTextView
        var isApplyingExternalUpdate = false

        init(parent: AgentPromptComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? NSTextView else {
                return
            }
            parent.text = textView.string
        }
    }
}

private final class AgentPromptNSTextView: NSTextView {
    static let supportedPasteboardTypes = AgentPromptAttachmentPasteboardReader.supportedPasteboardTypes

    private let pasteboardReader = AgentPromptAttachmentPasteboardReader()
    var onSubmit: (() -> Void)?
    var onTab: ((String, NSRange) -> AgentPromptTextEdit?)?
    var onTextChanged: ((String) -> Void)?
    var onImageData: ((Data, String?) -> Void)?
    var onFileURLs: (([URL]) -> Void)?

    override func paste(_ sender: Any?) {
        if handlePasteboard(NSPasteboard.general) {
            return
        }
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           event.charactersIgnoringModifiers == "\r" {
            onSubmit?()
            return
        }
        if event.keyCode == 48 || event.charactersIgnoringModifiers == "\t" {
            if let edit = onTab?(string, selectedRange()) {
                string = edit.text
                setSelectedRange(edit.selectedRange)
                onTextChanged?(string)
                return
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           handlePasteboard(NSPasteboard.general) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pasteboardContainsSupportedAttachment(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        handlePasteboard(sender.draggingPasteboard)
    }

    private func handlePasteboard(_ pasteboard: NSPasteboard) -> Bool {
        switch pasteboardReader.payload(from: pasteboard) {
        case .fileURLs(let fileURLs):
            onFileURLs?(fileURLs)
            return true
        case .imageData(let data, let filename):
            onImageData?(data, filename)
            return true
        case nil:
            return false
        }
    }

    private func pasteboardContainsSupportedAttachment(_ pasteboard: NSPasteboard) -> Bool {
        pasteboardReader.containsSupportedAttachment(pasteboard)
    }
}
