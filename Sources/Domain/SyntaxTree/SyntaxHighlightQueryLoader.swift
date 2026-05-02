// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxHighlightQueryLoader.swift - Safe bundle loading for Tree-sitter highlight queries.

import Foundation

struct SyntaxHighlightQuerySource: Equatable {
    var languageID: String
    var resourceURL: URL
    var query: String
}

enum SyntaxHighlightQueryLoaderError: Error, Equatable {
    case missingBundleResources
    case resourceEscapesBundle(String)
    case missingQueryResource(String)
    case emptyQuery(String)
}

struct SyntaxHighlightQueryLoader {
    typealias FileExists = (URL) -> Bool
    typealias ReadString = (URL) throws -> String

    private let bundleResourceURL: URL?
    private let fileExists: FileExists
    private let readString: ReadString

    init(
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) },
        readString: @escaping ReadString = { try String(contentsOf: $0, encoding: .utf8) }
    ) {
        self.bundleResourceURL = bundleResourceURL
        self.fileExists = fileExists
        self.readString = readString
    }

    func querySource(for language: SyntaxLanguage) throws -> SyntaxHighlightQuerySource {
        guard let bundleResourceURL else {
            throw SyntaxHighlightQueryLoaderError.missingBundleResources
        }

        let queryURL = try bundledURL(
            resource: language.highlightQueryResource,
            bundleResourceURL: bundleResourceURL
        )
        guard fileExists(queryURL) else {
            throw SyntaxHighlightQueryLoaderError.missingQueryResource(language.highlightQueryResource)
        }

        let query = try readString(queryURL)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SyntaxHighlightQueryLoaderError.emptyQuery(language.highlightQueryResource)
        }

        return SyntaxHighlightQuerySource(
            languageID: language.languageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            resourceURL: queryURL,
            query: query
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
            throw SyntaxHighlightQueryLoaderError.resourceEscapesBundle(resource)
        }
        return candidateURL
    }
}
