// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project clone service", .serialized)
struct ProjectCloneServiceSwiftTestingTests {
    @Test("remote validation accepts HTTPS, SSH, and SCP-style URLs")
    func validatesSupportedRemotes() throws {
        #expect(try ProjectCloneService.validatedRemote(
            "https://example.test/team/project.git"
        ).absoluteString == "https://example.test/team/project.git")
        #expect(try ProjectCloneService.validatedRemote(
            "ssh://git@example.test/team/project.git"
        ).absoluteString == "ssh://git@example.test/team/project.git")
        #expect(try ProjectCloneService.validatedRemote(
            "git@example.test:team/project.git"
        ).absoluteString == "ssh://git@example.test/team/project.git")
    }

    @Test("remote validation rejects insecure schemes and embedded secrets")
    func rejectsUnsafeRemotes() {
        #expect(throws: ProjectCloneError.self) {
            try ProjectCloneService.validatedRemote("http://example.test/project.git")
        }
        #expect(throws: ProjectCloneError.self) {
            try ProjectCloneService.validatedRemote(
                "https://user:token@example.test/project.git"
            )
        }
        #expect(throws: ProjectCloneError.self) {
            try ProjectCloneService.validatedRemote(
                "https://example.test/project.git?token=secret"
            )
        }
    }

    @Test("successful clone uses argument boundaries and verifies repository")
    func clonesVerifiedRepository() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let observedArguments = LockedArguments()
        let service = ProjectCloneService { workingDirectory, arguments in
            observedArguments.store(arguments)
            try FileManager.default.createDirectory(
                at: workingDirectory.displayURL.appendingPathComponent(
                    ".git",
                    isDirectory: true
                ),
                withIntermediateDirectories: true
            )
            #expect(workingDirectory.displayURL.lastPathComponent.hasPrefix(
                ".cocxy-project-"
            ))
            return successResult
        }

        let result = try service.clone(
            remote: "https://example.test/team/project.git",
            into: sandbox
        )

        #expect(observedArguments.value == [
            "clone", "--", "https://example.test/team/project.git",
            ".",
        ])
        #expect(result.rootURL == sandbox.appendingPathComponent("project"))
        #expect(try result.verifiedRootURL() == result.rootURL)
        #expect(result.remoteOrigin == "https://example.test/team/project.git")
    }

    @Test("failed clone removes only its newly-created partial destination")
    func cleansPartialClone() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let unrelated = sandbox.appendingPathComponent("keep.txt")
        try "keep".write(to: unrelated, atomically: true, encoding: .utf8)
        let service = ProjectCloneService { workingDirectory, _ in
            try "partial".write(
                to: workingDirectory.displayURL.appendingPathComponent("partial.txt"),
                atomically: true,
                encoding: .utf8
            )
            return BoundedProcessResult(
                exitCode: 3,
                stdout: "",
                stderr: "clone rejected",
                stdoutWasTruncated: false,
                stderrWasTruncated: false,
                timedOut: false
            )
        }

        #expect(throws: ProjectCloneError.self) {
            try service.clone(
                remote: "https://example.test/team/project.git",
                into: sandbox
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: sandbox.appendingPathComponent("project").path
        ))
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.path).allSatisfy {
            !$0.hasPrefix(".cocxy-project-")
        })
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("a failure after publishing a clone keeps the whole clone once files were added to it")
    func postPublicationFailureKeepsTaintedCloneWhole() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let hooks = ProjectDirectoryTransactionHooks(afterPublish: { context in
            try "user".write(
                to: context.destinationURL.appendingPathComponent("user-notes.txt"),
                atomically: false,
                encoding: .utf8
            )
            throw ProjectDirectoryError.publicationChanged(context.destinationURL.path)
        })
        let service = ProjectCloneService(hooks: hooks) { workingDirectory, _ in
            let checkout = workingDirectory.displayURL
            try FileManager.default.createDirectory(
                at: checkout.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: false
            )
            try "cloned".write(
                to: checkout.appendingPathComponent("README.md"),
                atomically: false,
                encoding: .utf8
            )
            return successResult
        }

        #expect(throws: ProjectCloneError.self) {
            try service.clone(remote: "https://example.test/team/project.git", into: sandbox)
        }
        let project = sandbox.appendingPathComponent("project", isDirectory: true)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: project.path)) == [
            ".git", "README.md", "user-notes.txt",
        ])
    }

    @Test("runner exceptions also remove a newly-created partial destination")
    func cleansPartialCloneAfterRunnerError() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let service = ProjectCloneService { workingDirectory, _ in
            try "partial".write(
                to: workingDirectory.displayURL.appendingPathComponent("partial.txt"),
                atomically: true,
                encoding: .utf8
            )
            throw BoundedProcessRunnerError.invalidInvocation
        }

        #expect(throws: BoundedProcessRunnerError.self) {
            try service.clone(
                remote: "https://example.test/team/project.git",
                into: sandbox
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: sandbox.appendingPathComponent("project").path
        ))
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.path).allSatisfy {
            !$0.hasPrefix(".cocxy-project-")
        })
    }

    @Test("existing destinations and symbolic-link parents fail before Git runs")
    func validatesDestinationBeforeClone() throws {
        let sandbox = makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let realParent = sandbox.appendingPathComponent("real")
        let linkedParent = sandbox.appendingPathComponent("linked")
        try FileManager.default.createDirectory(
            at: realParent.appendingPathComponent("project"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: realParent
        )
        let service = ProjectCloneService { _, _ in
            Issue.record("Git must not run for an invalid destination")
            return successResult
        }

        #expect(throws: ProjectCloneError.self) {
            try service.clone(
                remote: "https://example.test/project.git",
                into: realParent
            )
        }
        #expect(throws: ProjectCloneError.self) {
            try service.clone(
                remote: "https://example.test/project.git",
                into: linkedParent
            )
        }
    }

    private var successResult: BoundedProcessResult {
        BoundedProcessResult(
            exitCode: 0,
            stdout: "",
            stderr: "",
            stdoutWasTruncated: false,
            stderrWasTruncated: false,
            timedOut: false
        )
    }

    private func makeSandbox() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectCloneTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class LockedArguments: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var value: [String] {
        lock.withLock { storage }
    }

    func store(_ value: [String]) {
        lock.withLock { storage = value }
    }
}
