// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalKeyMapping.swift - Shared macOS hardware-key mappings for terminal input.

import Foundation

public enum TerminalKeyMapping {
    /// Maps a macOS hardware key code to CocxyCore's stable `cocxycore_key` value.
    public static func specialKey(forMacKeyCode code: UInt16) -> UInt8? {
        switch code {
        case 126: return 0   // Up
        case 125: return 1   // Down
        case 124: return 2   // Right
        case 123: return 3   // Left
        case 115: return 4   // Home
        case 119: return 5   // End
        case 114: return 6   // Insert / Help
        case 117: return 7   // Forward delete
        case 116: return 8   // Page Up
        case 121: return 9   // Page Down
        case 122: return 10  // F1
        case 120: return 11  // F2
        case 99: return 12   // F3
        case 118: return 13  // F4
        case 96: return 14   // F5
        case 97: return 15   // F6
        case 98: return 16   // F7
        case 100: return 17  // F8
        case 101: return 18  // F9
        case 109: return 19  // F10
        case 103: return 20  // F11
        case 111: return 21  // F12
        case 51: return 22   // Backspace
        case 48: return 23   // Tab
        case 36: return 24   // Return
        case 53: return 25   // Escape
        case 82: return 26   // Keypad 0
        case 83: return 27   // Keypad 1
        case 84: return 28   // Keypad 2
        case 85: return 29   // Keypad 3
        case 86: return 30   // Keypad 4
        case 87: return 31   // Keypad 5
        case 88: return 32   // Keypad 6
        case 89: return 33   // Keypad 7
        case 91: return 34   // Keypad 8
        case 92: return 35   // Keypad 9
        case 76: return 36   // Keypad Enter
        case 69: return 37   // Keypad Plus
        case 78: return 38   // Keypad Minus
        case 67: return 39   // Keypad Multiply
        case 75: return 40   // Keypad Divide
        case 65: return 41   // Keypad Decimal
        case 95: return 42   // Keypad Separator
        case 105: return 43  // F13
        case 107: return 44  // F14
        case 113: return 45  // F15
        case 106: return 46  // F16
        case 64: return 47   // F17
        case 79: return 48   // F18
        case 80: return 49   // F19
        case 90: return 50   // F20
        case 57: return 66   // Caps Lock
        case 71: return 68   // Keypad Clear / Num Lock
        case 81: return 72   // Keypad Equal
        case 56: return 73   // Left Shift
        case 59: return 74   // Left Control
        case 58: return 75   // Left Option
        case 55: return 76   // Left Command / Super
        case 60: return 79   // Right Shift
        case 62: return 80   // Right Control
        case 61: return 81   // Right Option
        case 54: return 82   // Right Command / Super
        case 73: return 106  // Volume Down
        case 72: return 107  // Volume Up
        case 74: return 108  // Mute
        default: return nil
        }
    }

    /// Whether a CocxyCore special key can carry printable associated text.
    /// Keypad Equal is outside the otherwise contiguous keypad ABI range.
    public static func carriesAssociatedText(_ key: UInt8) -> Bool {
        (26...42).contains(key) || key == 72
    }

    /// Returns the unshifted US-layout codepoint for Kitty's base-layout field.
    public static func baseLayoutCodepoint(forMacKeyCode code: UInt16) -> UInt32 {
        switch code {
        case 0: return 97    // a
        case 1: return 115   // s
        case 2: return 100   // d
        case 3: return 102   // f
        case 4: return 104   // h
        case 5: return 103   // g
        case 6: return 122   // z
        case 7: return 120   // x
        case 8: return 99    // c
        case 9: return 118   // v
        case 11: return 98   // b
        case 12: return 113  // q
        case 13: return 119  // w
        case 14: return 101  // e
        case 15: return 114  // r
        case 16: return 121  // y
        case 17: return 116  // t
        case 18: return 49   // 1
        case 19: return 50   // 2
        case 20: return 51   // 3
        case 21: return 52   // 4
        case 22: return 54   // 6
        case 23: return 53   // 5
        case 24: return 61   // =
        case 25: return 57   // 9
        case 26: return 55   // 7
        case 27: return 45   // -
        case 28: return 56   // 8
        case 29: return 48   // 0
        case 30: return 93   // ]
        case 31: return 111  // o
        case 32: return 117  // u
        case 33: return 91   // [
        case 34: return 105  // i
        case 35: return 112  // p
        case 37: return 108  // l
        case 38: return 106  // j
        case 39: return 39   // '
        case 40: return 107  // k
        case 41: return 59   // ;
        case 42: return 92   // backslash
        case 43: return 44   // ,
        case 44: return 47   // /
        case 45: return 110  // n
        case 46: return 109  // m
        case 47: return 46   // .
        case 49: return 32   // Space
        case 50: return 96   // `
        default: return 0
        }
    }

    /// Returns the shifted US-layout codepoint for Kitty's alternate-key field.
    public static func shiftedBaseLayoutCodepoint(forMacKeyCode code: UInt16) -> UInt32 {
        let base = baseLayoutCodepoint(forMacKeyCode: code)
        if (97...122).contains(base) {
            return base - 32
        }
        switch code {
        case 18: return 33   // !
        case 19: return 64   // @
        case 20: return 35   // #
        case 21: return 36   // $
        case 22: return 94   // ^
        case 23: return 37   // %
        case 24: return 43   // +
        case 25: return 40   // (
        case 26: return 38   // &
        case 27: return 95   // _
        case 28: return 42   // *
        case 29: return 41   // )
        case 30: return 125  // }
        case 33: return 123  // {
        case 39: return 34   // "
        case 41: return 58   // :
        case 42: return 124  // |
        case 43: return 60   // <
        case 44: return 63   // ?
        case 47: return 62   // >
        case 50: return 126  // ~
        default: return base
        }
    }
}
