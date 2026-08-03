// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalPasteDelivery.swift - Ordered, cancellable terminal paste delivery.

import Foundation

struct TerminalPasteDeliveryConfiguration: Equatable, Sendable {
    let usesBracketedPaste: Bool
    let agentPaced: Bool
    let normalizesText: Bool

    init(
        usesBracketedPaste: Bool,
        agentPaced: Bool,
        normalizesText: Bool = true
    ) {
        self.usesBracketedPaste = usesBracketedPaste
        self.agentPaced = agentPaced
        self.normalizesText = normalizesText
    }
}

struct TerminalPasteDeliveryTiming: Equatable, Sendable {
    let standardChunkMaxUTF8Bytes: Int
    let agentChunkMaxUTF8Bytes: Int
    let standardDelayNanoseconds: UInt64
    let agentDelayNanoseconds: UInt64

    static let production = TerminalPasteDeliveryTiming(
        standardChunkMaxUTF8Bytes: 512,
        agentChunkMaxUTF8Bytes: 128,
        standardDelayNanoseconds: 6_000_000,
        agentDelayNanoseconds: 18_000_000
    )
}

enum TerminalPasteDelivery {
    static let bracketedPasteStart = "\u{1B}[200~"
    static let bracketedPasteEnd = "\u{1B}[201~"

    nonisolated static func normalizedText(_ text: String) -> String {
        let lineNormalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(lineNormalized.unicodeScalars.count)
        for scalar in lineNormalized.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A:
                scalars.append(scalar)
            case 0x00...0x1F, 0x7F:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    nonisolated static func chunks(
        for text: String,
        maxUTF8Bytes: Int
    ) -> [String] {
        guard maxUTF8Bytes > 0 else { return text.isEmpty ? [] : [text] }

        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for character in text {
            let characterText = String(character)
            let byteCount = characterText.utf8.count
            if currentBytes > 0, currentBytes + byteCount > maxUTF8Bytes {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += byteCount
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    @MainActor
    fileprivate static func deliver(
        _ text: String,
        configuration: TerminalPasteDeliveryConfiguration,
        timing: TerminalPasteDeliveryTiming,
        bracketState: TerminalPasteBracketState,
        isAvailable: @escaping @MainActor () -> Bool,
        sendText: @escaping @MainActor (String) -> Bool
    ) async -> Bool {
        let payload = configuration.normalizesText ? normalizedText(text) : text
        let maximumBytes = configuration.agentPaced
            ? timing.agentChunkMaxUTF8Bytes
            : timing.standardChunkMaxUTF8Bytes
        let chunks = chunks(for: payload, maxUTF8Bytes: maximumBytes)
        guard !chunks.isEmpty, isAvailable() else { return false }

        defer {
            if bracketState.isOpen, isAvailable() {
                _ = sendText(bracketedPasteEnd)
                bracketState.isOpen = false
            }
        }

        var startIndex = 0
        if configuration.usesBracketedPaste {
            bracketState.isOpen = true
            guard sendText(bracketedPasteStart + chunks[0]) else { return false }
            startIndex = 1
            guard await pauseIfNeeded(
                afterChunkAt: 0,
                chunkCount: chunks.count,
                configuration: configuration,
                timing: timing
            ) else { return false }
        }

        for index in startIndex..<chunks.count {
            guard !Task.isCancelled, isAvailable(), sendText(chunks[index]) else {
                return false
            }
            guard await pauseIfNeeded(
                afterChunkAt: index,
                chunkCount: chunks.count,
                configuration: configuration,
                timing: timing
            ) else { return false }
        }

        guard !Task.isCancelled, isAvailable() else { return false }
        if bracketState.isOpen {
            let closed = sendText(bracketedPasteEnd)
            bracketState.isOpen = false
            return closed
        }
        return true
    }

    @MainActor
    private static func pauseIfNeeded(
        afterChunkAt index: Int,
        chunkCount: Int,
        configuration: TerminalPasteDeliveryConfiguration,
        timing: TerminalPasteDeliveryTiming
    ) async -> Bool {
        guard index + 1 < chunkCount else { return !Task.isCancelled }
        let delay = configuration.agentPaced
            ? timing.agentDelayNanoseconds
            : timing.standardDelayNanoseconds
        guard delay > 0 else { return !Task.isCancelled }
        do {
            try await Task.sleep(nanoseconds: delay)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

@MainActor
private final class TerminalPasteBracketState {
    var isOpen = false
}

@MainActor
final class TerminalPasteDeliveryCoordinator {
    private struct Session {
        let id: UUID
        let task: Task<Bool, Never>
        let closeActiveBracket: @MainActor () -> Void
    }

    private let timing: TerminalPasteDeliveryTiming
    private var sessions: [SurfaceID: Session] = [:]

    init(timing: TerminalPasteDeliveryTiming = .production) {
        self.timing = timing
    }

    func deliver(
        _ text: String,
        to surfaceID: SurfaceID,
        configuration: TerminalPasteDeliveryConfiguration,
        isAvailable: @escaping @MainActor () -> Bool,
        sendText: @escaping @MainActor (String) -> Bool
    ) async -> Bool {
        let previousSession = sessions[surfaceID]
        previousSession?.closeActiveBracket()
        previousSession?.task.cancel()
        let previousTask = previousSession?.task
        let sessionID = UUID()
        let timing = timing
        let bracketState = TerminalPasteBracketState()
        let closeActiveBracket = {
            guard bracketState.isOpen else { return }
            if isAvailable() { _ = sendText(TerminalPasteDelivery.bracketedPasteEnd) }
            bracketState.isOpen = false
        }
        let task = Task { @MainActor in
            _ = await previousTask?.value
            guard !Task.isCancelled else { return false }
            return await TerminalPasteDelivery.deliver(
                text,
                configuration: configuration,
                timing: timing,
                bracketState: bracketState,
                isAvailable: isAvailable,
                sendText: sendText
            )
        }
        sessions[surfaceID] = Session(
            id: sessionID,
            task: task,
            closeActiveBracket: closeActiveBracket
        )

        let delivered = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if sessions[surfaceID]?.id == sessionID {
            sessions.removeValue(forKey: surfaceID)
        }
        return delivered
    }

    func cancel(surfaceID: SurfaceID) {
        guard let session = sessions.removeValue(forKey: surfaceID) else { return }
        session.closeActiveBracket()
        session.task.cancel()
    }

    func cancelAll() {
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        for session in activeSessions {
            session.closeActiveBracket()
            session.task.cancel()
        }
    }
}
