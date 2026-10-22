// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonDescriptorIdentitySwiftTestingTests.swift - Descriptor identity integration coverage.

import CocxyShared
import Darwin
import Foundation
import Testing

extension PTYDaemonHelperIntegrationSwiftTestingTests {
    @Test("daemon rejects a changed descriptor-bound working directory identity")
    func daemonRejectsChangedWorkingDirectoryIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-daemon-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        var metadata = stat()
        #expect(directory.path.withCString {
            Darwin.fstatat(AT_FDCWD, $0, &metadata, 0)
        } == 0)
        let helper = try RunningHelperProcess()
        defer { helper.shutdownIfNeeded() }

        let rejected = try helper.sendAndWait(PTYDaemonRequest(
            id: "changed-working-directory",
            command: .surfaceCreate,
            payload: [
                "command": "/bin/sh",
                "workingDirectory": directory.path,
                "workingDirectoryDevice": "\(UInt64(truncatingIfNeeded: metadata.st_dev))",
                "workingDirectoryInode": "\(UInt64(truncatingIfNeeded: metadata.st_ino) + 1)",
                "workingDirectoryFileType": "\(metadata.st_mode & mode_t(S_IFMT))",
                "rows": "8",
                "columns": "40",
            ]
        ))

        #expect(rejected.ok == false)
        #expect(rejected.surfaceID == nil)
        #expect(rejected.error?.contains("identity changed") == true)
    }
}
