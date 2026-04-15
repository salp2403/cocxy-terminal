// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Dispatch
import Foundation

/// Main-actor helpers for tests that need deterministic coordination with
/// work scheduled onto `DispatchQueue.main` or `RunLoop.main`.
enum MainActorTestSupport {

    /// Drains the main queue by scheduling a continuation resume at its tail.
    ///
    /// Use this from `@MainActor` async tests when code under test delivers
    /// state changes through mechanisms such as Combine's `.receive(on: .main)`
    /// and the test needs to guarantee those callbacks have fired before
    /// asserting state.
    @MainActor
    static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    /// Advances the main run loop for a bounded amount of time.
    ///
    /// Useful for legacy XCTest integration tests that need to let main-thread
    /// dispatches and run-loop observers settle without introducing arbitrary
    /// sleeps that are more sensitive to CI load.
    @MainActor
    static func waitForMainDispatch(delay: TimeInterval) {
        let deadline = Date().addingTimeInterval(delay)
        while Date() < deadline {
            let sliceEnd = min(deadline, Date().addingTimeInterval(0.01))
            RunLoop.main.run(mode: .default, before: sliceEnd)
        }
    }

    /// Polls a main-actor condition while pumping the main run loop.
    ///
    /// Returns `true` as soon as `condition` becomes true, or the final value
    /// of `condition` once the timeout elapses.
    @MainActor
    @discardableResult
    static func waitForMainCondition(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.01,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            let sliceEnd = min(deadline, Date().addingTimeInterval(pollInterval))
            RunLoop.main.run(mode: .default, before: sliceEnd)
        }
        return condition()
    }
}
