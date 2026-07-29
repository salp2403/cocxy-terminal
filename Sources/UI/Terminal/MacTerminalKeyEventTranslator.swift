// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacTerminalKeyEventTranslator.swift - AppKit to terminal-domain key translation.

import AppKit
import CocxyShared

enum MacTerminalKeyEventTranslator {
    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        // AppKit's numericPad bit identifies the physical key group; it is
        // not the Num Lock state. Keypad identity is carried by keyCode.
        return modifiers
    }

    static func event(
        from event: NSEvent,
        characters: String? = nil,
        isKeyDown: Bool,
        isComposing: Bool
    ) -> KeyEvent {
        let exposesKeyText = event.type == .keyDown || event.type == .keyUp
        let resolvedCharacters = characters ?? (exposesKeyText ? event.characters : nil)
        let charactersIgnoringModifiers = exposesKeyText
            ? event.charactersIgnoringModifiers
            : nil
        let baseLayoutCodepoint = TerminalKeyMapping.baseLayoutCodepoint(
            forMacKeyCode: event.keyCode
        )
        return KeyEvent(
            characters: resolvedCharacters,
            keyCode: event.keyCode,
            modifiers: modifiers(from: event.modifierFlags),
            isKeyDown: isKeyDown,
            isRepeat: exposesKeyText && event.isARepeat,
            isComposing: isComposing,
            unshiftedCodepoint: unshiftedCodepoint(
                for: event,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                resolvedCharacters: resolvedCharacters,
                baseLayoutCodepoint: baseLayoutCodepoint
            ),
            shiftedCodepoint: shiftedCodepoint(
                for: event,
                resolvedCharacters: resolvedCharacters
            ),
            baseLayoutCodepoint: baseLayoutCodepoint
        )
    }

    static func modifierIsActive(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> Bool? {
        switch keyCode {
        case 56, 60: return flags.contains(.shift)
        case 59, 62: return flags.contains(.control)
        case 58, 61: return flags.contains(.option)
        case 54, 55: return flags.contains(.command)
        case 57: return flags.contains(.capsLock)
        default: return nil
        }
    }

    private static func unshiftedCodepoint(
        for event: NSEvent,
        charactersIgnoringModifiers: String?,
        resolvedCharacters: String?,
        baseLayoutCodepoint: UInt32
    ) -> UInt32 {
        guard let scalar = charactersIgnoringModifiers?.unicodeScalars.first else {
            return resolvedCharacters?.unicodeScalars.first?.value ?? baseLayoutCodepoint
        }
        guard event.modifierFlags.contains(.shift) else { return scalar.value }

        let shiftedBase = TerminalKeyMapping.shiftedBaseLayoutCodepoint(
            forMacKeyCode: event.keyCode
        )
        if baseLayoutCodepoint > 0, scalar.value == shiftedBase {
            return baseLayoutCodepoint
        }
        if let lowercase = String(scalar).lowercased().unicodeScalars.first,
           lowercase.value != scalar.value {
            return lowercase.value
        }
        return scalar.value
    }

    private static func shiftedCodepoint(
        for event: NSEvent,
        resolvedCharacters: String?
    ) -> UInt32 {
        if event.modifierFlags.contains(.shift),
           let scalar = resolvedCharacters?.unicodeScalars.first {
            return scalar.value
        }
        return TerminalKeyMapping.shiftedBaseLayoutCodepoint(forMacKeyCode: event.keyCode)
    }
}
