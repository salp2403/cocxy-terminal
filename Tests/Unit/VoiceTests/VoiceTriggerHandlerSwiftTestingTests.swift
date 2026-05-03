// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceTriggerHandlerSwiftTestingTests.swift - Voice trigger coordinator coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("VoiceTriggerHandler")
struct VoiceTriggerHandlerSwiftTestingTests {
    @Test("handler publishes status partials and delivers final transcript")
    @MainActor
    func handlerPublishesStatusPartialsAndDeliversFinalTranscript() async {
        var delivered: VoiceTranscript?
        let handler = VoiceTriggerHandler(
            sessionFactory: { statusDidChange, partialDidChange in
                VoiceSession(
                    localeResolver: VoiceLocaleResolver(
                        supportedLocales: [Locale(identifier: "en-US")],
                        systemLocale: Locale(identifier: "en-US")
                    ),
                    permissionManager: RecordingVoicePermissionManager(),
                    transcriber: RecordingVoiceTranscriber(
                        partials: [
                            VoiceTranscript(text: "open", localeIdentifier: "en-US", isFinal: false),
                        ],
                        result: VoiceTranscript(text: "open notes", localeIdentifier: "en-US", isFinal: true)
                    ),
                    statusDidChange: statusDidChange,
                    partialDidChange: partialDidChange
                )
            },
            transcriptConsumer: { transcript in
                delivered = transcript
            }
        )

        await handler.start(config: VoiceConfig(enabled: true, localeIdentifier: "system"))

        #expect(handler.status == .completed(VoiceTranscript(
            text: "open notes",
            localeIdentifier: "en-US",
            isFinal: true
        )))
        #expect(handler.partialText == "open")
        #expect(handler.isVisible == true)
        #expect(delivered == VoiceTranscript(text: "open notes", localeIdentifier: "en-US", isFinal: true))
    }

    @Test("handler does not deliver transcript when Voice is disabled")
    @MainActor
    func handlerDoesNotDeliverTranscriptWhenVoiceIsDisabled() async {
        var delivered: VoiceTranscript?
        let handler = VoiceTriggerHandler(
            sessionFactory: { statusDidChange, partialDidChange in
                VoiceSession(
                    localeResolver: VoiceLocaleResolver(
                        supportedLocales: [Locale(identifier: "en-US")],
                        systemLocale: Locale(identifier: "en-US")
                    ),
                    permissionManager: RecordingVoicePermissionManager(),
                    transcriber: RecordingVoiceTranscriber(
                        result: VoiceTranscript(text: "ignored", localeIdentifier: "en-US", isFinal: true)
                    ),
                    statusDidChange: statusDidChange,
                    partialDidChange: partialDidChange
                )
            },
            transcriptConsumer: { transcript in
                delivered = transcript
            }
        )

        await handler.start(config: VoiceConfig(enabled: false, localeIdentifier: "system"))

        #expect(handler.status == .failed(.disabled))
        #expect(handler.displayText == "Voice input is disabled.")
        #expect(delivered == nil)
    }
}

private final class RecordingVoicePermissionManager: VoicePermissionManaging, @unchecked Sendable {
    func currentAuthorizationState() async -> VoiceAuthorizationState {
        .authorized
    }

    func requestAuthorization() async -> VoiceAuthorizationState {
        .authorized
    }
}

private final class RecordingVoiceTranscriber: VoiceTranscribing, @unchecked Sendable {
    private let partials: [VoiceTranscript]
    private let result: VoiceTranscript

    init(partials: [VoiceTranscript] = [], result: VoiceTranscript) {
        self.partials = partials
        self.result = result
    }

    func transcribe(
        localeIdentifier: String,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript {
        for partial in partials {
            await onPartial(partial)
        }
        return result
    }
}
