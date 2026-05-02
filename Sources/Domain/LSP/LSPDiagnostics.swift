// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPDiagnostics.swift - Diagnostics and source locations for LSP events.

import Foundation

struct LSPPosition: Equatable, Sendable {
    let line: Int
    let character: Int

    init(line: Int, character: Int) {
        self.line = max(0, line)
        self.character = max(0, character)
    }

    var jsonValue: LSPJSONValue {
        .object([
            "line": .number(Double(line)),
            "character": .number(Double(character)),
        ])
    }

    init?(jsonValue: LSPJSONValue) {
        guard let object = jsonValue.objectValue,
              let line = object["line"]?.intValue,
              let character = object["character"]?.intValue else {
            return nil
        }
        self.init(line: line, character: character)
    }
}

struct LSPRange: Equatable, Sendable {
    let start: LSPPosition
    let end: LSPPosition

    static let zero = LSPRange(
        start: LSPPosition(line: 0, character: 0),
        end: LSPPosition(line: 0, character: 0)
    )

    var jsonValue: LSPJSONValue {
        .object([
            "start": start.jsonValue,
            "end": end.jsonValue,
        ])
    }

    init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }

    init?(jsonValue: LSPJSONValue) {
        guard let object = jsonValue.objectValue,
              let startValue = object["start"],
              let endValue = object["end"],
              let start = LSPPosition(jsonValue: startValue),
              let end = LSPPosition(jsonValue: endValue) else {
            return nil
        }
        self.init(start: start, end: end)
    }
}

enum LSPDiagnosticSeverity: Int, Equatable, Sendable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

struct LSPDiagnostic: Equatable, Sendable {
    let range: LSPRange
    let severity: LSPDiagnosticSeverity
    let message: String
    let source: String?

    var jsonValue: LSPJSONValue {
        var object: [String: LSPJSONValue] = [
            "range": range.jsonValue,
            "severity": .number(Double(severity.rawValue)),
            "message": .string(message),
        ]
        if let source {
            object["source"] = .string(source)
        }
        return .object(object)
    }

    init(
        range: LSPRange,
        severity: LSPDiagnosticSeverity,
        message: String,
        source: String? = nil
    ) {
        self.range = range
        self.severity = severity
        self.message = message
        self.source = source
    }

    init?(jsonValue: LSPJSONValue) {
        guard let object = jsonValue.objectValue,
              let rangeValue = object["range"],
              let range = LSPRange(jsonValue: rangeValue),
              let message = object["message"]?.stringValue else {
            return nil
        }

        let severity = object["severity"]?.intValue.flatMap(LSPDiagnosticSeverity.init(rawValue:))
            ?? .information

        self.init(
            range: range,
            severity: severity,
            message: message,
            source: object["source"]?.stringValue
        )
    }
}
