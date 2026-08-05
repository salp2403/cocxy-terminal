// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Aurora workspace rename canonicalization")
struct AuroraWorkspaceRenameCanonicalizationSwiftTestingTests {
    @Test("rename requests target the session and physical workspace root")
    func renameRequestsUseCanonicalWorkspaceIdentity() throws {
        let temporaryRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("aurora-rename-\(UUID().uuidString)", isDirectory: true)
        let physicalRoot = temporaryRoot.appendingPathComponent("physical", isDirectory: true)
        let aliasedRoot = temporaryRoot.appendingPathComponent("alias", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(
            at: physicalRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: aliasedRoot,
            withDestinationURL: physicalRoot
        )

        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let controller = AuroraChromeController(tabManager: tabManager, store: store)
        controller.beginObservingDomain()
        let tab = tabManager.addTab(workingDirectory: aliasedRoot)
        controller.refreshSources()

        #expect(controller.requestRenameSession(tab.id))
        #expect(
            controller.sidebarRenameRequest?.target
                == .session(tab.id.rawValue.uuidString)
        )
        #expect(controller.requestRenameWorkspace(containing: tab.id))
        #expect(controller.sidebarRenameRequest?.target == .workspace(physicalRoot.path))
    }
}
