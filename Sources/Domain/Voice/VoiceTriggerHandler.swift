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
        Self.displayText(for: status, partialText: partialText)
    }

    func displayText(using localizer: AppLocalizer) -> String {
        Self.localizedDisplayText(for: status, partialText: partialText, using: localizer)
    }

    static func localizedDisplayText(
        for status: VoiceSessionStatus,
        partialText: String,
        using localizer: AppLocalizer
    ) -> String {
        switch status {
        case .idle:
            return ""
        case .requestingPermission:
            return localizer.string("voice.indicator.requestingAccess", fallback: "Requesting access")
        case .recording:
            return partialText.isEmpty
                ? localizer.string("voice.indicator.listening", fallback: "Listening")
                : partialText
        case .completed(let transcript):
            return transcript.text
        case .failed(let failure):
            return localizedFailureDescription(failure, using: localizer)
        }
    }

    private static func displayText(for status: VoiceSessionStatus, partialText: String) -> String {
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

    private static func localizedFailureDescription(
        _ failure: VoiceSessionFailure,
        using localizer: AppLocalizer
    ) -> String {
        switch failure {
        case .disabled:
            return localizer.string("voice.failure.disabled", fallback: "Voice input is disabled.")
        case .localeUnavailable:
            return localizer.string(
                "voice.failure.localeUnavailable",
                fallback: "No local speech recognition locale is available."
            )
        case .permissionDenied:
            return localizer.string(
                "voice.failure.permissionDenied",
                fallback: "Voice input needs Speech Recognition and Microphone permission."
            )
        case .transcriberUnavailable:
            return localizer.string(
                "voice.failure.transcriberUnavailable",
                fallback: "Local speech recognition is unavailable on this Mac."
            )
        case .transcriptionFailed(let message):
            return message
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
