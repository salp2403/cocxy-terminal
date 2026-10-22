// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentWorkspaceFileMonitor.swift - Native, bounded workspace file events.

import CoreServices
import Foundation
import CocxyShared

enum AgentWorkspaceFileOperation: String, Sendable {
    case add
    case change
    case unlink
}

struct AgentWorkspaceFileChange: Equatable, Sendable {
    let sessionId: String
    let rootPath: String
    let filePath: String
    let operation: AgentWorkspaceFileOperation
    let timestamp: Date
}

protocol AgentWorkspaceFileMonitoring: AnyObject {
    func start(sessionId: String, rootPath: String)
    func stop(sessionId: String)
    func stopAll()
    func updateDebugLogging(enabled: Bool)
}

struct AgentWorkspaceFileMonitorStateSnapshot: Equatable, Sendable {
    let activeRootCount: Int
    let activeSessionCount: Int
}

/// Path and event policy kept separate from FSEvents so its security and
/// filtering decisions can be tested without starting a filesystem stream.
enum AgentWorkspaceFileMonitorPolicy {
    private static let ignoredDirectoryNames: Set<String> = [
        ".build",
        ".cache",
        ".git",
        ".gradle",
        ".hg",
        ".mypy_cache",
        ".next",
        ".nuxt",
        ".pnpm-store",
        ".pytest_cache",
        ".ruff_cache",
        ".svn",
        ".swiftpm",
        ".tox",
        ".turbo",
        ".venv",
        ".yarn",
        "__pycache__",
        "build",
        "carthage",
        "coverage",
        "deriveddata",
        "dist",
        "node_modules",
        "out",
        "pods",
        "target",
        "vendor",
        "venv",
    ]

    static func validatedRoot(
        _ rawPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              (trimmed as NSString).isAbsolutePath else {
            return nil
        }

        let normalized = HookPathNormalizer.normalize(trimmed)
        let components = URL(fileURLWithPath: normalized, isDirectory: true).pathComponents
        let home = HookPathNormalizer.normalize(fileManager.homeDirectoryForCurrentUser)
        let temporaryRoot = HookPathNormalizer.normalize(fileManager.temporaryDirectory)
        guard components.count >= 3,
              normalized != home,
              normalized != temporaryRoot else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return normalized
    }

    static func normalizedTrackedPath(_ rawPath: String, rootPath: String) -> String? {
        let lexicalPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let lexicalRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        guard lexicalPath != lexicalRoot,
              lexicalPath.hasPrefix(lexicalRoot + "/") else {
            return nil
        }

        let relativePath = String(lexicalPath.dropFirst(lexicalRoot.count + 1))
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              !components.contains(where: { ignoredDirectoryNames.contains($0.lowercased()) }),
              let fileName = components.last,
              !isTransientFileName(fileName) else {
            return nil
        }

        // Resolve symlinks only after cheap exclusions, then prove that the
        // canonical target still belongs to the authorized root.
        let path = HookPathNormalizer.normalize(lexicalPath)
        let root = HookPathNormalizer.normalize(lexicalRoot)
        guard path.hasPrefix(root + "/") else { return nil }
        return path
    }

    static func operation(
        for flags: FSEventStreamEventFlags,
        pathExists: Bool
    ) -> AgentWorkspaceFileOperation? {
        if flags.contains(kFSEventStreamEventFlagItemRemoved) {
            return .unlink
        }
        if flags.contains(kFSEventStreamEventFlagItemRenamed) {
            return pathExists ? .add : .unlink
        }
        if flags.contains(kFSEventStreamEventFlagItemCreated)
            || flags.contains(kFSEventStreamEventFlagItemCloned) {
            return .add
        }
        if flags.contains(kFSEventStreamEventFlagItemModified)
            || flags.contains(kFSEventStreamEventFlagItemInodeMetaMod)
            || flags.contains(kFSEventStreamEventFlagItemFinderInfoMod)
            || flags.contains(kFSEventStreamEventFlagItemChangeOwner)
            || flags.contains(kFSEventStreamEventFlagItemXattrMod) {
            return .change
        }
        return nil
    }

