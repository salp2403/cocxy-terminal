// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project config watcher registry")
struct ProjectConfigWatcherRegistrySwiftTestingTests {
    @Test("same project config shares one watcher until the final lease closes")
    func sharedReferenceCounting() {
        let factory = WatcherFactory()
        let registry = ProjectConfigWatcherRegistry(
            maximumWatcherCount: 2,
            watcherFactory: factory.make
        )
        let projectID = ProjectID(rawValue: "/tmp/project-a")
        let path = "/tmp/project-a/.cocxy.toml"
        var firstCount = 0
        var secondCount = 0

        let first = registry.acquire(projectID: projectID, configFilePath: path) {
            firstCount += 1
        }
        let second = registry.acquire(projectID: projectID, configFilePath: path) {
            secondCount += 1
        }

        #expect(factory.created.count == 1)
        #expect(registry.activeWatcherCount == 1)
        #expect(registry.referenceCount(projectID: projectID, configFilePath: path) == 2)

        registry.release(first)
        factory.created[0].fire()
        #expect(firstCount == 0)
        #expect(secondCount == 1)
        #expect(factory.created[0].stopCount == 0)

        registry.release(second)
        #expect(registry.activeWatcherCount == 0)
        #expect(factory.created[0].stopCount == 1)
    }

    @Test("LRU caps file descriptors while shared polling keeps every project live")
    func lruCapUsesPollingFallback() {
        let factory = WatcherFactory()
        let snapshots = SnapshotSource()
        let registry = ProjectConfigWatcherRegistry(
            maximumWatcherCount: 2,
            watcherFactory: factory.make,
            snapshotProvider: snapshots.snapshot
        )
        let projectA = ProjectID(rawValue: "/tmp/project-a")
        let projectB = ProjectID(rawValue: "/tmp/project-b")
        let projectC = ProjectID(rawValue: "/tmp/project-c")
        let pathA = "/tmp/project-a/.cocxy.toml"
        let pathB = "/tmp/project-b/.cocxy.toml"
        let pathC = "/tmp/project-c/.cocxy.toml"
        var fallbackChanges = 0

        let leaseA = registry.acquire(projectID: projectA, configFilePath: pathA) {}
        let leaseB = registry.acquire(projectID: projectB, configFilePath: pathB) {
            fallbackChanges += 1
        }
        registry.touch(leaseA)
        let leaseC = registry.acquire(projectID: projectC, configFilePath: pathC) {}

        #expect(registry.activeWatcherCount == 2)
        #expect(registry.fallbackEntryCount == 1)
        #expect(registry.isUsingFileWatcher(projectID: projectA, configFilePath: pathA))
        #expect(!registry.isUsingFileWatcher(projectID: projectB, configFilePath: pathB))
        #expect(registry.isUsingFileWatcher(projectID: projectC, configFilePath: pathC))

        snapshots.advance(pathB)
        registry.pollFallbackEntriesForTesting()
        #expect(fallbackChanges == 1)

        registry.release(leaseC)
        #expect(registry.isUsingFileWatcher(projectID: projectB, configFilePath: pathB))
        #expect(registry.fallbackEntryCount == 0)

        registry.release(leaseA)
        registry.release(leaseB)
    }

    @Test("missing files remain observable without consuming a file descriptor")
    func missingFileUsesFallback() {
        let factory = WatcherFactory(canStart: false)
        let snapshots = SnapshotSource()
        let registry = ProjectConfigWatcherRegistry(
            maximumWatcherCount: 1,
            watcherFactory: factory.make,
            snapshotProvider: snapshots.snapshot
        )
        let projectID = ProjectID(rawValue: "/tmp/project")
        let path = "/tmp/project/.cocxy.toml"
        var changes = 0

        let lease = registry.acquire(projectID: projectID, configFilePath: path) {
            changes += 1
        }
        #expect(registry.activeWatcherCount == 0)
        #expect(registry.fallbackEntryCount == 1)

        snapshots.advance(path)
        registry.pollFallbackEntriesForTesting()
        #expect(changes == 1)

        registry.release(lease)
        #expect(registry.fallbackEntryCount == 0)
    }

    @Test("windows receive the same app-scoped stores")
    func controllerOwnershipIsInjected() {
        let registry = ProjectConfigWatcherRegistry()
        let stores = WindowStoreFixture()
        let first = stores.makeController(registry: registry)
        let second = stores.makeController(registry: registry)

        #expect(first.projectConfigWatcherRegistry === registry)
        #expect(second.projectConfigWatcherRegistry === registry)
        #expect(first.auroraWorkspaceTitleStore === stores.titleStore)
        #expect(second.auroraWorkspaceTitleStore === stores.titleStore)
        #expect(first.tabConfigProjectContextStore === stores.contextStore)
        #expect(second.tabConfigProjectContextStore === stores.contextStore)
        #expect(first.commandBlockStore === stores.blockStore)
        #expect(second.commandBlockStore === stores.blockStore)
        #expect(first.worktreeService === stores.worktreeService)
        #expect(second.worktreeService === stores.worktreeService)
    }

    @Test("one project file reloads every subscribed window")
    func sharedWatcherReloadsEveryWindow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-project-watch-integration")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent(".cocxy.toml")
        try "font-size = 14\n".write(to: configURL, atomically: true, encoding: .utf8)

