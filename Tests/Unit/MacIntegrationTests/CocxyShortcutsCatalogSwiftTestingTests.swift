// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cocxy Shortcuts catalog")
struct CocxyShortcutsCatalogSwiftTestingTests {

    @Test("catalog exposes local only shortcuts with explicit privacy boundaries")
    func catalogExposesLocalOnlyShortcuts() {
        let descriptors = CocxyShortcutsCatalog.descriptors

        #expect(descriptors.map(\.id) == [
            "open-app",
            "run-command",
            "open-notebook",
            "list-skills",
        ])
        #expect(descriptors.allSatisfy { $0.requiresUserInitiation })
        #expect(descriptors.allSatisfy { $0.networkPolicy == .localOnly })
        #expect(descriptors.allSatisfy { !$0.title.isEmpty })
        #expect(descriptors.allSatisfy { !$0.privacySummary.isEmpty })
    }

    @Test("app bundle scripts emit and verify Shortcuts metadata")
    func appBundleScriptsEmitAndVerifyShortcutsMetadata() throws {
        let root = repositoryRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains("appintentsmetadataprocessor"))
        #expect(buildScript.contains("SwiftConstantValues/AppIntents.json"))
        #expect(buildScript.contains("Metadata.appintents"))
        #expect(verifyScript.contains("[Shortcuts]"))
        #expect(verifyScript.contains("Metadata.appintents"))
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let package = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: package.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
