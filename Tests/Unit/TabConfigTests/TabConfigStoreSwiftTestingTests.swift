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
