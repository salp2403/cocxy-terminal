// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayController.swift - Config-gated recording and replay orchestration.

import Foundation

protocol SessionReplayTerminalRecording: AnyObject {
    var isActive: Bool { get }
    var bytesWritten: Int { get }
    func stop()
}

extension TerminalSessionRecorder: SessionReplayTerminalRecording {}

@MainActor
protocol SessionReplayTerminalBridging: AnyObject {
    func beginSessionRecording(
        for surface: SurfaceID,
        outputURL: URL,
        title: String?
    ) -> (any SessionReplayTerminalRecording)?

    func replaySessionRecording(
        from recordingURL: URL,
        for surface: SurfaceID
    ) -> Bool
}

extension CocxyCoreBridge: SessionReplayTerminalBridging {
    func beginSessionRecording(
        for surface: SurfaceID,
        outputURL: URL,
        title: String?
    ) -> (any SessionReplayTerminalRecording)? {
        startSessionRecording(for: surface, outputURL: outputURL, title: title)
    }
}

enum SessionReplayRecordingMode: Sendable, Equatable {
    case manual
    case automatic
}

enum SessionReplayControllerError: Error, Equatable, LocalizedError {
    case disabled
    case autoRecordDisabled
    case consentRequired
    case recordingAlreadyActive(SurfaceID)
    case recordingNotActive(SurfaceID)
    case bridgeStartFailed
    case replayFailed(UUID)
    case recordingTooLarge(UUID, bytesWritten: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Session replay is disabled."
        case .autoRecordDisabled:
            return "Session replay auto-record is disabled."
        case .consentRequired:
            return "Session replay auto-record requires explicit consent."
        case .recordingAlreadyActive(let surfaceID):
            return "A session replay recording is already active for surface \(surfaceID.rawValue.uuidString)."
        case .recordingNotActive(let surfaceID):
            return "No session replay recording is active for surface \(surfaceID.rawValue.uuidString)."
        case .bridgeStartFailed:
            return "Session replay recording could not start."
        case .replayFailed(let recordingID):
            return "Session replay failed for recording \(recordingID.uuidString)."
        case .recordingTooLarge(let recordingID, let bytesWritten, let limit):
            return "Session replay recording \(recordingID.uuidString) exceeded \(limit) bytes: \(bytesWritten)."
        }
    }
}

@MainActor
final class SessionReplayController {
    var config: SessionReplayConfig

    private let store: SessionReplayStore
    private let bridge: any SessionReplayTerminalBridging
    private var activeRecordings: [SurfaceID: ActiveRecording] = [:]

    init(
        config: SessionReplayConfig,
        store: SessionReplayStore = SessionReplayStore(),
        bridge: any SessionReplayTerminalBridging
    ) {
        self.config = config
        self.store = store
        self.bridge = bridge
    }

    @discardableResult
    func startRecording(
        surfaceID: SurfaceID,
        title: String,
        mode: SessionReplayRecordingMode,
        startedAt: Date = Date()
    ) throws -> SessionReplayPreparedRecording {
        try validateStart(mode: mode)
        guard activeRecordings[surfaceID] == nil else {
            throw SessionReplayControllerError.recordingAlreadyActive(surfaceID)
        }

        let prepared = try store.prepareRecording(
            title: title,
            surfaceID: surfaceID,
            createdAt: startedAt
        )

        guard let recorder = bridge.beginSessionRecording(
            for: surfaceID,
            outputURL: prepared.castURL,
            title: prepared.recording.title
        ) else {
            try? store.deleteRecording(id: prepared.recording.id)
            throw SessionReplayControllerError.bridgeStartFailed
        }

        activeRecordings[surfaceID] = ActiveRecording(
            prepared: prepared,
            recorder: recorder,
            startedAt: startedAt
        )
        return prepared
    }

    @discardableResult
    func stopRecording(
        surfaceID: SurfaceID,
        endedAt: Date = Date()
    ) throws -> SessionReplayRecording {
        guard let active = activeRecordings.removeValue(forKey: surfaceID) else {
            throw SessionReplayControllerError.recordingNotActive(surfaceID)
        }

        active.recorder.stop()
        let bytesWritten = active.recorder.bytesWritten
        let recordingID = active.prepared.recording.id
        guard bytesWritten <= config.maxRecordingBytes else {
            try? store.deleteRecording(id: recordingID)
            throw SessionReplayControllerError.recordingTooLarge(
                recordingID,
                bytesWritten: bytesWritten,
                limit: config.maxRecordingBytes
            )
        }

        try store.finishRecording(
            id: recordingID,
            durationNs: Self.durationNanoseconds(from: active.startedAt, to: endedAt),
            byteCount: bytesWritten,
            updatedAt: endedAt
        )
        return try store.recording(id: recordingID)
    }

    func replay(recordingID: UUID, to surfaceID: SurfaceID) throws {
        let recordingURL = try store.castFileURL(for: recordingID)
        guard bridge.replaySessionRecording(from: recordingURL, for: surfaceID) else {
            throw SessionReplayControllerError.replayFailed(recordingID)
        }
    }

    func activeRecording(for surfaceID: SurfaceID) -> SessionReplayRecording? {
        activeRecordings[surfaceID]?.prepared.recording
    }

    private func validateStart(mode: SessionReplayRecordingMode) throws {
        guard config.enabled else {
            throw SessionReplayControllerError.disabled
        }

        if mode == .automatic {
            guard config.autoRecord else {
                throw SessionReplayControllerError.autoRecordDisabled
            }
            guard config.consentGranted else {
                throw SessionReplayControllerError.consentRequired
            }
        }
    }

    private static func durationNanoseconds(from start: Date, to end: Date) -> UInt64 {
        let elapsed = max(0, end.timeIntervalSince(start))
        let maxSeconds = Double(UInt64.max) / 1_000_000_000
        return UInt64(min(elapsed, maxSeconds) * 1_000_000_000)
    }

    private struct ActiveRecording {
        let prepared: SessionReplayPreparedRecording
        let recorder: any SessionReplayTerminalRecording
        let startedAt: Date
    }
}
