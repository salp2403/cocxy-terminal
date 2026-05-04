// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroRecorder.swift - Deterministic local macro recording.

import Foundation

enum MacroRecorderError: Error, Equatable, Sendable {
    case alreadyRecording
    case notRecording
    case emptyMacro
}

struct MacroRecorder: Sendable {
    private struct Recording: Sendable {
        let id: String
        let name: String
        let startedAt: Date
        var events: [MacroEvent]
    }

    private var recording: Recording?

    var isRecording: Bool { recording != nil }

    mutating func start(
        id: String = UUID().uuidString,
        name: String,
        at date: Date = Date()
    ) throws {
        guard recording == nil else {
            throw MacroRecorderError.alreadyRecording
        }
        recording = Recording(
            id: id,
            name: name,
            startedAt: date,
            events: []
        )
    }

    mutating func record(_ event: MacroEvent) throws {
        guard recording != nil else {
            throw MacroRecorderError.notRecording
        }
        recording?.events.append(event)
    }

    mutating func cancel() {
        recording = nil
    }

    mutating func stop(at date: Date = Date()) throws -> TerminalMacro {
        guard let current = recording else {
            throw MacroRecorderError.notRecording
        }
        guard !current.events.isEmpty else {
            recording = nil
            throw MacroRecorderError.emptyMacro
        }
        recording = nil
        return TerminalMacro(
            id: current.id,
            name: current.name,
            events: current.events,
            createdAt: current.startedAt,
            updatedAt: date
        )
    }
}
