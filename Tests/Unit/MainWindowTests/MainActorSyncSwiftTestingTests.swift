// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorSyncSwiftTestingTests.swift - Main actor sync helper coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Main actor sync helpers")
struct MainActorSyncSwiftTestingTests {

    @Test("non-blocking main actor sync returns a value when the main actor is available")
    func nonBlockingSyncReturnsWhenMainActorAvailable() async {
        let value = await Task.detached {
            syncOnMainActorIfAvailable(timeout: .seconds(5)) {
                42
            }
        }.value

        #expect(value == 42)
    }

    @MainActor
    @Test("non-blocking main actor sync executes inline when already on the main actor")
    func nonBlockingSyncRunsInlineOnMainActor() {
        let value = syncOnMainActorIfAvailable(timeout: .milliseconds(1)) {
            "ready"
        }

        #expect(value == "ready")
    }

    @MainActor
    @Test("non-blocking main actor sync returns nil without executing stale work after timeout")
    func nonBlockingSyncSkipsLateWorkAfterTimeout() {
        let executed = LockedBox(false)
        let result = LockedBox<(didFinish: Bool, value: Int?)>((false, nil))
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            let value = syncOnMainActorIfAvailable(timeout: .milliseconds(10)) {
                executed.withValue { $0 = true }
                return 99
            }
            result.withValue { $0 = (true, value) }
            finished.signal()
        }

        _ = DispatchSemaphore(value: 0).wait(timeout: .now() + .milliseconds(50))
        #expect(finished.wait(timeout: .now() + .seconds(1)) == .success)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        #expect(result.withValue { $0.didFinish })
        #expect(result.withValue { $0.value } == nil)
        #expect(executed.withValue { $0 } == false)
    }
}
