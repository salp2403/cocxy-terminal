// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Syntax.swift - Wires local syntax highlighting into editor panels.

import Foundation

extension MainWindowController {
    func wireEditorSyntaxIfAvailable(editorView: EditorView) {
        guard let service = makeEditorSyntaxService() else {
            editorView.syntaxDecorationProvider = nil
            return
        }

        editorView.syntaxDecorationProvider = { document in
            guard let fileURL = document.fileURL else { return [] }
            return service.decorations(forFileURL: fileURL, buffer: document.buffer)
        }
    }

    private func makeEditorSyntaxService() -> SyntaxTreeService? {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        do {
            let manifest = try SyntaxLanguageManifestLoader(bundleResourceURL: resourcesURL).load()
            let registry = try SyntaxLanguageRegistry(manifest: manifest) { resource in
                FileManager.default.fileExists(
                    atPath: resourcesURL.appendingPathComponent(resource, isDirectory: false).path
                )
            }
            let symbolProvider = TreeSitterSymbolProvider.bundledOrProcess(bundleResourceURL: resourcesURL)
            let queryAdapter = TreeSitterHighlightQueryAdapter.resolveBundledOrProcess(
                symbolProvider: symbolProvider
            )
            let parser = SyntaxTreeParser(
                bundleLoader: SyntaxGrammarBundleLoader(
                    locator: SyntaxGrammarLocator(bundleResourceURL: resourcesURL),
                    checksumVerifier: SyntaxGrammarChecksumVerifier(),
                    queryLoader: SyntaxHighlightQueryLoader(bundleResourceURL: resourcesURL),
                    dynamicLoader: SyntaxGrammarDynamicLoader()
                ),
                runtime: SyntaxTreeRuntime.treeSitterOrUnavailable(symbolProvider: symbolProvider),
                extractTokens: { tree, bundle, buffer in
                    guard let queryAdapter else {
                        return []
                    }
                    return try SyntaxHighlightQueryExecutor { tree, querySource, buffer in
                        try queryAdapter.collectCaptures(
                            for: tree,
                            bundle: bundle,
                            querySource: querySource,
                            buffer: buffer
                        )
                    }
                    .tokens(for: tree, querySource: bundle.querySource, buffer: buffer)
                }
            )
            return SyntaxTreeService(registry: registry, parser: parser)
        } catch {
            return nil
        }
    }
}
