// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxTreeDomainSwiftTestingTests.swift - Phase C syntax domain foundation tests.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Syntax language manifest")
struct SyntaxLanguageManifestSwiftTestingTests {
    @Test("manifest decodes languages and maps extensions case-insensitively")
    func manifestLookup() throws {
        let manifest = try JSONDecoder().decode(SyntaxLanguageManifest.self, from: Data("""
        {
          "languages": [
            {
              "languageID": "swift",
              "displayName": "Swift",
              "fileExtensions": ["swift"],
              "parserResource": "swift/parser.dylib",
              "highlightQueryResource": "swift/highlights.scm",
              "upstreamVersion": "0.0.1",
              "license": "MIT",
              "checksum": "sha256:abc"
            }
          ]
        }
        """.utf8))
        let registry = try SyntaxLanguageRegistry(manifest: manifest)

        let language = registry.language(forFileURL: URL(fileURLWithPath: "/tmp/App.SWIFT"))

        #expect(language?.languageID == "swift")
        #expect(language?.displayName == "Swift")
        #expect(language?.parserResource == "swift/parser.dylib")
        #expect(language?.highlightQueryResource == "swift/highlights.scm")
    }

    @Test("registry rejects duplicate file extensions")
    func duplicateExtensionsFail() throws {
        let manifest = SyntaxLanguageManifest(languages: [
            SyntaxLanguage(
                languageID: "javascript",
                displayName: "JavaScript",
                fileExtensions: ["js"],
                parserResource: "javascript/parser.dylib",
                highlightQueryResource: "javascript/highlights.scm",
                upstreamVersion: "0.1.0",
                license: "MIT",
                checksum: "sha256:one"
            ),
            SyntaxLanguage(
                languageID: "typescript",
                displayName: "TypeScript",
                fileExtensions: ["JS"],
                parserResource: "typescript/parser.dylib",
                highlightQueryResource: "typescript/highlights.scm",
                upstreamVersion: "0.1.0",
                license: "MIT",
                checksum: "sha256:two"
            ),
        ])

        #expect(throws: SyntaxLanguageRegistryError.duplicateExtension("js")) {
            _ = try SyntaxLanguageRegistry(manifest: manifest)
        }
    }

    @Test("availability keeps missing parser resources disabled")
    func missingParserResourceDisablesLanguage() throws {
        let manifest = SyntaxLanguageManifest(languages: [
            SyntaxLanguage(
                languageID: "swift",
                displayName: "Swift",
                fileExtensions: ["swift"],
                parserResource: "swift/parser.dylib",
                highlightQueryResource: "swift/highlights.scm",
                upstreamVersion: "0.1.0",
                license: "MIT",
                checksum: "sha256:abc"
            ),
        ])
        let registry = try SyntaxLanguageRegistry(
            manifest: manifest,
            resourceExists: { $0 == "swift/highlights.scm" }
        )

        #expect(registry.loadableLanguageIDs.isEmpty)
        #expect(registry.language(forFileURL: URL(fileURLWithPath: "/tmp/App.swift"))?.languageID == "swift")
    }

    @Test("default availability checker treats absent bundled resources as disabled")
    func defaultAvailabilityRequiresBundledResources() throws {
        let registry = try SyntaxLanguageRegistry(manifest: .fixtureSwift)

        #expect(registry.loadableLanguageIDs.isEmpty)
    }

    @Test("phase C default manifest covers the first smoke gate languages")
    func phaseCDefaultManifestCoversSmokeLanguages() throws {
        let registry = try SyntaxLanguageRegistry(
            manifest: .phaseCDefaults,
            resourceExists: { _ in false }
        )

        #expect(registry.language(forFileURL: URL(fileURLWithPath: "/tmp/App.swift"))?.languageID == "swift")
        #expect(registry.language(forFileURL: URL(fileURLWithPath: "/tmp/main.rs"))?.languageID == "rust")
        #expect(registry.language(forFileURL: URL(fileURLWithPath: "/tmp/app.py"))?.languageID == "python")
        #expect(registry.language(forFileURL: URL(fileURLWithPath: "/tmp/app.ts"))?.languageID == "typescript")
        #expect(registry.language(forFileURL: URL(fileURLWithPath: "/tmp/main.go"))?.languageID == "go")
        #expect(registry.loadableLanguageIDs.isEmpty)
    }
}

@Suite("Syntax language manifest loader")
struct SyntaxLanguageManifestLoaderSwiftTestingTests {
    @Test("loader reads and decodes the bundled grammar manifest")
    func loaderReadsBundledManifest() throws {
        let resourcesURL = URL(fileURLWithPath: "/tmp/CocxyTerminal.app/Contents/Resources", isDirectory: true)
        let loader = SyntaxLanguageManifestLoader(
            bundleResourceURL: resourcesURL,
            fileExists: { $0.path.hasSuffix("Contents/Resources/Grammars/manifest.json") },
            readData: { url in
                #expect(url.path.hasSuffix("Contents/Resources/Grammars/manifest.json"))
                return Data("""
                {
                  "languages": [
                    {
                      "languageID": "swift",
                      "displayName": "Swift",
                      "fileExtensions": ["swift"],
                      "parserResource": "Grammars/swift/parser.dylib",
                      "highlightQueryResource": "Grammars/swift/highlights.scm",
                      "upstreamVersion": "0.1.0",
                      "license": "MIT",
                      "checksum": "sha256:b17d45121150928f2146af49e195eff1eef5d67325be273a733fb74acadaa342"
                    }
                  ]
                }
                """.utf8)
            }
        )

        let manifest = try loader.load()

        #expect(manifest.languages.map(\.languageID) == ["swift"])
        #expect(manifest.languages[0].checksum == "sha256:b17d45121150928f2146af49e195eff1eef5d67325be273a733fb74acadaa342")
    }

    @Test("loader rejects missing bundled manifest")
    func loaderRejectsMissingManifest() {
        let loader = SyntaxLanguageManifestLoader(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            fileExists: { _ in false },
            readData: { _ in Data() }
        )

        #expect(throws: SyntaxLanguageManifestLoaderError.missingManifest("Grammars/manifest.json")) {
            _ = try loader.load()
        }
    }

    @Test("loader rejects manifest resources that escape the bundle")
    func loaderRejectsEscapingManifestPath() {
        let loader = SyntaxLanguageManifestLoader(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            manifestResource: "../manifest.json",
            fileExists: { _ in true },
            readData: { _ in Data() }
        )

        #expect(throws: SyntaxLanguageManifestLoaderError.resourceEscapesBundle("../manifest.json")) {
            _ = try loader.load()
        }
    }

    @Test("loader rejects malformed manifest JSON")
    func loaderRejectsMalformedManifest() {
        let loader = SyntaxLanguageManifestLoader(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            fileExists: { _ in true },
            readData: { _ in Data("{\"languages\":".utf8) }
        )

        #expect(throws: SyntaxLanguageManifestLoaderError.invalidManifest("Grammars/manifest.json")) {
            _ = try loader.load()
        }
    }
}

@Suite("Syntax grammar repository resources")
struct SyntaxGrammarRepositoryResourcesSwiftTestingTests {
    @Test("repository grammar manifest matches Phase C defaults and ships query resources")
    func repositoryManifestMatchesPhaseCDefaults() throws {
        let resourcesURL = repositoryRoot().appendingPathComponent("Resources", isDirectory: true)
        let manifest = try SyntaxLanguageManifestLoader(bundleResourceURL: resourcesURL).load()

        #expect(manifest == .phaseCDefaults)

        for language in manifest.languages {
            let queryURL = resourcesURL.appendingPathComponent(language.highlightQueryResource, isDirectory: false)
            let query = try String(contentsOf: queryURL, encoding: .utf8)
            #expect(!query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(language.parserResource == "Grammars/\(language.languageID)/parser.dylib")
            #expect(language.checksum == nil || language.checksum?.hasPrefix("sha256:") == true)
        }
    }

    @Test("app bundle scripts include grammar resources and require parser dylibs")
    func appBundleScriptsIncludeGrammarResources() throws {
        let root = repositoryRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains("Resources/TreeSitter"))
        #expect(buildScript.contains("${RESOURCES}/TreeSitter"))
        #expect(buildScript.contains("Resources/Grammars"))
        #expect(buildScript.contains("${RESOURCES}/Grammars"))
        #expect(verifyScript.contains("$RESOURCES/Grammars/manifest.json"))
        #expect(verifyScript.contains("$RESOURCES/TreeSitter/libtree-sitter.dylib"))
        #expect(verifyScript.contains("$RESOURCES/Grammars/LICENSES/tree-sitter-core-LICENSE.txt"))
        #expect(verifyScript.contains("$RESOURCES/Grammars/swift/parser.dylib"))
        #expect(verifyScript.contains("$RESOURCES/Grammars/rust/parser.dylib"))
        #expect(verifyScript.contains("$RESOURCES/Grammars/python/parser.dylib"))
        #expect(verifyScript.contains("$RESOURCES/Grammars/typescript/parser.dylib"))
        #expect(verifyScript.contains("$RESOURCES/Grammars/go/parser.dylib"))
    }

    @Test("repository bundled grammars parse and highlight the first smoke gate languages")
    func repositoryBundledGrammarsParseAndHighlightSmokeLanguages() throws {
        let resourcesURL = repositoryRoot().appendingPathComponent("Resources", isDirectory: true)
        let manifest = try SyntaxLanguageManifestLoader(bundleResourceURL: resourcesURL).load()
        let registry = try SyntaxLanguageRegistry(manifest: manifest) { resource in
            FileManager.default.fileExists(
                atPath: resourcesURL.appendingPathComponent(resource, isDirectory: false).path
            )
        }
        let symbolProvider = TreeSitterSymbolProvider.bundledOrProcess(bundleResourceURL: resourcesURL)
        let parser = SyntaxTreeParser(
            bundleLoader: SyntaxGrammarBundleLoader(
                locator: SyntaxGrammarLocator(bundleResourceURL: resourcesURL),
                checksumVerifier: SyntaxGrammarChecksumVerifier(),
                queryLoader: SyntaxHighlightQueryLoader(bundleResourceURL: resourcesURL),
                dynamicLoader: SyntaxGrammarDynamicLoader()
            ),
            runtime: SyntaxTreeRuntime.treeSitterOrUnavailable(symbolProvider: symbolProvider),
            extractTokens: { tree, bundle, buffer in
                guard let adapter = TreeSitterHighlightQueryAdapter.resolveBundledOrProcess(
                    symbolProvider: symbolProvider
                ) else {
                    return []
                }
                return try SyntaxHighlightQueryExecutor { tree, querySource, buffer in
                    try adapter.collectCaptures(
                        for: tree,
                        bundle: bundle,
                        querySource: querySource,
                        buffer: buffer
                    )
                }
                .tokens(for: tree, querySource: bundle.querySource, buffer: buffer)
            }
        )
        let samples: [(fileName: String, text: String)] = [
            ("App.swift", "func greet() {\n  return 1\n}\n"),
            ("main.rs", "fn main() {\n  println!(\"hi\");\n}\n"),
            ("app.py", "def greet():\n    return 1\n"),
            ("app.ts", "export function greet(): number {\n  return 1\n}\n"),
            ("main.go", "package main\nfunc main() {\n  println(\"hi\")\n}\n"),
        ]

        #expect(registry.loadableLanguageIDs.sorted() == ["go", "python", "rust", "swift", "typescript"])

        for sample in samples {
            let fileURL = URL(fileURLWithPath: "/tmp/\(sample.fileName)")
            let language = try #require(registry.language(forFileURL: fileURL))
            let tokens = try parser.tokens(for: sample.text, language: language)
            #expect(!tokens.isEmpty, "expected syntax tokens for \(language.languageID)")
        }
    }

    @Test("repository bundled Swift grammar supports real incremental reparsing")
    func repositoryBundledSwiftGrammarSupportsIncrementalReparsing() throws {
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
        let before = "func greet() {\n  return 1\n}\n"
        let after = "func greet() {\n  return 123\n}\n"
        let editRange = EditorTextRange(location: 24, length: 1)
        let edit = try #require(SyntaxInputEdit.replacement(
            in: before,
            range: editRange,
            replacementText: "123"
        ))
        let queryAdapter = try #require(TreeSitterHighlightQueryAdapter.resolveBundledOrProcess(
            symbolProvider: symbolProvider
        ))

        let previousTree = try runtime.parse(text: before, bundle: bundle)
        let nextTree = try runtime.parseIncremental(
            text: after,
            bundle: bundle,
            previousTree: previousTree,
            edit: edit
        )
        defer {
            nextTree.close()
            previousTree.close()
        }

        let tokens = try SyntaxHighlightQueryExecutor { tree, querySource, buffer in
            try queryAdapter.collectCaptures(
                for: tree,
                bundle: bundle,
                querySource: querySource,
                buffer: buffer
            )
        }
        .tokens(for: nextTree, querySource: bundle.querySource, buffer: EditorBuffer(text: after))

        #expect(nextTree.rootNode.editorRange(in: EditorBuffer(text: after)).length == (after as NSString).length)
        #expect(tokens.contains { $0.range == EditorTextRange(location: 24, length: 3) })
    }
}

