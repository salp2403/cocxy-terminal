// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TextCompositionState.swift - IME text composition state for NSTextInputClient.

import Foundation

// MARK: - Text Composition State

/// Tracks the state of IME (Input Method Editor) text composition.
///
/// During IME composition (e.g., typing Chinese/Japanese/Korean characters),
/// the input goes through stages:
/// 1. User starts typing romanized input (e.g., "ni" for Chinese).
/// 2. The terminal shows "marked text" — an underlined preview.
/// 3. User selects from candidates or continues typing.
/// 4. User confirms the final character(s), which are "committed".
///
/// This struct maintains the composition state needed by `NSTextInputClient`.
/// It is a value type to avoid shared mutable state issues.
struct TextCompositionState: Sendable {

    // MARK: - State

    /// The current marked (composing) text, or empty if no composition is active.
    private(set) var markedText: String = ""

    /// The selected range within the marked text.
    private(set) var selectedRange: NSRange = NSRange(location: 0, length: 0)

    // MARK: - Computed Properties

    /// Whether there is currently marked text (IME composition in progress).
    var hasMarkedText: Bool {
        !markedText.isEmpty
    }

    /// The range of the marked text within the input.
    ///
    /// Returns `NSRange(location: NSNotFound, length: 0)` when there is no
    /// marked text, per the `NSTextInputClient` contract.
    var markedRange: NSRange {
        if markedText.isEmpty {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.count)
    }

    // MARK: - Mutations

    /// Sets the marked text and selected range during IME composition.
    ///
    /// If the text is empty, this is equivalent to calling `unmarkText()`.
    ///
    /// - Parameters:
    ///   - text: The composing text to display.
    ///   - selectedRange: The selected range within the composing text.
    mutating func setMarkedText(_ text: String, selectedRange: NSRange) {
        if text.isEmpty {
            unmarkText()
            return
        }
        self.markedText = text
        self.selectedRange = selectedRange
    }

    /// Clears the marked text, ending the composition without committing.
    mutating func unmarkText() {
        markedText = ""
        selectedRange = NSRange(location: 0, length: 0)
    }

    /// Commits the current composition, clearing all state.
    ///
    /// The actual text insertion is handled separately by `insertText(_:replacementRange:)`.
    mutating func commit() {
        unmarkText()
    }
}
