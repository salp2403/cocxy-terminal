// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror project service")
struct MobileMirrorProjectServiceSwiftTestingTests {
    @Test("creates a real git project under the approved root")
    func createsProjectAtomically() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MobileMirrorProjectService()

        let publication = try await service.createProject(named: "Mobile Demo", in: root)
        let project = try publication.verifiedURL()
        #expect(project == root.appendingPathComponent("Mobile Demo", isDirectory: true))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: project.appendingPathComponent(".git", isDirectory: true).path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
        let stagedDirectories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".cocxy-project-") }
        #expect(stagedDirectories.isEmpty)
    }

    @Test("a verified publication can be rolled back without touching siblings")
    func publishedProjectRollbackIsDescriptorBound() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sibling = root.appendingPathComponent("Keep", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        let publication = try await MobileMirrorProjectService().createProject(
            named: "Rollback",
            in: root
        )

        try publication.rollback()

        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Rollback", isDirectory: true).path
        ) == false)
        #expect(FileManager.default.fileExists(atPath: sibling.path))
    }

    @Test("rejects traversal hidden names and existing destinations")
    func rejectsUnsafeNamesAndCollisions() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let service = MobileMirrorProjectService()

        for name in ["../escape", ".hidden", "bad:name", "line\nbreak"] {
            await #expect(throws: MobileMirrorError.invalidProjectName) {
                try await service.createProject(named: name, in: root)
            }
        }
        await #expect(throws: MobileMirrorError.projectAlreadyExists) {
            try await service.createProject(named: "Existing", in: root)
        }
    }

    @Test("rejects a symbolic-link creation root")
    func rejectsSymlinkRoot() async throws {
        let root = try temporaryDirectory()
        let parent = root.deletingLastPathComponent()
        let symlink = parent.appendingPathComponent("mobile-link-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: symlink)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: root)

        await #expect(throws: MobileMirrorError.projectCreationUnavailable) {
            try await MobileMirrorProjectService().createProject(named: "Demo", in: symlink)
        }
    }

    @Test("cancellation before publication removes staging and leaves no project")
    func cancellationBeforePublicationIsReversible() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let service = MobileMirrorProjectService(runGit: { workingDirectory, _ in
            try FileManager.default.createDirectory(
                at: workingDirectory.displayURL.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: false
            )
            started.signal()
            release.wait()
            return BoundedProcessResult(
                exitCode: 0,
                stdout: "",
                stderr: "",
                stdoutWasTruncated: false,
                stderrWasTruncated: false,
                timedOut: false
            )
        })
        let operation = Task {
            try await service.createProject(named: "Cancelled", in: root)
        }
        #expect(started.wait(timeout: .now() + 2) == .success)

        operation.cancel()
        release.signal()
        await #expect(throws: CancellationError.self) {
            try await operation.value
        }

        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Cancelled", isDirectory: true).path
        ) == false)
        let stagedDirectories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".cocxy-project-") }
        #expect(stagedDirectories.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-mobile-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url.standardizedFileURL
    }
}