@Suite("Syntax highlight bridge")
struct SyntaxHighlightBridgeSwiftTestingTests {
    @Test("query capture names map to stable syntax token roles")
    func captureNamesMapToTokenRoles() {
        #expect(SyntaxCaptureMapper.role(for: "keyword") == .keyword)
        #expect(SyntaxCaptureMapper.role(for: "function.method") == .function)
        #expect(SyntaxCaptureMapper.role(for: "type.builtin") == .type)
        #expect(SyntaxCaptureMapper.role(for: "string.special") == .string)
        #expect(SyntaxCaptureMapper.role(for: "comment.documentation") == .comment)
        #expect(SyntaxCaptureMapper.role(for: "number.float") == .number)
        #expect(SyntaxCaptureMapper.role(for: "operator") == .operatorToken)
        #expect(SyntaxCaptureMapper.role(for: "punctuation.bracket") == .punctuation)
        #expect(SyntaxCaptureMapper.role(for: "spell") == nil)
    }

    @Test("syntax tokens become editor syntax decorations without changing text")
    func tokensBecomeDecorations() {
        let buffer = EditorBuffer(text: "func greet() {\n  return \"hi\"\n}\n")
        let tokens = [
            SyntaxToken(role: .keyword, range: EditorTextRange(location: 0, length: 4)),
            SyntaxToken(role: .function, range: EditorTextRange(location: 5, length: 5)),
            SyntaxToken(role: .string, range: EditorTextRange(location: 22, length: 4)),
        ]

        let decorations = SyntaxHighlightBridge.decorations(from: tokens, in: buffer)

        #expect(buffer.text == "func greet() {\n  return \"hi\"\n}\n")
        #expect(decorations.map(\.kind) == [.syntaxToken, .syntaxToken, .syntaxToken])
        #expect(decorations.map(\.message) == ["syntax.keyword", "syntax.function", "syntax.string"])
        #expect(decorations.map(\.range) == [
            EditorTextRange(location: 0, length: 4),
            EditorTextRange(location: 5, length: 5),
            EditorTextRange(location: 22, length: 4),
        ])
    }

    @Test("point ranges convert through the editor UTF-16 buffer")
    func pointRangesUseEditorBufferOffsets() {
        let buffer = EditorBuffer(text: "let cafe = \"☕️\"\nprint(cafe)\n")
        let range = SyntaxPointRange(
            start: SyntaxPoint(line: 1, column: 0),
            end: SyntaxPoint(line: 1, column: 5)
        )

        #expect(range.editorRange(in: buffer) == EditorTextRange(location: 16, length: 5))
    }
}

@Suite("Syntax point converter")
struct SyntaxPointConverterSwiftTestingTests {
    @Test("Tree-sitter byte columns convert to editor UTF-16 columns")
    func byteColumnsConvertToUTF16Columns() {
        let converter = SyntaxPointConverter(text: "let ☕️ = 1\nprint(\"ok\")\n")

        #expect(converter.syntaxPoint(from: SyntaxBytePoint(line: 0, byteColumn: 0)) == SyntaxPoint(line: 0, column: 0))
        #expect(converter.syntaxPoint(from: SyntaxBytePoint(line: 0, byteColumn: 10)) == SyntaxPoint(line: 0, column: 6))
        #expect(converter.syntaxPoint(from: SyntaxBytePoint(line: 1, byteColumn: 5)) == SyntaxPoint(line: 1, column: 5))
    }

    @Test("byte columns clamp at valid scalar and line boundaries")
    func byteColumnsClampAtBoundaries() {
        let converter = SyntaxPointConverter(text: "é\n")

        #expect(converter.syntaxPoint(from: SyntaxBytePoint(line: 0, byteColumn: 1)) == SyntaxPoint(line: 0, column: 0))
        #expect(converter.syntaxPoint(from: SyntaxBytePoint(line: 0, byteColumn: 99)) == SyntaxPoint(line: 0, column: 1))
        #expect(converter.syntaxPoint(from: SyntaxBytePoint(line: 99, byteColumn: 0)) == SyntaxPoint(line: 1, column: 0))
    }
}

@Suite("Syntax highlight query executor")
struct SyntaxHighlightQueryExecutorSwiftTestingTests {
    @Test("executor maps query captures into syntax tokens")
    func executorMapsCapturesIntoTokens() throws {
        let buffer = EditorBuffer(text: "let value = 1\nprint(value)\n")
        let tree = SyntaxTree.fixtureTree()
        let querySource = SyntaxHighlightQuerySource.fixture
        let executor = SyntaxHighlightQueryExecutor { parsedTree, source, captureBuffer in
            #expect(parsedTree.languageID == "swift")
            #expect(source == querySource)
            #expect(captureBuffer == buffer)
            return [
                SyntaxQueryCapture(
                    captureName: "keyword.control",
                    range: SyntaxPointRange(
                        start: SyntaxPoint(line: 0, column: 0),
                        end: SyntaxPoint(line: 0, column: 3)
                    )
                ),
                SyntaxQueryCapture(
                    captureName: "function.method",
                    range: SyntaxPointRange(
                        start: SyntaxPoint(line: 1, column: 0),
                        end: SyntaxPoint(line: 1, column: 5)
                    )
                ),
            ]
        }

        let tokens = try executor.tokens(for: tree, querySource: querySource, buffer: buffer)

        #expect(tokens == [
            SyntaxToken(role: .keyword, range: EditorTextRange(location: 0, length: 3)),
            SyntaxToken(role: .function, range: EditorTextRange(location: 14, length: 5)),
        ])
    }

    @Test("executor ignores unsupported, empty and out-of-buffer captures")
    func executorIgnoresInvalidCaptures() throws {
        let buffer = EditorBuffer(text: "let value = 1\n")
        let tree = SyntaxTree.fixtureTree()
        let executor = SyntaxHighlightQueryExecutor { _, _, _ in
            [
                SyntaxQueryCapture(
                    captureName: "spell",
                    range: SyntaxPointRange(
                        start: SyntaxPoint(line: 0, column: 0),
                        end: SyntaxPoint(line: 0, column: 3)
                    )
                ),
                SyntaxQueryCapture(
                    captureName: "keyword",
                    range: SyntaxPointRange(
                        start: SyntaxPoint(line: 0, column: 4),
                        end: SyntaxPoint(line: 0, column: 4)
                    )
                ),
                SyntaxQueryCapture(
                    captureName: "variable",
                    range: SyntaxPointRange(
                        start: SyntaxPoint(line: 9, column: 0),
                        end: SyntaxPoint(line: 9, column: 5)
                    )
                ),
                SyntaxQueryCapture(
                    captureName: "number",
                    range: SyntaxPointRange(
                        start: SyntaxPoint(line: 0, column: 12),
                        end: SyntaxPoint(line: 0, column: 13)
                    )
                ),
            ]
        }

        let tokens = try executor.tokens(for: tree, querySource: .fixture, buffer: buffer)

        #expect(tokens == [
            SyntaxToken(role: .number, range: EditorTextRange(location: 12, length: 1)),
        ])
    }

    @Test("default executor preserves plain-text fallback until query cursor support is present")
    func defaultExecutorPreservesFallback() throws {
        let tokens = try SyntaxHighlightQueryExecutor().tokens(
            for: SyntaxTree.fixtureTree(),
            querySource: .fixture,
            buffer: EditorBuffer(text: "let value = 1\n")
        )

        #expect(tokens.isEmpty)
    }
}

@Suite("Syntax input edits")
struct SyntaxInputEditSwiftTestingTests {
    @Test("replacement edit maps UTF-16 ranges to Tree-sitter byte points")
    func replacementEditMapsUTF16RangesToBytePoints() throws {
        let text = "let cafe = \"☕️\"\nprint(cafe)\n"
        let range = EditorTextRange(location: 12, length: 2)

        let edit = try #require(SyntaxInputEdit.replacement(
            in: text,
            range: range,
            replacementText: "tea"
        ))

        #expect(edit.startByte == "let cafe = \"".utf8.count)
        #expect(edit.oldEndByte == "let cafe = \"☕️".utf8.count)
        #expect(edit.newEndByte == "let cafe = \"tea".utf8.count)
        #expect(edit.startPoint == SyntaxBytePoint(line: 0, byteColumn: "let cafe = \"".utf8.count))
        #expect(edit.oldEndPoint == SyntaxBytePoint(line: 0, byteColumn: "let cafe = \"☕️".utf8.count))
        #expect(edit.newEndPoint == SyntaxBytePoint(line: 0, byteColumn: "let cafe = \"tea".utf8.count))
    }

    @Test("multiline replacement edit reports new end point in replacement text")
    func multilineReplacementEditReportsNewEndPoint() throws {
        let text = "func old() {\n  return 1\n}\n"
        let range = EditorTextRange(location: 13, length: 10)

        let edit = try #require(SyntaxInputEdit.replacement(
            in: text,
            range: range,
            replacementText: "let value = 2\n  return value"
        ))

        #expect(edit.startPoint == SyntaxBytePoint(line: 1, byteColumn: 0))
        #expect(edit.oldEndPoint == SyntaxBytePoint(line: 1, byteColumn: "  return 1".utf8.count))
        #expect(edit.newEndPoint == SyntaxBytePoint(line: 2, byteColumn: "  return value".utf8.count))
    }
}

@Suite("Syntax tree wrappers")
struct SyntaxTreeWrapperSwiftTestingTests {
    @Test("syntax node ranges convert through the editor UTF-16 buffer")
    func syntaxNodeRangeConvertsThroughEditorBuffer() {
        let node = SyntaxNode(
            kind: "call_expression",
            range: SyntaxPointRange(
                start: SyntaxPoint(line: 1, column: 0),
                end: SyntaxPoint(line: 1, column: 5)
            ),
            isNamed: true,
            childCount: 2
        )
        let buffer = EditorBuffer(text: "let cafe = \"☕️\"\nprint(cafe)\n")

        #expect(node.editorRange(in: buffer) == EditorTextRange(location: 16, length: 5))
        #expect(node.kind == "call_expression")
        #expect(node.isNamed)
        #expect(node.childCount == 2)
    }

