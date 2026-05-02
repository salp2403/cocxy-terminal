// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxTreeParser.swift - Composes bundled grammar loading, Tree-sitter parsing and token extraction.

import Foundation

enum SyntaxTreeParserError: Error, Equatable {
    case bundleUnavailable(languageID: String)
    case runtimeFailed(languageID: String)
    case queryExecutionUnavailable(languageID: String)
}

final class SyntaxTreeParser: SyntaxParsing {
    typealias LoadBundle = (SyntaxLanguage) throws -> SyntaxGrammarBundle
    typealias ParseTree = (String, SyntaxGrammarBundle) throws -> SyntaxTree
    typealias ExtractTokens = (SyntaxTree, SyntaxGrammarBundle, EditorBuffer) throws -> [SyntaxToken]

    private let loadBundle: LoadBundle
    private let parseTree: ParseTree
    private let extractTokens: ExtractTokens

    init(
        bundleLoader: SyntaxGrammarBundleLoader = SyntaxGrammarBundleLoader(),
        runtime: SyntaxTreeRuntime = SyntaxTreeRuntime.treeSitterOrUnavailable(),
        extractTokens: @escaping ExtractTokens = SyntaxTreeParser.defaultExtractTokens
    ) {
        self.loadBundle = { language in
            try bundleLoader.bundle(for: language)
        }
        self.parseTree = { text, bundle in
            try runtime.parse(text: text, bundle: bundle)
        }
        self.extractTokens = extractTokens
    }

    init(
        loadBundle: @escaping LoadBundle,
        parseTree: @escaping ParseTree,
        extractTokens: @escaping ExtractTokens
    ) {
        self.loadBundle = loadBundle
        self.parseTree = parseTree
        self.extractTokens = extractTokens
    }

    func tokens(for text: String, language: SyntaxLanguage) throws -> [SyntaxToken] {
        let languageID = normalizedLanguageID(language.languageID)

        let bundle: SyntaxGrammarBundle
        do {
            bundle = try loadBundle(language)
        } catch {
            throw SyntaxTreeParserError.bundleUnavailable(languageID: languageID)
        }

        let tree: SyntaxTree
        do {
            tree = try parseTree(text, bundle)
        } catch {
            throw SyntaxTreeParserError.runtimeFailed(languageID: languageID)
        }
        defer {
            tree.close()
        }

        do {
            return try extractTokens(tree, bundle, EditorBuffer(text: text))
        } catch {
            throw SyntaxTreeParserError.queryExecutionUnavailable(languageID: languageID)
        }
    }

    private static func defaultExtractTokens(
        tree: SyntaxTree,
        bundle: SyntaxGrammarBundle,
        buffer: EditorBuffer
    ) throws -> [SyntaxToken] {
        let adapter = TreeSitterHighlightQueryAdapter.resolveBundledOrProcess()
        let executor = SyntaxHighlightQueryExecutor { tree, querySource, buffer in
            guard let adapter else { return [] }
            return try adapter.collectCaptures(
                for: tree,
                bundle: bundle,
                querySource: querySource,
                buffer: buffer
            )
        }
        return try executor.tokens(for: tree, querySource: bundle.querySource, buffer: buffer)
    }

    private func normalizedLanguageID(_ languageID: String) -> String {
        languageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
