// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import XCTest
@testable import CocxyCLILib

final class TaskHandoffCLIArgumentParserSwiftTestingTests: XCTestCase {
    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/test.sock")
    )

    func testExportParsesAndBuildsExactTabRequest() throws {
        let tabID = "00000000-0000-0000-0000-000000000123"
        let parsed = try CLIArgumentParser.parse([
            "handoff-export", "--tab", tabID, "--blocks", "12",
        ])

        XCTAssertEqual(parsed, .handoffExport(tabID: tabID, blockLimit: 12))
        XCTAssertEqual(runner.buildRequest(from: parsed).command, "handoff-export")
        XCTAssertEqual(runner.buildRequest(from: parsed).params, [
            "tabId": tabID,
            "limit": "12",
        ])
    }

    func testExportUsesDefaultLimitAndRejectsInvalidScope() throws {
        let tabID = "00000000-0000-0000-0000-000000000123"
        XCTAssertEqual(
            try CLIArgumentParser.parse(["handoff-export", "--tab", tabID]),
            .handoffExport(
                tabID: tabID,
                blockLimit: CocxyTaskHandoffWireContract.defaultBlockLimit
            )
        )

        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "handoff-export", "--tab", "not-a-uuid",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "handoff-export", "--tab", tabID, "--blocks", "17",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "handoff-export", "--tab", tabID, "--blocks", "8", "--blocks", "9",
        ]))
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "handoff-export", "--tab", tabID, "--tab", tabID,
        ]))
    }

    func testImportReadsBoundedUTF8FileAndBuildsRequest() throws {
        let artifact = "# Task Handoff\n\nContinue the exact task."
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-handoff-\(UUID().uuidString).md")
        try Data(artifact.utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let parsed = try CLIArgumentParser.parse([
            "handoff-import", "--agent", "CoDeX", "--file", fileURL.path,
        ])

        XCTAssertEqual(parsed, .handoffImport(agent: "codex", artifact: artifact))
        let request = runner.buildRequest(from: parsed)
        XCTAssertEqual(request.command, "handoff-import")
        XCTAssertEqual(request.params, ["agent": "codex", "artifact": artifact])
    }

    func testImportRejectsConflictingSourcesAndOversizedFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-handoff-large-\(UUID().uuidString).md")
        let data = Data(
            repeating: 0x61,
            count: CocxyTaskHandoffWireContract.maximumArtifactBytes + 1
        )
        try data.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "handoff-import", "--agent", "codex", "--file", fileURL.path,
        ])) { error in
            XCTAssertEqual(
                error as? CLIError,
                .payloadTooLarge(
                    size: CocxyTaskHandoffWireContract.maximumArtifactBytes + 1,
                    maximum: CocxyTaskHandoffWireContract.maximumArtifactBytes
                )
            )
        }
        XCTAssertThrowsError(try CLIArgumentParser.parse([
            "handoff-import", "--agent", "codex", "--stdin", "--file", fileURL.path,
        ]))
    }

    func testOutputKeepsExportPipeableAndReportsDestinationTab() {
        let export = OutputFormatter.formatSuccess(
            command: .handoffExport(tabID: UUID().uuidString, blockLimit: 8),
            response: CLISocketResponse(
                id: "export",
                success: true,
                data: ["artifact": "# Task Handoff"],
                error: nil
            )
        )
        XCTAssertEqual(export, "# Task Handoff")

        let imported = OutputFormatter.formatSuccess(
            command: .handoffImport(agent: "codex", artifact: "# Task Handoff"),
            response: CLISocketResponse(
                id: "import",
                success: true,
                data: ["provider": "codex", "tab-id": "tab-1"],
                error: nil
            )
        )
        XCTAssertEqual(imported, "Task passed to codex in tab tab-1.")
    }
}
