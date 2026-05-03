// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PlatformVoicePermissionManager.swift - macOS Speech and microphone permission bridge.

import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
import Speech
#endif

struct PlatformVoicePermissionManager: VoicePermissionManaging {
    func currentAuthorizationState() async -> VoiceAuthorizationState {
        VoiceAuthorizationState(
            speech: Self.currentSpeechAuthorizationStatus(),
            microphone: Self.currentMicrophoneAuthorizationStatus()
        )
    }

    func requestAuthorization() async -> VoiceAuthorizationState {
        async let speech = Self.requestSpeechAuthorization()
        async let microphone = Self.requestMicrophoneAuthorization()
        return await VoiceAuthorizationState(speech: speech, microphone: microphone)
    }

    private static func currentSpeechAuthorizationStatus() -> VoiceAuthorizationStatus {
        #if canImport(Speech)
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private static func requestSpeechAuthorization() async -> VoiceAuthorizationStatus {
        #if canImport(Speech)
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .notDetermined:
                    continuation.resume(returning: .notDetermined)
                case .denied:
                    continuation.resume(returning: .denied)
                case .restricted:
                    continuation.resume(returning: .restricted)
                case .authorized:
                    continuation.resume(returning: .authorized)
                @unknown default:
                    continuation.resume(returning: .unavailable)
                }
            }
        }
        #else
        return .unavailable
        #endif
    }

    private static func currentMicrophoneAuthorizationStatus() -> VoiceAuthorizationStatus {
        #if canImport(AVFoundation)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private static func requestMicrophoneAuthorization() async -> VoiceAuthorizationStatus {
        #if canImport(AVFoundation)
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .authorized : currentMicrophoneAuthorizationStatus()
        #else
        return .unavailable
        #endif
    }
}
