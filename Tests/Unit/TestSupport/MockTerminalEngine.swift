// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
@testable import CocxyTerminal

@MainActor
final class MockTerminalEngine: TerminalEngine {
    private(set) var initializeCalls: [TerminalEngineConfig] = []
    private(set) var createdSurfaces: [SurfaceID: NativeTerminalView] = [:]
    private(set) var destroyedSurfaces: [SurfaceID] = []
    private(set) var keyEvents: [(surface: SurfaceID, event: KeyEvent)] = []
    private(set) var sentTexts: [(surface: SurfaceID, text: String)] = []
    private(set) var preeditTexts: [(surface: SurfaceID, text: String)] = []
    private(set) var resizedSurfaces: [(surface: SurfaceID, size: TerminalSize)] = []
    private(set) var scrolledResults: [(surface: SurfaceID, lineNumber: Int)] = []
    private(set) var tickCount: Int = 0

    var createSurfaceError: Error?
    var sendKeyEventReturnValue: Bool = true

    private var outputHandlers: [SurfaceID: @Sendable (Data) -> Void] = [:]
    private var oscHandlers: [SurfaceID: @Sendable (OSCNotification) -> Void] = [:]

    func initialize(config: TerminalEngineConfig) throws {
        initializeCalls.append(config)
    }

    func createSurface(
        in view: NativeTerminalView,
        workingDirectory: URL?,
        command: String?
    ) throws -> SurfaceID {
        if let createSurfaceError {
            throw createSurfaceError
        }

        let surfaceID = SurfaceID()
        createdSurfaces[surfaceID] = view
        return surfaceID
    }

    func destroySurface(_ id: SurfaceID) {
        destroyedSurfaces.append(id)
        createdSurfaces.removeValue(forKey: id)
        outputHandlers.removeValue(forKey: id)
        oscHandlers.removeValue(forKey: id)
    }

    @discardableResult
    func sendKeyEvent(_ event: KeyEvent, to surface: SurfaceID) -> Bool {
        keyEvents.append((surface, event))
        return sendKeyEventReturnValue
    }

    func sendText(_ text: String, to surface: SurfaceID) {
        sentTexts.append((surface, text))
    }

    func sendPreeditText(_ text: String, to surface: SurfaceID) {
        preeditTexts.append((surface, text))
    }

    func resize(_ surface: SurfaceID, to size: TerminalSize) {
        resizedSurfaces.append((surface, size))
    }

    func tick() {
        tickCount += 1
    }

    func setOutputHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (Data) -> Void
    ) {
        outputHandlers[surface] = handler
    }

    func setOSCHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (OSCNotification) -> Void
    ) {
        oscHandlers[surface] = handler
    }

    func scrollToSearchResult(surfaceID: SurfaceID, lineNumber: Int) {
        scrolledResults.append((surfaceID, lineNumber))
    }

    func emitOutput(_ data: Data, for surface: SurfaceID) {
        outputHandlers[surface]?(data)
    }

    func emitOSC(_ notification: OSCNotification, for surface: SurfaceID) {
        oscHandlers[surface]?(notification)
    }
}
