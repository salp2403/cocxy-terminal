// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+MacroReplay.swift - Terminal-bound macro replay actions.

import Foundation

extension MainWindowController {
    func replayMacroPlaybackPlan(
        _ plan: MacroPlaybackPlan,
        preferredSurfaceID: SurfaceID? = nil
    ) throws -> Int {
        guard let surfaceID = preferredSurfaceID
            ?? focusedSplitSurfaceView?.terminalViewModel?.surfaceID
            ?? activeTerminalSurfaceView?.terminalViewModel?.surfaceID else {
            throw MacroTerminalInputReplayError.noTargetSurface
        }
        let engine = terminalEngine(for: surfaceID)
        let replayer = MacroTerminalInputReplayer { text in
            engine.sendText(text, to: surfaceID)
        }
        return try replayer.replay(plan)
    }

    func sendMacroTextToTerminal(
        _ text: String,
        preferredSurfaceID: SurfaceID? = nil
    ) throws {
        guard let surfaceID = preferredSurfaceID
            ?? focusedSplitSurfaceView?.terminalViewModel?.surfaceID
            ?? activeTerminalSurfaceView?.terminalViewModel?.surfaceID else {
            throw MacroTerminalInputReplayError.noTargetSurface
        }
        guard terminalEngine(for: surfaceID).sendText(text, to: surfaceID) else {
            throw MacroTerminalInputReplayError.deliveryFailed
        }
    }
}
