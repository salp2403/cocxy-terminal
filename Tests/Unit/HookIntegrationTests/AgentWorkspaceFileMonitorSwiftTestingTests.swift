// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CoreServices
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent workspace file monitor", .serialized, .timeLimit(.minutes(1)))
struct AgentWorkspaceFileMonitorSwiftTestingTests {
    @Test("root validation rejects broad or non-directory paths")
    func rootValidation() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cocxy-file-monitor-root-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        #expect(AgentWorkspaceFileMonitorPolicy.validatedRoot(root.path) == root.resolvingSymlinksInPath().path)
        #expect(AgentWorkspaceFileMonitorPolicy.validatedRoot("relative/project") == nil)
        #expect(AgentWorkspaceFileMonitorPolicy.validatedRoot("/") == nil)
        #expect(AgentWorkspaceFileMonitorPolicy.validatedRoot(
            fileManager.homeDirectoryForCurrentUser.path
        ) == nil)
        #expect(AgentWorkspaceFileMonitorPolicy.validatedRoot(
            fileManager.temporaryDirectory.path
        ) == nil)
        #expect(AgentWorkspaceFileMonitorPolicy.validatedRoot(
            root.appendingPathComponent("missing").path
        ) == nil)
    }

    @Test("path policy keeps source files inside the root and excludes generated trees")
    func pathPolicy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-file-policy-\(UUID().uuidString)", isDirectory: true)
        let sibling = root.deletingLastPathComponent()
            .appendingPathComponent("cocxy-file-policy-sibling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sibling)
        }

        let source = root.appendingPathComponent("Sources/App/Main.swift").path
        #expect(AgentWorkspaceFileMonitorPolicy.normalizedTrackedPath(
            source,
            rootPath: root.path
        ) == HookPathNormalizer.normalize(source))
        #expect(AgentWorkspaceFileMonitorPolicy.normalizedTrackedPath(
            root.appendingPathComponent("node_modules/pkg/index.js").path,
            rootPath: root.path
        ) == nil)
        #expect(AgentWorkspaceFileMonitorPolicy.normalizedTrackedPath(
            root.appendingPathComponent(".git/index").path,
            rootPath: root.path
        ) == nil)
        #expect(AgentWorkspaceFileMonitorPolicy.normalizedTrackedPath(
            root.appendingPathComponent("Sources/.Main.swift.swp").path,
            rootPath: root.path
        ) == nil)
        #expect(AgentWorkspaceFileMonitorPolicy.normalizedTrackedPath(
            sibling.appendingPathComponent("Main.swift").path,
            rootPath: root.path
        ) == nil)

        let outsideFile = sibling.appendingPathComponent("Outside.swift")
        try Data("let outside = true\n".utf8).write(to: outsideFile)
        let linkedFile = root.appendingPathComponent("Linked.swift")
        try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: outsideFile)
        #expect(AgentWorkspaceFileMonitorPolicy.normalizedTrackedPath(
            linkedFile.path,
            rootPath: root.path
        ) == nil)
    }

    @Test("event flags map deterministically to dashboard operations")
    func eventFlagMapping() {
        #expect(AgentWorkspaceFileMonitorPolicy.operation(
            for: flags(kFSEventStreamEventFlagItemRemoved),
            pathExists: false
        ) == .unlink)
        #expect(AgentWorkspaceFileMonitorPolicy.operation(
            for: flags(kFSEventStreamEventFlagItemRenamed),
            pathExists: true
        ) == .add)
        #expect(AgentWorkspaceFileMonitorPolicy.operation(
            for: flags(kFSEventStreamEventFlagItemRenamed),
            pathExists: false
        ) == .unlink)
        #expect(AgentWorkspaceFileMonitorPolicy.operation(
            for: flags(
                kFSEventStreamEventFlagItemCreated,
                kFSEventStreamEventFlagItemModified
            ),
            pathExists: true
        ) == .add)
        #expect(AgentWorkspaceFileMonitorPolicy.operation(
            for: flags(kFSEventStreamEventFlagItemXattrMod),
            pathExists: true
        ) == .change)
        #expect(AgentWorkspaceFileMonitorPolicy.operation(for: 0, pathExists: true) == nil)
    }

    @Test("sessions share one root stream and release it after the final stop")
    func rootStreamSharing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-file-sharing-\(UUID().uuidString)", isDirectory: true)
        let migratedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-file-migrated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: migratedRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: migratedRoot)
        }
        let monitor = AgentWorkspaceFileMonitorImpl { _ in }

        monitor.start(sessionId: "session-a", rootPath: root.path)
        monitor.start(sessionId: "session-b", rootPath: root.path)
        var snapshot = await monitor.stateSnapshot()
        #expect(snapshot.activeRootCount == 1)
        #expect(snapshot.activeSessionCount == 2)

        monitor.stop(sessionId: "session-a")
        snapshot = await monitor.stateSnapshot()
        #expect(snapshot.activeRootCount == 1)
        #expect(snapshot.activeSessionCount == 1)

        monitor.start(sessionId: "session-b", rootPath: migratedRoot.path)
        snapshot = await monitor.stateSnapshot()
        #expect(snapshot.activeRootCount == 1)
        #expect(snapshot.activeSessionCount == 1)

        monitor.stop(sessionId: "session-b")
        snapshot = await monitor.stateSnapshot()
        #expect(snapshot.activeRootCount == 0)
        #expect(snapshot.activeSessionCount == 0)
    }

    @Test("root validation and stream startup run away from the main thread")
    @MainActor
    func rootValidationIsAsynchronous() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-file-async-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let probe = AgentWorkspaceRootValidationProbe()
        let monitor = AgentWorkspaceFileMonitorImpl(
            rootValidator: { path in
                probe.record(isMainThread: Thread.isMainThread)
                return path
            },
            eventHandler: { _ in }
        )

        monitor.start(sessionId: "session-async", rootPath: root.path)
        let snapshot = await monitor.stateSnapshot()

        #expect(probe.wasMainThread == false)
        #expect(snapshot.activeRootCount == 1)
        #expect(snapshot.activeSessionCount == 1)

        monitor.stopAll()
        #expect(await monitor.stateSnapshot().activeRootCount == 0)
    }

    @Test("native stream emits source edits and excludes dependency files")
    func nativeStreamIntegration() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cocxy-file-events-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let dependencies = root.appendingPathComponent("node_modules/pkg", isDirectory: true)
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dependencies, withIntermediateDirectories: true)

        let collector = AgentWorkspaceFileChangeCollector()
        let monitor = AgentWorkspaceFileMonitorImpl(
            latency: 0.02,
            deduplicationInterval: 0
        ) { change in
            collector.append(change)
        }
        defer {
            monitor.stopAll()
            try? fileManager.removeItem(at: root)
        }

        monitor.start(sessionId: "session-live", rootPath: root.path)
        #expect(await monitor.stateSnapshot().activeSessionCount == 1)
        try await Task.sleep(for: .milliseconds(200))

        let sourceFile = sources.appendingPathComponent("Live.swift")
        try Data("let live = true\n".utf8).write(to: sourceFile, options: .atomic)
        let sourceChange = await waitForChange(in: collector) {
            $0.filePath == HookPathNormalizer.normalize(sourceFile)
        }
        let unwrappedSourceChange = try #require(sourceChange)
        #expect(unwrappedSourceChange.sessionId == "session-live")
        #expect(unwrappedSourceChange.rootPath == HookPathNormalizer.normalize(root))
        #expect([AgentWorkspaceFileOperation.add, .change].contains(unwrappedSourceChange.operation))

        let dependencyFile = dependencies.appendingPathComponent("ignored.js")
        try Data("module.exports = true;\n".utf8).write(to: dependencyFile, options: .atomic)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!collector.snapshot.contains {
            $0.filePath == HookPathNormalizer.normalize(dependencyFile)
        })
        monitor.stopAll()
        #expect(await monitor.stateSnapshot().activeRootCount == 0)
    }

    private func flags(_ values: Int...) -> FSEventStreamEventFlags {
        values.reduce(0) { $0 | FSEventStreamEventFlags($1) }
    }

    private func waitForChange(
        in collector: AgentWorkspaceFileChangeCollector,
        matching predicate: (AgentWorkspaceFileChange) -> Bool
    ) async -> AgentWorkspaceFileChange? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let match = collector.snapshot.first(where: predicate) {
                return match
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }
}

