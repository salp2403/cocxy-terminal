// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Aurora inline rename integration", .serialized)
struct AuroraRenameIntegrationSwiftTestingTests {

    @Test("session rename reaches TabManager and blank input restores automatic title")
    func sessionRenameReachesDomainModel() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tabID = controller.tabManager.tabs[0].id

        controller.applyAuroraSessionRename(tabID: tabID, newTitle: "  Build Session  ")
        #expect(controller.tabManager.tab(for: tabID)?.customTitle == "Build Session")
        #expect(controller.tabManager.tab(for: tabID)?.displayTitle == "Build Session")

        controller.applyAuroraSessionRename(tabID: tabID, newTitle: "   ")
        #expect(controller.tabManager.tab(for: tabID)?.customTitle == nil)
    }

    @Test("workspace rename persists once by identity without copying onto tabs")
    func workspaceRenameUsesIdentityStore() throws {
        let suiteName = "AuroraRenameIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(bridge: MockTerminalEngine())
        controller.auroraWorkspaceTitleStore = AuroraWorkspaceTitleStore(
            defaults: defaults,
            storageKey: "titles"
        )
        let tab = controller.tabManager.tabs[0]
        let resolver = GitAncestorWorkspaceRootResolver()
        let workspaceID = AuroraWorkspacePlanner.descriptor(
            for: tab,
            resolver: resolver
        ).identity

        controller.applyAuroraWorkspaceRename(
            workspaceID: workspaceID,
            newTitle: "  Product Workspace  "
        )

        #expect(controller.auroraWorkspaceTitleStore.title(for: workspaceID) == "Product Workspace")
        #expect(controller.tabManager.tab(for: tab.id)?.workspaceCustomTitle == nil)

        controller.applyAuroraWorkspaceRename(workspaceID: workspaceID, newTitle: "")
        #expect(controller.auroraWorkspaceTitleStore.title(for: workspaceID) == nil)
        #expect(controller.auroraWorkspaceTitleStore.snapshot[workspaceID] == "")
    }
}
