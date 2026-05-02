// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxTree.swift - Ownership wrapper for a parsed Tree-sitter tree handle.

import Foundation

final class SyntaxTree {
    typealias DeleteTree = (UnsafeMutableRawPointer) -> Void

    let languageID: String
    let rootNode: SyntaxNode

    private var treeHandle: UnsafeMutableRawPointer?
    private let deleteTree: DeleteTree
    private let retainedObjects: [AnyObject]

    init(
        languageID: String,
        treeHandle: UnsafeMutableRawPointer,
        rootNode: SyntaxNode,
        deleteTree: @escaping DeleteTree,
        retainedObjects: [AnyObject] = []
    ) {
        self.languageID = languageID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.treeHandle = treeHandle
        self.rootNode = rootNode
        self.deleteTree = deleteTree
        self.retainedObjects = retainedObjects
    }

    deinit {
        close()
    }

    var isClosed: Bool {
        treeHandle == nil
    }

    func withTreeHandle<T>(_ body: (UnsafeMutableRawPointer) throws -> T) throws -> T? {
        guard let handle = treeHandle else { return nil }
        return try body(handle)
    }

    func close() {
        guard let handle = treeHandle else { return }
        treeHandle = nil
        deleteTree(handle)
    }
}
