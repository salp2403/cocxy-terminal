// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputPanel.swift - Floating panel host for terminal rich input.

import AppKit

@MainActor
final class RichInputPanel: NSPanel, NSWindowDelegate {
    let hostedView: FocusableHostingView<RichInputComposerView>
    var onClose: (() -> Void)?

    private weak var hostWindow: NSWindow?
    private var suppressCloseCallback = false

    override var canBecomeKey: Bool { true }

    init(
        hostedView: FocusableHostingView<RichInputComposerView>,
        frame: NSRect,
        localizer: AppLocalizer
    ) {
        self.hostedView = hostedView

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = localizer.string("richInput.title", fallback: "Rich Input")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = CocxyColors.base.withAlphaComponent(0.98)
        collectionBehavior = [.fullScreenAuxiliary]
        contentMinSize = NSSize(width: 320, height: 220)
        setAccessibilityTitle(title)

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        hostedView.frame = NSRect(origin: .zero, size: frame.size)
        hostedView.autoresizingMask = [.width, .height]
        contentView = hostedView
        delegate = self
    }

    func show(attachedTo parentWindow: NSWindow?) {
        hostWindow = parentWindow
        if let parentWindow {
            parentWindow.addChildWindow(self, ordered: .above)
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(hostedView)
        focusTextEditorIfPresent()
        DispatchQueue.main.async { [weak self] in
            self?.focusTextEditorIfPresent()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusTextEditorIfPresent()
        }
    }

    private func focusTextEditorIfPresent() {
        guard let textView = hostedView.firstDescendantTextView() else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    }

    func closeWithoutCallback() {
        suppressCloseCallback = true
        close()
        suppressCloseCallback = false
    }

    func windowWillClose(_ notification: Notification) {
        if let hostWindow {
            hostWindow.removeChildWindow(self)
        }
        hostWindow = nil

        guard !suppressCloseCallback else { return }
        onClose?()
    }
}

private extension NSView {
    func firstDescendantTextView() -> NSTextView? {
        if let textView = self as? NSTextView {
            return textView
        }
        for subview in subviews {
            if let textView = subview.firstDescendantTextView() {
                return textView
            }
        }
        return nil
    }
}
