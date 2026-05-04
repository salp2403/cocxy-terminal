// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroPlayer.swift - Deterministic macro replay planning.

import Foundation

enum MacroPlayerError: Error, Equatable, Sendable {
    case emptyMacro(String)
    case invalidRepeatCount(Int)
}

struct MacroPlaybackPlan: Equatable, Sendable {
    let macroID: String
    let events: [MacroEvent]
}

struct MacroPlayer: Sendable {
    func playback(
        _ macro: TerminalMacro,
        repeatCount: Int = 1
    ) throws -> MacroPlaybackPlan {
        guard repeatCount > 0 else {
            throw MacroPlayerError.invalidRepeatCount(repeatCount)
        }
        guard !macro.events.isEmpty else {
            throw MacroPlayerError.emptyMacro(macro.id)
        }

        return MacroPlaybackPlan(
            macroID: macro.id,
            events: Array(repeating: macro.events, count: repeatCount).flatMap { $0 }
        )
    }
}
