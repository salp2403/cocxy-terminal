// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownSourceView.swift - NSTextView subview showing the raw markdown source with syntax highlighting.

import AppKit

// MARK: - Source View

enum MarkdownSourceShortcutCommand: Equatable {
    case setMode(MarkdownViewMode)
    case toggleOutline
    case reload
}

private final class MarkdownEditorTextView: NSTextView {
    var shortcutHandler: ((NSEvent) -> Bool)?
    var imagePasteHandler: ((Data) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if shortcutHandler?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let pngData = pasteboard.data(forType: .png),
           imagePasteHandler?(pngData) == true {
            return
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let pngData = Self.pngData(fromTIFF: tiffData),
           imagePasteHandler?(pngData) == true {
            return
        }
        super.paste(sender)
    }

    private static func pngData(fromTIFF tiffData: Data) -> Data? {
        guard let image = NSImage(data: tiffData),
              let rep = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Editable text view that displays a markdown document's raw source with
/// per-line syntax highlighting applied.
///
/// The editor remains plain-text (`isRichText = false`), but it re-applies
/// syntax highlighting with a small debounce so preview/outline can update
/// live without fighting the user's insertion point or undo stack.
@MainActor
final class MarkdownSourceView: NSView, NSTextViewDelegate {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private let textView: MarkdownEditorTextView
    private let highlighter: MarkdownSyntaxHighlighter
    private var highlightWorkItem: DispatchWorkItem?
    private var isApplyingProgrammaticUpdate = false

    /// Current document. Setting this re-applies highlighting.
    var document: MarkdownDocument = .empty {
        didSet {
            if document.source != textView.string {
                render(replacingSource: document.source, preserveSelection: true)
            }
        }
    }

    /// Called whenever the raw markdown source changes due to user editing.
    var onSourceChanged: ((String) -> Void)?

    /// Called for global commands that the host panel should handle.
    var onShortcutCommand: ((MarkdownSourceShortcutCommand) -> Bool)?

    /// Called when the source scroll position changes. Value is 0.0...1.0.
    var onScrollChanged: ((CGFloat) -> Void)?

    /// Called when the user pastes image data into the source editor.
    var onImagePaste: ((Data) -> Void)?

    private var scrollObserver: NSObjectProtocol?

    internal var currentSource: String { textView.string }
    internal var selectedSourceRange: NSRange { textView.selectedRange() }
    internal var editorTextView: NSTextView { textView }

    // MARK: - Init

    init(highlighter: MarkdownSyntaxHighlighter = MarkdownSyntaxHighlighter()) {
        self.highlighter = highlighter
        self.textView = MarkdownEditorTextView()
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownSourceView does not support NSCoding")
    }

    // MARK: - Public

    /// Scrolls the view so `sourceLine` (0-based) is visible.
    func scrollToSourceLine(_ sourceLine: Int) {
        let lines = document.source.components(separatedBy: "\n")
        guard sourceLine >= 0, sourceLine < lines.count else { return }
        var charIndex = 0
        for (index, line) in lines.enumerated() {
            if index == sourceLine { break }
            charIndex += line.utf16.count + 1
        }
        let range = NSRange(location: charIndex, length: 0)
        textView.scrollRangeToVisible(range)
        textView.setSelectedRange(range)
    }

    func focusEditor() {
        window?.makeFirstResponder(textView)
    }

    func setSelectedSourceRange(_ range: NSRange) {
        textView.setSelectedRange(clampedRange(range, maxLength: (textView.string as NSString).length))
    }

    func replaceEntireSource(with source: String) {
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        applyReplacement(in: fullRange, with: source, selectedRange: NSRange(location: (source as NSString).length, length: 0))
    }

    func insertMarkdown(_ markdown: String) {
        let selection = clampedRange(textView.selectedRange(), maxLength: (textView.string as NSString).length)
        let insertionEnd = selection.location + (markdown as NSString).length
        applyReplacement(
            in: selection,
            with: markdown,
            selectedRange: NSRange(location: insertionEnd, length: 0)
        )
    }

    @discardableResult
    func toggleCheckboxAtIndex(_ index: Int, checked: Bool) -> Bool {
        guard index >= 0 else { return false }
        let source = textView.string as NSString
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^\s*(?:[-+*]|\d+[.)])\s+(\[(?: |x|X)\])"#,
            options: []
        ) else {
            return false
        }

        let matches = regex.matches(in: textView.string, range: NSRange(location: 0, length: source.length))
        guard index < matches.count else { return false }
        let checkboxRange = matches[index].range(at: 1)
        guard checkboxRange.location != NSNotFound else { return false }

        let replacement = checked ? "[x]" : "[ ]"
        let caret = NSRange(location: checkboxRange.location + (replacement as NSString).length, length: 0)
        applyReplacement(in: checkboxRange, with: replacement, selectedRange: caret)
        return true
    }

    func applyBold() {
        toggleDelimitedSelection(prefix: "**", suffix: "**")
    }

    func applyItalic() {
        toggleDelimitedSelection(prefix: "*", suffix: "*")
    }

    func applyLink() {
        let text = textView.string as NSString
        let selection = clampedRange(textView.selectedRange(), maxLength: text.length)

        if selection.length > 0 {
            let selectedText = text.substring(with: selection)
            let replacement = "[\(selectedText)](https://)"
            let urlRange = NSRange(
                location: selection.location + 3 + (selectedText as NSString).length,
                length: ("https://" as NSString).length
            )
            applyReplacement(in: selection, with: replacement, selectedRange: urlRange)
        } else {
            let placeholder = "link text"
            let replacement = "[\(placeholder)](https://)"
            let placeholderRange = NSRange(location: selection.location + 1, length: (placeholder as NSString).length)
            applyReplacement(in: selection, with: replacement, selectedRange: placeholderRange)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(textView)
        return true
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = highlighter.theme.codeFont
        textView.typingAttributes = [
            .font: highlighter.theme.codeFont,
            .foregroundColor: highlighter.theme.textColor
        ]
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: CocxyColors.blue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        textView.shortcutHandler = { [weak self] event in
            self?.handleShortcut(event) ?? false
        }
        textView.imagePasteHandler = { [weak self] data in
            guard let self, let onImagePaste = self.onImagePaste else { return false }
            onImagePaste(data)
            return true
        }

        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emitScrollPosition()
            }
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    private func emitScrollPosition() {
        guard let onScrollChanged else { return }
        let contentHeight = scrollView.documentView?.frame.height ?? 0
        let visibleHeight = scrollView.contentSize.height
        let maxScroll = contentHeight - visibleHeight
        guard maxScroll > 0 else {
            onScrollChanged(0)
            return
        }
        let fraction = min(1.0, max(0.0, scrollView.contentView.bounds.origin.y / maxScroll))
        onScrollChanged(fraction)
    }

    // MARK: - Rendering

    private func render(replacingSource source: String, preserveSelection: Bool) {
        applyHighlightedSource(source, preserveSelection: preserveSelection)
    }

    private func scheduleHighlightRefresh() {
        highlightWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyHighlightedSource(self?.textView.string ?? "", preserveSelection: true)
        }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func applyHighlightedSource(_ source: String, preserveSelection: Bool) {
        guard let textStorage = textView.textStorage else { return }

        let selectedRanges = preserveSelection ? textView.selectedRanges : []
        let undoManager = textView.undoManager
        let attributed = highlighter.highlight(source)

        isApplyingProgrammaticUpdate = true
        undoManager?.disableUndoRegistration()
        textStorage.setAttributedString(attributed)
        textView.typingAttributes = [
            .font: highlighter.theme.codeFont,
            .foregroundColor: highlighter.theme.textColor
        ]
        undoManager?.enableUndoRegistration()
        isApplyingProgrammaticUpdate = false

        if preserveSelection, !selectedRanges.isEmpty {
            let maxLength = (source as NSString).length
            textView.selectedRanges = selectedRanges.map { value in
                let range = clampedRange(value.rangeValue, maxLength: maxLength)
                return NSValue(range: range)
            }
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()

        if flags.contains(.command) && !flags.contains(.shift) {
            switch characters {
            case "1":
                return onShortcutCommand?(.setMode(.source)) ?? false
            case "2":
                return onShortcutCommand?(.setMode(.preview)) ?? false
            case "3":
                return onShortcutCommand?(.setMode(.split)) ?? false
            case "r":
                return onShortcutCommand?(.reload) ?? false
            case "b":
                applyBold()
                return true
            case "i":
                applyItalic()
                return true
            case "k":
                applyLink()
                return true
            default:
                break
            }
        }

        if flags.contains(.command) && flags.contains(.shift), characters == "o" {
            return onShortcutCommand?(.toggleOutline) ?? false
        }

        return false
    }

    private func toggleDelimitedSelection(prefix: String, suffix: String) {
        let text = textView.string as NSString
        let selection = clampedRange(textView.selectedRange(), maxLength: text.length)
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length

        if selection.length > 0,
           selection.location >= prefixLength,
           NSMaxRange(selection) + suffixLength <= text.length,
           text.substring(with: NSRange(location: selection.location - prefixLength, length: prefixLength)) == prefix,
           text.substring(with: NSRange(location: NSMaxRange(selection), length: suffixLength)) == suffix {
            let wrappedRange = NSRange(
                location: selection.location - prefixLength,
                length: selection.length + prefixLength + suffixLength
            )
            let selectedText = text.substring(with: selection)
            let newSelection = NSRange(location: wrappedRange.location, length: (selectedText as NSString).length)
            applyReplacement(in: wrappedRange, with: selectedText, selectedRange: newSelection)
            return
        }

        if selection.length == 0 {
            let insertion = prefix + suffix
            let cursor = selection.location + prefixLength
            applyReplacement(in: selection, with: insertion, selectedRange: NSRange(location: cursor, length: 0))
            return
        }

        let selectedText = text.substring(with: selection)
        let replacement = prefix + selectedText + suffix
        let newSelection = NSRange(location: selection.location + prefixLength, length: selection.length)
        applyReplacement(in: selection, with: replacement, selectedRange: newSelection)
    }

    private func applyReplacement(in range: NSRange, with replacement: String, selectedRange: NSRange) {
        guard let textStorage = textView.textStorage else { return }
        let safeRange = clampedRange(range, maxLength: textStorage.length)
        guard textView.shouldChangeText(in: safeRange, replacementString: replacement) else { return }
        textStorage.replaceCharacters(in: safeRange, with: replacement)
        textView.didChangeText()
        let maxLength = textStorage.length
        textView.setSelectedRange(clampedRange(selectedRange, maxLength: maxLength))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
        let clampedLocation = max(0, min(range.location, maxLength))
        let maxAllowedLength = max(0, maxLength - clampedLocation)
        let clampedLength = max(0, min(range.length, maxAllowedLength))
        return NSRange(location: clampedLocation, length: clampedLength)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticUpdate else { return }
        scheduleHighlightRefresh()
        onSourceChanged?(textView.string)
    }
}
