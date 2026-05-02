// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxLanguage.swift - Tree-sitter grammar manifest and language lookup.

import Foundation

struct SyntaxLanguageManifest: Codable, Equatable {
    var languages: [SyntaxLanguage]

    static var phaseCDefaults: SyntaxLanguageManifest {
        SyntaxLanguageManifest(languages: [
            SyntaxLanguage(
                languageID: "swift",
                displayName: "Swift",
                fileExtensions: ["swift"],
                parserResource: "Grammars/swift/parser.dylib",
                highlightQueryResource: "Grammars/swift/highlights.scm",
                upstreamVersion: "tree-sitter-swift@c354345348cf8079e6794fa1b1324d8d44b6807b",
                license: "MIT",
                checksum: "sha256:bd56634202feda1dfb5ded3df3aad831fe02ebd7751a87721d88aadf1d4aac54"
            ),
            SyntaxLanguage(
                languageID: "rust",
                displayName: "Rust",
                fileExtensions: ["rs"],
                parserResource: "Grammars/rust/parser.dylib",
                highlightQueryResource: "Grammars/rust/highlights.scm",
                upstreamVersion: "tree-sitter-rust@77a3747266f4d621d0757825e6b11edcbf991ca5",
                license: "MIT",
                checksum: "sha256:e5ed4760141c35ccefef7afa514f0f5c546d9411002b6024586ffd20885b3791"
            ),
            SyntaxLanguage(
                languageID: "python",
                displayName: "Python",
                fileExtensions: ["py", "pyw"],
                parserResource: "Grammars/python/parser.dylib",
                highlightQueryResource: "Grammars/python/highlights.scm",
                upstreamVersion: "tree-sitter-python@293fdc02038ee2bf0e2e206711b69c90ac0d413f",
                license: "MIT",
                checksum: "sha256:8a25f6b2e8149e0d0589508d7aae9eeb54b3c86c21b3de5dde75ee5837fcfd19"
            ),
            SyntaxLanguage(
                languageID: "typescript",
                displayName: "TypeScript",
                fileExtensions: ["ts", "tsx"],
                parserResource: "Grammars/typescript/parser.dylib",
                highlightQueryResource: "Grammars/typescript/highlights.scm",
                upstreamVersion: "tree-sitter-typescript@f975a621f4e7f532fe322e13c4f79495e0a7b2e7",
                license: "MIT",
                checksum: "sha256:dd879f81f8213303d3656506e0656ee46e89418aa79165b15225a31bd8eb9802"
            ),
            SyntaxLanguage(
                languageID: "go",
                displayName: "Go",
                fileExtensions: ["go"],
                parserResource: "Grammars/go/parser.dylib",
                highlightQueryResource: "Grammars/go/highlights.scm",
                upstreamVersion: "tree-sitter-go@1547678a9da59885853f5f5cc8a99cc203fa2e2c",
                license: "MIT",
                checksum: "sha256:4bee4e9c2d63ab71aee3b4d6fa031b3bf1e5c1d56a638fa82d50e01fd0a52fb8"
            ),
        ])
    }
}

struct SyntaxLanguage: Codable, Equatable, Identifiable {
    var languageID: String
    var displayName: String
    var fileExtensions: [String]
    var parserResource: String
    var highlightQueryResource: String
    var upstreamVersion: String
    var license: String
    var checksum: String?

    var id: String { languageID }
}

enum SyntaxLanguageRegistryError: Error, Equatable {
    case duplicateLanguageID(String)
    case duplicateExtension(String)
}

struct SyntaxLanguageRegistry {
    typealias ResourceExists = (String) -> Bool

    private let languages: [SyntaxLanguage]
    private let languageByID: [String: SyntaxLanguage]
    private let languageIDByExtension: [String: String]
    private let resourceExists: ResourceExists

    init(
        manifest: SyntaxLanguageManifest,
        resourceExists: @escaping ResourceExists = SyntaxLanguageRegistry.bundleResourceExists
    ) throws {
        var languageByID: [String: SyntaxLanguage] = [:]
        var languageIDByExtension: [String: String] = [:]

        for language in manifest.languages {
            let languageID = Self.normalized(language.languageID)
            if languageByID[languageID] != nil {
                throw SyntaxLanguageRegistryError.duplicateLanguageID(languageID)
            }
            languageByID[languageID] = language

            for fileExtension in language.fileExtensions {
                let normalizedExtension = Self.normalizedExtension(fileExtension)
                if languageIDByExtension[normalizedExtension] != nil {
                    throw SyntaxLanguageRegistryError.duplicateExtension(normalizedExtension)
                }
                languageIDByExtension[normalizedExtension] = languageID
            }
        }

        self.languages = manifest.languages
        self.languageByID = languageByID
        self.languageIDByExtension = languageIDByExtension
        self.resourceExists = resourceExists
    }

    var loadableLanguageIDs: [String] {
        languages.compactMap { language in
            resourceExists(language.parserResource) && resourceExists(language.highlightQueryResource)
                ? Self.normalized(language.languageID)
                : nil
        }
    }

    func language(forFileURL fileURL: URL) -> SyntaxLanguage? {
        let fileExtension = Self.normalizedExtension(fileURL.pathExtension)
        guard let languageID = languageIDByExtension[fileExtension] else {
            return nil
        }
        return languageByID[languageID]
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedExtension(_ value: String) -> String {
        normalized(value).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func bundleResourceExists(_ resource: String) -> Bool {
        let normalizedResource = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedResource.isEmpty,
              !normalizedResource.contains(".."),
              let resourceURL = Bundle.main.resourceURL else {
            return false
        }
        let url = resourceURL.appendingPathComponent(normalizedResource, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
