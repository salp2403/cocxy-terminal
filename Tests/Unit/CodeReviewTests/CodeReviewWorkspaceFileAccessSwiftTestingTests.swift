// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Code Review workspace file access")
struct CodeReviewWorkspaceFileAccessSwiftTestingTests {
    @Test("reads and atomically writes a nested regular file")
    func readsAndWritesNestedFile() throws {
        let root = try makeWorkspaceFixture(named: "valid")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "let enabled = false\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: target.path
        )

        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)
        let original = try access.read(relativePath: "Sources/App.swift")
        #expect(original.content == "let enabled = false\n")

        let writtenVersion = try access.write(
            "let enabled = true\n",
            relativePath: "Sources/App.swift",
            expectedVersion: original.version
        )
        let updated = try access.read(relativePath: "Sources/App.swift")
        #expect(updated.content == "let enabled = true\n")
        #expect(updated.version == writtenVersion)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        let siblingNames = try FileManager.default.contentsOfDirectory(
            atPath: target.deletingLastPathComponent().path
        )
        #expect(siblingNames.allSatisfy { !$0.hasPrefix(".cocxy-review-") })
    }

    @Test("retains the opened root object when its pathname is replaced")
    func remainsBoundToOpenedRoot() throws {
        let container = try makeWorkspaceFixture(named: "root-binding")
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("workspace", isDirectory: true)
        let retainedRoot = container.appendingPathComponent("workspace-retained", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "original\n".write(
            to: root.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)
        try FileManager.default.moveItem(at: root, to: retainedRoot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "replacement root\n".write(
            to: root.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try access.read(relativePath: "file.txt")
        #expect(snapshot.content == "original\n")
    }

    @Test("rejects intermediate and final symbolic links")
    func rejectsSymbolicLinks() throws {
        let container = try makeWorkspaceFixture(named: "links")
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("workspace", isDirectory: true)
        let outside = container.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideTarget = outside.appendingPathComponent("secret.txt")
        try "outside\n".write(to: outsideTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("linked").path,
            withDestinationPath: outside.path
        )
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("final.txt").path,
            withDestinationPath: outsideTarget.path
        )

        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)
        #expect(throws: CodeReviewWorkspaceFileError.unsafePath("linked/secret.txt")) {
            _ = try access.read(relativePath: "linked/secret.txt")
        }
        #expect(throws: CodeReviewWorkspaceFileError.unsafePath("final.txt")) {
            _ = try access.read(relativePath: "final.txt")
        }
        #expect(throws: CodeReviewWorkspaceFileError.unsafePath("missing.txt")) {
            _ = try access.read(relativePath: "missing.txt")
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("directory.txt"),
            withIntermediateDirectories: true
        )
        #expect(throws: CodeReviewWorkspaceFileError.unsafePath("directory.txt")) {
            _ = try access.read(relativePath: "directory.txt")
        }
    }

    @Test("save cannot follow an intermediate symlink introduced after open")
    func saveRejectsSwappedParent() throws {
        let container = try makeWorkspaceFixture(named: "swapped-parent")
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("workspace", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        let retainedDirectory = root.appendingPathComponent("Sources-retained", isDirectory: true)
        let outside = container.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let insideTarget = sourceDirectory.appendingPathComponent("App.swift")
        let outsideTarget = outside.appendingPathComponent("App.swift")
        try "inside\n".write(to: insideTarget, atomically: true, encoding: .utf8)
        try "outside\n".write(to: outsideTarget, atomically: true, encoding: .utf8)

        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)
        let snapshot = try access.read(relativePath: "Sources/App.swift")
        try FileManager.default.moveItem(at: sourceDirectory, to: retainedDirectory)
        try FileManager.default.createSymbolicLink(
            atPath: sourceDirectory.path,
            withDestinationPath: outside.path
        )

        #expect(throws: CodeReviewWorkspaceFileError.unsafePath("Sources/App.swift")) {
            _ = try access.write(
                "replacement\n",
                relativePath: "Sources/App.swift",
                expectedVersion: snapshot.version
            )
        }
        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "outside\n")
        #expect(
            try String(
                contentsOf: retainedDirectory.appendingPathComponent("App.swift"),
                encoding: .utf8
            ) == "inside\n"
        )
    }

    @Test("save rejects a stale file identity")
    func saveRejectsStaleIdentity() throws {
        let root = try makeWorkspaceFixture(named: "stale")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("file.txt")
        try "original\n".write(to: target, atomically: true, encoding: .utf8)

        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)
        let original = try access.read(relativePath: "file.txt")
        try "concurrent replacement\n".write(to: target, atomically: true, encoding: .utf8)

        #expect(throws: CodeReviewWorkspaceFileError.fileChanged("file.txt")) {
            _ = try access.write(
                "editor replacement\n",
                relativePath: "file.txt",
                expectedVersion: original.version
            )
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "concurrent replacement\n")
    }

    @Test("save cannot follow a final symlink introduced after open")
    func saveRejectsSwappedFinalSymlink() throws {
        let container = try makeWorkspaceFixture(named: "swapped-final")
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("workspace", isDirectory: true)
        let outside = container.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("file.txt")
        let retainedTarget = root.appendingPathComponent("file-retained.txt")
        let outsideTarget = outside.appendingPathComponent("file.txt")
        try "inside\n".write(to: target, atomically: true, encoding: .utf8)
        try "outside\n".write(to: outsideTarget, atomically: true, encoding: .utf8)

        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)
        let snapshot = try access.read(relativePath: "file.txt")
        try FileManager.default.moveItem(at: target, to: retainedTarget)
        try FileManager.default.createSymbolicLink(
            atPath: target.path,
            withDestinationPath: outsideTarget.path
        )

        #expect(throws: CodeReviewWorkspaceFileError.unsafePath("file.txt")) {
            _ = try access.write(
                "replacement\n",
                relativePath: "file.txt",
                expectedVersion: snapshot.version
            )
        }
        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "outside\n")
        #expect(try String(contentsOf: retainedTarget, encoding: .utf8) == "inside\n")
    }

    @Test("rejects absolute traversal empty and control-character paths")
    func rejectsInvalidPaths() throws {
        let root = try makeWorkspaceFixture(named: "invalid-paths")
        defer { try? FileManager.default.removeItem(at: root) }
        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)

        for path in ["", "/etc/hosts", "../secret", "./file", "a//file", "a/\u{0001}file"] {
            #expect(throws: CodeReviewWorkspaceFileError.invalidPath(path)) {
                _ = try access.read(relativePath: path)
            }
        }
    }

    @Test("concurrent ancestor swaps never modify the symlink target")
    func concurrentAncestorSwapsFailClosed() throws {
        let container = try makeWorkspaceFixture(named: "ancestor-race")
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("workspace", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let outside = container.appendingPathComponent("outside", isDirectory: true)
        let escapeTarget = outside.appendingPathComponent("escape", isDirectory: true)
        let outsideSlot = outside.appendingPathComponent("outside-slot")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: escapeTarget, withIntermediateDirectories: true)
        try "inside\n".write(
            to: nested.appendingPathComponent("target.txt"),
            atomically: true,
            encoding: .utf8
        )
        let outsideTarget = escapeTarget.appendingPathComponent("target.txt")
        try "outside\n".write(to: outsideTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: outsideSlot.path,
            withDestinationPath: escapeTarget.path
        )

        let access = try CodeReviewWorkspaceFileAccess(rootURL: root)
        let rootDescriptor = try openDirectoryDescriptor(root)
        defer { Darwin.close(rootDescriptor) }
        let outsideDescriptor = try openDirectoryDescriptor(outside)
        defer { Darwin.close(outsideDescriptor) }
        let group = DispatchGroup()
        let started = DispatchSemaphore(value: 0)
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            started.signal()
            for _ in 0..<10_000 {
                "nested".withCString { nestedPath in
                    "outside-slot".withCString { outsidePath in
                        _ = Darwin.renameatx_np(
                            rootDescriptor,
                            nestedPath,
                            outsideDescriptor,
                            outsidePath,
                            UInt32(RENAME_SWAP)
                        )
                    }
                }
            }
        }
        started.wait()

        for _ in 0..<150 {
            do {
                let snapshot = try access.read(relativePath: "nested/target.txt")
                _ = try access.write(
                    "contained\n",
                    relativePath: "nested/target.txt",
                    expectedVersion: snapshot.version
                )
            } catch CodeReviewWorkspaceFileError.unsafePath {
                // The symlink occupied the workspace slot and was rejected.
            } catch CodeReviewWorkspaceFileError.fileChanged {
                // A swap crossed the identity checks and failed closed.
            } catch CodeReviewWorkspaceFileError.writeFailed {
                // A rename race can invalidate the atomic publication.
            } catch {
                Issue.record("Unexpected ancestor race result: \(error)")
                break
            }
        }
        group.wait()

        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "outside\n")
    }
}

private func makeWorkspaceFixture(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("code-review-file-access-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func openDirectoryDescriptor(_ url: URL) throws -> Int32 {
    let descriptor = url.path.withCString {
        Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
        throw CodeReviewWorkspaceFileError.unsafePath(url.path)
    }
    return descriptor
}
