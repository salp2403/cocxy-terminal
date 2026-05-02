// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxTreeRuntime.swift - Injectable Tree-sitter parser lifecycle boundary.

import Foundation

enum SyntaxTreeRuntimeError: Error, Equatable {
    case parserAllocationFailed(languageID: String)
    case languageRejected(languageID: String)
    case parseFailed(languageID: String)
    case missingRootNode(languageID: String)
}

struct SyntaxTreeRuntime {
    typealias CreateParser = () -> UnsafeMutableRawPointer?
    typealias DeleteParser = (UnsafeMutableRawPointer) -> Void
    typealias SetLanguage = (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Bool
    typealias ParseString = (UnsafeMutableRawPointer, String) -> UnsafeMutableRawPointer?
    typealias ParseStringWithOldTree = (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, String) -> UnsafeMutableRawPointer?
    typealias RootNode = (UnsafeMutableRawPointer, String, String) -> SyntaxNode?
    typealias DeleteTree = SyntaxTree.DeleteTree
    typealias EditTree = (UnsafeMutableRawPointer, SyntaxInputEdit) -> Void

    private let createParser: CreateParser
    private let deleteParser: DeleteParser
    private let setLanguage: SetLanguage
    private let parseStringWithOldTree: ParseStringWithOldTree
    private let rootNode: RootNode
    private let deleteTree: DeleteTree
    private let editTree: EditTree
    private let retainedObjects: [AnyObject]

    init(
        createParser: @escaping CreateParser = { nil },
        deleteParser: @escaping DeleteParser = { _ in },
        setLanguage: @escaping SetLanguage = { _, _ in false },
        parseString: @escaping ParseString = { _, _ in nil },
        parseStringWithOldTree: ParseStringWithOldTree? = nil,
        rootNode: @escaping RootNode = { _, _, _ in nil },
        deleteTree: @escaping DeleteTree = { _ in },
        editTree: @escaping EditTree = { _, _ in },
        retainedObjects: [AnyObject] = []
    ) {
        self.createParser = createParser
        self.deleteParser = deleteParser
        self.setLanguage = setLanguage
        self.parseStringWithOldTree = parseStringWithOldTree ?? { parser, _, text in
            parseString(parser, text)
        }
        self.rootNode = rootNode
        self.deleteTree = deleteTree
        self.editTree = editTree
        self.retainedObjects = retainedObjects
    }

    func parse(text: String, bundle: SyntaxGrammarBundle) throws -> SyntaxTree {
        try parse(text: text, bundle: bundle, oldTreeHandle: nil)
    }

    func parseIncremental(
        text: String,
        bundle: SyntaxGrammarBundle,
        previousTree: SyntaxTree,
        edit: SyntaxInputEdit
    ) throws -> SyntaxTree {
        guard let oldTreeHandle = try previousTree.withTreeHandle({ $0 }) else {
            return try parse(text: text, bundle: bundle)
        }
        editTree(oldTreeHandle, edit)
        return try parse(text: text, bundle: bundle, oldTreeHandle: oldTreeHandle)
    }

    private func parse(
        text: String,
        bundle: SyntaxGrammarBundle,
        oldTreeHandle: UnsafeMutableRawPointer?
    ) throws -> SyntaxTree {
        let languageID = normalizedLanguageID(bundle.language.languageID)
        guard let parserHandle = createParser() else {
            throw SyntaxTreeRuntimeError.parserAllocationFailed(languageID: languageID)
        }

        guard setLanguage(parserHandle, bundle.library.languageEntryPoint) else {
            deleteParser(parserHandle)
            throw SyntaxTreeRuntimeError.languageRejected(languageID: languageID)
        }

        guard let treeHandle = parseStringWithOldTree(parserHandle, oldTreeHandle, text) else {
            deleteParser(parserHandle)
            throw SyntaxTreeRuntimeError.parseFailed(languageID: languageID)
        }

        guard let rootNode = rootNode(treeHandle, text, languageID) else {
            deleteParser(parserHandle)
            deleteTree(treeHandle)
            throw SyntaxTreeRuntimeError.missingRootNode(languageID: languageID)
        }

        deleteParser(parserHandle)
        return SyntaxTree(
            languageID: languageID,
            treeHandle: treeHandle,
            rootNode: rootNode,
            deleteTree: deleteTree,
            retainedObjects: retainedObjects
        )
    }

    private func normalizedLanguageID(_ languageID: String) -> String {
        languageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
