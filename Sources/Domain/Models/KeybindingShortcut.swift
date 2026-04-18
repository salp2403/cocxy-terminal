// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingShortcut.swift - Parsed representation of a keyboard shortcut.

import Foundation
import AppKit

// MARK: - Keybinding Shortcut

/// A parsed keyboard shortcut with modifiers and a base key.
///
/// Shortcuts are stored in `config.toml` as canonical plus-separated strings
/// (e.g., `"cmd+shift+d"`). This value type handles round-trip conversion
/// between that canonical form and a user-facing pretty label
/// (e.g., `⌘⇧D`), plus construction from an `NSEvent`.
///
/// ## Canonical format
///
/// - All tokens lowercase, separated by `+`.
/// - Modifiers (in any order): `cmd`, `ctrl`, `alt`, `shift`.
/// - Aliases accepted on parse: `option` -> `alt`, `control` -> `ctrl`, `meta` -> `cmd`.
/// - Base key examples: single characters (`a`, `1`, `d`), or named keys
///   (`tab`, `escape`, `return`, `space`, `grave`, `left`, `right`, `up`, `down`,
///   `delete`, `backspace`, `home`, `end`, `pageup`, `pagedown`,
///   `f1`...`f20`, punctuation `[`, `]`, `,`, `.`, `/`, `;`, `'`, `-`, `=`, `\`).
///
/// ## Pretty format
///
/// Modifiers are rendered using the classic macOS glyphs in the order
/// `⌃⌥⇧⌘` followed by the key. Named keys use human-readable words
/// (e.g., `Space`, `Tab`) while single characters are uppercased.
///
/// - SeeAlso: `KeybindingAction` for the action catalog.
struct KeybindingShortcut: Equatable, Hashable, Sendable {

    /// Whether the shortcut requires the Command modifier.
    let requiresCommand: Bool

    /// Whether the shortcut requires the Control modifier.
    let requiresControl: Bool

    /// Whether the shortcut requires the Option (Alt) modifier.
    let requiresOption: Bool

    /// Whether the shortcut requires the Shift modifier.
    let requiresShift: Bool

    /// The non-modifier base key token in canonical lowercase form
    /// (e.g., `"a"`, `"tab"`, `"grave"`, `"f5"`).
    let baseKey: String

    // MARK: - Canonical String

    /// The canonical lower-case plus-separated representation suitable for
    /// storing in `config.toml` (e.g., `"cmd+shift+d"`).
    var canonical: String {
        var parts: [String] = []
        if requiresCommand { parts.append("cmd") }
        if requiresControl { parts.append("ctrl") }
        if requiresOption { parts.append("alt") }
        if requiresShift { parts.append("shift") }
        parts.append(baseKey)
        return parts.joined(separator: "+")
    }

    // MARK: - Pretty Label

    /// The user-facing label rendered with macOS modifier glyphs
    /// (e.g., `⌘⇧D`, `⌃⌥⇧F12`, `⌘Space`).
    var prettyLabel: String {
        var label = ""
        if requiresControl { label += "\u{2303}" }    // ⌃
        if requiresOption { label += "\u{2325}" }     // ⌥
        if requiresShift { label += "\u{21E7}" }      // ⇧
        if requiresCommand { label += "\u{2318}" }    // ⌘
        label += Self.prettyKeyName(for: baseKey)
        return label
    }

    // MARK: - Init

    init(
        requiresCommand: Bool = false,
        requiresControl: Bool = false,
        requiresOption: Bool = false,
        requiresShift: Bool = false,
        baseKey: String
    ) {
        self.requiresCommand = requiresCommand
        self.requiresControl = requiresControl
        self.requiresOption = requiresOption
        self.requiresShift = requiresShift
        self.baseKey = baseKey.lowercased()
    }

    // MARK: - Parsing

    /// Parses a canonical shortcut string such as `"cmd+shift+d"`.
    ///
    /// - Parameter raw: The input string. Whitespace is ignored; casing is
    ///   normalized. Separator must be `+`.
    /// - Returns: A parsed shortcut, or `nil` if the input is empty, has no
    ///   base key, or contains an unknown token.
    static func parse(_ raw: String) -> KeybindingShortcut? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed
            .lowercased()
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard tokens.allSatisfy({ !$0.isEmpty }) else { return nil }

        var requiresCommand = false
        var requiresControl = false
        var requiresOption = false
        var requiresShift = false
        var baseKey: String?

        for token in tokens {
            switch token {
            case "cmd", "command", "meta":
                requiresCommand = true
            case "ctrl", "control":
                requiresControl = true
            case "alt", "option", "opt":
                requiresOption = true
            case "shift":
                requiresShift = true
            default:
                guard baseKey == nil else { return nil }   // two base keys
                baseKey = token
            }
        }

