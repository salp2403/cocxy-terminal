// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
@testable import CocxyTerminal

@MainActor
final class MockTerminalEngine: TerminalEngine {
    private(set) var initializeCalls: [TerminalEngineConfig] = []
    private(set) var createdSurfaces: [SurfaceID: NativeTerminalView] = [:]
    private(set) var createSurfaceRequests: [(surface: SurfaceID, workingDirectory: URL?, command: String?)] = []
    private(set) var destroyedSurfaces: [SurfaceID] = []
    private(set) var keyEvents: [(surface: SurfaceID, event: KeyEvent)] = []
    private(set) var sentTexts: [(surface: SurfaceID, text: String)] = []
    private(set) var preeditTexts: [(surface: SurfaceID, text: String)] = []
    private(set) var resizedSurfaces: [(surface: SurfaceID, size: TerminalSize)] = []
    private(set) var scrolledResults: [(surface: SurfaceID, lineNumber: Int)] = []
    private(set) var focusNotifications: [(surface: SurfaceID, focused: Bool)] = []
    private(set) var nativeSearchRequests: [(surface: SurfaceID, options: SearchOptions)] = []
    private(set) var tickCount: Int = 0

    var createSurfaceError: Error?
    var sendKeyEventReturnValue: Bool = true
    var nativeSearchResults: [SurfaceID: [SearchResult]?] = [:]

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
        createSurfaceRequests.append((surface: surfaceID, workingDirectory: workingDirectory, command: command))
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

    func notifyFocus(_ focused: Bool, for surface: SurfaceID) {
        focusNotifications.append((surface, focused))
    }

    func searchScrollback(surfaceID: SurfaceID, options: SearchOptions) -> [SearchResult]? {
        nativeSearchRequests.append((surfaceID, options))
        return nativeSearchResults[surfaceID] ?? nil
    }

    func emitOutput(_ data: Data, for surface: SurfaceID) {
        outputHandlers[surface]?(data)
    }

    func emitOSC(_ notification: OSCNotification, for surface: SurfaceID) {
        oscHandlers[surface]?(notification)
    }
}
