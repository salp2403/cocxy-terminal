// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Exact terminal input surface authorization")
struct MainWindowExactTerminalSurfaceSwiftTestingTests {
    @Test("directed terminal input honors an exact surface and rejects a foreign one")
    func directedTerminalInputHonorsExactSurface() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.showWindow(nil)
        let tabID = controller.createTab(
            workingDirectory: URL(fileURLWithPath: "/tmp/cocxy-exact-surface")
        )
        let primarySurfaceID = try #require(controller.tabSurfaceMap[tabID])
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)

        let exactRequest = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "exact-surface-send",
                command: "send",
                params: [
                    "text": "status",
                    "tabId": tabID.rawValue.uuidString,
                    "surfaceId": primarySurfaceID.rawValue.uuidString,
                ]
            )
        ))
        let exactTarget = try #require(
            delegate.privilegedSocketCommandPresentationTarget(for: exactRequest)
        )
        #expect(exactTarget.context.surfaceID == primarySurfaceID.rawValue)

        let foreignRequest = try #require(SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: "foreign-surface-send",
                command: "send",
                params: [
                    "text": "status",
                    "tabId": tabID.rawValue.uuidString,
                    "surfaceId": UUID().uuidString,
                ]
            )
        ))
        #expect(delegate.privilegedSocketCommandPresentationTarget(for: foreignRequest) == nil)
    }
}