    @Test("syntax tree closes the underlying Tree-sitter handle exactly once")
    func syntaxTreeClosesHandleExactlyOnce() {
        let calls = SyntaxTreeCalls()
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x10)!
        let rootNode = SyntaxNode(
            kind: "source_file",
            range: SyntaxPointRange(
                start: SyntaxPoint(line: 0, column: 0),
                end: SyntaxPoint(line: 0, column: 3)
            )
        )

        var tree: SyntaxTree? = SyntaxTree(
            languageID: " Swift ",
            treeHandle: treeHandle,
            rootNode: rootNode,
            deleteTree: { handle in
                calls.closedHandles.append(handle)
            }
        )

        #expect(tree?.languageID == "swift")
        #expect(tree?.rootNode == rootNode)
        #expect(tree?.isClosed == false)

        tree?.close()
        tree?.close()
        #expect(tree?.isClosed == true)
        tree = nil

        #expect(calls.closedHandles == [treeHandle])
    }
}

@Suite("Syntax tree runtime")
struct SyntaxTreeRuntimeSwiftTestingTests {
    @Test("runtime parses text through parser lifecycle and returns an owned syntax tree")
    func runtimeParsesTextThroughLifecycle() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x20)!
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x21)!
        let rootNode = SyntaxNode(
            kind: "source_file",
            range: SyntaxPointRange(
                start: SyntaxPoint(line: 0, column: 0),
                end: SyntaxPoint(line: 0, column: 12)
            )
        )
        let runtime = SyntaxTreeRuntime(
            createParser: {
                calls.events.append("create-parser")
                return parserHandle
            },
            deleteParser: { handle in
                calls.events.append("delete-parser")
                calls.closedHandles.append(handle)
            },
            setLanguage: { parser, languageEntryPoint in
                calls.events.append("set-language")
                #expect(parser == parserHandle)
                #expect(languageEntryPoint == calls.languageEntryPoint)
                return true
            },
            parseString: { parser, text in
                calls.events.append("parse:\(text)")
                #expect(parser == parserHandle)
                return treeHandle
            },
            rootNode: { handle, text, languageID in
                calls.events.append("root:\(languageID)")
                #expect(handle == treeHandle)
                #expect(text == "let value = 1")
                return rootNode
            },
            deleteTree: { handle in
                calls.events.append("delete-tree")
                calls.closedHandles.append(handle)
            }
        )

        var tree: SyntaxTree? = try runtime.parse(text: "let value = 1", bundle: calls.makeBundle())

        #expect(tree?.languageID == "swift")
        #expect(tree?.rootNode == rootNode)
        #expect(calls.events == [
            "create-parser",
            "set-language",
            "parse:let value = 1",
            "root:swift",
            "delete-parser",
        ])
        #expect(calls.closedHandles == [parserHandle])

        tree = nil
        #expect(calls.closedHandles == [parserHandle, treeHandle])
    }

    @Test("runtime transfers retained objects to the owned syntax tree")
    func runtimeKeepsRetainedObjectsAliveForTreeLifetime() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x23)!
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x24)!
        let rootNode = SyntaxNode(
            kind: "source_file",
            range: SyntaxPointRange(
                start: SyntaxPoint(line: 0, column: 0),
                end: SyntaxPoint(line: 0, column: 12)
            )
        )
        var releaseCount = 0
        var runtime: SyntaxTreeRuntime? = SyntaxTreeRuntime(
            createParser: { parserHandle },
            deleteParser: { _ in },
            setLanguage: { _, _ in true },
            parseString: { _, _ in treeHandle },
            rootNode: { _, _, _ in rootNode },
            deleteTree: { _ in },
            retainedObjects: [LifetimeProbe { releaseCount += 1 }]
        )

        var tree: SyntaxTree? = try runtime?.parse(text: "let value = 1", bundle: calls.makeBundle())

        #expect(tree != nil)
        #expect(releaseCount == 0)

        runtime = nil
        #expect(releaseCount == 0)

        tree = nil
        #expect(releaseCount == 1)
    }

    @Test("runtime applies an incremental edit to the previous tree before reparsing")
    func runtimeAppliesIncrementalEditBeforeReparse() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x60)!
        let oldTreeHandle = UnsafeMutableRawPointer(bitPattern: 0x61)!
        let newTreeHandle = UnsafeMutableRawPointer(bitPattern: 0x62)!
        let rootNode = SyntaxNode(
            kind: "source_file",
            range: SyntaxPointRange(
                start: SyntaxPoint(line: 0, column: 0),
                end: SyntaxPoint(line: 0, column: 13)
            )
        )
        let edit = SyntaxInputEdit(
            startByte: 4,
            oldEndByte: 9,
            newEndByte: 10,
            startPoint: SyntaxBytePoint(line: 0, byteColumn: 4),
            oldEndPoint: SyntaxBytePoint(line: 0, byteColumn: 9),
            newEndPoint: SyntaxBytePoint(line: 0, byteColumn: 10)
        )
        let previousTree = SyntaxTree(
            languageID: "swift",
            treeHandle: oldTreeHandle,
            rootNode: rootNode,
            deleteTree: { calls.closedHandles.append($0) }
        )
        let runtime = SyntaxTreeRuntime(
            createParser: {
                calls.events.append("create-parser")
                return parserHandle
            },
            deleteParser: { handle in
                calls.events.append("delete-parser")
                calls.closedHandles.append(handle)
            },
            setLanguage: { _, _ in
                calls.events.append("set-language")
                return true
            },
            parseStringWithOldTree: { parser, oldTree, text in
                calls.events.append("parse:\(text)")
                #expect(parser == parserHandle)
                #expect(oldTree == oldTreeHandle)
                return newTreeHandle
            },
            rootNode: { handle, _, _ in
                calls.events.append("root")
                #expect(handle == newTreeHandle)
                return rootNode
            },
            deleteTree: { calls.closedHandles.append($0) },
            editTree: { handle, receivedEdit in
                calls.events.append("edit")
                #expect(handle == oldTreeHandle)
                #expect(receivedEdit == edit)
            }
        )

        let tree = try runtime.parseIncremental(
            text: "let values = 1",
            bundle: calls.makeBundle(),
            previousTree: previousTree,
            edit: edit
        )

        #expect(tree.languageID == "swift")
        #expect(calls.events == ["edit", "create-parser", "set-language", "parse:let values = 1", "root", "delete-parser"])
        #expect(calls.closedHandles == [parserHandle])
        tree.close()
        previousTree.close()
        #expect(calls.closedHandles == [parserHandle, newTreeHandle, oldTreeHandle])
    }

    @Test("runtime deletes parser when language is rejected before parsing")
    func runtimeDeletesParserWhenLanguageRejected() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x30)!
        let runtime = SyntaxTreeRuntime(
            createParser: { parserHandle },
            deleteParser: { handle in calls.closedHandles.append(handle) },
            setLanguage: { _, _ in false },
            parseString: { _, _ in
                calls.events.append("parse")
                return UnsafeMutableRawPointer(bitPattern: 0x31)
            },
            rootNode: { _, _, _ in nil },
            deleteTree: { handle in calls.closedHandles.append(handle) }
        )

        #expect(throws: SyntaxTreeRuntimeError.languageRejected(languageID: "swift")) {
            _ = try runtime.parse(text: "let value = 1", bundle: calls.makeBundle())
        }
        #expect(calls.events.isEmpty)
        #expect(calls.closedHandles == [parserHandle])
    }

    @Test("runtime deletes parser when parse returns no tree")
    func runtimeDeletesParserWhenParseFails() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x40)!
        let runtime = SyntaxTreeRuntime(
            createParser: { parserHandle },
            deleteParser: { handle in calls.closedHandles.append(handle) },
            setLanguage: { _, _ in true },
            parseString: { _, _ in nil },
            rootNode: { _, _, _ in
                calls.events.append("root")
                return nil
            },
            deleteTree: { handle in calls.closedHandles.append(handle) }
        )

        #expect(throws: SyntaxTreeRuntimeError.parseFailed(languageID: "swift")) {
            _ = try runtime.parse(text: "let value = 1", bundle: calls.makeBundle())
        }
        #expect(calls.events.isEmpty)
        #expect(calls.closedHandles == [parserHandle])
    }

    @Test("runtime deletes parser and tree when root node extraction fails")
    func runtimeDeletesParserAndTreeWhenRootNodeFails() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x50)!
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x51)!
        let runtime = SyntaxTreeRuntime(
            createParser: { parserHandle },
            deleteParser: { handle in calls.closedHandles.append(handle) },
            setLanguage: { _, _ in true },
            parseString: { _, _ in treeHandle },
            rootNode: { _, _, _ in nil },
            deleteTree: { handle in calls.closedHandles.append(handle) }
        )

        #expect(throws: SyntaxTreeRuntimeError.missingRootNode(languageID: "swift")) {
            _ = try runtime.parse(text: "let value = 1", bundle: calls.makeBundle())
        }
        #expect(calls.closedHandles == [parserHandle, treeHandle])
    }
}

@Suite("Tree-sitter runtime adapter")
struct TreeSitterRuntimeAdapterSwiftTestingTests {
    @Test("bundled runtime library opens the first available core inside app resources")
    func bundledRuntimeLibraryOpensAvailableCore() throws {
        let resourcesURL = URL(fileURLWithPath: "/tmp/CocxyTerminal.app/Contents/Resources", isDirectory: true)
        let availableURL = resourcesURL.appendingPathComponent("TreeSitter/libtree-sitter.dylib")
        let handle = UnsafeMutableRawPointer(bitPattern: 0xD00)!
        let symbol = UnsafeMutableRawPointer(bitPattern: 0xD01)!
        var openedPaths: [String] = []
        var lookedUpSymbols: [String] = []
        var closedHandles: [UnsafeMutableRawPointer] = []

        var library: TreeSitterRuntimeLibrary? = TreeSitterRuntimeLibrary.bundled(
            bundleResourceURL: resourcesURL,
            fileExists: { $0.standardizedFileURL.path == availableURL.standardizedFileURL.path },
            openLibrary: { url in
                openedPaths.append(url.standardizedFileURL.path)
                return handle
            },
            lookupSymbol: { openedHandle, name in
                #expect(openedHandle == handle)
                lookedUpSymbols.append(name)
                return symbol
            },
            closeLibrary: { closedHandles.append($0) }
        )

        do {
            let loadedLibrary = try #require(library)
            #expect(loadedLibrary.lookupSymbol("ts_parser_new") == symbol)
        }
        #expect(openedPaths == [availableURL.standardizedFileURL.path])
        #expect(lookedUpSymbols == ["ts_parser_new"])
        #expect(closedHandles.isEmpty)

        library = nil
        #expect(closedHandles == [handle])
    }

    @Test("bundled runtime library rejects escaping candidates and tries safe fallbacks")
    func bundledRuntimeLibraryRejectsEscapingCandidates() throws {
        let resourcesURL = URL(fileURLWithPath: "/tmp/CocxyTerminal.app/Contents/Resources", isDirectory: true)
        let fallbackURL = resourcesURL.appendingPathComponent("Grammars/libtree-sitter.dylib")
        let handle = UnsafeMutableRawPointer(bitPattern: 0xD10)!
        var openedPaths: [String] = []
        var closedHandles: [UnsafeMutableRawPointer] = []

        var library: TreeSitterRuntimeLibrary? = TreeSitterRuntimeLibrary.bundled(
            bundleResourceURL: resourcesURL,
            resourceCandidates: [
                "../libtree-sitter.dylib",
                "Grammars/libtree-sitter.dylib",
            ],
            fileExists: { $0.standardizedFileURL.path == fallbackURL.standardizedFileURL.path },
            openLibrary: { url in
                openedPaths.append(url.standardizedFileURL.path)
                return handle
            },
            lookupSymbol: { _, _ in nil },
            closeLibrary: { closedHandles.append($0) }
        )

        _ = try #require(library)
        #expect(openedPaths == [fallbackURL.standardizedFileURL.path])

        library = nil
        #expect(closedHandles == [handle])
    }

