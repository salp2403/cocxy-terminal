// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("TabConfigStore")
struct TabConfigStoreSwiftTestingTests {

    @Test("codec round-trips workdir, command, environment, and theme override")
    func codecRoundTripsFullConfig() throws {
        let config = TabConfig(
            name: "api",
            workingDirectory: "/Users/dev/project",
            command: "mise x -- npm run dev",
            environment: [
                "API_URL": "http://127.0.0.1:8080",
                "FEATURE_FLAG": "true"
            ],
            theme: "Catppuccin Mocha"
        )

        let rendered = TabConfigTOMLCodec.render(config)
        let parsed = try TabConfigTOMLCodec.parse(rendered)

        #expect(parsed == config)
        #expect(rendered.contains("[env]"))
        #expect(rendered.contains("schema-version = 1"))
    }

    @Test("store writes configs under the tabs directory and lists names sorted")
    func storeWritesAndListsConfigs() throws {
        let root = try temporaryDirectory()
        let store = TabConfigStore(rootDirectory: root)

        try store.save(TabConfig(name: "z-api", workingDirectory: "/tmp/z"))
        try store.save(TabConfig(name: "a-web", workingDirectory: "/tmp/a"))

        #expect(try store.listNames() == ["a-web", "z-api"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a-web.toml").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("z-api.toml").path))
    }

    @Test("load always reads the current TOML from disk so manual edits are picked up")
    func loadReadsManualEdits() throws {
        let root = try temporaryDirectory()
        let store = TabConfigStore(rootDirectory: root)
        try store.save(TabConfig(name: "dev", workingDirectory: "/tmp/old"))

        let edited = """
        schema-version = 1
        name = "dev"
        working-directory = "/tmp/new"
        command = "echo edited"
        theme = "Nord"

        [env]
        LOCAL_ONLY = "1"
        """
        try edited.write(
            to: root.appendingPathComponent("dev.toml"),
            atomically: true,
            encoding: .utf8
        )

        let loaded = try store.load(named: "dev")

        #expect(loaded.workingDirectory == "/tmp/new")
        #expect(loaded.command == "echo edited")
        #expect(loaded.environment == ["LOCAL_ONLY": "1"])
        #expect(loaded.theme == "Nord")
    }

