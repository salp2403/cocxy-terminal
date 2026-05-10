// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplateLoader.swift - Reads local scaffold template manifests.

import Foundation

struct ProjectTemplateLoader {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func loadTemplate(from directory: URL, source: ProjectTemplateSource) throws -> ProjectTemplate? {
        let templateDirectory = directory.standardizedFileURL
        let manifestURL = templateDirectory.appendingPathComponent("template.json")
        guard FileManager.default.isReadableFile(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(ProjectTemplateManifest.self, from: data)
        let id = manifest.id.lowercased()
        guard Self.isValidIdentifier(id) else {
            throw ProjectTemplateError.invalidIdentifier(id)
        }
        for variable in manifest.variables {
            guard Self.isValidIdentifier(variable.name) else {
                throw ProjectTemplateError.invalidIdentifier(variable.name)
            }
        }

        let filesURL = templateDirectory.appendingPathComponent("files", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filesURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectTemplateError.missingFilesDirectory(filesURL)
        }

        return ProjectTemplate(
            id: id,
            name: manifest.name,
            summary: manifest.description,
            variables: manifest.variables,
            hooks: manifest.hooks ?? ProjectTemplateHooks(),
            signature: manifest.signature,
            source: source,
            directoryURL: templateDirectory
        )
    }

    static func isValidIdentifier(_ id: String) -> Bool {
        guard (1...64).contains(id.count) else { return false }
        guard let first = id.unicodeScalars.first,
              isLowercaseASCII(first) || isDigitASCII(first) else {
            return false
        }
        return id.unicodeScalars.allSatisfy { scalar in
            isLowercaseASCII(scalar)
                || isDigitASCII(scalar)
                || scalar == "-"
                || scalar == "_"
        }
    }

    private static func isLowercaseASCII(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 97 && scalar.value <= 122
    }

    private static func isDigitASCII(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}