    @Test("symbol provider falls back to process lookup when no bundled core is present")
    func symbolProviderFallsBackToProcessLookup() {
        let symbol = UnsafeMutableRawPointer(bitPattern: 0xD20)!
        let provider = TreeSitterSymbolProvider.bundledOrProcess(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/CocxyTerminal.app/Contents/Resources", isDirectory: true),
            fileExists: { _ in false },
            openLibrary: { _ in
                Issue.record("no bundled library should be opened when candidates are absent")
                return nil
            },
            lookupLibrarySymbol: { _, _ in nil },
            closeLibrary: { _ in },
            lookupProcessSymbol: { name in
                name == "ts_parser_new" ? symbol : nil
            }
        )

        #expect(provider.lookupSymbol("ts_parser_new") == symbol)
        #expect(provider.retainedObjects.isEmpty)
    }

    @Test("resolved runtime retains symbol provider owner for function pointer lifetime")
    func resolvedRuntimeRetainsSymbolProviderOwner() {
        let symbol = UnsafeMutableRawPointer(bitPattern: 0xD30)!
        var releaseCount = 0
        var runtime: SyntaxTreeRuntime? = SyntaxTreeRuntime.treeSitterOrUnavailable(
            symbolProvider: TreeSitterSymbolProvider(
                lookupSymbol: { _ in symbol },
                retainedObjects: [LifetimeProbe { releaseCount += 1 }]
            )
        )

        #expect(runtime != nil)
        #expect(releaseCount == 0)

        runtime = nil
        #expect(releaseCount == 1)
    }

    @Test("resolved query adapter retains symbol provider owner for function pointer lifetime")
    func resolvedQueryAdapterRetainsSymbolProviderOwner() {
        let symbol = UnsafeMutableRawPointer(bitPattern: 0xD40)!
        var releaseCount = 0
        var adapter: TreeSitterHighlightQueryAdapter? = TreeSitterHighlightQueryAdapter.resolveBundledOrProcess(
            symbolProvider: TreeSitterSymbolProvider(
                lookupSymbol: { _ in symbol },
                retainedObjects: [LifetimeProbe { releaseCount += 1 }]
            )
        )

        #expect(adapter != nil)
        #expect(releaseCount == 0)

        adapter = nil
        #expect(releaseCount == 1)
    }

    @Test("adapter maps Tree-sitter C ABI calls into SyntaxTreeRuntime lifecycle")
    func adapterMapsTreeSitterLifecycle() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x70)!
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x71)!
        let languagePointer = UnsafeRawPointer(bitPattern: 0x72)!
        let rawRootNode = TreeSitterRawNode(
            context0: 0,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0x73),
            tree: UnsafeRawPointer(treeHandle)
        )
        let adapter = TreeSitterRuntimeAdapter(functions: TreeSitterRuntimeAdapter.Functions(
            createParser: {
                calls.events.append("create-parser")
                return parserHandle
            },
            deleteParser: { handle in
                calls.events.append("delete-parser")
                calls.closedHandles.append(handle)
            },
            languageFromEntryPoint: { entryPoint in
                calls.events.append("language-entry")
                #expect(entryPoint == calls.languageEntryPoint)
                return languagePointer
            },
            setLanguage: { parser, language in
                calls.events.append("set-language")
                #expect(parser == parserHandle)
                #expect(language == languagePointer)
                return true
            },
            parseString: { parser, oldTree, bytes, byteLength in
                calls.events.append("parse-bytes:\(byteLength)")
                #expect(parser == parserHandle)
                #expect(oldTree == nil)
                #expect(String(cString: bytes) == "let cafe = 1")
                #expect(byteLength == UInt32("let cafe = 1".utf8.count))
                return treeHandle
            },
            editTree: { _, _ in
                Issue.record("fresh parse should not edit an old tree")
            },
            rootNode: { handle in
                calls.events.append("root-node")
                #expect(handle == treeHandle)
                return rawRootNode
            },
            deleteTree: { handle in
                calls.events.append("delete-tree")
                calls.closedHandles.append(handle)
            },
            nodeType: { node in
                #expect(node.id == rawRootNode.id)
                return "source_file"
            },
            nodeIsNamed: { _ in true },
            nodeChildCount: { _ in 3 },
            nodeStartPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) },
            nodeEndPoint: { _ in TreeSitterRawPoint(row: 0, column: 12) }
        ))

        var tree: SyntaxTree? = try adapter.runtime().parse(text: "let cafe = 1", bundle: calls.makeBundle())

        #expect(tree?.rootNode == SyntaxNode(
            kind: "source_file",
            range: SyntaxPointRange(
                start: SyntaxPoint(line: 0, column: 0),
                end: SyntaxPoint(line: 0, column: 12)
            ),
            isNamed: true,
            childCount: 3
        ))
        #expect(calls.events == [
            "create-parser",
            "language-entry",
            "set-language",
            "parse-bytes:12",
            "root-node",
            "delete-parser",
        ])

        tree = nil
        #expect(calls.closedHandles == [parserHandle, treeHandle])
        #expect(calls.events.last == "delete-tree")
    }

    @Test("adapter converts Tree-sitter byte columns into editor UTF-16 columns")
    func adapterConvertsByteColumnsToUTF16Columns() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x90)!
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x91)!
        let languagePointer = UnsafeRawPointer(bitPattern: 0x92)!
        let rawRootNode = TreeSitterRawNode(
            context0: 0,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0x93),
            tree: UnsafeRawPointer(treeHandle)
        )
        let text = "let ☕️ = 1"
        let adapter = TreeSitterRuntimeAdapter(functions: TreeSitterRuntimeAdapter.Functions(
            createParser: { parserHandle },
            deleteParser: { handle in calls.closedHandles.append(handle) },
            languageFromEntryPoint: { _ in languagePointer },
            setLanguage: { _, _ in true },
            parseString: { _, _, _, byteLength in
                #expect(byteLength == UInt32(text.utf8.count))
                return treeHandle
            },
            editTree: { _, _ in },
            rootNode: { _ in rawRootNode },
            deleteTree: { handle in calls.closedHandles.append(handle) },
            nodeType: { _ in "source_file" },
            nodeIsNamed: { _ in true },
            nodeChildCount: { _ in 0 },
            nodeStartPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) },
            nodeEndPoint: { _ in TreeSitterRawPoint(row: 0, column: UInt32(text.utf8.count)) }
        ))

        let tree = try adapter.runtime().parse(text: text, bundle: calls.makeBundle())

        #expect(tree.rootNode.editorRange(in: EditorBuffer(text: text)) == EditorTextRange(location: 0, length: 10))
        #expect(tree.rootNode.range.end == SyntaxPoint(line: 0, column: 10))
        tree.close()
        #expect(calls.closedHandles == [parserHandle, treeHandle])
    }

    @Test("adapter rejects nil language pointers before parsing")
    func adapterRejectsNilLanguagePointer() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0x80)!
        let adapter = TreeSitterRuntimeAdapter(functions: TreeSitterRuntimeAdapter.Functions(
            createParser: { parserHandle },
            deleteParser: { handle in calls.closedHandles.append(handle) },
            languageFromEntryPoint: { _ in nil },
            setLanguage: { _, _ in
                calls.events.append("set-language")
                return true
            },
            parseString: { _, _, _, _ in
                calls.events.append("parse")
                return UnsafeMutableRawPointer(bitPattern: 0x81)
            },
            editTree: { _, _ in },
            rootNode: { _ in TreeSitterRawNode.invalid },
            deleteTree: { handle in calls.closedHandles.append(handle) },
            nodeType: { _ in "source_file" },
            nodeIsNamed: { _ in true },
            nodeChildCount: { _ in 0 },
            nodeStartPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) },
            nodeEndPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) }
        ))

        #expect(throws: SyntaxTreeRuntimeError.languageRejected(languageID: "swift")) {
            _ = try adapter.runtime().parse(text: "let value = 1", bundle: calls.makeBundle())
        }
        #expect(calls.events.isEmpty)
        #expect(calls.closedHandles == [parserHandle])
    }

    @Test("symbol resolver fails closed when Tree-sitter core symbols are absent")
    func symbolResolverFailsClosedWhenSymbolsAreAbsent() {
        var lookedUpSymbols: [String] = []
        let adapter = TreeSitterRuntimeAdapter.resolve { name in
            lookedUpSymbols.append(name)
            return nil
        }

        #expect(adapter == nil)
        #expect(lookedUpSymbols == ["ts_parser_new"])
    }

    @Test("adapter maps incremental edit values to Tree-sitter C ABI")
    func adapterMapsIncrementalEditValues() throws {
        let calls = SyntaxTreeCalls()
        let parserHandle = UnsafeMutableRawPointer(bitPattern: 0xB0)!
        let oldTreeHandle = UnsafeMutableRawPointer(bitPattern: 0xB1)!
        let newTreeHandle = UnsafeMutableRawPointer(bitPattern: 0xB2)!
        let languagePointer = UnsafeRawPointer(bitPattern: 0xB3)!
        let rawRootNode = TreeSitterRawNode(
            context0: 0,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0xB4),
            tree: UnsafeRawPointer(newTreeHandle)
        )
        let edit = SyntaxInputEdit(
            startByte: 4,
            oldEndByte: 9,
            newEndByte: 10,
            startPoint: SyntaxBytePoint(line: 0, byteColumn: 4),
            oldEndPoint: SyntaxBytePoint(line: 0, byteColumn: 9),
            newEndPoint: SyntaxBytePoint(line: 0, byteColumn: 10)
        )
        let previousTree = SyntaxTree(
            languageID: "swift",
            treeHandle: oldTreeHandle,
            rootNode: SyntaxNode(
                kind: "source_file",
                range: SyntaxPointRange(start: SyntaxPoint(line: 0, column: 0), end: SyntaxPoint(line: 0, column: 12))
            ),
            deleteTree: { calls.closedHandles.append($0) }
        )
        let adapter = TreeSitterRuntimeAdapter(functions: TreeSitterRuntimeAdapter.Functions(
            createParser: { parserHandle },
            deleteParser: { handle in calls.closedHandles.append(handle) },
            languageFromEntryPoint: { _ in languagePointer },
            setLanguage: { _, _ in true },
            parseString: { parser, oldTree, _, _ in
                #expect(parser == parserHandle)
                #expect(oldTree == UnsafeRawPointer(oldTreeHandle))
                return newTreeHandle
            },
            editTree: { tree, inputEdit in
                calls.events.append("edit")
                #expect(tree == oldTreeHandle)
                #expect(inputEdit.start_byte == 4)
                #expect(inputEdit.old_end_byte == 9)
                #expect(inputEdit.new_end_byte == 10)
                #expect(inputEdit.start_point.row == 0)
                #expect(inputEdit.start_point.column == 4)
                #expect(inputEdit.old_end_point.column == 9)
                #expect(inputEdit.new_end_point.column == 10)
            },
            rootNode: { _ in rawRootNode },
            deleteTree: { handle in calls.closedHandles.append(handle) },
            nodeType: { _ in "source_file" },
            nodeIsNamed: { _ in true },
            nodeChildCount: { _ in 0 },
            nodeStartPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) },
            nodeEndPoint: { _ in TreeSitterRawPoint(row: 0, column: 13) }
        ))

        let tree = try adapter.runtime().parseIncremental(
            text: "let values = 1",
            bundle: calls.makeBundle(),
            previousTree: previousTree,
            edit: edit
        )

        #expect(calls.events == ["edit"])
        tree.close()
        previousTree.close()
        #expect(calls.closedHandles == [parserHandle, newTreeHandle, oldTreeHandle])
    }
}

