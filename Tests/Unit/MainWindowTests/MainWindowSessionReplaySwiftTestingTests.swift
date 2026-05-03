// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowSessionReplaySwiftTestingTests.swift - Session replay surface lifecycle wiring.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MainWindowController Session Replay lifecycle")
@MainActor
struct MainWindowSessionReplaySwiftTestingTests {
    @Test("opted-in tab creation starts automatic local recording")
    func optedInTabCreationStartsAutomaticRecording() throws {
        let root = try makeTemporaryDirectory(named: "main-window-session-replay-start")
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: bridge,
            configService: try makeConfigService(recordingsRoot: root)
        )

        let tabID = controller.createTab(workingDirectory: root)

        let surfaceID = try #require(controller.tabSurfaceMap[tabID])
        #expect(bridge.sessionReplayStartRequests.count == 1)
        #expect(bridge.sessionReplayStartRequests.first?.surface == surfaceID)
        #expect(bridge.sessionReplayStartRequests.first?.outputURL.path.hasPrefix(root.path) == true)
        #expect(bridge.sessionReplayStartRequests.first?.title == root.lastPathComponent)
    }

    @Test("automatic recording remains disabled until explicit consent")
    func automaticRecordingRequiresConsent() throws {
        let root = try makeTemporaryDirectory(named: "main-window-session-replay-consent")
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: bridge,
            configService: try makeConfigService(
                recordingsRoot: root,
                consentGranted: false
            )
        )

        _ = controller.createTab(workingDirectory: root)

        #expect(bridge.sessionReplayStartRequests.isEmpty)
    }

    @Test("closing a tab stops its active automatic recording before destroying the surface")
    func tabCloseStopsAutomaticRecordingBeforeDestroyingSurface() throws {
        let root = try makeTemporaryDirectory(named: "main-window-session-replay-stop")
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: bridge,
            configService: try makeConfigService(recordingsRoot: root)
        )

        let tabID = controller.createTab(workingDirectory: root)
        let surfaceID = try #require(controller.tabSurfaceMap[tabID])
        let handle = try #require(bridge.sessionReplayRecordingHandles[surfaceID])

        controller.performCloseTab(tabID)

        #expect(handle.stopCallCount == 1)
        #expect(handle.isActive == false)
        #expect(bridge.destroyedSurfaces.contains(surfaceID))
        let recordings = try SessionReplayStore(rootDirectory: root).listRecordings()
        #expect(recordings.count == 1)
        #expect(recordings.first?.surfaceID == surfaceID)
    }

    @Test("transferred tabs keep active recording ownership in the destination window")
    func transferredTabKeepsActiveRecordingOwnership() throws {
        let root = try makeTemporaryDirectory(named: "main-window-session-replay-transfer")
        let sourceBridge = MockTerminalEngine()
        let destinationBridge = MockTerminalEngine()
        let source = MainWindowController(
            bridge: sourceBridge,
            configService: try makeConfigService(recordingsRoot: root)
        )
        let destination = MainWindowController(
            bridge: destinationBridge,
            configService: try makeConfigService(recordingsRoot: root)
        )

        let tabID = source.createTab(workingDirectory: root)
        let surfaceID = try #require(source.tabSurfaceMap[tabID])
        let handle = try #require(sourceBridge.sessionReplayRecordingHandles[surfaceID])

        #expect(source.transferTab(tabID, to: destination))
        #expect(source.sessionReplayControllers[surfaceID] == nil)
        #expect(destination.sessionReplayControllers[surfaceID] != nil)

        destination.performCloseTab(tabID)

        #expect(handle.stopCallCount == 1)
        #expect(handle.isActive == false)
    }

    private func makeConfigService(
        recordingsRoot: URL,
        consentGranted: Bool = true
    ) throws -> ConfigService {
        let provider = InMemoryConfigFileProvider(content: """
        [session-replay]
        enabled = true
        auto-record = true
        consent-granted = \(consentGranted)
        storage-directory = "\(tomlEscaped(recordingsRoot.path))"
        max-recording-bytes = 1048576
        """)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