        guard let resolvedBase = baseKey, !resolvedBase.isEmpty else { return nil }

        return KeybindingShortcut(
            requiresCommand: requiresCommand,
            requiresControl: requiresControl,
            requiresOption: requiresOption,
            requiresShift: requiresShift,
            baseKey: resolvedBase
        )
    }

    // MARK: - NSEvent Capture

    /// Builds a shortcut from an `NSEvent` produced by a capture field.
    ///
    /// - Parameter event: A `.keyDown` or `.flagsChanged` event.
    /// - Returns: A shortcut if the event resolves to a non-modifier base key,
    ///   or `nil` for pure modifier events (e.g., pressing only Shift).
    static func fromEvent(_ event: NSEvent) -> KeybindingShortcut? {
        let flags = event.modifierFlags
        let requiresCommand = flags.contains(.command)
        let requiresControl = flags.contains(.control)
        let requiresOption = flags.contains(.option)
        let requiresShift = flags.contains(.shift)

        guard let baseKey = canonicalKeyName(for: event) else { return nil }

        return KeybindingShortcut(
            requiresCommand: requiresCommand,
            requiresControl: requiresControl,
            requiresOption: requiresOption,
            requiresShift: requiresShift,
            baseKey: baseKey
        )
    }

    // MARK: - Key Name Resolution

    /// Canonical key token produced by an `NSEvent`.
    ///
    /// Uses `keyCode` for non-alphanumeric keys (arrows, function keys, tab)
    /// and `charactersIgnoringModifiers` for printable characters. The result
    /// is always lowercase and modifier-independent so Shift+A and A both
    /// resolve to `"a"` (the modifier bit lives on `requiresShift`).
    private static func canonicalKeyName(for event: NSEvent) -> String? {
        if let named = namedKey(forKeyCode: event.keyCode) {
            return named
        }

        // Fall back to the unshifted characters so Shift+1 maps to "1", not "!".
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            let character = characters.unicodeScalars.first.map { Character($0) }
            guard let first = character else { return nil }
            let scalar = first.unicodeScalars.first!

            if scalar.isASCII {
                let value = scalar.value
                if value >= 0x20 && value < 0x7F {
                    return String(first).lowercased()
                }
            }
        }

        return nil
    }

    /// Maps a handful of `NSEvent.keyCode` values to canonical string tokens.
    ///
    /// Only covers keys that do not produce a useful character via
    /// `charactersIgnoringModifiers` (e.g., arrow keys, Escape, Tab on some
    /// keyboard layouts) or whose glyph would be surprising to store in TOML.
    private static func namedKey(forKeyCode keyCode: UInt16) -> String? {
        switch keyCode {
        case 0x24: return "return"
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x33: return "backspace"
        case 0x35: return "escape"
        case 0x75: return "delete"
        case 0x73: return "home"
        case 0x77: return "end"
        case 0x74: return "pageup"
        case 0x79: return "pagedown"
        case 0x7B: return "left"
        case 0x7C: return "right"
        case 0x7D: return "down"
        case 0x7E: return "up"
        case 0x32: return "grave"
        case 0x7A: return "f1"
        case 0x78: return "f2"
        case 0x63: return "f3"
        case 0x76: return "f4"
        case 0x60: return "f5"
        case 0x61: return "f6"
        case 0x62: return "f7"
        case 0x64: return "f8"
        case 0x65: return "f9"
        case 0x6D: return "f10"
        case 0x67: return "f11"
        case 0x6F: return "f12"
        case 0x69: return "f13"
        case 0x6B: return "f14"
        case 0x71: return "f15"
        default: return nil
        }
    }

    /// Converts a canonical base key token into a human-readable label.
    private static func prettyKeyName(for key: String) -> String {
        switch key {
        case "return": return "Return"
        case "tab": return "Tab"
        case "space": return "Space"
        case "backspace": return "Backspace"
        case "escape": return "Esc"
        case "delete": return "Del"
        case "home": return "Home"
        case "end": return "End"
        case "pageup": return "PageUp"
        case "pagedown": return "PageDown"
        case "left": return "\u{2190}"      // ←
        case "right": return "\u{2192}"     // →
        case "up": return "\u{2191}"        // ↑
        case "down": return "\u{2193}"      // ↓
        case "grave": return "`"
        default:
            // Function keys f1...f20 render uppercase.
            if key.hasPrefix("f"), key.dropFirst().allSatisfy(\.isNumber) {
                return key.uppercased()
            }
            return key.uppercased()
        }
    }
}
