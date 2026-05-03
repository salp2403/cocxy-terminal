// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionTrigger.swift - Opt-in trigger policy for inline completions.

import Foundation

struct CompletionTriggerInput: Sendable, Equatable {
    let document: EditorDocument
    let selection: EditorSelection
    let languageID: String?
    let idleDuration: TimeInterval
    let insertedText: String?

    init(
        document: EditorDocument,
        selection: EditorSelection,
        languageID: String?,
        idleDuration: TimeInterval,
        insertedText: String? = nil
    ) {
        self.document = document
        self.selection = selection
        self.languageID = languageID
        self.idleDuration = idleDuration
        self.insertedText = insertedText
    }
}

struct CompletionTriggerPolicy: Sendable {
    let config: CompletionConfig

    init(config: CompletionConfig = .defaults) {
        self.config = config
    }

    func shouldTrigger(_ input: CompletionTriggerInput) -> Bool {
        guard config.inlineAIEnabled,
              input.idleDuration >= config.idleDelaySeconds,
              config.allows(languageID: input.languageID)
        else {
            return false
        }

        let selection = input.selection.clamped(to: input.document.buffer.utf16Length)
        guard selection.ranges.count == 1,
              selection.primaryRange.isCaret
        else {
            return false
        }

        if let insertedText = input.insertedText,
           insertedText.rangeOfCharacter(from: .newlines) != nil {
            return false
        }
        if input.insertedText == nil,
           characterBeforePrimaryCaret(in: input.document, selection: selection)
            .rangeOfCharacter(from: .newlines) != nil {
            return false
        }

        return true
    }

    private func characterBeforePrimaryCaret(
        in document: EditorDocument,
        selection: EditorSelection
    ) -> String {
        let range = selection.primaryRange
        guard range.location > 0 else { return "" }
        let nsText = document.text as NSString
        let composed = nsText.rangeOfComposedCharacterSequence(at: range.location - 1)
        return nsText.substring(with: composed)
    }
}
