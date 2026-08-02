// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Tab config layout runtime validation")
struct TabConfigLayoutRuntimeSwiftTestingTests {
    @Test("runtime resolves terminal and file panes inside the canonical project")
    func resolvesProjectRelativePaneResources() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let layout = TabConfigLayout.split(
            direction: .horizontal,
            ratio: 0.55,
            first: .pane(TabConfigPane(workingDirectory: "Sources")),
            second: .pane(TabConfigPane(type: .markdown, filePath: "README.md"))
        )

        let resolved = try TabConfigLayoutRuntimeResolver().resolve(
            layout,
            projectDirectory: fixture.project
        )

        guard case .split(_, _, let first, let second) = resolved,
              case .pane(let terminal) = first,
              case .pane(let markdown) = second else {
            Issue.record("Resolved layout did not retain its topology")
            return
        }
        #expect(terminal.workingDirectory == fixture.project.appendingPathComponent("Sources"))
        #expect(markdown.fileURL == fixture.project.appendingPathComponent("README.md"))
    }

    @Test("runtime rejects a pane path redirected outside by a symlink")
    func rejectsSymlinkEscape() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let outsideFile = fixture.outside.appendingPathComponent("secret.md")
        try Data("secret".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: fixture.project.appendingPathComponent("redirect"),
            withDestinationURL: fixture.outside
        )
        let layout = TabConfigLayout.split(
            direction: .horizontal,
            ratio: 0.5,
            first: .pane(TabConfigPane()),
            second: .pane(TabConfigPane(
                type: .markdown,
                filePath: "redirect/secret.md"
            ))
        )

        #expect(throws: TabConfigLayoutRuntimeError.self) {
            _ = try TabConfigLayoutRuntimeResolver().resolve(
                layout,
                projectDirectory: fixture.project
            )
        }
    }

    @Test("runtime fails before launch when a declared resource is missing")
    func rejectsMissingResources() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let layouts = [
            TabConfigLayout.pane(TabConfigPane(workingDirectory: "missing-directory")),
            TabConfigLayout.split(
                direction: .horizontal,
                ratio: 0.5,
                first: .pane(TabConfigPane()),
                second: .pane(TabConfigPane(
                    type: .markdown,
                    filePath: "missing.md"
                ))
            ),
        ]

        for layout in layouts {
            #expect(throws: TabConfigLayoutRuntimeError.self) {
                _ = try TabConfigLayoutRuntimeResolver().resolve(
                    layout,
                    projectDirectory: fixture.project
                )
            }
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-tab-config-runtime-tests")
            .appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        try Data("# Project\n".utf8).write(to: project.appendingPathComponent("README.md"))
        return Fixture(root: root, project: project, outside: outside)
    }

    private struct Fixture {
        let root: URL
        let project: URL
        let outside: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
