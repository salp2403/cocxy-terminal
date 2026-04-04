// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorSync.swift - Shared helpers for synchronous main-actor access.

import Foundation

@inline(__always)
func syncOnMainActor<T: Sendable>(_ body: @escaping @MainActor @Sendable () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            body()
        }
    }

    return DispatchQueue.main.sync {
        MainActor.assumeIsolated {
            body()
        }
    }
}

final class WeakReference<Object: AnyObject>: @unchecked Sendable {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ operation: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation(&value)
    }
}
