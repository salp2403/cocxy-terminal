// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyKeyConverter.swift - Conversion from domain key types to ghostty C types.

import GhosttyKit

// MARK: - Ghostty Key Converter

/// Pure conversion logic between domain keyboard types and ghostty C API types.
///
/// This struct is stateless and all methods are static. It encapsulates the
/// mapping tables and bitwise operations needed to translate between the
/// domain layer's `KeyEvent`/`KeyModifiers` and libghostty's
/// `ghostty_input_key_s`/`ghostty_input_mods_e`.
///
/// The key code mapping follows macOS HID key codes (hardware-level,
/// layout-independent) as documented in Events.h (Carbon framework).
///
/// - SeeAlso: `KeyEvent`, `KeyModifiers` (domain types)
/// - SeeAlso: `ghostty_input_key_s`, `ghostty_input_mods_e` (C types)
enum GhosttyKeyConverter {

    // MARK: - Modifier Conversion

    /// Converts domain `KeyModifiers` to ghostty's `ghostty_input_mods_e`.
    ///
    /// The mapping is straightforward bitwise:
    /// - `.shift`   -> `GHOSTTY_MODS_SHIFT`
    /// - `.control` -> `GHOSTTY_MODS_CTRL`
    /// - `.option`  -> `GHOSTTY_MODS_ALT`
    /// - `.command` -> `GHOSTTY_MODS_SUPER`
    ///
    /// - Parameter modifiers: The domain modifier flags.
    /// - Returns: The equivalent ghostty modifier bitmask.
    static func ghosttyMods(from modifiers: KeyModifiers) -> ghostty_input_mods_e {
        var rawMods: UInt32 = 0

        if modifiers.contains(.shift) {
            rawMods |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if modifiers.contains(.control) {
            rawMods |= GHOSTTY_MODS_CTRL.rawValue
        }
        if modifiers.contains(.option) {
            rawMods |= GHOSTTY_MODS_ALT.rawValue
        }
        if modifiers.contains(.command) {
            rawMods |= GHOSTTY_MODS_SUPER.rawValue
        }

        return ghostty_input_mods_e(rawValue: rawMods)
    }

    // MARK: - Key Event Conversion

    /// Converts a domain `KeyEvent` to ghostty's `ghostty_input_key_s`.
    ///
    /// This produces a struct suitable for passing to `ghostty_surface_key()`.
    /// The `text` field is not set here because it requires a stable pointer
    /// that outlives the function call -- the caller must manage text lifetime.
    ///
    /// - Parameter event: The domain key event.
    /// - Returns: The equivalent ghostty key event struct.
    static func ghosttyInputKey(from event: KeyEvent) -> ghostty_input_key_s {
        let action: ghostty_input_action_e
        if !event.isKeyDown {
            action = GHOSTTY_ACTION_RELEASE
        } else if event.isRepeat {
            action = GHOSTTY_ACTION_REPEAT
        } else {
            action = GHOSTTY_ACTION_PRESS
        }

        let mods = ghosttyMods(from: event.modifiers)
        let key = ghosttyKey(fromMacOSKeyCode: event.keyCode)

        return ghostty_input_key_s(
            action: action,
            mods: mods,
            consumed_mods: ghostty_input_mods_e(rawValue: 0),
            keycode: UInt32(key.rawValue),
            text: nil,
            unshifted_codepoint: event.unshiftedCodepoint,
            composing: event.isComposing
        )
    }

    // MARK: - macOS KeyCode to Ghostty Key

    /// Converts a macOS hardware key code to a `ghostty_input_key_e`.
    ///
    /// macOS key codes are layout-independent hardware identifiers defined
    /// in the Carbon Events.h header. This table maps the most common keys.
    /// Unmapped key codes return `GHOSTTY_KEY_UNIDENTIFIED`.
    ///
    /// - Parameter keyCode: The macOS hardware key code (`NSEvent.keyCode`).
    /// - Returns: The equivalent ghostty key enum value.
    static func ghosttyKey(fromMacOSKeyCode keyCode: UInt16) -> ghostty_input_key_e {
        return macOSKeyCodeToGhosttyKey[keyCode] ?? GHOSTTY_KEY_UNIDENTIFIED
    }

    // MARK: - Key Code Mapping Table

    /// Complete mapping from macOS hardware key codes to ghostty key enum values.
    ///
    /// Sources:
    /// - Carbon Events.h (kVK_* constants)
    /// - Ghostty's Ghostty.Input.swift (reference implementation)
    /// - W3C UIEvents KeyboardEvent code values (ghostty follows this spec)
    private static let macOSKeyCodeToGhosttyKey: [UInt16: ghostty_input_key_e] = [
        // Letters (QWERTY layout key codes)
        0x00: GHOSTTY_KEY_A,
        0x01: GHOSTTY_KEY_S,
        0x02: GHOSTTY_KEY_D,
        0x03: GHOSTTY_KEY_F,
        0x04: GHOSTTY_KEY_H,
        0x05: GHOSTTY_KEY_G,
        0x06: GHOSTTY_KEY_Z,
        0x07: GHOSTTY_KEY_X,
        0x08: GHOSTTY_KEY_C,
        0x09: GHOSTTY_KEY_V,
        0x0B: GHOSTTY_KEY_B,
        0x0C: GHOSTTY_KEY_Q,
        0x0D: GHOSTTY_KEY_W,
        0x0E: GHOSTTY_KEY_E,
        0x0F: GHOSTTY_KEY_R,
        0x10: GHOSTTY_KEY_Y,
        0x11: GHOSTTY_KEY_T,
        0x12: GHOSTTY_KEY_DIGIT_1,
        0x13: GHOSTTY_KEY_DIGIT_2,
        0x14: GHOSTTY_KEY_DIGIT_3,
        0x15: GHOSTTY_KEY_DIGIT_4,
        0x16: GHOSTTY_KEY_DIGIT_6,
        0x17: GHOSTTY_KEY_DIGIT_5,
        0x18: GHOSTTY_KEY_EQUAL,
        0x19: GHOSTTY_KEY_DIGIT_9,
        0x1A: GHOSTTY_KEY_DIGIT_7,
        0x1B: GHOSTTY_KEY_MINUS,
        0x1C: GHOSTTY_KEY_DIGIT_8,
        0x1D: GHOSTTY_KEY_DIGIT_0,
        0x1E: GHOSTTY_KEY_BRACKET_RIGHT,
        0x1F: GHOSTTY_KEY_O,
        0x20: GHOSTTY_KEY_U,
        0x21: GHOSTTY_KEY_BRACKET_LEFT,
        0x22: GHOSTTY_KEY_I,
        0x23: GHOSTTY_KEY_P,
        0x25: GHOSTTY_KEY_L,
        0x26: GHOSTTY_KEY_J,
        0x27: GHOSTTY_KEY_QUOTE,
        0x28: GHOSTTY_KEY_K,
        0x29: GHOSTTY_KEY_SEMICOLON,
        0x2A: GHOSTTY_KEY_BACKSLASH,
        0x2B: GHOSTTY_KEY_COMMA,
        0x2C: GHOSTTY_KEY_SLASH,
        0x2D: GHOSTTY_KEY_N,
        0x2E: GHOSTTY_KEY_M,
        0x2F: GHOSTTY_KEY_PERIOD,

        // Special keys
        0x24: GHOSTTY_KEY_ENTER,
        0x30: GHOSTTY_KEY_TAB,
        0x31: GHOSTTY_KEY_SPACE,
        0x32: GHOSTTY_KEY_BACKQUOTE,
        0x33: GHOSTTY_KEY_BACKSPACE,
        0x35: GHOSTTY_KEY_ESCAPE,

        // Modifier keys
        0x37: GHOSTTY_KEY_META_LEFT,
        0x38: GHOSTTY_KEY_SHIFT_LEFT,
        0x39: GHOSTTY_KEY_CAPS_LOCK,
        0x3A: GHOSTTY_KEY_ALT_LEFT,
        0x3B: GHOSTTY_KEY_CONTROL_LEFT,
        0x3C: GHOSTTY_KEY_SHIFT_RIGHT,
        0x3D: GHOSTTY_KEY_ALT_RIGHT,
        0x3E: GHOSTTY_KEY_CONTROL_RIGHT,
        0x36: GHOSTTY_KEY_META_RIGHT,

        // Function keys
        0x7A: GHOSTTY_KEY_F1,
        0x78: GHOSTTY_KEY_F2,
        0x63: GHOSTTY_KEY_F3,
        0x76: GHOSTTY_KEY_F4,
        0x60: GHOSTTY_KEY_F5,
        0x61: GHOSTTY_KEY_F6,
        0x62: GHOSTTY_KEY_F7,
        0x64: GHOSTTY_KEY_F8,
        0x65: GHOSTTY_KEY_F9,
        0x6D: GHOSTTY_KEY_F10,
        0x67: GHOSTTY_KEY_F11,
        0x6F: GHOSTTY_KEY_F12,
        0x69: GHOSTTY_KEY_F13,
        0x6B: GHOSTTY_KEY_F14,
        0x71: GHOSTTY_KEY_F15,
        0x6A: GHOSTTY_KEY_F16,
        0x40: GHOSTTY_KEY_F17,
        0x4F: GHOSTTY_KEY_F18,
        0x50: GHOSTTY_KEY_F19,
        0x5A: GHOSTTY_KEY_F20,

        // Arrow keys
        0x7B: GHOSTTY_KEY_ARROW_LEFT,
        0x7C: GHOSTTY_KEY_ARROW_RIGHT,
        0x7D: GHOSTTY_KEY_ARROW_DOWN,
        0x7E: GHOSTTY_KEY_ARROW_UP,

        // Navigation keys
        0x73: GHOSTTY_KEY_HOME,
        0x77: GHOSTTY_KEY_END,
        0x74: GHOSTTY_KEY_PAGE_UP,
        0x79: GHOSTTY_KEY_PAGE_DOWN,
        0x72: GHOSTTY_KEY_HELP,       // macOS Help key = Insert on PC keyboards
        0x75: GHOSTTY_KEY_DELETE,      // Forward Delete

        // Numpad
        0x52: GHOSTTY_KEY_NUMPAD_0,
        0x53: GHOSTTY_KEY_NUMPAD_1,
        0x54: GHOSTTY_KEY_NUMPAD_2,
        0x55: GHOSTTY_KEY_NUMPAD_3,
        0x56: GHOSTTY_KEY_NUMPAD_4,
        0x57: GHOSTTY_KEY_NUMPAD_5,
        0x58: GHOSTTY_KEY_NUMPAD_6,
        0x59: GHOSTTY_KEY_NUMPAD_7,
        0x5B: GHOSTTY_KEY_NUMPAD_8,
        0x5C: GHOSTTY_KEY_NUMPAD_9,
        0x41: GHOSTTY_KEY_NUMPAD_DECIMAL,
        0x43: GHOSTTY_KEY_NUMPAD_MULTIPLY,
        0x45: GHOSTTY_KEY_NUMPAD_ADD,
        0x47: GHOSTTY_KEY_NUMPAD_CLEAR,
        0x4B: GHOSTTY_KEY_NUMPAD_DIVIDE,
        0x4C: GHOSTTY_KEY_NUMPAD_ENTER,
        0x4E: GHOSTTY_KEY_NUMPAD_SUBTRACT,
        0x51: GHOSTTY_KEY_NUMPAD_EQUAL,

        // International keys
        0x0A: GHOSTTY_KEY_INTL_BACKSLASH,
        0x5D: GHOSTTY_KEY_INTL_YEN,
        0x5E: GHOSTTY_KEY_INTL_RO,
    ]
}