    static func isDirectoryEvent(_ flags: FSEventStreamEventFlags) -> Bool {
        flags.contains(kFSEventStreamEventFlagItemIsDir)
    }

    static func requiresStreamRestart(_ flags: FSEventStreamEventFlags) -> Bool {
        flags.contains(kFSEventStreamEventFlagMustScanSubDirs)
            || flags.contains(kFSEventStreamEventFlagUserDropped)
            || flags.contains(kFSEventStreamEventFlagKernelDropped)
            || flags.contains(kFSEventStreamEventFlagEventIdsWrapped)
    }

    static func rootWasInvalidated(_ flags: FSEventStreamEventFlags) -> Bool {
        flags.contains(kFSEventStreamEventFlagRootChanged)
            || flags.contains(kFSEventStreamEventFlagUnmount)
    }

    private static func isTransientFileName(_ fileName: String) -> Bool {
        fileName == ".DS_Store"
            || fileName == ".localized"
            || fileName.hasPrefix(".#")
            || fileName.hasPrefix(".~")
            || fileName.hasSuffix("~")
            || fileName.hasSuffix(".swp")
            || fileName.hasSuffix(".swo")
            || fileName.hasSuffix(".swx")
    }
}

private extension FSEventStreamEventFlags {
    func contains(_ flag: Int) -> Bool {
        self & FSEventStreamEventFlags(flag) != 0
    }
}

private final class AgentWorkspaceFileStreamContext {
    weak var monitor: AgentWorkspaceFileMonitorImpl?
    let rootPath: String

    init(monitor: AgentWorkspaceFileMonitorImpl, rootPath: String) {
        self.monitor = monitor
        self.rootPath = rootPath
    }
}

private struct AgentWorkspaceFileDeduplicationKey: Hashable {
    let path: String
    let operation: AgentWorkspaceFileOperation
}

private final class AgentWorkspaceRootWatch {
    let rootPath: String
    let stream: FSEventStreamRef
    let retainedContext: UnsafeMutableRawPointer
    var sessionIds: Set<String>
    var recentEvents: [AgentWorkspaceFileDeduplicationKey: Date] = [:]
    var restartScheduled = false

    init(
        rootPath: String,
        stream: FSEventStreamRef,
        retainedContext: UnsafeMutableRawPointer,
        sessionIds: Set<String>
    ) {
        self.rootPath = rootPath
        self.stream = stream
        self.retainedContext = retainedContext
        self.sessionIds = sessionIds
    }
}

private let agentWorkspaceFileStreamCallback: FSEventStreamCallback = {
    _, callbackInfo, eventCount, eventPaths, eventFlags, _ in
    guard let callbackInfo else { return }
    let context = Unmanaged<AgentWorkspaceFileStreamContext>
        .fromOpaque(callbackInfo)
        .takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self)
    guard let stringPaths = paths as? [String] else { return }
    context.monitor?.process(
        rootPath: context.rootPath,
        paths: stringPaths,
        flags: eventFlags,
        count: eventCount
    )
}

/// Observes authorized agent workspaces through FSEvents without recursively
/// enumerating their contents. A root stream is shared by all sessions bound
/// to the same workspace and is released when its final session unbinds.
final class AgentWorkspaceFileMonitorImpl: AgentWorkspaceFileMonitoring, @unchecked Sendable {
    typealias ChangeHandler = @Sendable (AgentWorkspaceFileChange) -> Void
    typealias RootValidator = @Sendable (String) -> String?

    private let eventHandler: ChangeHandler
    private let rootValidator: RootValidator
    private let latency: CFTimeInterval
    private let deduplicationInterval: TimeInterval
    private let queue = DispatchQueue(label: "dev.cocxy.workspace-file-monitor", qos: .utility)
    private var rootWatches: [String: AgentWorkspaceRootWatch] = [:]
    private var rootBySessionId: [String: String] = [:]
    private var debugLoggingEnabled: Bool

