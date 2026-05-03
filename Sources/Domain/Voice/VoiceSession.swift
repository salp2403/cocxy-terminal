// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceSession.swift - Local Voice input session state machine.

import Foundation

/// Failures surfaced by the local Voice session before any UI decides how to present them.
enum VoiceSessionFailure: Error, LocalizedError, Sendable, Equatable {
    case disabled
    case localeUnavailable
    case permissionDenied(VoiceAuthorizationState)
    case transcriberUnavailable
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Voice input is disabled."
        case .localeUnavailable:
            return "No local speech recognition locale is available."
        case .permissionDenied:
            return "Voice input needs Speech Recognition and Microphone permission."
        case .transcriberUnavailable:
            return "Local speech recognition is unavailable on this Mac."
        case .transcriptionFailed(let message):
            return message
        }
    }
}

/// User-visible lifecycle state for a single Voice input attempt.
enum VoiceSessionStatus: Sendable, Equatable {
    case idle
    case requestingPermission
    case recording(localeIdentifier: String)
    case completed(VoiceTranscript)
    case failed(VoiceSessionFailure)
}

@MainActor
final class VoiceSession {
    private let localeResolver: VoiceLocaleResolver
    private let permissionManager: any VoicePermissionManaging
    private let transcriber: any VoiceTranscribing

    private(set) var status: VoiceSessionStatus = .idle
    private(set) var partialTranscripts: [VoiceTranscript] = []

    init(
        localeResolver: VoiceLocaleResolver = .live(),
        permissionManager: any VoicePermissionManaging = PlatformVoicePermissionManager(),
        transcriber: any VoiceTranscribing = UnavailableVoiceTranscriber()
    ) {
        self.localeResolver = localeResolver
        self.permissionManager = permissionManager
        self.transcriber = transcriber
    }

    func start(config: VoiceConfig) async {
        partialTranscripts.removeAll()

        guard config.enabled else {
            status = .failed(.disabled)
            return
        }

        let localeResolution = localeResolver.resolve(config: config)
        guard let localeIdentifier = localeResolution.localeIdentifier else {
            status = .failed(.localeUnavailable)
            return
        }

        var authorizationState = await permissionManager.currentAuthorizationState()
        if authorizationState.requiresPrompt {
            status = .requestingPermission
            authorizationState = await permissionManager.requestAuthorization()
        }
        guard authorizationState.isAuthorized else {
            status = .failed(.permissionDenied(authorizationState))
            return
        }

        status = .recording(localeIdentifier: localeIdentifier)
        do {
            let transcript = try await transcriber.transcribe(localeIdentifier: localeIdentifier) { [weak self] partial in
                self?.partialTranscripts.append(partial)
            }
            status = .completed(transcript)
        } catch let failure as VoiceSessionFailure {
            status = .failed(failure)
        } catch {
            status = .failed(.transcriptionFailed(error.localizedDescription))
        }
    }
}
