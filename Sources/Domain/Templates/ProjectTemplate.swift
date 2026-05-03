// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplate.swift - Local project scaffold template models.

import Foundation

enum ProjectTemplateSource: String, Sendable, Codable, Equatable {
    case builtIn = "built-in"
    case user
    case project
}

struct ProjectTemplateDirectory: Sendable, Equatable {
    let url: URL
    let source: ProjectTemplateSource

    init(url: URL, source: ProjectTemplateSource) {
        self.url = url.standardizedFileURL
        self.source = source
    }
}

struct ProjectTemplate: Sendable, Equatable {
    let id: String
    let name: String
    let summary: String
    let variables: [ProjectTemplateVariable]
    let hooks: ProjectTemplateHooks
    let source: ProjectTemplateSource
    let directoryURL: URL

    var filesURL: URL {
        directoryURL.appendingPathComponent("files", isDirectory: true)
    }
}

struct ProjectTemplateVariable: Codable, Sendable, Equatable {
    let name: String
    let prompt: String
    let defaultValue: String?
    let required: Bool

    init(
        name: String,
        prompt: String,
        defaultValue: String? = nil,
        required: Bool = true
    ) {
        self.name = name
        self.prompt = prompt
        self.defaultValue = defaultValue
        self.required = required
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case prompt
        case defaultValue
        case defaultAlias = "default"
        case required
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? name
        self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            ?? container.decodeIfPresent(String.self, forKey: .defaultAlias)
        self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encode(required, forKey: .required)
    }
}

struct ProjectTemplateHooks: Codable, Sendable, Equatable {
    let pre: [String]
    let post: [String]

    init(pre: [String] = [], post: [String] = []) {
        self.pre = pre
        self.post = post
    }

    private enum CodingKeys: String, CodingKey {
        case pre
        case post
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pre = try container.decodeIfPresent([String].self, forKey: .pre) ?? []
        self.post = try container.decodeIfPresent([String].self, forKey: .post) ?? []
    }
}

enum ProjectTemplateError: Error, Sendable, Equatable {
    case missingManifest(URL)
    case invalidIdentifier(String)
    case missingFilesDirectory(URL)
    case missingRequiredVariable(String)
    case unresolvedVariables([String])
    case destinationExists(String)
    case unsafeOutputPath(String)
    case nonUTF8TemplateFile(String)
    case unreadableTemplateFile(String)
}

extension ProjectTemplateError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "Missing template manifest: \(url.path)"
        case .invalidIdentifier(let id):
            return "Invalid template identifier: \(id)"
        case .missingFilesDirectory(let url):
            return "Missing template files directory: \(url.path)"
        case .missingRequiredVariable(let name):
            return "Missing required template variable: \(name)"
        case .unresolvedVariables(let names):
            return "Unresolved template variables: \(names.joined(separator: ", "))"
        case .destinationExists(let path):
            return "Template destination already exists: \(path)"
        case .unsafeOutputPath(let path):
            return "Template output path escapes the destination: \(path)"
        case .nonUTF8TemplateFile(let path):
            return "Template file is not valid UTF-8: \(path)"
        case .unreadableTemplateFile(let path):
            return "Template file cannot be read: \(path)"
        }
    }
}

struct ProjectTemplateManifest: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let description: String
    let variables: [ProjectTemplateVariable]
    let hooks: ProjectTemplateHooks?
}