    init(
        debugLoggingEnabled: Bool = false,
        latency: CFTimeInterval = 0.1,
        deduplicationInterval: TimeInterval = 0.15,
        rootValidator: @escaping RootValidator = {
            AgentWorkspaceFileMonitorPolicy.validatedRoot($0)
        },
        eventHandler: @escaping ChangeHandler
    ) {
        self.debugLoggingEnabled = debugLoggingEnabled
        self.latency = max(0.02, latency)
        self.deduplicationInterval = max(0, deduplicationInterval)
        self.rootValidator = rootValidator
        self.eventHandler = eventHandler
    }

    deinit {
        // Public operations retain the monitor until their queued work has
        // completed. Any remaining watches here therefore have no concurrent
        // owner and can be released without synchronously hopping to the
        // FSEvents queue from the thread that drops the final reference.
        let watches = Array(rootWatches.values)
        for watch in watches {
            destroyWatch(watch)
        }
    }

    func start(sessionId: String, rootPath: String) {
        queue.async { [self] in
            startLocked(sessionId: sessionId, rootPath: rootPath)
        }
    }

    func stop(sessionId: String) {
        queue.async { [self] in
            detachSessionLocked(sessionId)
        }
    }

    func stopAll() {
        queue.async { [self] in
            stopAllLocked()
        }
    }

    func updateDebugLogging(enabled: Bool) {
        queue.async { [self] in
            debugLoggingEnabled = enabled
        }
    }

