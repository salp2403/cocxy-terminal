// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SpeechVoiceTranscriberSwiftTestingTests.swift - Local Speech transcriber contract coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SpeechVoiceTranscriber")
struct SpeechVoiceTranscriberSwiftTestingTests {
    @Test("transcriber forces on-device recognition and forwards partials")
    @MainActor
    func transcriberForcesOnDeviceRecognitionAndForwardsPartials() async throws {
        let runner = RecordingSpeechRecognitionRunner(
            partials: [
                VoiceTranscript(text: " open ", localeIdentifier: "es_ES", isFinal: false),
                VoiceTranscript(text: "open notes", localeIdentifier: "es-ES", isFinal: false),
            ],
            result: VoiceTranscript(text: "open notes", localeIdentifier: "es-ES", isFinal: true)
        )
        let transcriber = SpeechVoiceTranscriber(
            configuration: SpeechVoiceTranscriberConfiguration(
                maximumDuration: 12,
                requiresOnDeviceRecognition: true,
                reportPartialResults: true
            ),
            runner: runner
        )
        var partials: [VoiceTranscript] = []

        let transcript = try await transcriber.transcribe(localeIdentifier: "es_ES") { partial in
            partials.append(partial)
        }

        #expect(transcript == VoiceTranscript(text: "open notes", localeIdentifier: "es-ES", isFinal: true))
        #expect(partials.map(\.text) == ["open", "open notes"])
        #expect(runner.calls == [
            SpeechRecognitionRunnerCall(
                localeIdentifier: "es-ES",
                maximumDuration: 12,
                requiresOnDeviceRecognition: true,
                reportPartialResults: true
            ),
        ])
    }

    @Test("blank final transcript fails closed")
    @MainActor
    func blankFinalTranscriptFailsClosed() async {
        let runner = RecordingSpeechRecognitionRunner(
            partials: [],
            result: VoiceTranscript(text: "   ", localeIdentifier: "en-US", isFinal: true)
        )
        let transcriber = SpeechVoiceTranscriber(runner: runner)

        await #expect(throws: VoiceSessionFailure.transcriptionFailed("Speech recognition returned an empty transcript.")) {
            _ = try await transcriber.transcribe(localeIdentifier: "en-US") { _ in }
        }
    }
}

private struct SpeechRecognitionRunnerCall: Equatable {
    let localeIdentifier: String
    let maximumDuration: TimeInterval
    let requiresOnDeviceRecognition: Bool
    let reportPartialResults: Bool
}

private final class RecordingSpeechRecognitionRunner: SpeechRecognitionRunning, @unchecked Sendable {
    private(set) var calls: [SpeechRecognitionRunnerCall] = []
    private let partials: [VoiceTranscript]
    private let result: VoiceTranscript

    init(partials: [VoiceTranscript], result: VoiceTranscript) {
        self.partials = partials
        self.result = result
    }

    func run(
        localeIdentifier: String,
        maximumDuration: TimeInterval,
        requiresOnDeviceRecognition: Bool,
        reportPartialResults: Bool,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript {
        calls.append(SpeechRecognitionRunnerCall(
            localeIdentifier: localeIdentifier,
            maximumDuration: maximumDuration,
            requiresOnDeviceRecognition: requiresOnDeviceRecognition,
            reportPartialResults: reportPartialResults
        ))
        for partial in partials {
            await onPartial(partial)
        }
        return result
    }
}
