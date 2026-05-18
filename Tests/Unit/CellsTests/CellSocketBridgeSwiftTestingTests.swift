// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellSocketBridgeSwiftTestingTests.swift - Cocxy Cells socket bridge coverage.

import XCTest
@testable import CocxyTerminal

@MainActor
final class CellSocketBridgeSwiftTestingTests: XCTestCase {
    func testCellCommandNamesAreClosedAndRegistered() {
        let rawValues = Set(CLICommandName.allCases.map(\.rawValue))
        XCTAssertTrue(rawValues.contains("cell-create"))
        XCTAssertTrue(rawValues.contains("cell-list"))
        XCTAssertTrue(rawValues.contains("cell-exec"))
        XCTAssertTrue(rawValues.contains("cell-attach"))
        XCTAssertTrue(rawValues.contains("cell-destroy"))
        XCTAssertTrue(rawValues.contains("cell-logs"))
        XCTAssertTrue(rawValues.contains("cell-status"))
    }

    func testCellSocketDispatchesToInjectedProvider() {
        let capture = CellCLIProviderCapture()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            cellCLIProvider: { kind, params in
                capture.record(kind: kind, params: params)
                return (true, [
                    "status": "created",
                    "cell-id": "cell-1",
                ])
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "cell-create-1",
            command: "cell-create",
            params: ["provider": "docker", "profile": "local-dev"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "created")
        XCTAssertEqual(response.data?["cell-id"], "cell-1")
        XCTAssertEqual(capture.kind, "create")
        XCTAssertEqual(capture.params?["provider"], "docker")
        XCTAssertEqual(capture.params?["profile"], "local-dev")
    }

    func testCellSocketReturnsUsefulErrorWhenProviderIsUnavailable() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "cell-list-1",
            command: "cell-list",
            params: nil
        ))

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Cells not available")
    }
}

private final class CellCLIProviderCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedKind: String?
    private var capturedParams: [String: String]?

    var kind: String? {
        lock.lock()
        defer { lock.unlock() }
        return capturedKind
    }

    var params: [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return capturedParams
    }

    func record(kind: String, params: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        capturedKind = kind
        capturedParams = params
    }
}