@Suite("Tree-sitter highlight query adapter")
struct TreeSitterHighlightQueryAdapterSwiftTestingTests {
    @Test("adapter compiles highlights query, executes cursor and returns captures")
    func adapterCollectsQueryCaptures() throws {
        let calls = SyntaxTreeCalls()
        let queryHandle = UnsafeMutableRawPointer(bitPattern: 0xA0)!
        let cursorHandle = UnsafeMutableRawPointer(bitPattern: 0xA1)!
        let languagePointer = UnsafeRawPointer(bitPattern: 0xA2)!
        let rootNode = TreeSitterRawNode(
            context0: 0,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0xA3),
            tree: UnsafeRawPointer(bitPattern: 0xA4)
        )
        let keywordNode = TreeSitterRawNode(
            context0: 1,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0xA5),
            tree: UnsafeRawPointer(bitPattern: 0xA4)
        )
        let functionNode = TreeSitterRawNode(
            context0: 2,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0xA6),
            tree: UnsafeRawPointer(bitPattern: 0xA4)
        )
        var captures = [
            TreeSitterRawQueryCapture(node: keywordNode, index: 0),
            TreeSitterRawQueryCapture(node: functionNode, index: 1),
        ]
        let querySource = SyntaxHighlightQuerySource.fixture
        let buffer = EditorBuffer(text: "let ☕️ = 1\nprint(1)\n")
        var adapter: TreeSitterHighlightQueryAdapter? = TreeSitterHighlightQueryAdapter(functions: TreeSitterHighlightQueryAdapter.Functions(
            languageFromEntryPoint: { entryPoint in
                calls.events.append("language-entry")
                #expect(entryPoint == calls.languageEntryPoint)
                return languagePointer
            },
            createQuery: { language, source, length, errorOffset, _ in
                calls.events.append("query:\(String(cString: source)):\(length)")
                #expect(language == languagePointer)
                #expect(length == UInt32(querySource.query.utf8.count))
                errorOffset.pointee = 0
                return queryHandle
            },
            deleteQuery: { handle in
                calls.events.append("delete-query")
                #expect(handle == queryHandle)
            },
            createCursor: {
                calls.events.append("create-cursor")
                return cursorHandle
            },
            deleteCursor: { handle in
                calls.events.append("delete-cursor")
                #expect(handle == cursorHandle)
            },
            exec: { cursor, query, node in
                calls.events.append("exec")
                #expect(cursor == cursorHandle)
                #expect(query == queryHandle)
                #expect(node == rootNode)
            },
            nextCapture: { cursor in
                #expect(cursor == cursorHandle)
                return captures.isEmpty ? nil : captures.removeFirst()
            },
            captureName: { query, index in
                #expect(query == queryHandle)
                return index == 0 ? "keyword.control" : "function.call"
            },
            rootNode: { handle in
                calls.events.append("root")
                #expect(handle == UnsafeMutableRawPointer(bitPattern: 0x200)!)
                return rootNode
            },
            nodeStartPoint: { node in
                node == keywordNode
                    ? TreeSitterRawPoint(row: 0, column: 0)
                    : TreeSitterRawPoint(row: 1, column: 0)
            },
            nodeEndPoint: { node in
                node == keywordNode
                    ? TreeSitterRawPoint(row: 0, column: 3)
                    : TreeSitterRawPoint(row: 1, column: 5)
            }
        ))

        let syntaxCaptures = try adapter?.collectCaptures(
            for: SyntaxTree.fixtureTree(),
            bundle: calls.makeBundle(),
            querySource: querySource,
            buffer: buffer
        )
        adapter = nil

        #expect(syntaxCaptures == [
            SyntaxQueryCapture(
                captureName: "keyword.control",
                range: SyntaxPointRange(
                    start: SyntaxPoint(line: 0, column: 0),
                    end: SyntaxPoint(line: 0, column: 3)
                )
            ),
            SyntaxQueryCapture(
                captureName: "function.call",
                range: SyntaxPointRange(
                    start: SyntaxPoint(line: 1, column: 0),
                    end: SyntaxPoint(line: 1, column: 5)
                )
            ),
        ])
        #expect(calls.events == [
            "language-entry",
            "query:\(querySource.query):\(querySource.query.utf8.count)",
            "create-cursor",
            "root",
            "exec",
            "delete-cursor",
            "delete-query",
        ])
    }

    @Test("adapter skips captures whose names cannot be resolved and continues")
    func adapterSkipsUnresolvedCaptureNames() throws {
        let calls = SyntaxTreeCalls()
        let queryHandle = UnsafeMutableRawPointer(bitPattern: 0xD0)!
        let cursorHandle = UnsafeMutableRawPointer(bitPattern: 0xD1)!
        let languagePointer = UnsafeRawPointer(bitPattern: 0xD2)!
        let rootNode = TreeSitterRawNode(
            context0: 0,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0xD3),
            tree: UnsafeRawPointer(bitPattern: 0xD4)
        )
        let unresolvedNode = TreeSitterRawNode(
            context0: 1,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0xD5),
            tree: UnsafeRawPointer(bitPattern: 0xD4)
        )
        let keywordNode = TreeSitterRawNode(
            context0: 2,
            context1: 0,
            context2: 0,
            context3: 0,
            id: UnsafeRawPointer(bitPattern: 0xD6),
            tree: UnsafeRawPointer(bitPattern: 0xD4)
        )
        var captures = [
            TreeSitterRawQueryCapture(node: unresolvedNode, index: 99),
            TreeSitterRawQueryCapture(node: keywordNode, index: 0),
        ]
        var resolvedNames: [UInt32] = []
        let adapter = TreeSitterHighlightQueryAdapter(functions: TreeSitterHighlightQueryAdapter.Functions(
            languageFromEntryPoint: { _ in languagePointer },
            createQuery: { _, _, _, errorOffset, _ in
                errorOffset.pointee = 0
                return queryHandle
            },
            deleteQuery: { _ in },
            createCursor: { cursorHandle },
            deleteCursor: { _ in },
            exec: { _, _, node in
                #expect(node == rootNode)
            },
            nextCapture: { _ in
                captures.isEmpty ? nil : captures.removeFirst()
            },
            captureName: { _, index in
                resolvedNames.append(index)
                return index == 0 ? "keyword.control" : nil
            },
            rootNode: { handle in
                #expect(handle == UnsafeMutableRawPointer(bitPattern: 0x200)!)
                return rootNode
            },
            nodeStartPoint: { node in
                node == keywordNode
                    ? TreeSitterRawPoint(row: 0, column: 0)
                    : TreeSitterRawPoint(row: 0, column: 4)
            },
            nodeEndPoint: { node in
                node == keywordNode
                    ? TreeSitterRawPoint(row: 0, column: 3)
                    : TreeSitterRawPoint(row: 0, column: 9)
            }
        ))

        let syntaxCaptures = try adapter.collectCaptures(
            for: SyntaxTree.fixtureTree(),
            bundle: calls.makeBundle(),
            querySource: .fixture,
            buffer: EditorBuffer(text: "let value = 1\n")
        )

        #expect(syntaxCaptures == [
            SyntaxQueryCapture(
                captureName: "keyword.control",
                range: SyntaxPointRange(
                    start: SyntaxPoint(line: 0, column: 0),
                    end: SyntaxPoint(line: 0, column: 3)
                )
            ),
        ])
        #expect(resolvedNames == [99, 0])
    }

    @Test("adapter maps query compilation failures without allocating a cursor")
    func adapterMapsQueryCompilationFailure() {
        let calls = SyntaxTreeCalls()
        let adapter = TreeSitterHighlightQueryAdapter(functions: TreeSitterHighlightQueryAdapter.Functions(
            languageFromEntryPoint: { _ in UnsafeRawPointer(bitPattern: 0xB0) },
            createQuery: { _, _, _, errorOffset, _ in
                calls.events.append("query")
                errorOffset.pointee = 7
                return nil
            },
            deleteQuery: { _ in calls.events.append("delete-query") },
            createCursor: {
                calls.events.append("cursor")
                return UnsafeMutableRawPointer(bitPattern: 0xB1)
            },
            deleteCursor: { _ in calls.events.append("delete-cursor") },
            exec: { _, _, _ in calls.events.append("exec") },
            nextCapture: { _ in nil },
            captureName: { _, _ in nil },
            rootNode: { _ in TreeSitterRawNode.invalid },
            nodeStartPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) },
            nodeEndPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) }
        ))

        #expect(throws: TreeSitterHighlightQueryAdapterError.queryCompilationFailed(
            languageID: "swift",
            offset: 7,
            errorType: 0
        )) {
            _ = try adapter.collectCaptures(
                for: SyntaxTree.fixtureTree(),
                bundle: calls.makeBundle(),
                querySource: .fixture,
                buffer: EditorBuffer(text: "let value = 1\n")
            )
        }
        #expect(calls.events == ["query"])
    }

    @Test("adapter releases query when cursor allocation fails")
    func adapterReleasesQueryWhenCursorAllocationFails() {
        let calls = SyntaxTreeCalls()
        let queryHandle = UnsafeMutableRawPointer(bitPattern: 0xC0)!
        var adapter: TreeSitterHighlightQueryAdapter? = TreeSitterHighlightQueryAdapter(functions: TreeSitterHighlightQueryAdapter.Functions(
            languageFromEntryPoint: { _ in UnsafeRawPointer(bitPattern: 0xC1) },
            createQuery: { _, _, _, _, _ in queryHandle },
            deleteQuery: { handle in
                #expect(handle == queryHandle)
                calls.events.append("delete-query")
            },
            createCursor: { nil },
            deleteCursor: { _ in calls.events.append("delete-cursor") },
            exec: { _, _, _ in calls.events.append("exec") },
            nextCapture: { _ in nil },
            captureName: { _, _ in nil },
            rootNode: { _ in TreeSitterRawNode.invalid },
            nodeStartPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) },
            nodeEndPoint: { _ in TreeSitterRawPoint(row: 0, column: 0) }
        ))

        #expect(throws: TreeSitterHighlightQueryAdapterError.cursorAllocationFailed(languageID: "swift")) {
            _ = try adapter?.collectCaptures(
                for: SyntaxTree.fixtureTree(),
                bundle: calls.makeBundle(),
                querySource: .fixture,
                buffer: EditorBuffer(text: "let value = 1\n")
            )
        }
        adapter = nil
        #expect(calls.events == ["delete-query"])
    }

    @Test("symbol resolver fails closed when query symbols are absent")
    func querySymbolResolverFailsClosedWhenSymbolsAreAbsent() {
        var lookedUpSymbols: [String] = []
        let adapter = TreeSitterHighlightQueryAdapter.resolve { name in
            lookedUpSymbols.append(name)
            return nil
        }

        #expect(adapter == nil)
        #expect(lookedUpSymbols == ["ts_query_new"])
    }
}

