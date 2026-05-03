// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceSessionSwiftTestingTests.swift - Local Voice session state machine coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("VoiceSession")
struct VoiceSessionSwiftTestingTests {
    @Test("disabled config fails closed before permissions or transcription")
    @MainActor
    func disabledConfigFailsClosed() async {
        let permissions = RecordingVoicePermissionManager(
            current: .authorized,
            requested: .authorized
        )
        let transcriber = RecordingVoiceTranscriber(result: VoiceTranscript(
            text: "ignored",
            localeIdentifier: "en-US",
            isFinal: true
        ))
        let session = VoiceSession(
            localeResolver: resolver(supported: ["en-US"]),
            permissionManager: permissions,
            transcriber: transcriber
        )

        await session.start(config: VoiceConfig(enabled: false, localeIdentifier: "system"))

        #expect(session.status == .failed(.disabled))
        #expect(permissions.requestCount == 0)
        #expect(transcriber.calls.isEmpty)
    }

    @Test("unavailable locale fails before prompting for microphone or speech")
    @MainActor
    func unavailableLocaleFailsBeforePermissionPrompt() async {
        let permissions = RecordingVoicePermissionManager(
            current: .authorized,
            requested: .authorized
        )
        let transcriber = RecordingVoiceTranscriber(result: VoiceTranscript(
            text: "ignored",
            localeIdentifier: "en-US",
            isFinal: true
        ))
        let session = VoiceSession(
            localeResolver: resolver(supported: []),
            permissionManager: permissions,
            transcriber: transcriber
        )

        await session.start(config: VoiceConfig(enabled: true, localeIdentifier: "system"))

        #expect(session.status == .failed(.localeUnavailable))
        #expect(permissions.requestCount == 0)
        #expect(transcriber.calls.isEmpty)
    }

    @Test("denied authorization is reported without starting transcription")
    @MainActor
    func deniedAuthorizationStopsBeforeTranscription() async {
        let denied = VoiceAuthorizationState(speech: .authorized, microphone: .denied)
        let permissions = RecordingVoicePermissionManager(current: .notDetermined, requested: denied)
        let transcriber = RecordingVoiceTranscriber(result: VoiceTranscript(
            text: "ignored",
            localeIdentifier: "en-US",
            isFinal: true
        ))
        let session = VoiceSession(
            localeResolver: resolver(supported: ["en-US"]),
            permissionManager: permissions,
            transcriber: transcriber
        )

        await session.start(config: VoiceConfig(enabled: true, localeIdentifier: "system"))

        #expect(session.status == .failed(.permissionDenied(denied)))
        #expect(permissions.requestCount == 1)
        #expect(transcriber.calls.isEmpty)
    }

    @Test("authorized session records final transcript and partial updates")
    @MainActor
    func authorizedSessionRecordsFinalTranscriptAndPartialUpdates() async {
        let permissions = RecordingVoicePermissionManager(
            current: .authorized,
            requested: .authorized
        )
        let transcriber = RecordingVoiceTranscriber(
            partials: [
                VoiceTranscript(text: "open", localeIdentifier: "es-ES", isFinal: false),
                VoiceTranscript(text: "open notes", localeIdentifier: "es-ES", isFinal: false),
            ],
            result: VoiceTranscript(text: "open notes", localeIdentifier: "es-ES", isFinal: true)
        )
        let session = VoiceSession(
            localeResolver: resolver(supported: ["en-US", "es-ES"], system: "es-HN"),
            permissionManager: permissions,
            transcriber: transcriber
        )

        await session.start(config: VoiceConfig(enabled: true, localeIdentifier: "system"))

        #expect(session.status == .completed(VoiceTranscript(
            text: "open notes",
            localeIdentifier: "es-ES",
            isFinal: true
        )))
        #expect(session.partialTranscripts.map(\.text) == ["open", "open notes"])
        #expect(transcriber.calls == ["es-ES"])
    }
}

private final class RecordingVoicePermissionManager: VoicePermissionManaging, @unchecked Sendable {
    private(set) var requestCount = 0
    private let current: VoiceAuthorizationState
    private let requested: VoiceAuthorizationState

    init(current: VoiceAuthorizationState, requested: VoiceAuthorizationState) {
        self.current = current
        self.requested = requested
    }

    func currentAuthorizationState() async -> VoiceAuthorizationState {
        current
    }

    func requestAuthorization() async -> VoiceAuthorizationState {
        requestCount += 1
        return requested
    }
}

private final class RecordingVoiceTranscriber: VoiceTranscribing, @unchecked Sendable {
    private(set) var calls: [String] = []
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
        calls.append(localeIdentifier)
        for partial in partials {
            await onPartial(partial)
        }
        return result
    }
}

private func resolver(
    supported identifiers: Set<String>,
    system systemIdentifier: String = "en-US"
) -> VoiceLocaleResolver {
    VoiceLocaleResolver(
        supportedLocales: Set(identifiers.map { Locale(identifier: $0) }),
        systemLocale: Locale(identifier: systemIdentifier)
    )
}
