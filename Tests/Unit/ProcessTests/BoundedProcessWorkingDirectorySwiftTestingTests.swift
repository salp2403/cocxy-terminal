// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Bounded process working directory", .serialized)
struct BoundedProcessWorkingDirectorySwiftTestingTests {
    @Test("descriptor working directory survives pathname replacement")
    func descriptorSurvivesPathReplacement() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BoundedCWD-\(UUID().uuidString)",
            isDirectory: true
        )
        let original = container.appendingPathComponent("original", isDirectory: true)
        let moved = container.appendingPathComponent("moved", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        try FileManager.default.createDirectory(
            at: original,
            withIntermediateDirectories: true
        )
        let descriptor = original.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        let openedDescriptor = try #require(descriptor >= 0 ? descriptor : nil)
        defer { Darwin.close(openedDescriptor) }
        let workingDirectory = BoundedProcessWorkingDirectory.descriptor(
            displayURL: original,
            rawValue: openedDescriptor
        )

        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.createDirectory(
            at: original,
            withIntermediateDirectories: false
        )
        let result = try BoundedProcessRunner(
            maximumRetainedBytesPerStream: 64 * 1_024
        ).run(
            executableURL: URL(fileURLWithPath: "/usr/bin/touch"),
            arguments: ["descriptor-marker"],
            workingDirectory: workingDirectory,
            timeoutSeconds: 5
        )

        #expect(result.exitCode == 0)
        #expect(FileManager.default.fileExists(
            atPath: moved.appendingPathComponent("descriptor-marker").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: original.appendingPathComponent("descriptor-marker").path
        ))
    }

    @Test("closed descriptor is rejected before spawning")
    func rejectsClosedDescriptor() throws {
        let directory = FileManager.default.temporaryDirectory
        let descriptor = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        let openedDescriptor = try #require(descriptor >= 0 ? descriptor : nil)
        Darwin.close(openedDescriptor)

        #expect(throws: BoundedProcessRunnerError.invalidInvocation) {
            try BoundedProcessRunner(maximumRetainedBytesPerStream: 1_024).run(
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: [],
                workingDirectory: .descriptor(
                    displayURL: directory,
                    rawValue: openedDescriptor
                ),
                timeoutSeconds: 1
            )
        }
    }
}
