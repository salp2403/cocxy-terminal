// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
@testable import CocxyTerminal

func permissionBits(at url: URL) -> Int {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

final class TaskRunSaveProbe: @unchecked Sendable {
    let firstSaveStarted = DispatchSemaphore(value: 0)
    let releaseFirstSave = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private let blocksFirstSave: Bool
    private let failsFirstSave: Bool
    private var storedSnapshots: [TaskRun] = []
    private var storedSuccessfulSnapshots: [TaskRun] = []
    private var observedMainThread = false

    init(blocksFirstSave: Bool = false, failsFirstSave: Bool = false) {
        self.blocksFirstSave = blocksFirstSave
        self.failsFirstSave = failsFirstSave
    }

    var snapshots: [TaskRun] {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshots
    }

    var savedOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedMainThread
    }

    var successfulSnapshots: [TaskRun] {
        lock.withLock { storedSuccessfulSnapshots }
    }

    func save(_ run: TaskRun) throws {
        lock.lock()
        storedSnapshots.append(run)
        observedMainThread = observedMainThread || Thread.isMainThread
        let isFirstSave = storedSnapshots.count == 1
        lock.unlock()
        if isFirstSave {
            firstSaveStarted.signal()
        }
        if blocksFirstSave && isFirstSave {
            releaseFirstSave.wait()
        }
        if failsFirstSave && isFirstSave {
            throw TaskRunStoreError.persistenceFailed("controlled stale snapshot failure")
        }
        lock.withLock {
            storedSuccessfulSnapshots.append(run)
        }
    }
}

final class TaskRunGitProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func recordCall() {
        lock.lock()
        calls += 1
        lock.unlock()
    }
}

final class TaskRunTransientSaveProbe: @unchecked Sendable {
    private let store: TaskRunStore
    private let failuresBeforeSuccess: Int
    private let lock = NSLock()
    private var attempts = 0

    init(store: TaskRunStore, failuresBeforeSuccess: Int) {
        self.store = store
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    var attemptCount: Int {
        lock.withLock { attempts }
    }

    func save(_ run: TaskRun) throws {
        let shouldFail = lock.withLock {
            attempts += 1
            return attempts <= failuresBeforeSuccess
        }
        if shouldFail {
            throw TaskRunStoreError.persistenceFailed("controlled transient failure")
        }
        try store.save(run)
    }
}

final class TaskRunPersistenceEventProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [TaskRunPersistenceEvent] = []

    var events: [TaskRunPersistenceEvent] {
        lock.withLock { storedEvents }
    }

    func record(_ event: TaskRunPersistenceEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
    }
}
