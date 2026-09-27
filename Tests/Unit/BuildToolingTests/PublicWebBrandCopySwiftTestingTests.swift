// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PublicWebBrandCopySwiftTestingTests.swift - Agent names, vendors, and rivals in public copy.

import Foundation
import Testing

@Suite("Public web brand copy")
struct PublicWebBrandCopySwiftTestingTests {
    @Test("public marketing copy confines named agent brands to the marked compatibility block")
    func publicMarketingCopyConfinesNamedAgentBrandsToCompatibilityBlock() throws {
        let root = repositoryRoot()
        let webRoot = root.appendingPathComponent("web/public", isDirectory: true)
        var files = [
            root.appendingPathComponent("README.md"),
        ]
        files += try Self.files(under: webRoot, fileExtension: "html")
        files += try Self.files(under: webRoot, fileExtension: "js")

        let brandPattern = try NSRegularExpression(
            pattern: #"\b(claude|codex|gemini|aider|kiro|opencode|copilot|qoder|codebuddy|rovo)\b"#,
            options: [.caseInsensitive]
        )
        let compatibilityBlockPattern = try NSRegularExpression(
            pattern: #"<!-- compatibility -->[\s\S]*?<!-- /compatibility -->"#
        )
        let comparisonPattern = try NSRegularExpression(
            pattern: #"\b(cocxy\s+vs\.?|vs\.?\s+cocxy|versus|better than|faster than|beats|mejor que|más rápido que|supera a)\b"#,
            options: [.caseInsensitive]
        )
        let homepages: Set<String> = [
            "web/public/index.html",
            "web/public/es/index.html",
        ]
        let agentReferencePages: Set<String> = [
            "web/public/agents.html",
            "web/public/es/agents.html",
            "web/public/features/agents.html",
            "web/public/es/features/agents.html",
        ]

        for file in files {
            let relativePath = Self.relativePath(file, root: root)
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(location: 0, length: (contents as NSString).length)
            #expect(
                comparisonPattern.firstMatch(in: contents, range: range) == nil,
                "\(relativePath) should describe Cocxy without competitor comparisons"
            )
            guard !agentReferencePages.contains(relativePath) else { continue }

            let blocks = compatibilityBlockPattern.matches(in: contents, range: range)
            if homepages.contains(relativePath) {
                #expect(blocks.count == 1, "\(relativePath) should mark exactly one compatibility block")
                if let block = blocks.first {
                    #expect(
                        brandPattern.firstMatch(in: contents, range: block.range) != nil,
                        "\(relativePath) compatibility block should list the supported agents"
                    )
                }
            } else {
                #expect(blocks.isEmpty, "\(relativePath) should not declare a compatibility block")
            }

            let outsideBlocks = compatibilityBlockPattern.stringByReplacingMatches(
                in: contents,
                range: range,
                withTemplate: " "
            )
            #expect(
                brandPattern.firstMatch(
                    in: outsideBlocks,
                    range: NSRange(location: 0, length: (outsideBlocks as NSString).length)
                ) == nil,
                "\(relativePath) should keep named agent brands inside the compatibility block"
            )
        }
    }

    @Test("public web copy never names agent vendors or rival terminals")
    func publicWebCopyNeverNamesAgentVendorsOrRivalTerminals() throws {
        let root = repositoryRoot()
        let webRoot = root.appendingPathComponent("web/public", isDirectory: true)
        var files = [
            root.appendingPathComponent("README.md"),
        ]
        files += try Self.files(under: webRoot, fileExtension: "html")
        files += try Self.files(under: webRoot, fileExtension: "js")

        let vendors = ["anthropic", "openai", "google", "alibaba", "tencent", "atlassian", "anysphere"]
        let rivalTerminals = [
            "w" + "arp",
            "gh" + "ostty",
            "it" + "erm2?",
            "alac" + "ritty",
            "wez" + "term",
            "ki" + "tty",
            "c" + "mux",
        ]
        let pattern = try NSRegularExpression(
            pattern: #"\b("# + (vendors + rivalTerminals).joined(separator: "|") + #")\b"#,
            options: [.caseInsensitive]
        )

        for file in files {
            let relativePath = Self.relativePath(file, root: root)
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(location: 0, length: (contents as NSString).length)
            #expect(
                pattern.firstMatch(in: contents, range: range) == nil,
                "\(relativePath) should not name agent vendors or rival terminals"
            )
        }
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func files(under root: URL, fileExtension: String) throws -> [URL] {
        let urls = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        return try urls
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true && url.pathExtension == fileExtension
            }
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = root.standardizedFileURL.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
