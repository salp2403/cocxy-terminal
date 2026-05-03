// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SpeechVoiceTranscriber.swift - Local Speech.framework transcription.

import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
import Speech
#endif

/// Runtime knobs for local speech recognition.
struct SpeechVoiceTranscriberConfiguration: Sendable, Equatable {
    let maximumDuration: TimeInterval
    let requiresOnDeviceRecognition: Bool
    let reportPartialResults: Bool

    static let defaults = SpeechVoiceTranscriberConfiguration(
        maximumDuration: 30,
        requiresOnDeviceRecognition: true,
        reportPartialResults: true
    )

    init(
        maximumDuration: TimeInterval = Self.defaults.maximumDuration,
        requiresOnDeviceRecognition: Bool = Self.defaults.requiresOnDeviceRecognition,
        reportPartialResults: Bool = Self.defaults.reportPartialResults
    ) {
        self.maximumDuration = max(1, maximumDuration)
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.reportPartialResults = reportPartialResults
    }
}

/// Testable runner boundary around Speech.framework and AVAudioEngine.
protocol SpeechRecognitionRunning: Sendable {
    func run(
        localeIdentifier: String,
        maximumDuration: TimeInterval,
        requiresOnDeviceRecognition: Bool,
        reportPartialResults: Bool,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript
}

/// Voice transcriber backed by Apple's local Speech recognizer.
final class SpeechVoiceTranscriber: VoiceTranscribing, @unchecked Sendable {
    private let configuration: SpeechVoiceTranscriberConfiguration
    private let runner: any SpeechRecognitionRunning

    init(
        configuration: SpeechVoiceTranscriberConfiguration = .defaults,
        runner: any SpeechRecognitionRunning = PlatformSpeechRecognitionRunner()
    ) {
        self.configuration = configuration
        self.runner = runner
    }

    func transcribe(
        localeIdentifier: String,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript {
        let normalizedLocale = VoiceConfig.normalizedLocaleIdentifier(localeIdentifier)
        let transcript = try await runner.run(
            localeIdentifier: normalizedLocale,
            maximumDuration: configuration.maximumDuration,
            requiresOnDeviceRecognition: configuration.requiresOnDeviceRecognition,
            reportPartialResults: configuration.reportPartialResults,
            onPartial: onPartial
        )
        guard !transcript.text.isEmpty else {
            throw VoiceSessionFailure.transcriptionFailed("Speech recognition returned an empty transcript.")
        }
        return VoiceTranscript(
            text: transcript.text,
            localeIdentifier: transcript.localeIdentifier,
            isFinal: true
        )
    }
}

#if canImport(AVFoundation) && canImport(Speech)
private struct PlatformSpeechRecognitionRunner: SpeechRecognitionRunning {
    func run(
        localeIdentifier: String,
        maximumDuration: TimeInterval,
        requiresOnDeviceRecognition: Bool,
        reportPartialResults: Bool,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            throw VoiceSessionFailure.transcriberUnavailable
        }
        if requiresOnDeviceRecognition, !recognizer.supportsOnDeviceRecognition {
            throw VoiceSessionFailure.transcriberUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let run = SpeechRecognitionAudioEngineRun(
                localeIdentifier: localeIdentifier,
                recognizer: recognizer,
                maximumDuration: maximumDuration,
                requiresOnDeviceRecognition: requiresOnDeviceRecognition,
                reportPartialResults: reportPartialResults,
                onPartial: onPartial,
                continuation: continuation
            )
            run.start()
        }
    }
}

private final class SpeechRecognitionAudioEngineRun: @unchecked Sendable {
    private let localeIdentifier: String
    private let recognizer: SFSpeechRecognizer
    private let maximumDuration: TimeInterval
    private let requiresOnDeviceRecognition: Bool
    private let reportPartialResults: Bool
    private let onPartial: @MainActor @Sendable (VoiceTranscript) -> Void
    private let continuation: CheckedContinuation<VoiceTranscript, Error>

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var installedTap = false
    private var latestTranscript: VoiceTranscript?
    private var finished = false

    init(
        localeIdentifier: String,
        recognizer: SFSpeechRecognizer,
        maximumDuration: TimeInterval,
        requiresOnDeviceRecognition: Bool,
        reportPartialResults: Bool,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void,
        continuation: CheckedContinuation<VoiceTranscript, Error>
    ) {
        self.localeIdentifier = localeIdentifier
        self.recognizer = recognizer
        self.maximumDuration = maximumDuration
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.reportPartialResults = reportPartialResults
        self.onPartial = onPartial
        self.continuation = continuation
    }

    func start() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = reportPartialResults
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        request.taskHint = .dictation
        self.request = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            finish(.failure(VoiceSessionFailure.transcriptionFailed("No microphone input format is available.")))
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognition(result: result, error: error)
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        installedTap = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            finish(.failure(VoiceSessionFailure.transcriptionFailed(error.localizedDescription)))
            return
        }

        let timeoutNanoseconds = UInt64(maximumDuration * 1_000_000_000)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            self?.finishAfterTimeout()
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let transcript = VoiceTranscript(
                text: result.bestTranscription.formattedString,
                localeIdentifier: localeIdentifier,
                isFinal: result.isFinal
            )
            if !transcript.text.isEmpty {
                lock.lock()
                latestTranscript = transcript
                lock.unlock()
                Task { @MainActor in
                    onPartial(transcript)
                }
            }
            if result.isFinal {
                finish(.success(transcript))
                return
            }
        }

        if let error {
            finish(.failure(VoiceSessionFailure.transcriptionFailed(error.localizedDescription)))
        }
    }

    private func finishAfterTimeout() {
        lock.lock()
        let transcript = latestTranscript
        lock.unlock()

        if let transcript, !transcript.text.isEmpty {
            finish(.success(VoiceTranscript(
                text: transcript.text,
                localeIdentifier: transcript.localeIdentifier,
                isFinal: true
            )))
        } else {
            finish(.failure(VoiceSessionFailure.transcriptionFailed("No speech was recognized before the recording timed out.")))
        }
    }

    private func finish(_ result: Result<VoiceTranscript, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let request = self.request
        let task = self.task
        let timeoutTask = self.timeoutTask
        let shouldRemoveTap = installedTap
        lock.unlock()

        timeoutTask?.cancel()
        request?.endAudio()
        engine.stop()
        if shouldRemoveTap {
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()

        switch result {
        case .success(let transcript):
            continuation.resume(returning: transcript)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
#else
private struct PlatformSpeechRecognitionRunner: SpeechRecognitionRunning {
    func run(
        localeIdentifier: String,
        maximumDuration: TimeInterval,
        requiresOnDeviceRecognition: Bool,
        reportPartialResults: Bool,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript {
        throw VoiceSessionFailure.transcriberUnavailable
    }
}
#endif