        let factory = WatcherFactory()
        let registry = ProjectConfigWatcherRegistry(
            maximumWatcherCount: 2,
            watcherFactory: factory.make
        )
        let stores = WindowStoreFixture()
        let first = stores.makeController(registry: registry)
        let second = stores.makeController(registry: registry)
        let firstTab = first.tabManager.addTab(workingDirectory: root)
        let secondTab = second.tabManager.addTab(workingDirectory: root)
        first.tabManager.setActive(id: firstTab.id)
        second.tabManager.setActive(id: secondTab.id)
        first.synchronizeProjectConfigWatcher(for: firstTab)
        second.synchronizeProjectConfigWatcher(for: secondTab)

        #expect(factory.created.count == 1)
        try "font-size = 19\n".write(to: configURL, atomically: true, encoding: .utf8)
        factory.created[0].fire()

        #expect(first.tabManager.tab(for: firstTab.id)?.projectConfig?.fontSize == 19)
        #expect(second.tabManager.tab(for: secondTab.id)?.projectConfig?.fontSize == 19)

        first.releaseProjectConfigWatcher(for: firstTab.id)
        second.releaseProjectConfigWatcher(for: secondTab.id)
    }

    @Test("background tabs retain independent project config subscriptions")
    func backgroundTabsRemainSubscribed() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-project-watch-tabs")
            .appendingPathComponent(UUID().uuidString)
        let firstRoot = base.appendingPathComponent("first")
        let secondRoot = base.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let firstConfig = firstRoot.appendingPathComponent(".cocxy.toml")
        let secondConfig = secondRoot.appendingPathComponent(".cocxy.toml")
        try "font-size = 14\n".write(to: firstConfig, atomically: true, encoding: .utf8)
        try "font-size = 15\n".write(to: secondConfig, atomically: true, encoding: .utf8)

        let factory = WatcherFactory()
        let registry = ProjectConfigWatcherRegistry(watcherFactory: factory.make)
        let controller = WindowStoreFixture().makeController(registry: registry)
        let firstTab = controller.tabManager.addTab(workingDirectory: firstRoot)
        let secondTab = controller.tabManager.addTab(workingDirectory: secondRoot)
        controller.synchronizeProjectConfigWatcher(for: firstTab)
        controller.synchronizeProjectConfigWatcher(for: secondTab)

        #expect(controller.projectConfigWatchLeases.count == 2)
        #expect(factory.created.count == 2)
        try "font-size = 21\n".write(to: firstConfig, atomically: true, encoding: .utf8)
        let firstWatcher = try #require(factory.created.first {
            $0.watchedPath == firstConfig.path
        })
        firstWatcher.fire()
        #expect(controller.tabManager.tab(for: firstTab.id)?.projectConfig?.fontSize == 21)

        controller.releaseProjectConfigWatcher(for: firstTab.id)
        #expect(controller.projectConfigWatchLeases[secondTab.id] != nil)
        controller.releaseProjectConfigWatchers()
    }
}

@MainActor
private struct WindowStoreFixture {
    let titleStore = AuroraWorkspaceTitleStore()
    let contextStore = TabConfigProjectContextStore()
    let blockStore = TerminalBlockStore()
    let gitInfoProvider = GitInfoProviderImpl()
    let worktreeService: WorktreeService

    init() {
        worktreeService = WorktreeService(gitInfoProvider: gitInfoProvider)
    }

    func makeController(registry: ProjectConfigWatcherRegistry) -> MainWindowController {
        MainWindowController(
            bridge: MockTerminalEngine(),
            appStores: MainWindowAppStores(
                auroraWorkspaceTitleStore: titleStore,
                projectRegistry: nil,
                projectConfigWatcherRegistry: registry,
                tabConfigProjectContextStore: contextStore,
                commandBlockStore: blockStore,
                worktreeService: worktreeService
            ),
            gitInfoProvider: gitInfoProvider,
            deferContentSetup: true
        )
    }
}

private final class FakeProjectConfigWatcher: ProjectConfigWatching {
    let watchedPath: String
    private let canStart: Bool
    private var callback: (() -> Void)?
    private(set) var isWatching = false
    private(set) var stopCount = 0

    init(path: String, canStart: Bool) {
        watchedPath = path
        self.canStart = canStart
    }

    func startWatching(onChange: @escaping () -> Void) {
        callback = onChange
        isWatching = canStart
    }

    func stopWatching() {
        if isWatching {
            stopCount += 1
        }
        isWatching = false
        callback = nil
    }

    func fire() {
        callback?()
    }
}

private final class WatcherFactory {
    let canStart: Bool
    private(set) var created: [FakeProjectConfigWatcher] = []

    init(canStart: Bool = true) {
        self.canStart = canStart
    }

    func make(path: String) -> any ProjectConfigWatching {
        let watcher = FakeProjectConfigWatcher(path: path, canStart: canStart)
        created.append(watcher)
        return watcher
    }
}

private final class SnapshotSource {
    private var versions: [String: Int] = [:]

    func advance(_ path: String) {
        let key = URL(fileURLWithPath: path).standardizedFileURL.path
        versions[key, default: 0] += 1
    }

    func snapshot(path: String) -> ProjectConfigWatcherRegistry.FileSnapshot? {
        let version = versions[path, default: 0]
        return ProjectConfigWatcherRegistry.FileSnapshot(
            device: 1,
            inode: 1,
            size: Int64(version),
            modifiedSeconds: version,
            modifiedNanoseconds: 0
        )
    }
}