@Suite("Syntax tree parser")
struct SyntaxTreeParserSwiftTestingTests {
    @Test("parser loads bundle, parses tree, extracts tokens and closes the tree")
    func parserComposesBundleRuntimeAndTokenExtraction() throws {
        let calls = SyntaxTreeCalls()
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x60)!
        let expectedToken = SyntaxToken(
            role: .keyword,
            range: EditorTextRange(location: 0, length: 3)
        )
        let tree = SyntaxTree(
            languageID: " swift ",
            treeHandle: treeHandle,
            rootNode: SyntaxNode(
                kind: "source_file",
                range: SyntaxPointRange(
                    start: SyntaxPoint(line: 0, column: 0),
                    end: SyntaxPoint(line: 0, column: 13)
                )
            ),
            deleteTree: { handle in
                calls.events.append("close-tree")
                calls.closedHandles.append(handle)
            }
        )
        let parser = SyntaxTreeParser(
            loadBundle: { language in
                calls.events.append("bundle:\(language.languageID)")
                return calls.makeBundle()
            },
            parseTree: { text, bundle in
                calls.events.append("parse:\(text):\(bundle.querySource.languageID)")
                return tree
            },
            extractTokens: { parsedTree, bundle, buffer in
                calls.events.append("extract:\(parsedTree.languageID):\(bundle.querySource.languageID):\(buffer.text)")
                #expect(parsedTree.isClosed == false)
                return [expectedToken]
            }
        )

        let tokens = try parser.tokens(
            for: "let value = 1",
            language: SyntaxLanguageManifest.phaseCDefaults.languages[0]
        )

        #expect(tokens == [expectedToken])
        #expect(calls.events == [
            "bundle:swift",
            "parse:let value = 1:swift",
            "extract:swift:swift:let value = 1",
            "close-tree",
        ])
        #expect(calls.closedHandles == [treeHandle])
    }

    @Test("parser maps bundle load failures before parsing")
    func parserMapsBundleFailure() {
        let calls = SyntaxTreeCalls()
        let parser = SyntaxTreeParser(
            loadBundle: { language in
                calls.events.append("bundle:\(language.languageID)")
                throw SyntaxGrammarBundleLoaderError.parserResourceUnavailable(languageID: "swift")
            },
            parseTree: { _, _ in
                calls.events.append("parse")
                throw SyntaxTreeRuntimeError.parseFailed(languageID: "swift")
            },
            extractTokens: { _, _, _ in
                calls.events.append("extract")
                return []
            }
        )

        #expect(throws: SyntaxTreeParserError.bundleUnavailable(languageID: "swift")) {
            _ = try parser.tokens(
                for: "let value = 1",
                language: SyntaxLanguageManifest.phaseCDefaults.languages[0]
            )
        }
        #expect(calls.events == ["bundle:swift"])
    }

    @Test("parser maps runtime failures and releases the loaded grammar library")
    func parserMapsRuntimeFailureAndReleasesBundle() {
        let calls = SyntaxTreeCalls()
        let parser = SyntaxTreeParser(
            loadBundle: { language in
                calls.events.append("bundle:\(language.languageID)")
                return calls.makeBundle(closeLibrary: {
                    calls.events.append("close-library")
                })
            },
            parseTree: { _, _ in
                calls.events.append("parse")
                throw SyntaxTreeRuntimeError.parseFailed(languageID: "swift")
            },
            extractTokens: { _, _, _ in
                calls.events.append("extract")
                return []
            }
        )

        #expect(throws: SyntaxTreeParserError.runtimeFailed(languageID: "swift")) {
            _ = try parser.tokens(
                for: "let value = 1",
                language: SyntaxLanguageManifest.phaseCDefaults.languages[0]
            )
        }
        #expect(calls.events == ["bundle:swift", "parse", "close-library"])
    }

    @Test("parser closes the parsed tree when token extraction fails")
    func parserClosesTreeWhenExtractionFails() {
        let calls = SyntaxTreeCalls()
        let treeHandle = UnsafeMutableRawPointer(bitPattern: 0x70)!
        let tree = SyntaxTree(
            languageID: "swift",
            treeHandle: treeHandle,
            rootNode: SyntaxNode(
                kind: "source_file",
                range: SyntaxPointRange(
                    start: SyntaxPoint(line: 0, column: 0),
                    end: SyntaxPoint(line: 0, column: 13)
                )
            ),
            deleteTree: { handle in
                calls.events.append("close-tree")
                calls.closedHandles.append(handle)
            }
        )
        let parser = SyntaxTreeParser(
            loadBundle: { _ in calls.makeBundle() },
            parseTree: { _, _ in tree },
            extractTokens: { _, _, _ in
                calls.events.append("extract")
                throw SyntaxTreeParserError.queryExecutionUnavailable(languageID: "swift")
            }
        )

        #expect(throws: SyntaxTreeParserError.queryExecutionUnavailable(languageID: "swift")) {
            _ = try parser.tokens(
                for: "let value = 1",
                language: SyntaxLanguageManifest.phaseCDefaults.languages[0]
            )
        }
        #expect(calls.events == ["extract", "close-tree"])
        #expect(calls.closedHandles == [treeHandle])
    }
}

@Suite("Syntax tree service")
struct SyntaxTreeServiceSwiftTestingTests {
    @Test("service returns syntax decorations for loadable languages")
    func serviceHighlightsLoadableLanguage() throws {
        let registry = try SyntaxLanguageRegistry(
            manifest: .fixtureSwift,
            resourceExists: { _ in true }
        )
        let parser = FakeSyntaxParser(tokens: [
            SyntaxToken(role: .keyword, range: EditorTextRange(location: 0, length: 3)),
        ])
        let service = SyntaxTreeService(registry: registry, parser: parser)

        let decorations = service.decorations(
            forFileURL: URL(fileURLWithPath: "/tmp/App.swift"),
            buffer: EditorBuffer(text: "let value = 1\n")
        )

        #expect(parser.requests == ["swift"])
        #expect(decorations.map(\.message) == ["syntax.keyword"])
    }

    @Test("service degrades to plain text when grammar resources are unavailable")
    func serviceSkipsUnavailableGrammar() throws {
        let registry = try SyntaxLanguageRegistry(
            manifest: .fixtureSwift,
            resourceExists: { _ in false }
        )
        let parser = FakeSyntaxParser(tokens: [
            SyntaxToken(role: .keyword, range: EditorTextRange(location: 0, length: 3)),
        ])
        let service = SyntaxTreeService(registry: registry, parser: parser)

        let decorations = service.decorations(
            forFileURL: URL(fileURLWithPath: "/tmp/App.swift"),
            buffer: EditorBuffer(text: "let value = 1\n")
        )

        #expect(parser.requests.isEmpty)
        #expect(decorations.isEmpty)
    }

    @Test("service degrades to plain text when parser fails")
    func serviceSkipsParserFailure() throws {
        let registry = try SyntaxLanguageRegistry(
            manifest: .fixtureSwift,
            resourceExists: { _ in true }
        )
        let parser = FakeSyntaxParser(error: SyntaxParserError.parserUnavailable(languageID: "swift"))
        let service = SyntaxTreeService(registry: registry, parser: parser)

        let decorations = service.decorations(
            forFileURL: URL(fileURLWithPath: "/tmp/App.swift"),
            buffer: EditorBuffer(text: "let value = 1\n")
        )

        #expect(parser.requests == ["swift"])
        #expect(decorations.isEmpty)
    }
}

@Suite("Syntax parse coordinator")
struct SyntaxParseCoordinatorSwiftTestingTests {
    @Test("coordinator creates versioned parse snapshots and accepts the current result")
    func coordinatorAcceptsCurrentResult() throws {
        let documentID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let document = EditorDocument(
            id: documentID,
            fileURL: URL(fileURLWithPath: "/tmp/App.swift"),
            text: "let value = 1\n"
        )
        let registry = try SyntaxLanguageRegistry(
            manifest: .fixtureSwift,
            resourceExists: { _ in true }
        )
        let parser = FakeSyntaxParser(tokens: [
            SyntaxToken(role: .keyword, range: EditorTextRange(location: 0, length: 3)),
        ])
        var coordinator = SyntaxParseCoordinator(
            service: SyntaxTreeService(registry: registry, parser: parser)
        )

        let maybeRequest = coordinator.makeRequest(for: document)
        let request = try #require(maybeRequest)
        let result = coordinator.parse(request)

        #expect(request.documentID == documentID)
        #expect(request.version == 0)
        #expect(request.buffer.text == "let value = 1\n")
        #expect(result.documentID == documentID)
        #expect(result.version == 0)
        #expect(parser.requests == ["swift"])
        #expect(parser.texts == ["let value = 1\n"])
        #expect(coordinator.acceptedDecorations(from: result)?.map(\.message) == ["syntax.keyword"])
    }

    @Test("coordinator rejects stale syntax results after a newer document version is requested")
    func coordinatorRejectsStaleResult() throws {
        let documentID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        var document = EditorDocument(
            id: documentID,
            fileURL: URL(fileURLWithPath: "/tmp/App.swift"),
            text: "let value = 1\n"
        )
        let registry = try SyntaxLanguageRegistry(
            manifest: .fixtureSwift,
            resourceExists: { _ in true }
        )
        let parser = FakeSyntaxParser(tokens: [
            SyntaxToken(role: .keyword, range: EditorTextRange(location: 0, length: 3)),
        ])
        var coordinator = SyntaxParseCoordinator(
            service: SyntaxTreeService(registry: registry, parser: parser)
        )

        let maybeStaleRequest = coordinator.makeRequest(for: document)
        let staleRequest = try #require(maybeStaleRequest)
        document.replaceSelection(.caret(at: 0), with: "// ")
        let maybeCurrentRequest = coordinator.makeRequest(for: document)
        let currentRequest = try #require(maybeCurrentRequest)

        let staleResult = coordinator.parse(staleRequest)
        let currentResult = coordinator.parse(currentRequest)

        #expect(staleRequest.version == 0)
        #expect(currentRequest.version == 1)
        #expect(coordinator.acceptedDecorations(from: staleResult) == nil)
        #expect(coordinator.acceptedDecorations(from: currentResult)?.map(\.message) == ["syntax.keyword"])
        #expect(parser.texts == ["let value = 1\n", "// let value = 1\n"])
    }

    @Test("coordinator does not schedule syntax parse for unfiled documents")
    func coordinatorSkipsUnfiledDocuments() {
        let document = EditorDocument(text: "let value = 1\n")
        let parser = FakeSyntaxParser()
        var coordinator = SyntaxParseCoordinator(
            service: SyntaxTreeService(
                registry: try! SyntaxLanguageRegistry(manifest: .fixtureSwift, resourceExists: { _ in true }),
                parser: parser
            )
        )

        #expect(coordinator.makeRequest(for: document) == nil)
        #expect(parser.requests.isEmpty)
    }

    @Test("unsupported files produce an accepted empty result to clear stale syntax")
    func coordinatorAcceptsEmptyResultForUnsupportedFiles() throws {
        let document = EditorDocument(
            fileURL: URL(fileURLWithPath: "/tmp/README.md"),
            text: "# Notes\n"
        )
        let registry = try SyntaxLanguageRegistry(
            manifest: .fixtureSwift,
            resourceExists: { _ in true }
        )
        let parser = FakeSyntaxParser(tokens: [
            SyntaxToken(role: .keyword, range: EditorTextRange(location: 0, length: 3)),
        ])
        var coordinator = SyntaxParseCoordinator(
            service: SyntaxTreeService(registry: registry, parser: parser)
        )

        let maybeRequest = coordinator.makeRequest(for: document)
        let request = try #require(maybeRequest)
        let result = coordinator.parse(request)

        #expect(parser.requests.isEmpty)
        #expect(result.decorations.isEmpty)
        #expect(coordinator.acceptedDecorations(from: result) == [])
    }
}

