// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("TaskRun promotion reservations")
struct TaskRunPromotionReservationSwiftTestingTests {
    @Test("two window callers can reserve the same run only once")
    func concurrentWindowCallersAreSingleFlight() async {
        let store = TaskRunPromotionReservationStore()
        let revision = Date(timeIntervalSince1970: 100)

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        _ = try await store.acquire(runID: "shared-run", revision: revision)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var values: [Bool] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        #expect(results.filter { $0 }.count == 1)
        #expect(results.filter { !$0 }.count == 1)
    }

    @Test("only the exact revision owner can validate or release a lease")
    func ownerTokenGuardsLeaseLifetime() async throws {
        let store = TaskRunPromotionReservationStore()
        let revision = Date(timeIntervalSince1970: 200)
        let lease = try await store.acquire(runID: "owned-run", revision: revision)
        let foreignLease = TaskRunPromotionLease(
            runID: lease.runID,
            revision: lease.revision,
            ownerToken: UUID()
        )

        #expect(await store.owns(lease))
        #expect(!(await store.owns(foreignLease)))
        await store.release(foreignLease)
        #expect(await store.owns(lease))
        await store.release(lease)
        #expect(!(await store.owns(lease)))

        let replacement = try await store.acquire(runID: lease.runID, revision: revision)
        await store.release(lease)
        #expect(await store.owns(replacement))
    }
}
