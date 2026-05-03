// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoiceAuthorization.swift - Local speech and microphone authorization models.

import Foundation

/// Authorization state for one local Voice capability.
enum VoiceAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
    case unavailable
}

/// Combined local permissions needed before recording or transcribing speech.
struct VoiceAuthorizationState: Sendable, Equatable {
    let speech: VoiceAuthorizationStatus
    let microphone: VoiceAuthorizationStatus

    static let notDetermined = VoiceAuthorizationState(
        speech: .notDetermined,
        microphone: .notDetermined
    )

    static let authorized = VoiceAuthorizationState(
        speech: .authorized,
        microphone: .authorized
    )

    var isAuthorized: Bool {
        speech == .authorized && microphone == .authorized
    }

    var requiresPrompt: Bool {
        speech == .notDetermined || microphone == .notDetermined
    }
}

/// Requests local speech and microphone permissions.
protocol VoicePermissionManaging: Sendable {
    func currentAuthorizationState() async -> VoiceAuthorizationState
    func requestAuthorization() async -> VoiceAuthorizationState
}
