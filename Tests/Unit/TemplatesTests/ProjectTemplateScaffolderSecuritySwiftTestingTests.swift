// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplateScaffolderSecuritySwiftTestingTests.swift - Destination containment tests.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project template scaffolder security")
struct ProjectTemplateScaffolderSecuritySwiftTestingTests {

    @Test("rejects dot traversal absolute and sibling-prefix output paths")
    func rejectsUnsafeOutputPathShapes() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let absoluteOutput = root.appendingPathComponent("absolute.swift")
        let template = try makeTemplate(
            files: ["{{target_path}}": "content\n"],
            variables: [
                ProjectTemplateVariable(name: "target_path", prompt: "Target path", required: false),
            ],
            in: root
        )
        let probes = [
            "",
            ".",
            "..",
            "../escaped.swift",
            "../output-sibling/escaped.swift",
            "nested/./escaped.swift",
            "nested/../escaped.swift",
            "nested//escaped.swift",
            absoluteOutput.path,
            "nul\0escaped.swift",
        ]

        for (index, probe) in probes.enumerated() {
            let destination = root.appendingPathComponent("output-\(index)", isDirectory: true)
            #expect(throws: ProjectTemplateError.unsafeOutputPath(probe)) {
                _ = try ProjectTemplateScaffolder().scaffold(
                    template: template,
                    values: ["target_path": probe],
                    destinationURL: destination
                )
            }
        }

        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.swift").path))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("output-sibling/escaped.swift").path
        ))
        #expect(!FileManager.default.fileExists(atPath: absoluteOutput.path))
    }

    @Test("rejects relative absolute and traversal destinations")
    func rejectsUnsafeDestinations() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try makeTemplate(files: ["created.conf": "safe content\n"], in: root)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let relativeDestination = workspace.appendingPathComponent("RelativeProject", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: relativeDestination.path,
            withDestinationPath: "../outside"
        )
        #expect(throws: ProjectTemplateError.unsafeOutputPath(relativeDestination.path)) {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: [:],
                destinationURL: relativeDestination
            )
        }
        try FileManager.default.removeItem(at: relativeDestination)

        let absoluteDestination = workspace.appendingPathComponent("AbsoluteProject", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: absoluteDestination.path,
            withDestinationPath: outside.path
        )
        #expect(throws: ProjectTemplateError.unsafeOutputPath(absoluteDestination.path)) {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: [:],
                destinationURL: absoluteDestination
            )
        }

        let traversalDestination = URL(
            fileURLWithPath: workspace.path + "/../outside/TraversalProject",
            isDirectory: true
        )
        #expect(throws: ProjectTemplateError.unsafeOutputPath(traversalDestination.path)) {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: [:],
                destinationURL: traversalDestination
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: outside.appendingPathComponent("created.conf").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: outside.appendingPathComponent("TraversalProject/created.conf").path
        ))
    }

    @Test("rejects a symlink in any destination ancestor")
    func rejectsDestinationAncestorSymlinks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try makeTemplate(files: ["created.conf": "safe content\n"], in: root)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let outsideParent = outside.appendingPathComponent("parent", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideParent, withIntermediateDirectories: true)

        let linkedAncestor = workspace.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: linkedAncestor.path,
            withDestinationPath: outside.path
        )
        let destination = linkedAncestor
            .appendingPathComponent("parent", isDirectory: true)
            .appendingPathComponent("NewProject", isDirectory: true)

        #expect(throws: ProjectTemplateError.unsafeOutputPath(destination.path)) {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: [:],
                destinationURL: destination
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: outsideParent.appendingPathComponent("NewProject/created.conf").path
        ))
    }

    @Test("rejects symlinks at every output ancestor depth")
    func rejectsOutputAncestorSymlinks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try makeTemplate(
            files: ["Sources/App/main.swift": "print(\"safe\")\n"],
            in: root
        )
        let scaffolder = ProjectTemplateScaffolder()

        let topDestination = root.appendingPathComponent("top-output", isDirectory: true)
        let topOutside = root.appendingPathComponent("top-outside", isDirectory: true)
        try FileManager.default.createDirectory(at: topDestination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: topOutside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: topDestination.appendingPathComponent("Sources").path,
            withDestinationPath: "../top-outside"
        )
        #expect(throws: ProjectTemplateError.unsafeOutputPath("Sources/App/main.swift")) {
            _ = try scaffolder.scaffold(template: template, values: [:], destinationURL: topDestination)
        }

        let deepDestination = root.appendingPathComponent("deep-output", isDirectory: true)
        let deepSources = deepDestination.appendingPathComponent("Sources", isDirectory: true)
        let deepOutside = root.appendingPathComponent("deep-outside", isDirectory: true)
        try FileManager.default.createDirectory(at: deepSources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deepOutside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: deepSources.appendingPathComponent("App").path,
            withDestinationPath: deepOutside.path
        )
        #expect(throws: ProjectTemplateError.unsafeOutputPath("Sources/App/main.swift")) {
            _ = try scaffolder.scaffold(template: template, values: [:], destinationURL: deepDestination)
        }

        #expect(!FileManager.default.fileExists(
            atPath: topOutside.appendingPathComponent("App/main.swift").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: deepOutside.appendingPathComponent("main.swift").path
        ))
    }

    @Test("never follows a final symlink even with overwrite authorization")
    func rejectsFinalSymlinks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try makeTemplate(files: ["config.txt": "replacement\n"], in: root)
        let destination = root.appendingPathComponent("output", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let outsideTarget = outside.appendingPathComponent("config.txt")
        let outputSymlink = destination.appendingPathComponent("config.txt")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "preserve\n".write(to: outsideTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: outputSymlink.path,
            withDestinationPath: outsideTarget.path
        )

        for overwrite in [false, true] {
            #expect(throws: ProjectTemplateError.unsafeOutputPath("config.txt")) {
                _ = try ProjectTemplateScaffolder().scaffold(
                    template: template,
                    values: [:],
                    destinationURL: destination,
                    overwrite: overwrite
                )
            }
        }
        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "preserve\n")

        try FileManager.default.removeItem(at: outputSymlink)
        let danglingTarget = outside.appendingPathComponent("missing.txt")
        try FileManager.default.createSymbolicLink(
            atPath: outputSymlink.path,
            withDestinationPath: danglingTarget.path
        )
        #expect(throws: ProjectTemplateError.unsafeOutputPath("config.txt")) {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: [:],
                destinationURL: destination
            )
        }
        #expect(!FileManager.default.fileExists(atPath: danglingTarget.path))
    }

    @Test("cannot overwrite a final symlink introduced concurrently")
    func containsConcurrentFinalSymlinkSwaps() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try makeTemplate(files: ["config.txt": "replacement\n"], in: root)
        let destination = root.appendingPathComponent("output", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let existingFile = destination.appendingPathComponent("config.txt")
        let outsideTarget = outside.appendingPathComponent("target.txt")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "preserve\n".write(to: existingFile, atomically: true, encoding: .utf8)
        try "outside\n".write(to: outsideTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: destination.appendingPathComponent("symlink-slot").path,
            withDestinationPath: outsideTarget.path
        )

        let destinationDescriptor = try openDirectoryDescriptor(destination)
        defer { Darwin.close(destinationDescriptor) }
        let group = DispatchGroup()
        let started = DispatchSemaphore(value: 0)
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            started.signal()
            for _ in 0..<20_000 {
                "config.txt".withCString { filePath in
                    "symlink-slot".withCString { symlinkPath in
                        _ = Darwin.renameatx_np(
                            destinationDescriptor,
                            filePath,
                            destinationDescriptor,
                            symlinkPath,
                            UInt32(RENAME_SWAP)
                        )
                    }
                }
            }
        }
        started.wait()

        let scaffolder = ProjectTemplateScaffolder()
        for _ in 0..<200 {
            do {
                _ = try scaffolder.scaffold(
                    template: template,
                    values: [:],
                    destinationURL: destination,
                    overwrite: true
                )
            } catch ProjectTemplateError.unsafeOutputPath {
                // A detected swap is the expected fail-closed result.
            } catch {
                Issue.record("Unexpected final-path race result: \(error)")
                break
            }
        }
        group.wait()

        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "outside\n")
    }

    @Test("cannot be redirected by a concurrent output ancestor swap")
    func containsConcurrentAncestorSwaps() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try makeTemplate(files: ["nested/payload.txt": "contained\n"], in: root)
        let destination = root.appendingPathComponent("output", isDirectory: true)
        let nestedDirectory = destination.appendingPathComponent("nested", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let escapeTarget = outside.appendingPathComponent("escape-target", isDirectory: true)
        let outsideSlot = outside.appendingPathComponent("outside-slot")
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: escapeTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: outsideSlot.path,
            withDestinationPath: escapeTarget.path
        )

        let destinationDescriptor = try openDirectoryDescriptor(destination)
        defer { Darwin.close(destinationDescriptor) }
        let outsideDescriptor = try openDirectoryDescriptor(outside)
        defer { Darwin.close(outsideDescriptor) }
        let group = DispatchGroup()
        let started = DispatchSemaphore(value: 0)
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            started.signal()
            for _ in 0..<20_000 {
                "nested".withCString { nestedPath in
                    "outside-slot".withCString { symlinkPath in
                        _ = Darwin.renameatx_np(
                            destinationDescriptor,
                            nestedPath,
                            outsideDescriptor,
                            symlinkPath,
                            UInt32(RENAME_SWAP)
                        )
                    }
                }
            }
        }
        started.wait()

        let scaffolder = ProjectTemplateScaffolder()
        for _ in 0..<200 {
            do {
                _ = try scaffolder.scaffold(
                    template: template,
                    values: [:],
                    destinationURL: destination,
                    overwrite: true
                )
            } catch ProjectTemplateError.unsafeOutputPath {
                // A detected swap is the expected fail-closed result.
            } catch {
                Issue.record("Unexpected race result: \(error)")
                break
            }
        }
        group.wait()

        #expect(!FileManager.default.fileExists(
            atPath: escapeTarget.appendingPathComponent("payload.txt").path
        ))
    }

    @Test("overwrites regular files only when explicitly authorized")
    func requiresOverwriteAuthorization() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try makeTemplate(files: ["README.md": "replacement\n"], in: root)
        let destination = root.appendingPathComponent("output", isDirectory: true)
        let existingFile = destination.appendingPathComponent("README.md")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "preserve\n".write(to: existingFile, atomically: true, encoding: .utf8)

        #expect(throws: ProjectTemplateError.destinationExists("README.md")) {
            _ = try ProjectTemplateScaffolder().scaffold(
                template: template,
                values: [:],
                destinationURL: destination
            )
        }
        #expect(try String(contentsOf: existingFile, encoding: .utf8) == "preserve\n")

        let result = try ProjectTemplateScaffolder().scaffold(
            template: template,
            values: [:],
            destinationURL: destination,
            overwrite: true
        )
        #expect(result.createdFiles == ["README.md"])
        #expect(try String(contentsOf: existingFile, encoding: .utf8) == "replacement\n")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-template-security-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTemplate(
        files: [String: String],
        variables: [ProjectTemplateVariable] = [],
        in root: URL
    ) throws -> ProjectTemplate {
        let directory = root.appendingPathComponent("template", isDirectory: true)
        let filesRoot = directory.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        for (relativePath, content) in files {
            let fileURL = filesRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return ProjectTemplate(
            id: "filesystem-safety",
            name: "Filesystem Safety",
            summary: "Filesystem safety fixture",
            variables: variables,
            hooks: ProjectTemplateHooks(),
            signature: nil,
            source: .builtIn,
            directoryURL: directory
        )
    }

    private func openDirectoryDescriptor(_ url: URL) throws -> Int32 {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw ProjectTemplateError.unsafeOutputPath(url.path)
        }
        return descriptor
    }
}
