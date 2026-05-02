// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPEditorBridge.swift - Maps local LSP events into editor domain models.

import Foundation

enum LSPEditorBridge {
    static func decorations(
        from diagnostics: [LSPDiagnostic],
        in buffer: EditorBuffer,
        uri: String
    ) -> [EditorDecoration] {
        diagnostics.enumerated().map { index, diagnostic in
            let range = editorRange(from: diagnostic.range, in: buffer)
            return EditorDecoration(
                id: "lsp:\(uri):\(index):\(range.location):\(range.length)",
                range: range,
                kind: .diagnostic,
                priority: priority(for: diagnostic.severity),
                message: message(for: diagnostic),
                severity: editorSeverity(for: diagnostic.severity)
            )
        }
    }

    private static func editorRange(from range: LSPRange, in buffer: EditorBuffer) -> EditorTextRange {
        var start = buffer.offset(line: range.start.line, column: range.start.character)
        let end = buffer.offset(line: range.end.line, column: range.end.character)
        var length = max(0, end - start)

        if length == 0, buffer.utf16Length > 0 {
            if start >= buffer.utf16Length {
                start = buffer.utf16Length - 1
            }
            length = 1
        }

        return EditorTextRange(location: start, length: length).clamped(to: buffer.utf16Length)
    }

    private static func editorSeverity(for severity: LSPDiagnosticSeverity) -> EditorDiagnosticSeverity {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .information, .hint:
            return .info
        }
    }

    private static func priority(for severity: LSPDiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            return 30
        case .warning:
            return 20
        case .information, .hint:
            return 10
        }
    }

    private static func message(for diagnostic: LSPDiagnostic) -> String {
        guard let source = diagnostic.source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return diagnostic.message
        }
        return "\(source): \(diagnostic.message)"
    }
}