@Suite("AgentWorkspaceFileMonitorLargeRepoSmoke", .serialized, .timeLimit(.minutes(1)))
struct AgentWorkspaceFileMonitorLargeRepoSmokeSwiftTestingTests {
    @Test("large workspace startup and delivery stay bounded when explicitly enabled")
    func largeWorkspaceSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COCXY_ENABLE_LARGE_WORKSPACE_FILE_MONITOR_SMOKE"] == "1",
              let rootPath = environment["COCXY_WORKSPACE_FILE_MONITOR_SMOKE_ROOT"] else {
            return
        }

        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("node_modules").path))
        let collector = AgentWorkspaceFileChangeCollector()
        let monitor = AgentWorkspaceFileMonitorImpl(
            latency: 0.02,
            deduplicationInterval: 0
        ) { change in
            collector.append(change)
        }
        let probe = root.appendingPathComponent(
            ".cocxy-file-monitor-probe-\(UUID().uuidString).swift"
        )
        defer {
            monitor.stopAll()
            try? fileManager.removeItem(at: probe)
        }

        let memoryBefore = MemoryDiagnostics.current()
        let startTime = Date()
        monitor.start(sessionId: "large-smoke", rootPath: root.path)
        let monitorState = await monitor.stateSnapshot()
        let startupSeconds = Date().timeIntervalSince(startTime)
        let memoryAfterStart = MemoryDiagnostics.current()
        let residentDelta = max(
            0,
            Int64(memoryAfterStart.residentBytes) - Int64(memoryBefore.residentBytes)
        )

        try await Task.sleep(for: .milliseconds(200))
        let writeTime = Date()
        try Data("let probe = true\n".utf8).write(to: probe, options: .atomic)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let normalizedProbe = HookPathNormalizer.normalize(probe)
        while ContinuousClock.now < deadline,
              !collector.snapshot.contains(where: { $0.filePath == normalizedProbe }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let deliverySeconds = Date().timeIntervalSince(writeTime)

        print(
            "WORKSPACE_FILE_MONITOR_LARGE_SMOKE "
                + "startup_ms=\(String(format: "%.3f", startupSeconds * 1_000)) "
                + "resident_delta_bytes=\(residentDelta) "
                + "delivery_ms=\(String(format: "%.3f", deliverySeconds * 1_000))"
        )
        #expect(collector.snapshot.contains { $0.filePath == normalizedProbe })
        #expect(monitorState.activeSessionCount == 1)
        #expect(startupSeconds < 1)
        #expect(residentDelta < 64 * 1_048_576)
        #expect(deliverySeconds < 1)
        monitor.stopAll()
        #expect(await monitor.stateSnapshot().activeRootCount == 0)
    }
}

