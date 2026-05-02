// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxGrammarLocator.swift - Safe bundle lookup for Tree-sitter parser resources.

import Foundation

struct SyntaxGrammarLoadPlan: Equatable {
    var parserURL: URL
    var symbolName: String
}

enum SyntaxGrammarLocatorError: Error, Equatable {
    case missingBundleResources
    case resourceEscapesBundle(String)
    case missingParserResource(String)
    case invalidLanguageID(String)
}

struct SyntaxGrammarLocator {
    typealias FileExists = (URL) -> Bool

    private let bundleResourceURL: URL?
    private let fileExists: FileExists

    init(
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.bundleResourceURL = bundleResourceURL
        self.fileExists = fileExists
    }

    func loadPlan(for language: SyntaxLanguage) throws -> SyntaxGrammarLoadPlan {
        guard let bundleResourceURL else {
            throw SyntaxGrammarLocatorError.missingBundleResources
        }

        let parserURL = try bundledURL(
            resource: language.parserResource,
            bundleResourceURL: bundleResourceURL
        )
        guard fileExists(parserURL) else {
            throw SyntaxGrammarLocatorError.missingParserResource(language.parserResource)
        }

        return SyntaxGrammarLoadPlan(
            parserURL: parserURL,
            symbolName: try symbolName(for: language.languageID)
        )
    }

    private func bundledURL(resource: String, bundleResourceURL: URL) throws -> URL {
        let cleanResource = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = bundleResourceURL.standardizedFileURL
        let candidateURL = baseURL
            .appendingPathComponent(cleanResource, isDirectory: false)
            .standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        guard candidateURL.path.hasPrefix(basePath) else {
            throw SyntaxGrammarLocatorError.resourceEscapesBundle(resource)
        }
        return candidateURL
    }

    private func symbolName(for languageID: String) throws -> String {
        let normalized = languageID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var scalars: [UnicodeScalar] = []
        var previousWasUnderscore = false

        for scalar in normalized.unicodeScalars {
            let isAlphanumeric = CharacterSet.alphanumerics.contains(scalar)
            if isAlphanumeric {
                scalars.append(scalar)
                previousWasUnderscore = false
            } else if !previousWasUnderscore {
                scalars.append("_")
                previousWasUnderscore = true
            }
        }

        let symbolBody = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !symbolBody.isEmpty else {
            throw SyntaxGrammarLocatorError.invalidLanguageID(languageID)
        }
        return "tree_sitter_\(symbolBody)"
    }
}
