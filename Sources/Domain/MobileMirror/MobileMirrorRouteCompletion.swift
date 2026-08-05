// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorRouteCompletion.swift - Single-resolution gateway route lifetime.

import Foundation

enum MobileMirrorRouteOutcome: Sendable {
    case result(MobileMirrorHTTPRouteResult)
    case timedOut
}

final class MobileMirrorRouteCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let completion: @Sendable (MobileMirrorRouteOutcome) -> Void
    private var routeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isResolved = false

    init(completion: @escaping @Sendable (MobileMirrorRouteOutcome) -> Void) {
        self.completion = completion
    }

    func install(routeTask: Task<Void, Never>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            routeTask.cancel()
            return
        }
        self.routeTask = routeTask
        lock.unlock()
    }

    func install(timeoutTask: Task<Void, Never>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    func cancelRouteAndWait() async {
        let state = lock.withLock {
            (isResolved: isResolved, task: routeTask)
        }
        guard !state.isResolved else { return }

        state.task?.cancel()
        await state.task?.value
        resolve(.timedOut)
    }

    func resolve(_ outcome: MobileMirrorRouteOutcome) {
        let tasks: (Task<Void, Never>?, Task<Void, Never>?)
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        tasks = (routeTask, timeoutTask)
        routeTask = nil
        timeoutTask = nil
        lock.unlock()

        tasks.0?.cancel()
        tasks.1?.cancel()
        completion(outcome)
    }
}
