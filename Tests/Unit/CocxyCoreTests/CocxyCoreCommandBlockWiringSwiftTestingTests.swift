// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import CocxyCoreKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyCore command block wiring", .serialized)
@MainActor
struct CocxyCoreCommandBlockWiringSwiftTestingTests {
    @Test("command finish performs one metadata list and one output reload")
    func commandFinishReloadsOutputWithinBudget() async throws {
        let fixture = try makeFixture(named: "command-finish")
        defer { fixture.cleanup() }

        fixture.coreView.updateCommandBlockOverlayConfiguration(CommandBlocksConfig(
            enabled: false,
            showOnlyOnHover: true
        ))
        var metadataLoads = 0
        var outputCopies = 0
        fixture.bridge.commandBlockMetadataLoadObserver = { metadataLoads += 1 }
        fixture.bridge.commandBlockOutputCopyObserver = { outputCopies += 1 }
        let shellHint = "zsh: correct 'cocxytst' to 'cocxytest' [nyae]?"

        feedCommandBlock(
            command: "cocxytst --version",
            output: shellHint,
            exitCode: 127,
            into: fixture.terminal
        )

        try await waitUntil {
            fixture.coreView.pendingCommandCorrection?.source == .shellHint
                && (try? fixture.store.load(sessionID: fixture.sessionID).last?.output) == shellHint
        }
        #expect(fixture.coreView.pendingCommandCorrection?.suggestion == "cocxytest --version")
        #expect(metadataLoads == 2)
        #expect(outputCopies == 1)
    }

    @Test("bookmark reloads output and writes through the injected store")
    func bookmarkPreservesOutputInInjectedStore() async throws {
        let fixture = try makeFixture(named: "command-bookmark")
        defer { fixture.cleanup() }
        let output = "bookmark-output"

        feedCommandBlock(
            command: "printf bookmark-output",
            output: output,
            exitCode: 0,
            into: fixture.terminal
        )
        try await waitUntil {
            (try? fixture.store.load(sessionID: fixture.sessionID).last?.output) == output
        }

        let metadataOnlyBlock = try #require(fixture.bridge.commandBlocks(
            for: fixture.surfaceID,
            limit: 1,
            includeOutput: false,
            includeVisibleMapping: false
        ).last)
        #expect(metadataOnlyBlock.output.isEmpty)
        var outputCopies = 0
        fixture.bridge.commandBlockOutputCopyObserver = { outputCopies += 1 }
        try #require(fixture.coreView.commandBlockOverlayView)
            .onToggleBookmark?(metadataOnlyBlock)

        try await waitUntil {
            (try? fixture.store.load(sessionID: fixture.sessionID).last?.isBookmarked) == true
        }
        let bookmarked = try #require(
            fixture.store.load(sessionID: fixture.sessionID).last
        )
        #expect(bookmarked.output == output)
        #expect(bookmarked.isBookmarked)
        #expect(outputCopies == 1)
    }

    private func makeFixture(named name: String) throws -> CommandBlockWiringFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-\(name)-\(UUID().uuidString)", isDirectory: true)
        let bridge = try makeSilentBridge()
        let store = TerminalBlockStore(rootDirectory: root)
        let controller = MainWindowController(
            bridge: bridge,
            commandBlockStore: store
        )
        controller.showWindow(nil)
        if controller.tabManager.activeTabID.flatMap({ controller.tabSurfaceMap[$0] }) == nil {
            controller.createTerminalSurface()
        }

        let tabID = try #require(controller.tabManager.activeTabID)
        let surfaceID = try #require(controller.tabSurfaceMap[tabID])
        let coreView = try #require(controller.surfaceViewForTab(tabID) as? CocxyCoreView)
        let terminal = try #require(bridge.surfaceState(for: surfaceID)?.terminal)
        return CommandBlockWiringFixture(
            root: root,
            bridge: bridge,
            controller: controller,
            store: store,
            surfaceID: surfaceID,
            coreView: coreView,
            terminal: terminal,
            sessionID: controller.sessionIDForTab(tabID).rawValue.uuidString
        )
    }
}

@MainActor
private struct CommandBlockWiringFixture {
    let root: URL
    let bridge: CocxyCoreBridge
    let controller: MainWindowController
    let store: TerminalBlockStore
    let surfaceID: SurfaceID
    let coreView: CocxyCoreView
    let terminal: OpaquePointer
    let sessionID: String

    func cleanup() {
        controller.close()
        try? FileManager.default.removeItem(at: root)
    }
}

/// The fixture feeds its own OSC 133 marks. A real shell would print prompt
/// marks into the same terminal whenever it finishes starting, which on a slow
/// machine lands inside the fed block, so the surface runs `cat` instead.
@MainActor
private func makeSilentBridge() throws -> CocxyCoreBridge {
    let bridge = CocxyCoreBridge()
    try bridge.initialize(config: TerminalEngineConfig(
        fontFamily: "Menlo",
        fontSize: 14,
        themeName: "Test",
        shell: "/bin/cat",
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        windowPaddingX: 8,
        windowPaddingY: 4
    ))
    return bridge
}

private func feedCommandBlock(
    command: String,
    output: String,
    exitCode: Int,
    into terminal: OpaquePointer
) {
    let text = "\u{1B}]133;A\u{7}$ "
        + "\u{1B}]133;B\u{7}\(command)\r\n"
        + "\u{1B}]133;C\u{7}\(output)\r\n"
        + "\u{1B}]133;D;\(exitCode)\u{7}"
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}
