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

@inline(__always)
func syncOnMainActorIfAvailable<T: Sendable>(
    timeout: DispatchTimeInterval,
    _ body: @escaping @MainActor @Sendable () -> T
) -> T? {
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            body()
        }
    }

    let result = LockedBox<T?>(nil)
    let timedOut = LockedBox(false)
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
        guard timedOut.withValue({ $0 == false }) else { return }
        let value = MainActor.assumeIsolated {
            body()
        }
        result.withValue { $0 = value }
        semaphore.signal()
    }

    guard semaphore.wait(timeout: .now() + timeout) == .success else {
        timedOut.withValue { $0 = true }
        return nil
    }
    return result.withValue { $0 }
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
