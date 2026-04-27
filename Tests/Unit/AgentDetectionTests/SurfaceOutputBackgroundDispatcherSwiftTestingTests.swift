// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `SurfaceOutputBackgroundDispatcher`, the per-surface
/// queue that fans PTY chunks to thread-safe detectors off the main
/// thread.
///
/// Two invariants matter for correctness:
///
///   1. **Processor order**: every processor sees every chunk in the
///      order it was registered. Partial-OSC parsers (CommandDuration,
///      InlineImage) own state machines that decode bytes one by one
///      and require the same byte stream every detector receives.
///
///   2. **Chunk order (FIFO)**: chunks dispatched in succession reach
///      the processors in the same order. Without this guarantee an
///      OSC sequence split across two chunks would parse incorrectly
///      because the second half could land before the first.
///
/// Thread testing is intentionally avoided here — verifying "did this
/// run on a non-main thread" is inherently flaky and adds no real
/// guarantee for production code; the value of the dispatcher is its
/// ordering contract, which the tests below pin precisely.
@Suite("SurfaceOutputBackgroundDispatcher")
struct SurfaceOutputBackgroundDispatcherSwiftTestingTests {

    /// Recorder shared by the test processors. Wraps `[Entry]` in a
    /// serial queue so the dispatcher's processors can append from the
    /// background queue without racing against the assertion in the
    /// test body.
    private final class CallRecorder: @unchecked Sendable {
        struct Entry: Equatable {
            let processor: Int
            let data: Data
        }

        private let lock = NSLock()
        private var entries: [Entry] = []

        func record(processor: Int, data: Data) {
            lock.lock()
            defer { lock.unlock() }
            entries.append(Entry(processor: processor, data: data))
        }

        var snapshot: [Entry] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
    }

    // MARK: - Processor order

    @Test("dispatch invokes every processor with the bytes in registration order")
    func dispatchInvokesProcessorsInRegistrationOrder() {
        let recorder = CallRecorder()
        let dispatcher = SurfaceOutputBackgroundDispatcher(
            label: "test.processor-order",
            processors: [
                { data in recorder.record(processor: 0, data: data) },
                { data in recorder.record(processor: 1, data: data) },
                { data in recorder.record(processor: 2, data: data) },
            ]
        )
        let payload = Data([0x41, 0x42, 0x43])

        dispatcher.dispatch(payload)
        dispatcher.sync()

        let entries = recorder.snapshot
        #expect(entries.map { $0.processor } == [0, 1, 2])
        #expect(entries.allSatisfy { $0.data == payload })
    }

    // MARK: - Chunk order (FIFO)

    @Test("multiple dispatched chunks reach the processors in FIFO order")
    func multipleChunksAreFIFOPerProcessor() {
        let recorder = CallRecorder()
        let dispatcher = SurfaceOutputBackgroundDispatcher(
            label: "test.fifo-order",
            processors: [
                { data in recorder.record(processor: 0, data: data) },
            ]
        )
        let chunks = [Data([0x01]), Data([0x02]), Data([0x03])]

        for chunk in chunks {
            dispatcher.dispatch(chunk)
        }
        dispatcher.sync()

        let observed = recorder.snapshot.map { $0.data }
        #expect(observed == chunks)
    }

    // MARK: - Empty processor list

    @Test("dispatch does not crash when the dispatcher has no processors")
    func dispatchWithNoProcessorsIsANoOp() {
        let dispatcher = SurfaceOutputBackgroundDispatcher(
            label: "test.empty",
            processors: []
        )

        dispatcher.dispatch(Data([0x44]))
        dispatcher.sync()
        // Reaching this point without crashing is the assertion: the
        // dispatcher must tolerate a zero-processor configuration so the
        // surface lifecycle can register the dispatcher before its
        // detectors are wired up.
    }

    // MARK: - Independence

    @Test("two dispatchers process their chunks independently of each other")
    func dispatchersDoNotInterfere() {
        let recorderA = CallRecorder()
        let recorderB = CallRecorder()
        let dispatcherA = SurfaceOutputBackgroundDispatcher(
            label: "test.independence.A",
            processors: [
                { data in recorderA.record(processor: 0, data: data) },
            ]
        )
        let dispatcherB = SurfaceOutputBackgroundDispatcher(
            label: "test.independence.B",
            processors: [
                { data in recorderB.record(processor: 0, data: data) },
            ]
        )

        dispatcherA.dispatch(Data([0xAA]))
        dispatcherB.dispatch(Data([0xBB]))
        dispatcherA.sync()
        dispatcherB.sync()

        #expect(recorderA.snapshot.map { $0.data } == [Data([0xAA])])
        #expect(recorderB.snapshot.map { $0.data } == [Data([0xBB])])
    }
}
