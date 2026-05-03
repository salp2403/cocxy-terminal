// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorTextView.swift - NSTextView subclass for the native reusable text editor.

import AppKit

enum EditorTextKeyCommand: Equatable {
    case tab
    case escape
}

@MainActor
final class EditorTextView: NSTextView {
    var saveHandler: (() -> Void)?
    var keyDownHandler: ((VimInput) -> Bool)?
    var insertTextHandler: ((String) -> Bool)?
    var deleteBackwardHandler: (() -> Bool)?
    var additiveCursorHandler: ((Int) -> Bool)?
    var inlineCompletionKeyHandler: ((EditorTextKeyCommand) -> Bool)?

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

    func applyDefaultConfiguration() {
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        allowsUndo = true
        drawsBackground = false
        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textColor = CocxyColors.text
        insertionPointColor = CocxyColors.text
        selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28),
            .foregroundColor: CocxyColors.text,
        ]
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
