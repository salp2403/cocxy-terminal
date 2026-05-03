// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceTriggerHandler.swift - Coordinates a local Voice input trigger.

import Combine
import Foundation

@MainActor
final class VoiceTriggerHandler: ObservableObject {
    typealias SessionFactory = @MainActor @Sendable (
        @escaping VoiceSession.StatusHandler,
        @escaping VoiceSession.PartialHandler
    ) -> VoiceSession
    typealias TranscriptConsumer = @MainActor @Sendable (VoiceTranscript) -> Void

    @Published private(set) var status: VoiceSessionStatus = .idle
    @Published private(set) var partialText: String = ""

    private let sessionFactory: SessionFactory
    private let transcriptConsumer: TranscriptConsumer

    init(
        sessionFactory: @escaping SessionFactory = { statusDidChange, partialDidChange in
            VoiceSession(
                statusDidChange: statusDidChange,
                partialDidChange: partialDidChange
            )
        },
        transcriptConsumer: @escaping TranscriptConsumer
    ) {
        self.sessionFactory = sessionFactory
        self.transcriptConsumer = transcriptConsumer
    }

    var isVisible: Bool {
        switch status {
        case .idle:
            return false
        case .requestingPermission, .recording, .completed, .failed:
            return true
        }
    }

    var isRunning: Bool {
        switch status {
        case .requestingPermission, .recording:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var displayText: String {
        switch status {
        case .idle:
            return ""
        case .requestingPermission:
            return "Requesting access"
        case .recording:
            return partialText.isEmpty ? "Listening" : partialText
        case .completed(let transcript):
            return transcript.text
        case .failed(let failure):
            return failure.localizedDescription
        }
    }

    var systemImageName: String {
        switch status {
        case .failed:
            return "mic.slash"
        case .completed:
            return "checkmark.circle"
        default:
            return "mic"
        }
    }

    func start(config: VoiceConfig) async {
        partialText = ""
        status = .requestingPermission

        let session = sessionFactory(
            { [weak self] newStatus in
                self?.status = newStatus
            },
            { [weak self] partial in
                self?.partialText = partial.text
            }
        )
        await session.start(config: config)

        if case .completed(let transcript) = session.status {
            transcriptConsumer(transcript)
        }
    }

    func reset() {
        status = .idle
        partialText = ""
    }
}
