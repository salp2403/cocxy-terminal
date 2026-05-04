// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayControllerSwiftTestingTests.swift - Controller gates and bridge orchestration.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Session Replay controller")
struct SessionReplayControllerSwiftTestingTests {

    @Test("manual recording requires the feature enabled")
    func manualRecordingRequiresFeatureEnabled() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-controller-disabled")
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = SessionReplayController(
            config: .defaults,
            store: SessionReplayStore(rootDirectory: root),
            bridge: RecordingSessionReplayBridge()
        )

        #expect(throws: SessionReplayControllerError.disabled) {
            try controller.startRecording(
                surfaceID: SurfaceID(),
                title: "Blocked",
                mode: .manual
            )
        }
    }

    @Test("automatic recording requires enabled auto record and consent")
    func automaticRecordingRequiresConsent() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-controller-consent")
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = SessionReplayController(
            config: SessionReplayConfig(enabled: true, autoRecord: true, consentGranted: false),
            store: SessionReplayStore(rootDirectory: root),
            bridge: RecordingSessionReplayBridge()
        )

        #expect(throws: SessionReplayControllerError.consentRequired) {
            try controller.startRecording(
                surfaceID: SurfaceID(),
                title: "Auto",
                mode: .automatic
            )
        }
    }

    @Test("manual recording starts bridge and finishes private metadata")
    func manualRecordingStartsBridgeAndFinishesMetadata() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-controller-record")
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = RecordingSessionReplayBridge()
        let store = SessionReplayStore(rootDirectory: root)
        let controller = SessionReplayController(
            config: SessionReplayConfig(enabled: true),
            store: store,
            bridge: bridge
        )
        let surfaceID = SurfaceID()
        let startedAt = Date(timeIntervalSince1970: 100)

        let prepared = try controller.startRecording(
            surfaceID: surfaceID,
            title: " Build smoke ",
            mode: .manual,
            startedAt: startedAt
        )
        try sampleCast().write(to: prepared.castURL, atomically: true, encoding: .utf8)
        bridge.handle.bytesWrittenValue = 128

        let recording = try controller.stopRecording(
            surfaceID: surfaceID,
            endedAt: Date(timeIntervalSince1970: 102.5)
        )

        #expect(bridge.startRequests.count == 1)
        #expect(bridge.startRequests[0].surfaceID == surfaceID)
        #expect(bridge.startRequests[0].outputURL == prepared.castURL)
        #expect(bridge.startRequests[0].title == "Build smoke")
        #expect(bridge.handle.stopCallCount == 1)
        #expect(recording.title == "Build smoke")
        #expect(recording.durationNs == 2_500_000_000)
        #expect(recording.byteCount == 128)
        #expect(try store.recording(id: recording.id) == recording)
        #expect(controller.activeRecording(for: surfaceID) == nil)
    }

    @Test("bridge start failure cleans prepared metadata")
    func bridgeStartFailureCleansPreparedMetadata() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-controller-start-fail")
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = RecordingSessionReplayBridge(shouldStart: false)
        let store = SessionReplayStore(rootDirectory: root)
        let controller = SessionReplayController(
            config: SessionReplayConfig(enabled: true),
            store: store,
            bridge: bridge
        )

        #expect(throws: SessionReplayControllerError.bridgeStartFailed) {
            try controller.startRecording(
                surfaceID: SurfaceID(),
                title: "Fail",
                mode: .manual
            )
        }
        #expect(try store.listRecordings().isEmpty)
    }

    @Test("controller replays stored cast through bridge")
    func controllerReplaysStoredCastThroughBridge() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-controller-replay")
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = RecordingSessionReplayBridge()
        let store = SessionReplayStore(rootDirectory: root)
        let controller = SessionReplayController(
            config: SessionReplayConfig(enabled: true),
            store: store,
            bridge: bridge
        )
        let sourceSurface = SurfaceID()
        let targetSurface = SurfaceID()

        let prepared = try controller.startRecording(
            surfaceID: sourceSurface,
            title: "Replay",
            mode: .manual
        )
        try sampleCast().write(to: prepared.castURL, atomically: true, encoding: .utf8)
        bridge.handle.bytesWrittenValue = 64
        let recording = try controller.stopRecording(surfaceID: sourceSurface)

        try controller.replay(
            recordingID: recording.id,
            to: targetSurface,
            seekNs: 500_000_000,
            speedMultiplier: 0
        )

        #expect(bridge.replayRequests == [
            RecordingSessionReplayBridge.ReplayRequest(
                recordingURL: prepared.castURL,
                surfaceID: targetSurface,
                seekNs: 500_000_000,
                speedMultiplier: 1
            )
        ])
    }

    @Test("controller preserves positive fractional replay speed")
    func controllerPreservesPositiveFractionalReplaySpeed() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-controller-fractional-speed")
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = RecordingSessionReplayBridge()
        let store = SessionReplayStore(rootDirectory: root)
        let controller = SessionReplayController(
            config: SessionReplayConfig(enabled: true),
            store: store,
            bridge: bridge
        )
        let sourceSurface = SurfaceID()
        let targetSurface = SurfaceID()

        let prepared = try controller.startRecording(
            surfaceID: sourceSurface,
            title: "Half speed",
            mode: .manual,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        bridge.handle.bytesWrittenValue = 32
        let recording = try controller.stopRecording(surfaceID: sourceSurface)

        try controller.replay(
            recordingID: recording.id,
            to: targetSurface,
            seekNs: 250_000_000,
            speedMultiplier: 0.5
        )

        #expect(bridge.replayRequests == [
            RecordingSessionReplayBridge.ReplayRequest(
                recordingURL: prepared.castURL,
                surfaceID: targetSurface,
                seekNs: 250_000_000,
                speedMultiplier: 0.5
            )
        ])
    }

    @Test("sixty second local recording smoke exports and replays deterministically")
    func sixtySecondLocalRecordingSmokeExportsAndReplaysDeterministically() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-controller-sixty-second-smoke")
        let exportRoot = try makeTemporaryDirectory(named: "session-replay-controller-sixty-second-export")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exportRoot)
        }

        let bridge = RecordingSessionReplayBridge()
        let store = SessionReplayStore(rootDirectory: root)
        let controller = SessionReplayController(
            config: SessionReplayConfig(enabled: true),
            store: store,
            bridge: bridge
        )
        let sourceSurface = SurfaceID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
        let targetSurface = SurfaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let prepared = try controller.startRecording(
            surfaceID: sourceSurface,
            title: "Deterministic smoke",
            mode: .manual,
            startedAt: startedAt
        )
        let cast = sixtySecondCast()
        try cast.write(to: prepared.castURL, atomically: true, encoding: .utf8)
        bridge.handle.bytesWrittenValue = cast.utf8.count

        let recording = try controller.stopRecording(
            surfaceID: sourceSurface,
            endedAt: startedAt.addingTimeInterval(60)
        )

        #expect(recording.durationNs == 60_000_000_000)
        #expect(recording.byteCount == cast.utf8.count)
        #expect(recording.surfaceID == sourceSurface)
        #expect(try store.recording(id: recording.id) == recording)

        let matches = try store.search(recordingID: recording.id, query: "final marker")
        #expect(matches.map(\.offsetNs) == [60_000_000_000])

        let exportURL = exportRoot.appendingPathComponent("deterministic-smoke.cast")
        try store.exportCast(recordingID: recording.id, to: exportURL)
        #expect(try String(contentsOf: exportURL, encoding: .utf8) == cast)

        try controller.replay(
            recordingID: recording.id,
            to: targetSurface,
            seekNs: 30_000_000_000,
            speedMultiplier: 2
        )

        #expect(bridge.replayRequests == [
            RecordingSessionReplayBridge.ReplayRequest(
                recordingURL: prepared.castURL,
                surfaceID: targetSurface,
                seekNs: 30_000_000_000,
                speedMultiplier: 2
            ),
        ])
    }

    private func sampleCast() -> String {
        """
        {"version":2,"width":80,"height":24,"timestamp":1800000000}
        [0.0,"o","hello"]

        """
    }

    private func sixtySecondCast() -> String {
        """
        {"version":2,"width":120,"height":32,"timestamp":1800000000}
        [0.0,"o","start marker\\r\\n"]
        [30.0,"o","midpoint marker\\r\\n"]
        [60.0,"o","final marker\\r\\n"]

        """
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }
}

