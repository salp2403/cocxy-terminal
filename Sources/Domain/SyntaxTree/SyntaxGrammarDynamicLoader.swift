// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxGrammarDynamicLoader.swift - Dynamic loader boundary for bundled Tree-sitter grammars.

import Darwin
import Foundation

enum SyntaxGrammarDynamicLoaderError: Error, Equatable {
    case openFailed(String)
    case missingSymbol(String)
}

final class SyntaxGrammarLibrary {
    let parserURL: URL
    let symbolName: String
    let languageEntryPoint: UnsafeMutableRawPointer

    private let libraryHandle: UnsafeMutableRawPointer
    private let closeLibrary: SyntaxGrammarDynamicLoader.CloseLibrary
    private var didClose = false

    init(
        parserURL: URL,
        symbolName: String,
        languageEntryPoint: UnsafeMutableRawPointer,
        libraryHandle: UnsafeMutableRawPointer,
        closeLibrary: @escaping SyntaxGrammarDynamicLoader.CloseLibrary
    ) {
        self.parserURL = parserURL
        self.symbolName = symbolName
        self.languageEntryPoint = languageEntryPoint
        self.libraryHandle = libraryHandle
        self.closeLibrary = closeLibrary
    }

    deinit {
        close()
    }

    private func close() {
        guard !didClose else { return }
        didClose = true
        closeLibrary(libraryHandle)
    }
}

struct SyntaxGrammarDynamicLoader {
    typealias OpenLibrary = (URL) -> UnsafeMutableRawPointer?
    typealias LookupSymbol = (UnsafeMutableRawPointer, String) -> UnsafeMutableRawPointer?
    typealias CloseLibrary = (UnsafeMutableRawPointer) -> Void

    private let openLibrary: OpenLibrary
    private let lookupSymbol: LookupSymbol
    private let closeLibrary: CloseLibrary

    init(
        openLibrary: @escaping OpenLibrary = SyntaxGrammarDynamicLoader.defaultOpenLibrary,
        lookupSymbol: @escaping LookupSymbol = SyntaxGrammarDynamicLoader.defaultLookupSymbol,
        closeLibrary: @escaping CloseLibrary = SyntaxGrammarDynamicLoader.defaultCloseLibrary
    ) {
        self.openLibrary = openLibrary
        self.lookupSymbol = lookupSymbol
        self.closeLibrary = closeLibrary
    }

    func load(plan: SyntaxGrammarLoadPlan) throws -> SyntaxGrammarLibrary {
        guard let libraryHandle = openLibrary(plan.parserURL) else {
            throw SyntaxGrammarDynamicLoaderError.openFailed(plan.parserURL.path)
        }

        guard let languageEntryPoint = lookupSymbol(libraryHandle, plan.symbolName) else {
            closeLibrary(libraryHandle)
            throw SyntaxGrammarDynamicLoaderError.missingSymbol(plan.symbolName)
        }

        return SyntaxGrammarLibrary(
            parserURL: plan.parserURL,
            symbolName: plan.symbolName,
            languageEntryPoint: languageEntryPoint,
            libraryHandle: libraryHandle,
            closeLibrary: closeLibrary
        )
    }

    private static func defaultOpenLibrary(_ parserURL: URL) -> UnsafeMutableRawPointer? {
        dlopen(parserURL.path, RTLD_NOW | RTLD_LOCAL)
    }

    private static func defaultLookupSymbol(
        _ libraryHandle: UnsafeMutableRawPointer,
        _ symbolName: String
    ) -> UnsafeMutableRawPointer? {
        dlsym(libraryHandle, symbolName)
    }

    private static func defaultCloseLibrary(_ libraryHandle: UnsafeMutableRawPointer) {
        dlclose(libraryHandle)
    }
}
