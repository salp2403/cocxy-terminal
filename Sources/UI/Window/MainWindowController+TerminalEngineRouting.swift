// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TerminalEngineRouting.swift - Per-tab engine routing.

import Foundation

extension MainWindowController {
    func makeTerminalEngine(for preference: TerminalEnginePreference?) -> any TerminalEngine {
        guard let preference, preference != .system else {
            return bridge
        }
        return terminalEngineFactory?(preference) ?? bridge
    }

    func terminalEngine(for tabID: TabID) -> any TerminalEngine {
        tabTerminalEngines[tabID] ?? bridge
    }

    func terminalEngine(for surfaceID: SurfaceID) -> any TerminalEngine {
        surfaceTerminalEngines[surfaceID] ?? bridge
    }

    func registerTerminalEngine(
        _ engine: any TerminalEngine,
        tabID: TabID,
        surfaceID: SurfaceID
    ) {
        if engine === bridge {
            tabTerminalEngines.removeValue(forKey: tabID)
            surfaceTerminalEngines.removeValue(forKey: surfaceID)
        } else {
            tabTerminalEngines[tabID] = engine
            surfaceTerminalEngines[surfaceID] = engine
        }
    }

    func clearTerminalEngineTracking(surfaceID: SurfaceID) {
        surfaceTerminalEngines.removeValue(forKey: surfaceID)
    }

    func clearTerminalEngineTracking(tabID: TabID) {
        tabTerminalEngines.removeValue(forKey: tabID)
    }

    func resetTerminalEngineRouting() {
        tabTerminalEngines.removeAll()
        surfaceTerminalEngines.removeAll()
    }
}