    func stateSnapshot() async -> AgentWorkspaceFileMonitorStateSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: AgentWorkspaceFileMonitorStateSnapshot(
                    activeRootCount: rootWatches.count,
                    activeSessionCount: rootBySessionId.count
                ))
            }
        }
    }

    fileprivate func process(
        rootPath: String,
        paths: [String],
        flags: UnsafePointer<FSEventStreamEventFlags>,
        count: Int
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let watch = rootWatches[rootPath] else { return }
        let eventCount = min(count, paths.count)

        for index in 0..<eventCount {
            let eventFlags = flags[index]
            if AgentWorkspaceFileMonitorPolicy.rootWasInvalidated(eventFlags) {
                scheduleRestartLocked(watch, reason: "root-invalidated")
                continue
            }
            if AgentWorkspaceFileMonitorPolicy.requiresStreamRestart(eventFlags) {
                scheduleRestartLocked(watch, reason: "events-dropped")
                continue
            }
            guard !AgentWorkspaceFileMonitorPolicy.isDirectoryEvent(eventFlags),
                  let path = AgentWorkspaceFileMonitorPolicy.normalizedTrackedPath(
                      paths[index],
                      rootPath: rootPath
                  ),
                  let operation = AgentWorkspaceFileMonitorPolicy.operation(
                      for: eventFlags,
                      pathExists: FileManager.default.fileExists(atPath: path)
                  ) else {
                continue
            }

            let timestamp = Date()
            let deduplicationKey = AgentWorkspaceFileDeduplicationKey(
                path: path,
                operation: operation
            )
            if let previous = watch.recentEvents[deduplicationKey],
               timestamp.timeIntervalSince(previous) < deduplicationInterval {
                continue
            }
            if watch.recentEvents.count >= 2_048 {
                watch.recentEvents = watch.recentEvents.filter {
                    timestamp.timeIntervalSince($0.value) < deduplicationInterval
                }
                if watch.recentEvents.count >= 2_048 {
                    watch.recentEvents.removeAll(keepingCapacity: true)
                }
            }
            watch.recentEvents[deduplicationKey] = timestamp

            for sessionId in watch.sessionIds.sorted() {
                eventHandler(AgentWorkspaceFileChange(
                    sessionId: sessionId,
                    rootPath: rootPath,
                    filePath: path,
                    operation: operation,
                    timestamp: timestamp
                ))
            }
        }
    }

    private func makeWatchLocked(
        rootPath: String,
        sessionIds: Set<String>
    ) -> AgentWorkspaceRootWatch? {
        dispatchPrecondition(condition: .onQueue(queue))
        let callbackContext = AgentWorkspaceFileStreamContext(
            monitor: self,
            rootPath: rootPath
        )
        let retainedContext = Unmanaged.passRetained(callbackContext).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: retainedContext,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            agentWorkspaceFileStreamCallback,
            &streamContext,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            createFlags
        ) else {
            Unmanaged<AgentWorkspaceFileStreamContext>.fromOpaque(retainedContext).release()
            return nil
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Unmanaged<AgentWorkspaceFileStreamContext>.fromOpaque(retainedContext).release()
            return nil
        }

        return AgentWorkspaceRootWatch(
            rootPath: rootPath,
            stream: stream,
            retainedContext: retainedContext,
            sessionIds: sessionIds
        )
    }

    private func startLocked(sessionId rawSessionId: String, rootPath rawRootPath: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        let sessionId = rawSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty,
              let rootPath = rootValidator(rawRootPath) else {
            writeDebugLog("stage=workspace-monitor-rejected reason=invalid-session-or-root")
            return
        }

        guard rootBySessionId[sessionId] != rootPath else { return }
        detachSessionLocked(sessionId)

        if let existingWatch = rootWatches[rootPath] {
            existingWatch.sessionIds.insert(sessionId)
            rootBySessionId[sessionId] = rootPath
            return
        }

        guard let watch = makeWatchLocked(rootPath: rootPath, sessionIds: [sessionId]) else {
            writeDebugLog("stage=workspace-monitor-start-failed root=\(rootPath)")
            return
        }
        rootWatches[rootPath] = watch
        rootBySessionId[sessionId] = rootPath
        writeDebugLog("stage=workspace-monitor-started root=\(rootPath)")
    }

    private func detachSessionLocked(_ sessionId: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let rootPath = rootBySessionId.removeValue(forKey: sessionId),
              let watch = rootWatches[rootPath] else {
            return
        }
        watch.sessionIds.remove(sessionId)
        guard watch.sessionIds.isEmpty else { return }
        rootWatches.removeValue(forKey: rootPath)
        destroyWatch(watch)
        writeDebugLog("stage=workspace-monitor-stopped root=\(rootPath)")
    }

    private func stopAllLocked() {
        dispatchPrecondition(condition: .onQueue(queue))
        let watches = Array(rootWatches.values)
        rootWatches.removeAll()
        rootBySessionId.removeAll()
        for watch in watches {
            destroyWatch(watch)
        }
    }

    private func destroyWatch(_ watch: AgentWorkspaceRootWatch) {
        FSEventStreamStop(watch.stream)
        FSEventStreamInvalidate(watch.stream)
        FSEventStreamRelease(watch.stream)
        Unmanaged<AgentWorkspaceFileStreamContext>
            .fromOpaque(watch.retainedContext)
            .release()
    }

    private func scheduleRestartLocked(
        _ watch: AgentWorkspaceRootWatch,
        reason: String
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !watch.restartScheduled else { return }
        watch.restartScheduled = true
        writeDebugLog("stage=workspace-monitor-restart reason=\(reason) root=\(watch.rootPath)")
        let rootPath = watch.rootPath
        queue.async { [weak self] in
            self?.restartLocked(rootPath: rootPath)
        }
    }

    private func restartLocked(rootPath: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let oldWatch = rootWatches.removeValue(forKey: rootPath) else { return }
        let sessionIds = oldWatch.sessionIds
        destroyWatch(oldWatch)

        guard rootValidator(rootPath) != nil,
              let replacement = makeWatchLocked(rootPath: rootPath, sessionIds: sessionIds) else {
            for sessionId in sessionIds {
                rootBySessionId.removeValue(forKey: sessionId)
            }
            writeDebugLog("stage=workspace-monitor-restart-failed root=\(rootPath)")
            return
        }
        rootWatches[rootPath] = replacement
    }

    private func writeDebugLog(_ message: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard debugLoggingEnabled else { return }
        var environment = ProcessInfo.processInfo.environment
        environment[HookIntegrationDebugLog.enabledEnvironmentKey] = "1"
        HookIntegrationDebugLog.append(message, environment: environment)
    }
}
