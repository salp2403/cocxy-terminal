// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownFileExplorerTests.swift - Tests for file tree building and explorer view.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("MarkdownFileExplorer")
struct MarkdownFileExplorerTests {

    // MARK: - FileTreeNode.buildTree

    @Test("buildTree returns empty for empty directory")
    func buildTreeEmptyDir() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let tree = FileTreeNode.buildTree(from: dir)
        #expect(tree.isEmpty)
    }

    @Test("buildTree finds .md files")
    func buildTreeFindsMdFiles() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "# Hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "# World".write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let tree = FileTreeNode.buildTree(from: dir)
        #expect(tree.count == 2)
        #expect(tree.allSatisfy { !$0.isDirectory })
    }

    @Test("buildTree ignores non-markdown files")
    func buildTreeIgnoresNonMd() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "# Hello".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "not md".write(to: dir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try "swift".write(to: dir.appendingPathComponent("code.swift"), atomically: true, encoding: .utf8)

        let tree = FileTreeNode.buildTree(from: dir)
        #expect(tree.count == 1)
        #expect(tree[0].name == "README.md")
    }

    @Test("buildTree includes subdirectories with markdown files")
    func buildTreeSubdirectories() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let subDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "# Sub".write(to: subDir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)
        try "# Root".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let tree = FileTreeNode.buildTree(from: dir)
        // Should have: docs/ (directory) + README.md (file)
        #expect(tree.count == 2)

        let dirNode = tree.first { $0.isDirectory }
        #expect(dirNode != nil)
        #expect(dirNode?.name == "docs")
        #expect(dirNode?.children.count == 1)
        #expect(dirNode?.children.first?.name == "guide.md")
    }

    @Test("buildTree excludes empty subdirectories")
    func buildTreeExcludesEmptySubdirs() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let emptyDir = dir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        try "# Root".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let tree = FileTreeNode.buildTree(from: dir)
        #expect(tree.count == 1)
        #expect(tree[0].name == "README.md")
    }

    @Test("buildTree sorts directories first, then files")
    func buildTreeSortOrder() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        let subDir = dir.appendingPathComponent("aaa")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "x".write(to: subDir.appendingPathComponent("file.md"), atomically: true, encoding: .utf8)
        try "a".write(to: dir.appendingPathComponent("zzz.md"), atomically: true, encoding: .utf8)
        try "b".write(to: dir.appendingPathComponent("aaa.md"), atomically: true, encoding: .utf8)

        let tree = FileTreeNode.buildTree(from: dir)
        #expect(tree.count == 3)
        #expect(tree[0].isDirectory) // aaa/ comes first (directory)
        #expect(tree[1].name == "aaa.md") // then aaa.md
        #expect(tree[2].name == "zzz.md") // then zzz.md
    }

    @Test("buildTree recognizes .markdown extension")
    func buildTreeMarkdownExtension() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "# Alt".write(to: dir.appendingPathComponent("doc.markdown"), atomically: true, encoding: .utf8)

        let tree = FileTreeNode.buildTree(from: dir)
        #expect(tree.count == 1)
        #expect(tree[0].name == "doc.markdown")
    }

    @Test("buildTree skips hidden files and directories")
    func buildTreeSkipsHidden() throws {
        let dir = createTempDir()
        defer { cleanup(dir) }

        try "# Visible".write(to: dir.appendingPathComponent("visible.md"), atomically: true, encoding: .utf8)
        try "# Hidden".write(to: dir.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)

        let tree = FileTreeNode.buildTree(from: dir)
        #expect(tree.count == 1)
        #expect(tree[0].name == "visible.md")
    }

    // MARK: - Helpers

    private func createTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-explorer-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
