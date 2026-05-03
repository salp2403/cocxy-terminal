// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceTranscribing.swift - Local Voice transcription contracts.

import Foundation

/// A partial or final local speech recognition result.
struct VoiceTranscript: Sendable, Equatable {
    let text: String
    let localeIdentifier: String
    let isFinal: Bool

    init(text: String, localeIdentifier: String, isFinal: Bool) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.localeIdentifier = VoiceConfig.normalizedLocaleIdentifier(localeIdentifier)
        self.isFinal = isFinal
    }
}

/// Runs local transcription and emits partial updates as they arrive.
protocol VoiceTranscribing: Sendable {
    func transcribe(
        localeIdentifier: String,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript
}

/// Fallback transcriber used on platforms where Speech is unavailable.
struct UnavailableVoiceTranscriber: VoiceTranscribing {
    func transcribe(
        localeIdentifier: String,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript {
        throw VoiceSessionFailure.transcriberUnavailable
    }
}
