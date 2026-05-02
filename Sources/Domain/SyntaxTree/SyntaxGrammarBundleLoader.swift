// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxGrammarBundleLoader.swift - Composes bundled Tree-sitter parser and query resources.

import Foundation

struct SyntaxGrammarBundle {
    var language: SyntaxLanguage
    var library: SyntaxGrammarLibrary
    var querySource: SyntaxHighlightQuerySource
}

enum SyntaxGrammarBundleLoaderError: Error, Equatable {
    case parserResourceUnavailable(languageID: String)
    case parserChecksumMismatch(languageID: String)
    case highlightQueryUnavailable(languageID: String)
    case parserLibraryUnavailable(languageID: String)
}

struct SyntaxGrammarBundleLoader {
    typealias LoadPlan = (SyntaxLanguage) throws -> SyntaxGrammarLoadPlan
    typealias VerifyParserResource = (SyntaxLanguage, SyntaxGrammarLoadPlan) throws -> Void
    typealias LoadQuery = (SyntaxLanguage) throws -> SyntaxHighlightQuerySource
    typealias LoadLibrary = (SyntaxGrammarLoadPlan) throws -> SyntaxGrammarLibrary

    private let loadPlan: LoadPlan
    private let verifyParserResource: VerifyParserResource
    private let loadQuery: LoadQuery
    private let loadLibrary: LoadLibrary

    init(
        locator: SyntaxGrammarLocator = SyntaxGrammarLocator(),
        checksumVerifier: SyntaxGrammarChecksumVerifier = SyntaxGrammarChecksumVerifier(),
        queryLoader: SyntaxHighlightQueryLoader = SyntaxHighlightQueryLoader(),
        dynamicLoader: SyntaxGrammarDynamicLoader = SyntaxGrammarDynamicLoader()
    ) {
        self.init(
            loadPlan: locator.loadPlan,
            verifyParserResource: checksumVerifier.verify,
            loadQuery: queryLoader.querySource,
            loadLibrary: dynamicLoader.load
        )
    }

    init(
        loadPlan: @escaping LoadPlan,
        verifyParserResource: @escaping VerifyParserResource = { _, _ in },
        loadQuery: @escaping LoadQuery,
        loadLibrary: @escaping LoadLibrary
    ) {
        self.loadPlan = loadPlan
        self.verifyParserResource = verifyParserResource
        self.loadQuery = loadQuery
        self.loadLibrary = loadLibrary
    }

    func bundle(for language: SyntaxLanguage) throws -> SyntaxGrammarBundle {
        let languageID = normalizedLanguageID(language.languageID)

        let plan: SyntaxGrammarLoadPlan
        do {
            plan = try loadPlan(language)
        } catch {
            throw SyntaxGrammarBundleLoaderError.parserResourceUnavailable(languageID: languageID)
        }

        do {
            try verifyParserResource(language, plan)
        } catch {
            throw SyntaxGrammarBundleLoaderError.parserChecksumMismatch(languageID: languageID)
        }

        let querySource: SyntaxHighlightQuerySource
        do {
            querySource = try loadQuery(language)
        } catch {
            throw SyntaxGrammarBundleLoaderError.highlightQueryUnavailable(languageID: languageID)
        }

        do {
            let library = try loadLibrary(plan)
            return SyntaxGrammarBundle(
                language: language,
                library: library,
                querySource: querySource
            )
        } catch {
            throw SyntaxGrammarBundleLoaderError.parserLibraryUnavailable(languageID: languageID)
        }
    }

    private func normalizedLanguageID(_ languageID: String) -> String {
        languageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
