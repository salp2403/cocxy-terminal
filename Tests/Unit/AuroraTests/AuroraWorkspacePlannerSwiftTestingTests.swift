// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Aurora workspace identity and titles", .serialized)
struct AuroraWorkspacePlannerSwiftTestingTests {

    private struct StubResolver: AuroraWorkspaceRootResolver, @unchecked Sendable {
        let roots: [URL: URL]

        func workspaceRoot(for directory: URL) -> URL? {
            roots[directory]
        }
    }

    @Test("full root path is stable identity and same basenames do not collide")
    func fullRootPathIdentityDoesNotCollide() {
        let cwdA = URL(fileURLWithPath: "/Users/user/a/html/src")
        let cwdB = URL(fileURLWithPath: "/Users/user/b/html/src")
        let rootA = URL(fileURLWithPath: "/Users/user/a/html")
        let rootB = URL(fileURLWithPath: "/Users/user/b/html")
        let resolver = StubResolver(roots: [cwdA: rootA, cwdB: rootB])
        let tabA = Tab(title: "A", workingDirectory: cwdA)
        let tabB = Tab(title: "B", workingDirectory: cwdB)

        let descriptorA = AuroraWorkspacePlanner.descriptor(for: tabA, resolver: resolver)
        let descriptorB = AuroraWorkspacePlanner.descriptor(for: tabB, resolver: resolver)

        #expect(descriptorA.identity == "/Users/user/a/html")
        #expect(descriptorB.identity == "/Users/user/b/html")
        #expect(descriptorA.identity != descriptorB.identity)
        #expect(descriptorA.automaticName == "html")
        #expect(descriptorB.automaticName == "html")
    }

    @Test("group matching returns every tab sharing the same resolved root")
    func matchingUsesStableWorkspaceIdentity() {
        let firstCWD = URL(fileURLWithPath: "/repo/app/Sources")
        let secondCWD = URL(fileURLWithPath: "/repo/app/Tests")
        let otherCWD = URL(fileURLWithPath: "/repo/other")
        let root = URL(fileURLWithPath: "/repo/app")
        let first = Tab(title: "First", workingDirectory: firstCWD)
        let second = Tab(title: "Second", workingDirectory: secondCWD)
        let other = Tab(title: "Other", workingDirectory: otherCWD)
        let resolver = StubResolver(roots: [firstCWD: root, secondCWD: root])

        let matches = AuroraWorkspacePlanner.matchingTabIDs(
            workspaceID: "/repo/app",
            in: [first, second, other],
            resolver: resolver
        )

        #expect(matches == [first.id, second.id])
    }

    @Test("renaming preserves identity and blank title restores the automatic name")
    func titleStorePersistsRenameAndExplicitReset() throws {
        let suiteName = HermeticUserDefaults.suiteName()
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "titles"
        let store = AuroraWorkspaceTitleStore(defaults: defaults, storageKey: storageKey)
        let tab = Tab(
            title: "Session",
            workingDirectory: URL(fileURLWithPath: "/repo/app")
        )
        let resolver = StubResolver(roots: [:])
        let beforeRename = AuroraWorkspacePlanner.descriptor(for: tab, resolver: resolver)

        store.setTitle("  Product Workspace  ", for: beforeRename.identity)
        let afterRename = AuroraWorkspacePlanner.descriptor(for: tab, resolver: resolver)

        #expect(afterRename.identity == beforeRename.identity)
        #expect(store.title(for: beforeRename.identity) == "Product Workspace")

        store.setTitle("   ", for: beforeRename.identity)
        #expect(store.title(for: beforeRename.identity) == nil)
        #expect(store.snapshot[beforeRename.identity] == "")

        store.mergeMissing([beforeRename.identity: "Legacy Name"])
        let reloaded = AuroraWorkspaceTitleStore(defaults: defaults, storageKey: storageKey)
        #expect(reloaded.title(for: beforeRename.identity) == nil)
        #expect(afterRename.automaticName == "app")
    }

    @Test("legacy per-tab workspace title migrates once per identity")
    func legacyTitlesMigrateWithoutReplication() throws {
        let suiteName = HermeticUserDefaults.suiteName()
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = Tab(
            title: "First",
            workingDirectory: URL(fileURLWithPath: "/repo/app"),
            workspaceCustomTitle: "Application"
        )
        let second = Tab(
            title: "Second",
            workingDirectory: URL(fileURLWithPath: "/repo/app"),
            workspaceCustomTitle: "Conflicting Legacy Name"
        )
        let resolver = StubResolver(roots: [:])
        let migrated = AuroraWorkspacePlanner.legacyTitlesByIdentity(
            from: [first, second],
            resolver: resolver
        )
        let store = AuroraWorkspaceTitleStore(defaults: defaults, storageKey: "titles")

        store.mergeMissing(migrated)

        #expect(migrated == ["/repo/app": "Application"])
        #expect(store.title(for: "/repo/app") == "Application")
    }
}
