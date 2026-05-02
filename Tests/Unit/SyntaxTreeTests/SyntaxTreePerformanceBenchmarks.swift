// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxTreePerformanceBenchmarks.swift - Opt-in real Tree-sitter performance gates.

import Foundation
import Testing
@testable import CocxyTerminal

private enum SyntaxBenchmarkConfiguration {
    static let isEnabled =
        ProcessInfo.processInfo.environment["COCXY_RUN_SYNTAX_BENCHMARKS"] == "1"
}

@Suite(
    "Syntax tree performance benchmarks",
    .serialized,
    .enabled(
        if: SyntaxBenchmarkConfiguration.isEnabled,
        Comment("Run with COCXY_RUN_SYNTAX_BENCHMARKS=1 swift test -Xswiftc -O --filter SyntaxTreePerformanceBenchmarks.")
    )
)
struct SyntaxTreePerformanceBenchmarks {
    private static let highlightThreshold = 0.050
    private static let incrementalParseThreshold = 0.005

    @Test("5000-line Swift cached viewport highlight stays below Phase C budget")
    func fiveThousandLineSwiftViewportHighlightBudget() throws {
        let resourcesURL = repositoryRoot().appendingPathComponent("Resources", isDirectory: true)
        let bundleLoader = SyntaxGrammarBundleLoader(
            locator: SyntaxGrammarLocator(bundleResourceURL: resourcesURL),
            checksumVerifier: SyntaxGrammarChecksumVerifier(),
            queryLoader: SyntaxHighlightQueryLoader(bundleResourceURL: resourcesURL),
            dynamicLoader: SyntaxGrammarDynamicLoader()
        )
        let manifest = try SyntaxLanguageManifestLoader(bundleResourceURL: resourcesURL).load()
        let language = try #require(manifest.languages.first { $0.languageID == "swift" })
        let bundle = try bundleLoader.bundle(for: language)
        let symbolProvider = TreeSitterSymbolProvider.bundledOrProcess(bundleResourceURL: resourcesURL)
        let runtime = SyntaxTreeRuntime.treeSitterOrUnavailable(symbolProvider: symbolProvider)
        let adapter = try #require(TreeSitterHighlightQueryAdapter.resolveBundledOrProcess(
            symbolProvider: symbolProvider
        ))
        let text = (0..<5_000)
            .map { "// large Swift syntax smoke line \($0)" }
            .joined(separator: "\n")
        let buffer = EditorBuffer(text: text)
        let viewportByteRange = 0..<byteOffset(atLine: 80, in: text)
        try adapter.warmQuery(bundle: bundle, querySource: bundle.querySource)

        let parseStartedAt = DispatchTime.now().uptimeNanoseconds
        let tree = try runtime.parse(text: text, bundle: bundle)
        let parseElapsed = secondsSince(parseStartedAt)

        let captureStartedAt = DispatchTime.now().uptimeNanoseconds
        let captures = try adapter.collectCaptures(
            for: tree,
            bundle: bundle,
            querySource: bundle.querySource,
            buffer: buffer,
            byteRange: viewportByteRange
        )
        let captureElapsed = secondsSince(captureStartedAt)

        let mappingStartedAt = DispatchTime.now().uptimeNanoseconds
        let tokens = try SyntaxHighlightQueryExecutor { _, _, _ in captures }
            .tokens(for: tree, querySource: bundle.querySource, buffer: buffer)
        let mappingElapsed = secondsSince(mappingStartedAt)
        let elapsed = parseElapsed + captureElapsed + mappingElapsed
        tree.close()
        print("Syntax 5000-line Swift cold parse time: \(formatMilliseconds(parseElapsed))")
        print("Syntax 5000-line Swift viewport capture time: \(formatMilliseconds(captureElapsed))")
        print("Syntax 5000-line Swift viewport token mapping time: \(formatMilliseconds(mappingElapsed))")
        print("Syntax 5000-line Swift viewport captures: \(captures.count), tokens: \(tokens.count)")
        print("Syntax 5000-line Swift viewport highlight time: \(formatMilliseconds(elapsed))")

        #expect(!tokens.isEmpty)
        #expect(
            elapsed < Self.highlightThreshold,
            Comment("Measured 5000-line Swift viewport highlight time: \(formatMilliseconds(elapsed))")
        )
    }

    @Test("incremental Swift parse stays below Phase C edit budget")
    func incrementalSwiftParseBudget() throws {
        let resourcesURL = repositoryRoot().appendingPathComponent("Resources", isDirectory: true)
        let bundleLoader = SyntaxGrammarBundleLoader(
            locator: SyntaxGrammarLocator(bundleResourceURL: resourcesURL),
            checksumVerifier: SyntaxGrammarChecksumVerifier(),
            queryLoader: SyntaxHighlightQueryLoader(bundleResourceURL: resourcesURL),
            dynamicLoader: SyntaxGrammarDynamicLoader()
        )
        let manifest = try SyntaxLanguageManifestLoader(bundleResourceURL: resourcesURL).load()
        let language = try #require(manifest.languages.first { $0.languageID == "swift" })
        let bundle = try bundleLoader.bundle(for: language)
        let runtime = SyntaxTreeRuntime.treeSitterOrUnavailable(
            symbolProvider: TreeSitterSymbolProvider.bundledOrProcess(bundleResourceURL: resourcesURL)
        )
        let before = (0..<5_000)
            .map { "// large Swift syntax smoke line \($0)" }
            .joined(separator: "\n")
        let editLocation = (before as NSString).range(of: "line 40").location + "line ".count
        let edit = try #require(SyntaxInputEdit.replacement(
            in: before,
            range: EditorTextRange(location: editLocation, length: 2),
            replacementText: "99"
        ))
        let after = (before as NSString).replacingCharacters(
            in: NSRange(location: editLocation, length: 2),
            with: "99"
        )
        let previousTree = try runtime.parse(text: before, bundle: bundle)
        defer { previousTree.close() }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let nextTree = try runtime.parseIncremental(
            text: after,
            bundle: bundle,
            previousTree: previousTree,
            edit: edit
        )
        let elapsed = secondsSince(startedAt)
        print("Syntax 5000-line incremental Swift parse time: \(formatMilliseconds(elapsed))")
        nextTree.close()

        #expect(
            elapsed < Self.incrementalParseThreshold,
            Comment("Measured incremental Swift parse time: \(formatMilliseconds(elapsed))")
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func byteOffset(atLine requestedLine: Int, in text: String) -> Int {
        guard requestedLine > 0 else { return 0 }
        var line = 0
        var offset = 0
        for byte in text.utf8 {
            if line >= requestedLine { break }
            offset += 1
            if byte == 0x0A {
                line += 1
            }
        }
        return offset
    }

    private func secondsSince(_ startedAt: UInt64) -> Double {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        return Double(elapsedNanoseconds) / 1_000_000_000.0
    }

    private func formatMilliseconds(_ seconds: Double) -> String {
        String(format: "%.2fms", seconds * 1_000.0)
    }
}