@Suite("Syntax grammar locator")
struct SyntaxGrammarLocatorSwiftTestingTests {
    @Test("locator builds bundled parser URLs and Tree-sitter symbol names")
    func locatorBuildsLoadPlan() throws {
        let resourcesURL = URL(fileURLWithPath: "/tmp/CocxyTerminal.app/Contents/Resources", isDirectory: true)
        let locator = SyntaxGrammarLocator(
            bundleResourceURL: resourcesURL,
            fileExists: { $0.path.hasSuffix("Grammars/typescript/parser.dylib") }
        )
        let language = SyntaxLanguage(
            languageID: "type-script",
            displayName: "TypeScript",
            fileExtensions: ["ts"],
            parserResource: "Grammars/typescript/parser.dylib",
            highlightQueryResource: "Grammars/typescript/highlights.scm",
            upstreamVersion: "0.1.0",
            license: "MIT",
            checksum: nil
        )

        let plan = try locator.loadPlan(for: language)

        #expect(plan.parserURL.path.hasSuffix("Contents/Resources/Grammars/typescript/parser.dylib"))
        #expect(plan.symbolName == "tree_sitter_type_script")
    }

    @Test("locator rejects missing parser resources")
    func locatorRejectsMissingParser() throws {
        let locator = SyntaxGrammarLocator(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            fileExists: { _ in false }
        )

        #expect(throws: SyntaxGrammarLocatorError.missingParserResource("Grammars/swift/parser.dylib")) {
            _ = try locator.loadPlan(for: SyntaxLanguageManifest.phaseCDefaults.languages[0])
        }
    }

    @Test("locator rejects parser resources that escape the bundle")
    func locatorRejectsEscapingParserPath() throws {
        let locator = SyntaxGrammarLocator(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            fileExists: { _ in true }
        )
        let language = SyntaxLanguage(
            languageID: "swift",
            displayName: "Swift",
            fileExtensions: ["swift"],
            parserResource: "../parser.dylib",
            highlightQueryResource: "swift/highlights.scm",
            upstreamVersion: "0.1.0",
            license: "MIT",
            checksum: nil
        )

        #expect(throws: SyntaxGrammarLocatorError.resourceEscapesBundle("../parser.dylib")) {
            _ = try locator.loadPlan(for: language)
        }
    }
}

@Suite("Syntax highlight query loader")
struct SyntaxHighlightQueryLoaderSwiftTestingTests {
    @Test("query loader reads bundled highlights.scm text")
    func queryLoaderReadsBundledQuery() throws {
        let resourcesURL = URL(fileURLWithPath: "/tmp/CocxyTerminal.app/Contents/Resources", isDirectory: true)
        let language = SyntaxLanguageManifest.phaseCDefaults.languages[0]
        let loader = SyntaxHighlightQueryLoader(
            bundleResourceURL: resourcesURL,
            fileExists: { $0.path.hasSuffix("Grammars/swift/highlights.scm") },
            readString: { url in
                #expect(url.path.hasSuffix("Contents/Resources/Grammars/swift/highlights.scm"))
                return "(function_declaration name: (identifier) @function)"
            }
        )

        let source = try loader.querySource(for: language)

        #expect(source.languageID == "swift")
        #expect(source.resourceURL.path.hasSuffix("Contents/Resources/Grammars/swift/highlights.scm"))
        #expect(source.query.contains("@function"))
    }

    @Test("query loader rejects missing query resources")
    func queryLoaderRejectsMissingQuery() throws {
        let loader = SyntaxHighlightQueryLoader(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            fileExists: { _ in false },
            readString: { _ in "" }
        )

        #expect(throws: SyntaxHighlightQueryLoaderError.missingQueryResource("Grammars/swift/highlights.scm")) {
            _ = try loader.querySource(for: SyntaxLanguageManifest.phaseCDefaults.languages[0])
        }
    }

    @Test("query loader rejects query resources that escape the bundle")
    func queryLoaderRejectsEscapingQueryPath() throws {
        let loader = SyntaxHighlightQueryLoader(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            fileExists: { _ in true },
            readString: { _ in "(identifier) @variable" }
        )
        let language = SyntaxLanguage(
            languageID: "swift",
            displayName: "Swift",
            fileExtensions: ["swift"],
            parserResource: "Grammars/swift/parser.dylib",
            highlightQueryResource: "../highlights.scm",
            upstreamVersion: "0.1.0",
            license: "MIT",
            checksum: nil
        )

        #expect(throws: SyntaxHighlightQueryLoaderError.resourceEscapesBundle("../highlights.scm")) {
            _ = try loader.querySource(for: language)
        }
    }

    @Test("query loader rejects empty highlight queries")
    func queryLoaderRejectsEmptyQueryText() throws {
        let loader = SyntaxHighlightQueryLoader(
            bundleResourceURL: URL(fileURLWithPath: "/tmp/Resources", isDirectory: true),
            fileExists: { _ in true },
            readString: { _ in " \n\t " }
        )

        #expect(throws: SyntaxHighlightQueryLoaderError.emptyQuery("Grammars/swift/highlights.scm")) {
            _ = try loader.querySource(for: SyntaxLanguageManifest.phaseCDefaults.languages[0])
        }
    }
}

@Suite("Syntax grammar dynamic loader")
struct SyntaxGrammarDynamicLoaderSwiftTestingTests {
    @Test("dynamic loader opens parser library and resolves the Tree-sitter language symbol")
    func dynamicLoaderResolvesLanguageSymbol() throws {
        let calls = DynamicLoaderCalls()
        let libraryHandle = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let languageSymbol = UnsafeMutableRawPointer(bitPattern: 0x2)!
        let plan = SyntaxGrammarLoadPlan(
            parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
            symbolName: "tree_sitter_swift"
        )
        let loader = SyntaxGrammarDynamicLoader(
            openLibrary: { url in
                calls.openedPaths.append(url.path)
                return libraryHandle
            },
            lookupSymbol: { handle, symbolName in
                #expect(handle == libraryHandle)
                calls.lookupSymbols.append(symbolName)
                return languageSymbol
            },
            closeLibrary: { handle in
                #expect(handle == libraryHandle)
                calls.closeCount += 1
            }
        )

        var library: SyntaxGrammarLibrary? = try loader.load(plan: plan)

        #expect(calls.openedPaths == ["/tmp/Resources/Grammars/swift/parser.dylib"])
        #expect(calls.lookupSymbols == ["tree_sitter_swift"])
        #expect(library?.parserURL == plan.parserURL)
        #expect(library?.symbolName == "tree_sitter_swift")
        #expect(library?.languageEntryPoint == languageSymbol)

        library = nil
        #expect(calls.closeCount == 1)
    }

    @Test("dynamic loader fails before symbol lookup when dlopen fails")
    func dynamicLoaderFailsBeforeLookupWhenOpenFails() throws {
        let calls = DynamicLoaderCalls()
        let plan = SyntaxGrammarLoadPlan(
            parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
            symbolName: "tree_sitter_swift"
        )
        let loader = SyntaxGrammarDynamicLoader(
            openLibrary: { _ in nil },
            lookupSymbol: { _, symbolName in
                calls.lookupSymbols.append(symbolName)
                return UnsafeMutableRawPointer(bitPattern: 0x2)
            },
            closeLibrary: { _ in calls.closeCount += 1 }
        )

        #expect(throws: SyntaxGrammarDynamicLoaderError.openFailed(plan.parserURL.path)) {
            _ = try loader.load(plan: plan)
        }
        #expect(calls.lookupSymbols.isEmpty)
        #expect(calls.closeCount == 0)
    }

    @Test("dynamic loader closes the library when the language symbol is missing")
    func dynamicLoaderClosesLibraryWhenSymbolMissing() throws {
        let calls = DynamicLoaderCalls()
        let libraryHandle = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let plan = SyntaxGrammarLoadPlan(
            parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
            symbolName: "tree_sitter_swift"
        )
        let loader = SyntaxGrammarDynamicLoader(
            openLibrary: { _ in libraryHandle },
            lookupSymbol: { _, symbolName in
                calls.lookupSymbols.append(symbolName)
                return nil
            },
            closeLibrary: { handle in
                #expect(handle == libraryHandle)
                calls.closeCount += 1
            }
        )

        #expect(throws: SyntaxGrammarDynamicLoaderError.missingSymbol("tree_sitter_swift")) {
            _ = try loader.load(plan: plan)
        }
        #expect(calls.lookupSymbols == ["tree_sitter_swift"])
        #expect(calls.closeCount == 1)
    }
}

@Suite("Syntax grammar bundle loader")
struct SyntaxGrammarBundleLoaderSwiftTestingTests {
    @Test("bundle loader composes parser plan, highlight query and parser library")
    func bundleLoaderComposesGrammarPieces() throws {
        let calls = DynamicLoaderCalls()
        let language = SyntaxLanguageManifest.phaseCDefaults.languages[0]
        let plan = SyntaxGrammarLoadPlan(
            parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
            symbolName: "tree_sitter_swift"
        )
        let query = SyntaxHighlightQuerySource(
            languageID: "swift",
            resourceURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/highlights.scm"),
            query: "(identifier) @variable"
        )
        let libraryHandle = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let languageSymbol = UnsafeMutableRawPointer(bitPattern: 0x2)!
        let loader = SyntaxGrammarBundleLoader(
            loadPlan: { requestedLanguage in
                calls.events.append("plan:\(requestedLanguage.languageID)")
                return plan
            },
            loadQuery: { requestedLanguage in
                calls.events.append("query:\(requestedLanguage.languageID)")
                return query
            },
            loadLibrary: { requestedPlan in
                calls.events.append("library:\(requestedPlan.symbolName)")
                return SyntaxGrammarLibrary(
                    parserURL: requestedPlan.parserURL,
                    symbolName: requestedPlan.symbolName,
                    languageEntryPoint: languageSymbol,
                    libraryHandle: libraryHandle,
                    closeLibrary: { _ in calls.closeCount += 1 }
                )
            }
        )

        var bundle: SyntaxGrammarBundle? = try loader.bundle(for: language)

        #expect(calls.events == ["plan:swift", "query:swift", "library:tree_sitter_swift"])
        #expect(bundle?.language.languageID == "swift")
        #expect(bundle?.querySource == query)
        #expect(bundle?.library.symbolName == "tree_sitter_swift")

        bundle = nil
        #expect(calls.closeCount == 1)
    }

