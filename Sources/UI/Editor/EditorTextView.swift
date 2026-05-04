// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorTextView.swift - NSTextView subclass for the native reusable text editor.

import AppKit

enum EditorTextKeyCommand: Equatable {
    case tab
    case escape
}

@MainActor
final class EditorTextView: NSTextView {
    static let defaultEditorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    var saveHandler: (() -> Void)?
    var keyDownHandler: ((VimInput) -> Bool)?
    var insertTextHandler: ((String) -> Bool)?
    var deleteBackwardHandler: (() -> Bool)?
    var additiveCursorHandler: ((Int) -> Bool)?
    var inlineCompletionKeyHandler: ((EditorTextKeyCommand) -> Bool)?
    var appearanceRepairHandler: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            saveHandler?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let command = inlineCompletionCommand(for: event),
           inlineCompletionKeyHandler?(command) == true {
            return
        }
        if let input = vimInput(for: event),
           keyDownHandler?(input) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let string = insertString as? String,
           keyDownHandler?(.text(string)) == true {
            return
        }
        if let attributed = insertString as? NSAttributedString,
           keyDownHandler?(.text(attributed.string)) == true {
            return
        }
        if let string = insertString as? String,
           insertTextHandler?(string) == true {
            return
        }
        if let attributed = insertString as? NSAttributedString,
           insertTextHandler?(attributed.string) == true {
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if keyDownHandler?(.deleteBackward) == true {
            return
        }
        if deleteBackwardHandler?() == true {
            return
        }
        super.deleteBackward(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if requestsAdditiveCursor(event),
           additiveCursorHandler?(additiveCursorOffset(for: event)) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let appearanceRepairHandler {
            appearanceRepairHandler()
        } else {
            applyReadableTextTheme()
        }
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        repairReadableTextThemeIfNeeded()
    }

    func applyDefaultConfiguration() {
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        allowsUndo = true
        drawsBackground = true
        backgroundColor = CocxyColors.base
        font = Self.defaultEditorFont
        usesFontPanel = false
        usesFindPanel = true
        applyReadableTextTheme()
    }

    func applyReadableTextTheme(reapplyStorageForeground: Bool = true) {
        let editorFont = Self.defaultEditorFont
        backgroundColor = CocxyColors.base
        drawsBackground = true
        font = editorFont
        textColor = CocxyColors.text
        insertionPointColor = CocxyColors.text
        typingAttributes[.font] = editorFont
        typingAttributes[.foregroundColor] = CocxyColors.text
        selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28),
            .foregroundColor: CocxyColors.text,
        ]

        guard reapplyStorageForeground else { return }
        guard let textStorage, textStorage.length > 0 else { return }
        textStorage.addAttributes(
            [
                .font: editorFont,
                .foregroundColor: CocxyColors.text,
            ],
            range: NSRange(location: 0, length: textStorage.length)
        )
    }

    func repairReadableTextThemeIfNeeded() {
        guard needsReadableTextThemeRepair() else { return }
        if let appearanceRepairHandler {
            appearanceRepairHandler()
        } else {
            applyReadableTextTheme()
        }
    }

    private func needsReadableTextThemeRepair() -> Bool {
        if !drawsBackground || !isUsableEditorBackground(backgroundColor) {
            return true
        }
        if !isReadableOnEditorBackground(textColor) {
            return true
        }
        if !isReadableOnEditorBackground(insertionPointColor) {
            return true
        }
        if let typingForeground = typingAttributes[.foregroundColor] as? NSColor,
           !isReadableOnEditorBackground(typingForeground) {
            return true
        }

        guard let textStorage, textStorage.length > 0 else { return false }
        for location in sampledAttributeLocations(textLength: textStorage.length) {
            let foreground = textStorage.attribute(
                .foregroundColor,
                at: location,
                effectiveRange: nil
            ) as? NSColor
            if let foreground, !isReadableOnEditorBackground(foreground) {
                return true
            }
        }
        return false
    }

    private func sampledAttributeLocations(textLength: Int) -> [Int] {
        let last = max(0, textLength - 1)
        return Array(Set([0, last / 2, last])).sorted()
    }

    private func isReadableOnEditorBackground(_ color: NSColor?) -> Bool {
        guard let color else { return true }
        guard let foreground = relativeLuminance(color),
              let background = relativeLuminance(CocxyColors.base)
        else {
            return true
        }

        let lighter = max(foreground, background)
        let darker = min(foreground, background)
        let contrastRatio = (lighter + 0.05) / (darker + 0.05)
        return contrastRatio >= 3.0
    }

    private func isUsableEditorBackground(_ color: NSColor?) -> Bool {
        guard let color else { return true }
        guard let background = relativeLuminance(color),
              let foreground = relativeLuminance(CocxyColors.text)
        else {
            return true
        }

        let lighter = max(foreground, background)
        let darker = min(foreground, background)
        let contrastRatio = (lighter + 0.05) / (darker + 0.05)
        return contrastRatio >= 3.0
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat? {
        guard let rgb = color.usingColorSpace(NSColorSpace.sRGB) else { return nil }

        func adjusted(_ component: CGFloat) -> CGFloat {
            if component <= 0.03928 {
                return component / 12.92
            }
            return pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * adjusted(rgb.redComponent)
            + 0.7152 * adjusted(rgb.greenComponent)
            + 0.0722 * adjusted(rgb.blueComponent)
    }

    private func requestsAdditiveCursor(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command) || flags.contains(.option)
    }

    private func inlineCompletionCommand(for event: NSEvent) -> EditorTextKeyCommand? {
        switch event.keyCode {
        case 48:
            return .tab
        case 53:
            return .escape
        default:
            return nil
        }
    }

    private func vimInput(for event: NSEvent) -> VimInput? {
        if event.keyCode == 53 {
            return .escape
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            return .enter
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            return .character("\u{16}")
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "r" {
            return .character("\u{12}")
        }

        guard let character = event.charactersIgnoringModifiers,
              !character.isEmpty else {
            return nil
        }
        return .character(character)
    }

    private func additiveCursorOffset(for event: NSEvent) -> Int {
        let pointInTextView = convert(event.locationInWindow, from: nil)
        let rawOffset = characterIndexForInsertion(at: pointInTextView)
        let maximumLength = (string as NSString).length
        return min(max(0, rawOffset), maximumLength)
    }
}