@Suite("Agent workspace file monitor routing", .serialized)
struct AgentWorkspaceFileMonitorRoutingSwiftTestingTests {
    @Test("accepted lifecycle events start monitoring while native events do not recurse")
    @MainActor
    func acceptedEventRouting() {
        let delegate = AppDelegate()
        let monitor = RecordingAgentWorkspaceFileMonitor()
        delegate.agentWorkspaceFileMonitor = monitor

        delegate.updateAgentWorkspaceFileMonitoring(forAccepted: HookEvent(
            type: .sessionStart,
            sessionId: "session-1",
            data: .sessionStart(SessionStartData(workingDirectory: "/tmp/project-a")),
            cwd: "/tmp/project-a"
        ))
        delegate.updateAgentWorkspaceFileMonitoring(forAccepted: HookEvent(
            type: .cwdChanged,
            sessionId: "session-1",
            data: .cwdChanged(CwdChangedData(
                previousCwd: "/tmp/project-a",
                newCwd: "/tmp/project-b"
            )),
            cwd: "/tmp/project-b"
        ))
        delegate.updateAgentWorkspaceFileMonitoring(forAccepted: HookEvent(
            type: .fileChanged,
            sessionId: "session-1",
            data: .fileChanged(FileChangedData(
                filePath: "/tmp/project-b/Main.swift",
                changeType: "change"
            )),
            cwd: "/tmp/project-b"
        ))
        delegate.updateAgentWorkspaceFileMonitoring(forAccepted: HookEvent(
            type: .sessionEnd,
            sessionId: "session-1",
            data: .stop(StopData()),
            cwd: "/tmp/project-b"
        ))

        #expect(monitor.startCalls == [
            .init(sessionId: "session-1", rootPath: "/tmp/project-a"),
            .init(sessionId: "session-1", rootPath: "/tmp/project-b"),
        ])
    }

    @Test("unbinding a hook session stops its native monitor")
    @MainActor
    func unbindStopsMonitor() {
        let delegate = AppDelegate()
        let monitor = RecordingAgentWorkspaceFileMonitor()
        delegate.agentWorkspaceFileMonitor = monitor

        delegate.unbindHookSession("session-closed")

        #expect(monitor.stopCalls == ["session-closed"])
    }

    @Test("an OSC-applied CWD change migrates the authorized native monitor")
    @MainActor
    func alreadyAppliedCwdChangeMigratesMonitor() async {
        let delegate = AppDelegate()
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let receiver = HookEventReceiverImpl()
        let monitor = RecordingAgentWorkspaceFileMonitor()
        let engine = AgentDetectionEngineImpl(compiledConfigs: [], debounceInterval: 0)
        delegate.additionalWindowControllers = [controller]
        delegate.hookEventReceiver = receiver
        delegate.agentWorkspaceFileMonitor = monitor

        let tabId = controller.tabManager.tabs[0].id
        let updatedPath = "/tmp/cocxy-osc-updated"
        controller.tabManager.updateTab(id: tabId) {
            $0.workingDirectory = URL(fileURLWithPath: updatedPath, isDirectory: true)
        }
        delegate.bindHookSession("session-osc", to: tabId)
        delegate.wireHookReceiverToEngine(engine)

        receiver.receive(HookEvent(
            type: .cwdChanged,
            sessionId: "session-osc",
            data: .cwdChanged(CwdChangedData(
                previousCwd: "/tmp/cocxy-osc-previous",
                newCwd: updatedPath
            )),
            cwd: updatedPath
        ))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(monitor.startCalls == [
            .init(sessionId: "session-osc", rootPath: updatedPath),
        ])
        #expect(receiver.droppedByCwdCount == 0)
    }

    @Test("a hook event rejected by exact CWD matching cannot start monitoring")
    @MainActor
    func rejectedCwdCannotStartMonitor() async {
        let delegate = AppDelegate()
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let receiver = HookEventReceiverImpl()
        let monitor = RecordingAgentWorkspaceFileMonitor()
        let engine = AgentDetectionEngineImpl(compiledConfigs: [], debounceInterval: 0)
        delegate.additionalWindowControllers = [controller]
        delegate.hookEventReceiver = receiver
        delegate.agentWorkspaceFileMonitor = monitor

        let tabId = controller.tabManager.tabs[0].id
        controller.tabManager.updateTab(id: tabId) {
            $0.workingDirectory = URL(fileURLWithPath: "/tmp/cocxy-authorized", isDirectory: true)
        }
        delegate.wireHookReceiverToEngine(engine)

        receiver.receive(HookEvent(
            type: .sessionStart,
            sessionId: "session-external",
            data: .sessionStart(SessionStartData(
                workingDirectory: "/tmp/cocxy-unrelated"
            )),
            cwd: "/tmp/cocxy-unrelated"
        ))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(monitor.startCalls.isEmpty)
        #expect(receiver.droppedByCwdCount == 1)
    }
}

private final class AgentWorkspaceFileChangeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var changes: [AgentWorkspaceFileChange] = []

    var snapshot: [AgentWorkspaceFileChange] {
        lock.withLock { changes }
    }

    func append(_ change: AgentWorkspaceFileChange) {
        lock.withLock {
            changes.append(change)
        }
    }
}

private final class AgentWorkspaceRootValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var validationRanOnMainThread: Bool?

    var wasMainThread: Bool? {
        lock.withLock { validationRanOnMainThread }
    }

    func record(isMainThread: Bool) {
        lock.withLock {
            validationRanOnMainThread = isMainThread
        }
    }
}

private final class RecordingAgentWorkspaceFileMonitor: AgentWorkspaceFileMonitoring {
    struct StartCall: Equatable {
        let sessionId: String
        let rootPath: String
    }

    private(set) var startCalls: [StartCall] = []
    private(set) var stopCalls: [String] = []

    func start(sessionId: String, rootPath: String) {
        startCalls.append(StartCall(sessionId: sessionId, rootPath: rootPath))
    }

    func stop(sessionId: String) {
        stopCalls.append(sessionId)
    }

    func stopAll() {}
    func updateDebugLogging(enabled: Bool) {}
}