    @Test("bundle loader stops before query loading when parser resources are unavailable")
    func bundleLoaderStopsBeforeQueryWhenParserPlanFails() throws {
        let calls = DynamicLoaderCalls()
        let loader = SyntaxGrammarBundleLoader(
            loadPlan: { language in
                calls.events.append("plan:\(language.languageID)")
                throw SyntaxGrammarLocatorError.missingParserResource(language.parserResource)
            },
            loadQuery: { language in
                calls.events.append("query:\(language.languageID)")
                return SyntaxHighlightQuerySource(
                    languageID: language.languageID,
                    resourceURL: URL(fileURLWithPath: "/tmp/query.scm"),
                    query: "(identifier) @variable"
                )
            },
            loadLibrary: { plan in
                calls.events.append("library:\(plan.symbolName)")
                throw SyntaxGrammarDynamicLoaderError.openFailed(plan.parserURL.path)
            }
        )

        #expect(throws: SyntaxGrammarBundleLoaderError.parserResourceUnavailable(languageID: "swift")) {
            _ = try loader.bundle(for: SyntaxLanguageManifest.phaseCDefaults.languages[0])
        }
        #expect(calls.events == ["plan:swift"])
    }

    @Test("bundle loader stops before dlopen when highlight query is unavailable")
    func bundleLoaderStopsBeforeLibraryWhenQueryFails() throws {
        let calls = DynamicLoaderCalls()
        let plan = SyntaxGrammarLoadPlan(
            parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
            symbolName: "tree_sitter_swift"
        )
        let loader = SyntaxGrammarBundleLoader(
            loadPlan: { language in
                calls.events.append("plan:\(language.languageID)")
                return plan
            },
            loadQuery: { language in
                calls.events.append("query:\(language.languageID)")
                throw SyntaxHighlightQueryLoaderError.emptyQuery(language.highlightQueryResource)
            },
            loadLibrary: { plan in
                calls.events.append("library:\(plan.symbolName)")
                throw SyntaxGrammarDynamicLoaderError.openFailed(plan.parserURL.path)
            }
        )

        #expect(throws: SyntaxGrammarBundleLoaderError.highlightQueryUnavailable(languageID: "swift")) {
            _ = try loader.bundle(for: SyntaxLanguageManifest.phaseCDefaults.languages[0])
        }
        #expect(calls.events == ["plan:swift", "query:swift"])
    }

    @Test("bundle loader maps dynamic library failures to parser library unavailable")
    func bundleLoaderMapsLibraryFailure() throws {
        let calls = DynamicLoaderCalls()
        let plan = SyntaxGrammarLoadPlan(
            parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
            symbolName: "tree_sitter_swift"
        )
        let loader = SyntaxGrammarBundleLoader(
            loadPlan: { language in
                calls.events.append("plan:\(language.languageID)")
                return plan
            },
            loadQuery: { language in
                calls.events.append("query:\(language.languageID)")
                return SyntaxHighlightQuerySource(
                    languageID: language.languageID,
                    resourceURL: URL(fileURLWithPath: "/tmp/query.scm"),
                    query: "(identifier) @variable"
                )
            },
            loadLibrary: { plan in
                calls.events.append("library:\(plan.symbolName)")
                throw SyntaxGrammarDynamicLoaderError.missingSymbol(plan.symbolName)
            }
        )

        #expect(throws: SyntaxGrammarBundleLoaderError.parserLibraryUnavailable(languageID: "swift")) {
            _ = try loader.bundle(for: SyntaxLanguageManifest.phaseCDefaults.languages[0])
        }
        #expect(calls.events == ["plan:swift", "query:swift", "library:tree_sitter_swift"])
    }

    @Test("bundle loader stops before query loading when parser checksum verification fails")
    func bundleLoaderStopsBeforeQueryWhenChecksumFails() throws {
        let calls = DynamicLoaderCalls()
        let plan = SyntaxGrammarLoadPlan(
            parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
            symbolName: "tree_sitter_swift"
        )
        let loader = SyntaxGrammarBundleLoader(
            loadPlan: { language in
                calls.events.append("plan:\(language.languageID)")
                return plan
            },
            verifyParserResource: { language, _ in
                calls.events.append("verify:\(language.languageID)")
                throw SyntaxGrammarChecksumVerifierError.checksumMismatch(
                    expected: "sha256:expected",
                    actual: "sha256:actual"
                )
            },
            loadQuery: { language in
                calls.events.append("query:\(language.languageID)")
                return SyntaxHighlightQuerySource(
                    languageID: language.languageID,
                    resourceURL: URL(fileURLWithPath: "/tmp/query.scm"),
                    query: "(identifier) @variable"
                )
            },
            loadLibrary: { plan in
                calls.events.append("library:\(plan.symbolName)")
                throw SyntaxGrammarDynamicLoaderError.missingSymbol(plan.symbolName)
            }
        )

        #expect(throws: SyntaxGrammarBundleLoaderError.parserChecksumMismatch(languageID: "swift")) {
            _ = try loader.bundle(for: SyntaxLanguageManifest.phaseCDefaults.languages[0])
        }
        #expect(calls.events == ["plan:swift", "verify:swift"])
    }
}

@Suite("Syntax grammar checksum verifier")
struct SyntaxGrammarChecksumVerifierSwiftTestingTests {
    @Test("verifier accepts a matching sha256 parser checksum")
    func verifierAcceptsMatchingChecksum() throws {
        let verifier = SyntaxGrammarChecksumVerifier(
            readData: { url in
                #expect(url.path == "/tmp/Resources/Grammars/swift/parser.dylib")
                return Data("parser".utf8)
            }
        )
        let language = SyntaxLanguage(
            languageID: "swift",
            displayName: "Swift",
            fileExtensions: ["swift"],
            parserResource: "Grammars/swift/parser.dylib",
            highlightQueryResource: "Grammars/swift/highlights.scm",
            upstreamVersion: "0.1.0",
            license: "MIT",
            checksum: "sha256:b17d45121150928f2146af49e195eff1eef5d67325be273a733fb74acadaa342"
        )

        try verifier.verify(
            language: language,
            plan: SyntaxGrammarLoadPlan(
                parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
                symbolName: "tree_sitter_swift"
            )
        )
    }

    @Test("verifier skips reading resources when checksum is absent")
    func verifierSkipsAbsentChecksum() throws {
        let verifier = SyntaxGrammarChecksumVerifier(
            readData: { _ in
                Issue.record("checksum verifier should not read files without a checksum")
                return Data()
            }
        )
        var language = SyntaxLanguageManifest.phaseCDefaults.languages[0]
        language.checksum = nil

        try verifier.verify(
            language: language,
            plan: SyntaxGrammarLoadPlan(
                parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
                symbolName: "tree_sitter_swift"
            )
        )
    }

    @Test("verifier rejects mismatched sha256 parser checksum")
    func verifierRejectsChecksumMismatch() {
        let verifier = SyntaxGrammarChecksumVerifier(
            readData: { _ in Data("parser".utf8) }
        )
        let language = SyntaxLanguage(
            languageID: "swift",
            displayName: "Swift",
            fileExtensions: ["swift"],
            parserResource: "Grammars/swift/parser.dylib",
            highlightQueryResource: "Grammars/swift/highlights.scm",
            upstreamVersion: "0.1.0",
            license: "MIT",
            checksum: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        )

        #expect(throws: SyntaxGrammarChecksumVerifierError.checksumMismatch(
            expected: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
            actual: "sha256:b17d45121150928f2146af49e195eff1eef5d67325be273a733fb74acadaa342"
        )) {
            try verifier.verify(
                language: language,
                plan: SyntaxGrammarLoadPlan(
                    parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
                    symbolName: "tree_sitter_swift"
                )
            )
        }
    }

    @Test("verifier rejects unsupported checksum formats before reading")
    func verifierRejectsUnsupportedChecksumFormat() {
        let verifier = SyntaxGrammarChecksumVerifier(
            readData: { _ in
                Issue.record("unsupported checksum should fail before reading files")
                return Data()
            }
        )
        var language = SyntaxLanguageManifest.phaseCDefaults.languages[0]
        language.checksum = "md5:abc"

        #expect(throws: SyntaxGrammarChecksumVerifierError.unsupportedChecksum("md5:abc")) {
            try verifier.verify(
                language: language,
                plan: SyntaxGrammarLoadPlan(
                    parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
                    symbolName: "tree_sitter_swift"
                )
            )
        }
    }
}

@Suite("Editor syntax decoration rendering")
struct EditorSyntaxDecorationRenderingSwiftTestingTests {
    @Test("syntax token decorations apply role-specific foreground colors")
    func syntaxDecorationColors() {
        let storage = NSTextStorage(string: "func greet = \"hi\"")
        let decorations = EditorDecorationSet([
            EditorDecoration(
                id: "keyword",
                range: EditorTextRange(location: 0, length: 4),
                kind: .syntaxToken,
                message: "syntax.keyword"
            ),
            EditorDecoration(
                id: "function",
                range: EditorTextRange(location: 5, length: 5),
                kind: .syntaxToken,
                message: "syntax.function"
            ),
            EditorDecoration(
                id: "string",
                range: EditorTextRange(location: 13, length: 4),
                kind: .syntaxToken,
                message: "syntax.string"
            ),
        ])

        EditorDecorationLayer.apply(decorations, to: storage, textLength: storage.length)

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == CocxyColors.mauve)
        #expect(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor == CocxyColors.blue)
        #expect(storage.attribute(.foregroundColor, at: 13, effectiveRange: nil) as? NSColor == CocxyColors.green)
    }
}

private final class DynamicLoaderCalls {
    var openedPaths: [String] = []
    var lookupSymbols: [String] = []
    var events: [String] = []
    var closeCount = 0
}

private final class LifetimeProbe {
    private let onDeinit: () -> Void

    init(onDeinit: @escaping () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit()
    }
}

private final class SyntaxTreeCalls {
    let languageEntryPoint = UnsafeMutableRawPointer(bitPattern: 0x11)!
    var closedHandles: [UnsafeMutableRawPointer] = []
    var events: [String] = []

    func makeBundle(closeLibrary: (() -> Void)? = nil) -> SyntaxGrammarBundle {
        SyntaxGrammarBundle(
            language: SyntaxLanguageManifest.phaseCDefaults.languages[0],
            library: SyntaxGrammarLibrary(
                parserURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/parser.dylib"),
                symbolName: "tree_sitter_swift",
                languageEntryPoint: languageEntryPoint,
                libraryHandle: UnsafeMutableRawPointer(bitPattern: 0x12)!,
                closeLibrary: { _ in closeLibrary?() }
            ),
            querySource: SyntaxHighlightQuerySource(
                languageID: "swift",
                resourceURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/highlights.scm"),
                query: "(identifier) @variable"
            )
        )
    }
}

private final class FakeSyntaxParser: SyntaxParsing {
    private let tokens: [SyntaxToken]
    private let error: Error?
    private(set) var requests: [String] = []
    private(set) var texts: [String] = []

    init(tokens: [SyntaxToken] = [], error: Error? = nil) {
        self.tokens = tokens
        self.error = error
    }

    func tokens(for text: String, language: SyntaxLanguage) throws -> [SyntaxToken] {
        requests.append(language.languageID)
        texts.append(text)
        if let error {
            throw error
        }
        return tokens
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private extension SyntaxLanguageManifest {
    static var fixtureSwift: SyntaxLanguageManifest {
        SyntaxLanguageManifest(languages: [
            SyntaxLanguage(
                languageID: "swift",
                displayName: "Swift",
                fileExtensions: ["swift"],
                parserResource: "swift/parser.dylib",
                highlightQueryResource: "swift/highlights.scm",
                upstreamVersion: "0.1.0",
                license: "MIT",
                checksum: "sha256:abc"
            ),
        ])
    }
}

private extension SyntaxHighlightQuerySource {
    static var fixture: SyntaxHighlightQuerySource {
        SyntaxHighlightQuerySource(
            languageID: "swift",
            resourceURL: URL(fileURLWithPath: "/tmp/Resources/Grammars/swift/highlights.scm"),
            query: "(identifier) @variable"
        )
    }
}

private extension SyntaxTree {
    static func fixtureTree() -> SyntaxTree {
        SyntaxTree(
            languageID: "swift",
            treeHandle: UnsafeMutableRawPointer(bitPattern: 0x200)!,
            rootNode: SyntaxNode(
                kind: "source_file",
                range: SyntaxPointRange(
                    start: SyntaxPoint(line: 0, column: 0),
                    end: SyntaxPoint(line: 0, column: 13)
                )
            ),
            deleteTree: { _ in }
        )
    }
}
