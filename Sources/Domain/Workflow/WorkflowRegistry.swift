// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowRegistry.swift - Local workflow file discovery.

import Foundation

struct WorkflowRegistry: Sendable {
    let directory: URL

    init(directory: URL = WorkflowRegistry.defaultDirectory()) {
        self.directory = directory
    }

    func list() throws -> [WorkflowDocument] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { $0.pathExtension == "toml" }
            .map(loadWorkflow)
            .sorted { $0.id < $1.id }
    }

    func load(id rawID: String) throws -> WorkflowDocument? {
        let id = WorkflowStep.normalizedID(rawID)
        return try list().first { $0.id == id }
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/workflows", isDirectory: true)
    }

    private func loadWorkflow(from url: URL) throws -> WorkflowDocument {
        let source = try String(contentsOf: url, encoding: .utf8)
        return try WorkflowTOMLCodec.parse(source)
    }
}
