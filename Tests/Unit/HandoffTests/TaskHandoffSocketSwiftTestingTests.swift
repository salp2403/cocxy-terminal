// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import XCTest
@testable import CocxyTerminal

@MainActor
final class TaskHandoffSocketSwiftTestingTests: XCTestCase {
    func testCommandsArePrivilegedInTheirExactCategories() {
        XCTAssertEqual(
            SocketPrivilegedCommandSecurity.category(for: .handoffExport),
            .terminalRead
        )
        XCTAssertEqual(
            SocketPrivilegedCommandSecurity.category(for: .handoffImport),
            .localExecution
        )
    }

    func testExportAndImportDispatchOnlyValidatedParameters() {
        let capture = TaskHandoffProviderCapture()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskHandoffCLIProvider: { kind, params in
                capture.record(kind: kind, params: params)
                if kind == "export" {
                    return (true, ["artifact": "# Task Handoff"])
                }
                return (true, ["provider": params["agent"] ?? "", "tab-id": "tab-2"])
            }
        )
        let tabID = UUID().uuidString

        let export = handler.handleCommand(SocketRequest(
            id: "export",
            command: "handoff-export",
            params: ["tabId": tabID, "limit": "8"]
        ))
        XCTAssertTrue(export.success)
        XCTAssertEqual(export.data?["artifact"], "# Task Handoff")
        XCTAssertEqual(capture.kind, "export")

        let artifact = "# Task Handoff\n\nContinue."
        let imported = handler.handleCommand(SocketRequest(
            id: "import",
            command: "handoff-import",
            params: ["agent": "codex", "artifact": artifact]
        ))
        XCTAssertTrue(imported.success)
        XCTAssertEqual(imported.data?["tab-id"], "tab-2")
        XCTAssertEqual(capture.kind, "import")
        XCTAssertEqual(capture.params?["artifact"], artifact)
    }

    func testValidationRejectsUnexpectedAndOversizedInputBeforeProvider() {
        let capture = TaskHandoffProviderCapture()
        let handler = AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in
                .internalTrusted(for: request)
            },
            tabManager: nil,
            hookEventReceiver: nil,
            taskHandoffCLIProvider: { kind, params in
                capture.record(kind: kind, params: params)
                return (true, [:])
            }
        )

        let invalidExport = handler.handleCommand(SocketRequest(
            id: "invalid-export",
            command: "handoff-export",
            params: ["tabId": UUID().uuidString, "limit": "8", "extra": "value"]
        ))
        XCTAssertFalse(invalidExport.success)

        let oversized = String(
            repeating: "a",
            count: CocxyTaskHandoffWireContract.maximumArtifactBytes + 1
        )
        let invalidImport = handler.handleCommand(SocketRequest(
            id: "invalid-import",
            command: "handoff-import",
            params: ["agent": "codex", "artifact": oversized]
        ))
        XCTAssertFalse(invalidImport.success)
        XCTAssertNil(capture.kind)
    }

    func testApprovalPreviewBindsArtifactWithoutDisplayingItsContents() throws {
        let secret = "# Task Handoff\nAuthorization: Bearer hidden-secret-value"
        let request = try XCTUnwrap(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "preview",
                command: "handoff-import",
                params: ["agent": "codex", "artifact": secret]
            )
        ))

        let preview = SocketPrivilegedCommandSecurity.approvalPreview(request)

        XCTAssertTrue(preview.contains("artifact: \(secret.utf8.count) UTF-8 bytes"))
        XCTAssertTrue(preview.contains("sha256"))
        XCTAssertFalse(preview.contains("hidden-secret-value"))
    }
}

private final class TaskHandoffProviderCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedKind: String?
    private var capturedParams: [String: String]?

    var kind: String? {
        lock.withLock { capturedKind }
    }

    var params: [String: String]? {
        lock.withLock { capturedParams }
    }

    func record(kind: String, params: [String: String]) {
        lock.withLock {
            capturedKind = kind
            capturedParams = params
        }
    }
}