private final class RecordingSessionReplayHandle: SessionReplayTerminalRecording {
    var isActiveValue = true
    var bytesWrittenValue = 0
    private(set) var stopCallCount = 0

    var isActive: Bool { isActiveValue }
    var bytesWritten: Int { bytesWrittenValue }

    func stop() {
        isActiveValue = false
        stopCallCount += 1
    }
}

@MainActor
private final class RecordingSessionReplayBridge: SessionReplayTerminalBridging {
    struct StartRequest: Equatable {
        let surfaceID: SurfaceID
        let outputURL: URL
        let title: String?
    }

    struct ReplayRequest: Equatable {
        let recordingURL: URL
        let surfaceID: SurfaceID
        let seekNs: UInt64
        let speedMultiplier: Float
    }

    let shouldStart: Bool
    let shouldReplay: Bool
    let handle = RecordingSessionReplayHandle()
    private(set) var startRequests: [StartRequest] = []
    private(set) var replayRequests: [ReplayRequest] = []

    init(shouldStart: Bool = true, shouldReplay: Bool = true) {
        self.shouldStart = shouldStart
        self.shouldReplay = shouldReplay
    }

    func beginSessionRecording(
        for surface: SurfaceID,
        outputURL: URL,
        title: String?
    ) -> (any SessionReplayTerminalRecording)? {
        startRequests.append(StartRequest(
            surfaceID: surface,
            outputURL: outputURL,
            title: title
        ))
        return shouldStart ? handle : nil
    }

    func replaySessionRecording(
        from recordingURL: URL,
        for surface: SurfaceID,
        seekNs: UInt64,
        speedMultiplier: Float
    ) -> Bool {
        replayRequests.append(ReplayRequest(
            recordingURL: recordingURL,
            surfaceID: surface,
            seekNs: seekNs,
            speedMultiplier: speedMultiplier
        ))
        return shouldReplay
    }
}
