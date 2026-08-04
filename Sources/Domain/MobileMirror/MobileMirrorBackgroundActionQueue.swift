// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorBackgroundActionQueue.swift - Request-independent mobile work ownership.

import Foundation

@MainActor
final class MobileMirrorBackgroundActionQueue {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    var activeCount: Int { tasks.count }

    @discardableResult
    func enqueue(
        _ operation: @escaping @MainActor () async -> Void
    ) -> UUID {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await operation()
            self?.tasks.removeValue(forKey: id)
        }
        tasks[id] = task
        return id
    }

    func cancelAll() {
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
    }
}
