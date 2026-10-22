// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

struct TerminalDetectedContentActionSwiftTestingTests {
    @Test("inferred web links allow HTTP and HTTPS only")
    func inferredWebLinksUseSafeSchemes() {
        let https = detected(kind: .url, target: "https://cocxy.dev/docs")
        let custom = detected(kind: .url, target: "ssh://host.example")

        #expect(
            TerminalDetectedContentActionResolver.resolve(https, workingDirectory: nil)
                == .openURL(URL(string: "https://cocxy.dev/docs")!)
        )
        #expect(TerminalDetectedContentActionResolver.resolve(custom, workingDirectory: nil) == nil)
    }

    @Test("explicit links allow mail and reject arbitrary handlers")
    func explicitLinksUseRestrictedSchemes() {
        let email = detected(
            kind: .hyperlink,
            target: "mailto:dev@cocxy.dev",
            isExplicitHyperlink: true
        )
        let custom = detected(
            kind: .hyperlink,
            target: "custom-app://run",
            isExplicitHyperlink: true
        )

        #expect(
            TerminalDetectedContentActionResolver.resolve(email, workingDirectory: nil)
                == .openURL(URL(string: "mailto:dev@cocxy.dev")!)
        )
        #expect(TerminalDetectedContentActionResolver.resolve(custom, workingDirectory: nil) == nil)
    }

    @Test("relative file locations resolve against the surface directory")
    func relativeFileLocationsPreserveLineAndColumn() {
        let cwd = URL(fileURLWithPath: "/tmp/cocxy-project", isDirectory: true)
        let content = detected(
            kind: .filePath,
            target: "Sources/App.swift",
            line: 42,
            column: 7
        )

        let action = TerminalDetectedContentActionResolver.resolve(
            content,
            workingDirectory: cwd,
            fileExists: { $0.path == "/tmp/cocxy-project/Sources/App.swift" }
        )

        #expect(action == .openFile(
            URL(fileURLWithPath: "/tmp/cocxy-project/Sources/App.swift"),
            line: 42,
            column: 7
        ))
    }

    @Test("missing files and relative paths without a surface directory are rejected")
    func invalidFileTargetsAreRejected() {
        let content = detected(kind: .filePath, target: "Sources/Missing.swift")

        #expect(TerminalDetectedContentActionResolver.resolve(
            content,
            workingDirectory: nil,
            fileExists: { _ in true }
        ) == nil)
        #expect(TerminalDetectedContentActionResolver.resolve(
            content,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            fileExists: { _ in false }
        ) == nil)
    }

    @Test("copy-only detections use the engine target")
    func copyTargetsComeFromEngineDetection() {
        for kind in [
            TerminalDetectedContentKind.ipAddress,
            .gitHash,
            .email,
        ] {
            let content = detected(kind: kind, target: "engine-target")
            #expect(
                TerminalDetectedContentActionResolver.resolve(content, workingDirectory: nil)
                    == .copy("engine-target")
            )
        }
    }

    @Test("control characters are never handed to the workspace")
    func controlCharactersAreRejected() {
        let content = detected(kind: .url, target: "https://cocxy.dev\nfile:///tmp/payload")
        #expect(TerminalDetectedContentActionResolver.resolve(content, workingDirectory: nil) == nil)
    }

    private func detected(
        kind: TerminalDetectedContentKind,
        target: String,
        line: Int? = nil,
        column: Int? = nil,
        isExplicitHyperlink: Bool = false
    ) -> TerminalDetectedContent {
        TerminalDetectedContent(
            kind: kind,
            text: target,
            target: target,
            startRow: 0,
            startColumn: 0,
            endRow: 0,
            endColumn: UInt16(clamping: max(0, target.utf8.count - 1)),
            line: line,
            column: column,
            isExplicitHyperlink: isExplicitHyperlink
        )
    }
}
