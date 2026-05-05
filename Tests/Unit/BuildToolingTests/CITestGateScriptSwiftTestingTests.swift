// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CITestGateScriptSwiftTestingTests.swift - Local/CI test gate drift checks.

import Foundation
import Testing

@Suite("CI test gate script")
struct CITestGateScriptSwiftTestingTests {

    @Test("local test gate mirrors the CI split XCTest and Swift Testing commands")
    func localTestGateMirrorsCISplitCommands() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/run-tests.sh")
        let script = try String(
            contentsOf: scriptURL,
            encoding: .utf8
        )
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let pullRequestTemplate = try String(
            contentsOf: root.appendingPathComponent(".github/PULL_REQUEST_TEMPLATE.md"),
            encoding: .utf8
        )

        #expect(script.contains("set -euo pipefail"))
        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("swift test --disable-swift-testing --skip PerformanceTests --skip CocxyCorePerformanceBenchmarks"))
        #expect(script.contains("./scripts/run-swift-testing-serial.sh"))
        #expect(ci.contains("./scripts/run-tests.sh"))
        #expect(pullRequestTemplate.contains("`./scripts/run-tests.sh` passes locally"))
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
