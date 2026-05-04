// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroTerminalInputReplayer.swift - Sends deterministic macro playback into a terminal PTY.

import Foundation

enum MacroTerminalInputReplayError: Error, Equatable, Sendable {
    case noTargetSurface
    case unsupportedKey(String)
    case unsupportedDelay(Int)
}

@MainActor
struct MacroTerminalInputReplayer {
    let sendText: (String) -> Void

    @discardableResult
    func replay(_ plan: MacroPlaybackPlan) throws -> Int {
        for event in plan.events {
            try replay(event)
        }
        return plan.events.count
    }

    private func replay(_ event: MacroEvent) throws {
        switch event {
        case .text(let value):
            sendText(value)
        case .command(let value):
            sendText(value + "\r")
        case .key(let value):
            guard let sequence = Self.sequence(forKey: value) else {
                throw MacroTerminalInputReplayError.unsupportedKey(value)
            }
            sendText(sequence)
        case .delay(let milliseconds):
            throw MacroTerminalInputReplayError.unsupportedDelay(milliseconds)
        }
    }

    static func sequence(forKey key: String) -> String? {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "enter", "return": return "\r"
        case "tab": return "\t"
        case "escape", "esc": return "\u{1B}"
        case "backspace", "bs": return "\u{7F}"
        case "space": return " "
        case "up": return "\u{1B}[A"
        case "down": return "\u{1B}[B"
        case "right": return "\u{1B}[C"
        case "left": return "\u{1B}[D"
        case "delete", "del": return "\u{1B}[3~"
        case "home": return "\u{1B}[H"
        case "end": return "\u{1B}[F"
        case "pageup", "pgup": return "\u{1B}[5~"
        case "pagedown", "pgdn": return "\u{1B}[6~"
        case "insert", "ins": return "\u{1B}[2~"
        case "ctrl-c": return "\u{03}"
        case "ctrl-d": return "\u{04}"
        case "ctrl-z": return "\u{1A}"
        case "ctrl-l": return "\u{0C}"
        case "ctrl-a": return "\u{01}"
        case "ctrl-e": return "\u{05}"
        case "ctrl-k": return "\u{0B}"
        case "ctrl-u": return "\u{15}"
        case "ctrl-w": return "\u{17}"
        default: return nil
        }
    }
}
