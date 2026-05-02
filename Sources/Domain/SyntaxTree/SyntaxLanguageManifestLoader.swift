// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxLanguageManifestLoader.swift - Loads the bundled grammar manifest safely.

import Foundation

enum SyntaxLanguageManifestLoaderError: Error, Equatable {
    case missingBundleResources
    case resourceEscapesBundle(String)
    case missingManifest(String)
    case invalidManifest(String)
}

struct SyntaxLanguageManifestLoader {
    typealias FileExists = (URL) -> Bool
    typealias ReadData = (URL) throws -> Data

    private let bundleResourceURL: URL?
    private let manifestResource: String
    private let fileExists: FileExists
    private let readData: ReadData

    init(
        bundleResourceURL: URL? = Bundle.main.resourceURL,
        manifestResource: String = "Grammars/manifest.json",
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0.path) },
        readData: @escaping ReadData = { try Data(contentsOf: $0) }
    ) {
        self.bundleResourceURL = bundleResourceURL
        self.manifestResource = manifestResource
        self.fileExists = fileExists
        self.readData = readData
    }

    func load() throws -> SyntaxLanguageManifest {
        guard let bundleResourceURL else {
            throw SyntaxLanguageManifestLoaderError.missingBundleResources
        }

        let manifestURL = try bundledURL(
            resource: manifestResource,
            bundleResourceURL: bundleResourceURL
        )
        guard fileExists(manifestURL) else {
            throw SyntaxLanguageManifestLoaderError.missingManifest(manifestResource)
        }

        do {
            let data = try readData(manifestURL)
            return try JSONDecoder().decode(SyntaxLanguageManifest.self, from: data)
        } catch {
            throw SyntaxLanguageManifestLoaderError.invalidManifest(manifestResource)
        }
    }

    private func bundledURL(resource: String, bundleResourceURL: URL) throws -> URL {
        let cleanResource = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = bundleResourceURL.standardizedFileURL
        let candidateURL = baseURL
            .appendingPathComponent(cleanResource, isDirectory: false)
            .standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        guard candidateURL.path.hasPrefix(basePath) else {
            throw SyntaxLanguageManifestLoaderError.resourceEscapesBundle(resource)
        }
        return candidateURL
    }
}
