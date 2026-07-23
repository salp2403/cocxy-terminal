// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SFTP browser UI state")
struct SFTPBrowserUIStateSwiftTestingTests {
    @Test("delete eligibility matches the reviewed-entry removal contract")
    func deleteEligibilityMatchesRemovalContract() {
        #expect(SFTPBrowserView.isDeleteEligible(entry(
            name: "folder",
            isDirectory: true,
            permissions: "drwxr-xr-x"
        )))
        #expect(SFTPBrowserView.isDeleteEligible(entry(
            name: "notes.txt",
            permissions: "-rw-r--r--"
        )))
        #expect(!SFTPBrowserView.isDeleteEligible(entry(
            name: "folder-link",
            isDirectory: true,
            isSymbolicLink: true,
            permissions: "lrwxr-xr-x"
        )))
        #expect(!SFTPBrowserView.isDeleteEligible(entry(
            name: "notes-link",
            isSymbolicLink: true,
            permissions: "lrwxr-xr-x"
        )))
        #expect(!SFTPBrowserView.isDeleteEligible(entry(
            name: "agent.sock",
            permissions: "srwx------"
        )))
    }

    private func entry(
        name: String,
        isDirectory: Bool = false,
        isSymbolicLink: Bool = false,
        permissions: String
    ) -> RemoteFileEntry {
        RemoteFileEntry(
            id: "/remote/\(name)",
            name: name,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 0),
            permissions: permissions
        )
    }
}
