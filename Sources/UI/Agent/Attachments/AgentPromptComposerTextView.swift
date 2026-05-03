// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPromptComposerTextView.swift - AppKit prompt input with image paste/drop support.

import AppKit
import SwiftUI

struct AgentPromptComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let onSubmit: () -> Void
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
    static let jpegPasteboardType = NSPasteboard.PasteboardType("public.jpeg")
    static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .png,
        .tiff,
        jpegPasteboardType,
    ]

    var onSubmit: (() -> Void)?
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
        let fileURLs = fileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            onFileURLs?(fileURLs)
            return true
        }

        for imageType in Self.imagePasteboardTypes {
            if let data = pasteboard.data(forType: imageType.type) {
                onImageData?(data, imageType.filename)
                return true
            }
        }

        return false
    }

    private func pasteboardContainsSupportedAttachment(_ pasteboard: NSPasteboard) -> Bool {
        if !fileURLs(from: pasteboard).isEmpty {
            return true
        }
        return Self.imagePasteboardTypes.contains { pasteboard.availableType(from: [$0.type]) != nil }
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []
        return objects.compactMap { object -> URL? in
            if let url = object as? URL {
                return url.isFileURL ? url : nil
            }
            if let nsURL = object as? NSURL {
                let url = nsURL as URL
                return url.isFileURL ? url : nil
            }
            return nil
        }
    }

    private static let imagePasteboardTypes: [(type: NSPasteboard.PasteboardType, filename: String)] = [
        (.png, "pasted-image.png"),
        (jpegPasteboardType, "pasted-image.jpg"),
        (.tiff, "pasted-image.tiff"),
    ]
}
