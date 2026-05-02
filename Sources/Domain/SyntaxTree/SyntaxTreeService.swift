// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxTreeService.swift - Coordinates syntax parsing and editor decorations.

import Foundation

enum SyntaxParserError: Error, Equatable {
    case parserUnavailable(languageID: String)
}

protocol SyntaxParsing: AnyObject {
    func tokens(for text: String, language: SyntaxLanguage) throws -> [SyntaxToken]
}

struct SyntaxTreeService {
    private let registry: SyntaxLanguageRegistry
    private let parser: any SyntaxParsing

    init(registry: SyntaxLanguageRegistry, parser: any SyntaxParsing) {
        self.registry = registry
        self.parser = parser
    }

    func decorations(forFileURL fileURL: URL, buffer: EditorBuffer) -> [EditorDecoration] {
        guard let language = registry.language(forFileURL: fileURL),
              registry.loadableLanguageIDs.contains(language.languageID.lowercased()) else {
            return []
        }

        do {
            let tokens = try parser.tokens(for: buffer.text, language: language)
            return SyntaxHighlightBridge.decorations(from: tokens, in: buffer)
        } catch {
            return []
        }
    }
}
