// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookPersistence.swift - Local file persistence for Cocxy notebooks.

import Foundation

enum NotebookPersistenceError: Error, Sendable, Equatable {
    case invalidNotebookName(String)
}

extension NotebookPersistenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidNotebookName(let name):
            return "Notebook file name is invalid: \(name)"
        }
    }
}

struct NotebookFileStore: Sendable {
    let directory: URL

    init(directory: URL = NotebookFileStore.defaultDirectory()) {
        self.directory = directory
    }

    func save(_ document: NotebookDocument, named name: String) throws -> URL {
        let url = try fileURL(named: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try NotebookMarkdownCodec.render(document).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func load(named name: String) throws -> NotebookDocument {
        try load(from: fileURL(named: name))
    }

    func load(from url: URL) throws -> NotebookDocument {
        let source = try String(contentsOf: url, encoding: .utf8)
        return NotebookDocument.parseMarkdown(source)
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/notebooks", isDirectory: true)
    }

    private func fileURL(named rawName: String) throws -> URL {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\")
        else {
            throw NotebookPersistenceError.invalidNotebookName(rawName)
        }

        let filename = trimmed.hasSuffix(".cocxynb") ? trimmed : "\(trimmed).cocxynb"
        return directory.appendingPathComponent(filename, isDirectory: false)
    }
}
