// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AgentStatePerSurfaceStore")
struct AgentStatePerSurfaceStoreSwiftTestingTests {

    @Test("state(for:) returns idle for an unknown surface")
    func stateForUnknownReturnsIdle() {
        let store = AgentStatePerSurfaceStore()
        #expect(store.state(for: SurfaceID()) == .idle)
    }

    @Test("update isolates mutations between surfaces")
    func updateIsolatesBetweenSurfaces() {
        let store = AgentStatePerSurfaceStore()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        store.update(surfaceID: surfaceA) { state in
            state.agentState = .working
            state.agentToolCount = 3
        }
        store.update(surfaceID: surfaceB) { state in
            state.agentState = .waitingInput
        }

        let stateA = store.state(for: surfaceA)
        let stateB = store.state(for: surfaceB)

        #expect(stateA.agentState == .working)
        #expect(stateA.agentToolCount == 3)
        #expect(stateB.agentState == .waitingInput)
        #expect(stateB.agentToolCount == 0)
    }

    @Test("update starts from idle when surface has no prior entry")
    func updateStartsFromIdle() {
        let store = AgentStatePerSurfaceStore()
        let id = SurfaceID()

        store.update(surfaceID: id) { state in
            state.agentToolCount += 1
        }

        let result = store.state(for: id)
        #expect(result.agentState == .idle)
        #expect(result.agentToolCount == 1)
    }

    @Test("set replaces the whole state atomically")
    func setReplacesWholeState() {
        let store = AgentStatePerSurfaceStore()
        let id = SurfaceID()

        store.set(
            surfaceID: id,
            state: SurfaceAgentState(agentState: .working, agentToolCount: 5)
        )
        #expect(store.state(for: id).agentToolCount == 5)

        store.set(surfaceID: id, state: .idle)
        #expect(store.state(for: id) == .idle)
    }

    @Test("reset removes the surface entry entirely")
    func resetRemovesEntry() {
        let store = AgentStatePerSurfaceStore()
        let id = SurfaceID()
        store.update(surfaceID: id) { $0.agentState = .working }

        store.reset(surfaceID: id)

        #expect(store.state(for: id) == .idle)
        #expect(store.states[id] == nil)
    }

    @Test("prune keeps alive surfaces and drops the rest")
    func pruneKeepsOnlyAlive() {
        let store = AgentStatePerSurfaceStore()
        let keep = SurfaceID()
        let dropA = SurfaceID()
        let dropB = SurfaceID()

        for id in [keep, dropA, dropB] {
            store.update(surfaceID: id) { $0.agentState = .working }
        }

        store.prune(alive: [keep])

        #expect(store.states[keep] != nil)
        #expect(store.states[dropA] == nil)
        #expect(store.states[dropB] == nil)
    }

    @Test("clearAll empties the store")
    func clearAllEmpties() {
        let store = AgentStatePerSurfaceStore()
        store.update(surfaceID: SurfaceID()) { $0.agentState = .working }
        store.update(surfaceID: SurfaceID()) { $0.agentState = .error }

        store.clearAll()

        #expect(store.states.isEmpty)
    }

    @Test("publisher emits the current state on subscribe")
    func publisherEmitsInitialState() {
        let store = AgentStatePerSurfaceStore()
        let id = SurfaceID()
        store.update(surfaceID: id) { $0.agentState = .working }

        var received: [SurfaceAgentState] = []
        let cancellable = store.publisher(for: id).sink { state in
            received.append(state)
        }
        defer { cancellable.cancel() }

        #expect(received.count == 1)
        #expect(received.first?.agentState == .working)
    }

    @Test("publisher deduplicates consecutive identical emissions")
    func publisherDeduplicates() {
        let store = AgentStatePerSurfaceStore()
        let id = SurfaceID()

        var received: [SurfaceAgentState] = []
        let cancellable = store.publisher(for: id).sink { state in
            received.append(state)
        }
        defer { cancellable.cancel() }
        // Subscribe emits initial idle: received[0]

        store.update(surfaceID: id) { $0.agentState = .working }   // received[1]
        store.update(surfaceID: id) { $0.agentState = .working }   // filtered
        store.update(surfaceID: id) { $0.agentToolCount = 1 }      // received[2]
        store.update(surfaceID: id) { $0.agentToolCount = 1 }      // filtered

        #expect(received.count == 3)
        #expect(received[0] == .idle)
        #expect(received[1].agentState == .working)
        #expect(received[1].agentToolCount == 0)
        #expect(received[2].agentToolCount == 1)
    }

    @Test("publisher emits idle again after reset")
    func publisherEmitsIdleAfterReset() {
        let store = AgentStatePerSurfaceStore()
        let id = SurfaceID()

        var received: [SurfaceAgentState] = []
        let cancellable = store.publisher(for: id).sink { state in
            received.append(state)
        }
        defer { cancellable.cancel() }

        store.update(surfaceID: id) { $0.agentState = .working }
        store.reset(surfaceID: id)

        #expect(received.count == 3)
        #expect(received[0] == .idle)
        #expect(received[1].agentState == .working)
        #expect(received[2] == .idle)
    }

    @Test("activeSurfaceIDs returns surfaces with active state or detected agent")
    func activeSurfaceIDsFilters() {
        let store = AgentStatePerSurfaceStore()
        let untracked = SurfaceID()
        let working = SurfaceID()
        let finishedWithAgent = SurfaceID()
        let finishedWithoutAgent = SurfaceID()

        store.update(surfaceID: working) { $0.agentState = .working }

        let agent = DetectedAgent(
            name: "claude",
            launchCommand: "claude",
            startedAt: Date()
        )
        store.update(surfaceID: finishedWithAgent) { state in
            state.agentState = .finished
            state.detectedAgent = agent
        }

        store.update(surfaceID: finishedWithoutAgent) { state in
            state.agentState = .finished
        }

        let active = Set(store.activeSurfaceIDs())
        #expect(active.contains(working))
        #expect(active.contains(finishedWithAgent))
        #expect(!active.contains(finishedWithoutAgent))
        #expect(!active.contains(untracked))
    }

    @Test("activeSurfaceIDs output is sorted deterministically by UUID string")
    func activeSurfaceIDsSortedDeterministic() {
        let store = AgentStatePerSurfaceStore()
        var created: [SurfaceID] = []

        for _ in 0..<5 {
            let id = SurfaceID()
            store.update(surfaceID: id) { $0.agentState = .working }
            created.append(id)
        }

        let firstCall = store.activeSurfaceIDs()
        let secondCall = store.activeSurfaceIDs()

        #expect(firstCall == secondCall)
        #expect(firstCall.count == 5)

        let sortedExpected = created.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        #expect(firstCall == sortedExpected)
    }
}
