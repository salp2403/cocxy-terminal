// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Tab config project layouts")
struct TabConfigLayoutCodecSwiftTestingTests {
    @Test("nested mixed-pane layout round trips through readable TOML")
    func nestedLayoutRoundTrip() throws {
        let layout = TabConfigLayout.split(
            direction: .horizontal,
            ratio: 0.6,
            first: .pane(TabConfigPane(
                workingDirectory: ".",
                title: "Shell"
            )),
            second: .split(
                direction: .vertical,
                ratio: 0.4,
                first: .pane(TabConfigPane(
                    type: .markdown,
                    filePath: "README.md",
                    title: "Docs"
                )),
                second: .pane(TabConfigPane(
                    type: .browser,
                    initialURL: URL(string: "http://127.0.0.1:3000"),
                    title: "Preview"
                ))
            )
        )
        let config = TabConfig(
            name: "project",
            workingDirectory: "/tmp/project",
            environment: ["MODE": "dev"],
            theme: "Nord",
            layout: layout
        )

        let source = TabConfigTOMLCodec.render(config)
        let decoded = try TabConfigTOMLCodec.parse(source)

        #expect(decoded == config)
        #expect(source.contains("[layout]"))
        #expect(source.contains("[layout.node.n0]"))
        #expect(source.contains("direction = \"horizontal\""))
        #expect(source.contains("type = \"browser\""))
    }

    @Test("legacy config without layout keeps the optional field nil")
    func legacyConfigDefaultsToNoLayout() throws {
        let source = """
        schema-version = 1
        name = "legacy"
        working-directory = "/tmp/project"
        """

        let decoded = try TabConfigTOMLCodec.parse(source)

        #expect(decoded.layout == nil)
    }

    @Test("layout graph rejects cycles, orphan nodes, and unknown tables")
    func graphValidationRejectsMalformedTopology() {
        let malformedLayouts = [
            """
            [layout]
            root = "n0"
            [layout.node.n0]
            kind = "split"
            direction = "horizontal"
            ratio = 0.5
            first = "n0"
            second = "n1"
            [layout.node.n1]
            kind = "pane"
            type = "terminal"
            """,
            """
            [layout]
            root = "n0"
            [layout.node.n0]
            kind = "pane"
            type = "terminal"
            [layout.node.orphan]
            kind = "pane"
            type = "terminal"
            """,
            """
            [layout]
            root = "n0"
            [layout.extra]
            value = "ignored"
            [layout.node.n0]
            kind = "pane"
            type = "terminal"
            """,
        ]

        for layoutSource in malformedLayouts {
            #expect(throws: TabConfigStoreError.self) {
                _ = try TabConfigTOMLCodec.parse(baseConfig + layoutSource)
            }
        }
    }

    @Test("layout rejects remote URLs, traversal, dynamic panes, and nonterminal roots")
    func paneValidationFailsClosed() {
        let unsafePanes = [
            """
            kind = "pane"
            type = "browser"
            url = "https://example.com"
            """,
            """
            kind = "pane"
            type = "terminal"
            working-directory = "../outside"
            """,
            """
            kind = "pane"
            type = "subagent"
            """,
            """
            kind = "pane"
            type = "editor"
            file-path = "README.md"
            """,
        ]

        for pane in unsafePanes {
            let source = baseConfig + """
            [layout]
            root = "n0"
            [layout.node.n0]
            \(pane)
            """
            #expect(throws: TabConfigStoreError.self) {
                _ = try TabConfigTOMLCodec.parse(source)
            }
        }
    }

    @Test("store rejects programmatic layouts beyond the four-pane UI limit")
    func storeRejectsOversizedProgrammaticLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-layout-codec-tests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pane = TabConfigLayout.pane(TabConfigPane())
        let oversized = TabConfigLayout.split(
            direction: .horizontal,
            ratio: 0.5,
            first: .split(
                direction: .vertical,
                ratio: 0.5,
                first: pane,
                second: pane
            ),
            second: .split(
                direction: .vertical,
                ratio: 0.5,
                first: pane,
                second: .split(
                    direction: .horizontal,
                    ratio: 0.5,
                    first: pane,
                    second: pane
                )
            )
        )
        let store = TabConfigStore(rootDirectory: root)

        #expect(throws: TabConfigStoreError.self) {
            try store.save(TabConfig(
                name: "oversized",
                workingDirectory: "/tmp/project",
                layout: oversized
            ))
        }
    }

    private var baseConfig: String {
        """
        schema-version = 1
        name = "project"
        working-directory = "/tmp/project"

        """
    }
}
