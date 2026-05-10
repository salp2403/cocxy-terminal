// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FinderServiceProviderSwiftTestingTests.swift - Finder Services path safety.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("UX polish - Finder service provider")
struct FinderServiceProviderSwiftTestingTests {

    @Test("normalization deduplicates standardized directories in pasteboard order")
    func normalizationDeduplicatesDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-finder-service-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inputs = [
            nested,
            root.appendingPathComponent("nested/../nested", isDirectory: true),
            root,
        ]

        let urls = FinderServiceProvider.normalizedWorkspaceURLs(from: inputs)

        #expect(urls == [nested.standardizedFileURL, root.standardizedFileURL])
    }

    @Test("normalization opens containing folder for selected files")
    func normalizationMapsFilesToContainingDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-finder-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("README.md", isDirectory: false)
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let urls = FinderServiceProvider.normalizedWorkspaceURLs(from: [file])

        #expect(urls == [root.standardizedFileURL])
    }
}