    @Test("load refuses final symlinks and multiply-linked config files")
    func loadRejectsUnsafeSourceEntries() throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let source = outside.appendingPathComponent("source.toml")
        try TabConfigTOMLCodec.render(
            TabConfig(name: "source", workingDirectory: "/tmp/project")
        ).write(to: source, atomically: true, encoding: .utf8)
        let store = TabConfigStore(rootDirectory: root)

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("symlink.toml"),
            withDestinationURL: source
        )
        #expect(throws: TabConfigStoreError.self) {
            _ = try store.load(named: "symlink")
        }

        try FileManager.default.linkItem(
            at: source,
            to: root.appendingPathComponent("hardlink.toml")
        )
        #expect(throws: TabConfigStoreError.self) {
            _ = try store.load(named: "hardlink")
        }
    }

    @Test("config names reject path traversal and slashes")
    func namesRejectPathTraversal() throws {
        let store = TabConfigStore(rootDirectory: try temporaryDirectory())

        #expect(throws: TabConfigStoreError.self) {
            try store.save(TabConfig(name: "../escape", workingDirectory: "/tmp"))
        }
        #expect(throws: TabConfigStoreError.self) {
            _ = try store.load(named: "nested/name")
        }
    }

    @Test("suggested names stay compatible with the store validator")
    func suggestedNamesStayASCIIAndStoreSafe() throws {
        let suggested = TabConfigStore.suggestedName(from: "Café API / Dev")
        let store = TabConfigStore(rootDirectory: try temporaryDirectory())

        #expect(suggested == "caf-api-dev")
        #expect(try store.fileURL(forName: suggested).lastPathComponent == "caf-api-dev.toml")
    }

    @Test("export copies the exact TOML to a user selected destination")
    func exportCopiesExactTOMLToDestination() throws {
        let root = try temporaryDirectory()
        let exportRoot = try temporaryDirectory()
        let store = TabConfigStore(rootDirectory: root)
        try store.save(TabConfig(
            name: "api",
            workingDirectory: "/tmp/project",
            command: "make dev",
            environment: ["API_URL": "http://127.0.0.1:8080"],
            theme: "Nord"
        ))

        let source = try String(contentsOf: store.fileURL(forName: "api"), encoding: .utf8)
        let destination = exportRoot.appendingPathComponent("shared-api.toml")

        let exported = try store.export(named: "api", to: destination, overwrite: false)

        #expect(exported == destination.standardizedFileURL)
        #expect(try String(contentsOf: destination, encoding: .utf8) == source)
        #expect(throws: TabConfigStoreError.self) {
            _ = try store.export(named: "api", to: destination, overwrite: false)
        }
        _ = try store.export(named: "api", to: destination, overwrite: true)
    }

    @Test("socket export accepts only a visible TOML leaf name")
    func socketExportLeafValidation() throws {
        #expect(try TabConfigStore.validatedSocketExportLeafName("shared-api.toml") == "shared-api.toml")

        for invalid in [
            "",
            "/tmp/shared-api.toml",
            "../shared-api.toml",
            "nested/shared-api.toml",
            "nested\\shared-api.toml",
            ".hidden.toml",
            "shared..api.toml",
            "shared-api.txt",
            " shared-api.toml",
        ] {
            #expect(throws: TabConfigStoreError.self) {
                _ = try TabConfigStore.validatedSocketExportLeafName(invalid)
            }
        }
    }

    @Test("socket export publishes exact bytes beneath an owner-only root")
    func socketExportUsesPrivateRoot() throws {
        let root = try temporaryDirectory()
        let exportRoot = try temporaryDirectory().appendingPathComponent("private-exports")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exportRoot.deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o777],
            ofItemAtPath: exportRoot.path
        )
        let store = TabConfigStore(
            rootDirectory: root,
            socketExportDirectory: exportRoot
        )
        try store.save(TabConfig(
            name: "api",
            workingDirectory: "/tmp/project",
            command: "make dev",
            environment: ["API_URL": "http://127.0.0.1:8080"],
            theme: "Nord"
        ))
        let sourceURL = try store.fileURL(forName: "api")
        let sourceData = try Data(contentsOf: sourceURL)

        let exported = try store.exportForSocket(
            named: "api",
            fileName: "shared-api.toml"
        )

        #expect(exported == exportRoot.appendingPathComponent("shared-api.toml").standardizedFileURL)
        #expect(try Data(contentsOf: exported) == sourceData)
        #expect(try permissions(at: exportRoot) == 0o700)
        #expect(try permissions(at: exported) == 0o600)
        #expect(throws: TabConfigStoreError.self) {
            _ = try store.exportForSocket(named: "api", fileName: "shared-api.toml")
        }
        _ = try store.exportForSocket(
            named: "api",
            fileName: "shared-api.toml",
            overwrite: true
        )
    }

    @Test("socket export refuses a symlinked export root")
    func socketExportRejectsSymlinkedRoot() throws {
        let root = try temporaryDirectory()
        let container = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: container)
            try? FileManager.default.removeItem(at: outside)
        }
        let exportRoot = container.appendingPathComponent("exports")
        try FileManager.default.createSymbolicLink(at: exportRoot, withDestinationURL: outside)
        let store = TabConfigStore(
            rootDirectory: root,
            socketExportDirectory: exportRoot
        )
        try store.save(TabConfig(name: "api", workingDirectory: "/tmp/project"))

        #expect(throws: TabConfigStoreError.self) {
            _ = try store.exportForSocket(
                named: "api",
                fileName: "outside.toml",
                overwrite: true
            )
        }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("outside.toml").path))
    }

    @Test("socket export refuses a final symlink and preserves its target")
    func socketExportRejectsFinalSymlink() throws {
        let root = try temporaryDirectory()
        let exportRoot = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exportRoot)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideTarget = outside.appendingPathComponent("sentinel.toml")
        try Data("sentinel".utf8).write(to: outsideTarget)
        try FileManager.default.createSymbolicLink(
            at: exportRoot.appendingPathComponent("shared-api.toml"),
            withDestinationURL: outsideTarget
        )
        let store = TabConfigStore(
            rootDirectory: root,
            socketExportDirectory: exportRoot
        )
        try store.save(TabConfig(name: "api", workingDirectory: "/tmp/project"))

        #expect(throws: TabConfigStoreError.self) {
            _ = try store.exportForSocket(
                named: "api",
                fileName: "shared-api.toml",
                overwrite: true
            )
        }
        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "sentinel")
    }

    @Test("startup authorization binds exact config bytes, directory, and destination tab")
    func startupAuthorizationBindsExactContext() throws {
        let config = TabConfig(
            name: "api",
            workingDirectory: "/tmp/project",
            command: "npm run dev",
            environment: ["QUOTE": "it's safe"]
        )
        let sourceData = Data(TabConfigTOMLCodec.render(config).utf8)
        let snapshot = TabConfigSnapshot(
            config: config,
            sourceData: sourceData,
            sourceDigest: TabConfigStartupSecurity.sourceDigest(for: sourceData)
        )
        let tabID = TabID()
        let now = Date(timeIntervalSince1970: 1_000)

        let request = try #require(TabConfigStartupSecurity.makeAuthorizationRequest(
            snapshot: snapshot,
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            destinationTabID: tabID,
            launchOrigin: .userInterface,
            now: now
        ))

        #expect(request.sourceDigest == TabConfigStartupSecurity.sourceDigest(for: sourceData))
        #expect(request.destinationTabID == tabID)
        #expect(request.launchOrigin == .userInterface)
        #expect(request.workingDirectory == "/tmp/project")
        #expect(request.startupInput == "QUOTE='it'\\''s safe' npm run dev\r")
        #expect(request.expiresAt == now.addingTimeInterval(TabConfigStartupSecurity.authorizationLifetime))
        #expect(TabConfigStartupSecurity.approvalPreview(request).hasSuffix("\\r"))
    }

    @Test("commandless environment-free config needs no startup approval")
    func commandlessConfigNeedsNoStartupApproval() {
        let config = TabConfig(name: "plain", workingDirectory: "/tmp/project")
        let sourceData = Data(TabConfigTOMLCodec.render(config).utf8)
        let snapshot = TabConfigSnapshot(
            config: config,
            sourceData: sourceData,
            sourceDigest: TabConfigStartupSecurity.sourceDigest(for: sourceData)
        )

        #expect(TabConfigStartupSecurity.makeAuthorizationRequest(
            snapshot: snapshot,
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            destinationTabID: TabID(),
            launchOrigin: .userInterface
        ) == nil)
    }

    @Test("approval previews expose literal escapes and invisible Unicode")
    func approvalPreviewsExposeInvisibleInput() {
        let bidiOverride = String(UnicodeScalar(0x202E)!)
        let request = TabConfigStartupAuthorizationRequest(
            id: UUID(),
            configName: "api",
            sourceDigest: String(repeating: "a", count: 64),
            workingDirectory: "/tmp/project",
            destinationTabID: TabID(),
            launchOrigin: .userInterface,
            command: nil,
            environment: [:],
            startupInput: #"literal\r"# + bidiOverride + "\t\r",
            expiresAt: Date().addingTimeInterval(60)
        )

        #expect(
            TabConfigStartupSecurity.approvalPreview(request) ==
                #"literal\\r\u{202E}\t\r"#
        )
        #expect(
            TabConfigStartupSecurity.approvalMetadataPreview(
                #"name\path"# + bidiOverride + "\n"
            ) == #"name\\path\u{202E}\u{000A}"#
        )
    }

    @Test("socket-origin config never produces startup authorization or terminal input")
    func socketOriginNeverProducesStartupAuthorization() {
        let config = TabConfig(
            name: "socket",
            workingDirectory: "/tmp/project",
            command: "touch /tmp/should-not-run",
            environment: ["TOKEN": "secret"]
        )
        let sourceData = Data(TabConfigTOMLCodec.render(config).utf8)
        let snapshot = TabConfigSnapshot(
            config: config,
            sourceData: sourceData,
            sourceDigest: TabConfigStartupSecurity.sourceDigest(for: sourceData)
        )

        #expect(TabConfigStartupSecurity.makeAuthorizationRequest(
            snapshot: snapshot,
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            destinationTabID: TabID(),
            launchOrigin: .localSocket
        ) == nil)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-tab-config-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return root
    }
}
