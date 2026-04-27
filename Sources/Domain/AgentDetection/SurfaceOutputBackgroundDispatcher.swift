// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceOutputBackgroundDispatcher.swift - Per-surface serial queue
// that fans PTY output to thread-safe detectors off the main thread.

import Foundation

/// Per-surface dispatcher that fans PTY output bytes to thread-safe
/// processors on a private serial background queue. Keeps the main
/// thread free to render the terminal under heavy agent output while
/// preserving FIFO ordering across chunks so partial-OSC parsers stay
/// correct.
///
/// ## Why a serial queue
///
/// Each registered processor (CommandDurationTracker, InlineImageOSCDetector,
/// future text-stream detectors) owns an incremental parser that needs
/// the byte stream in submission order:
///   * an OSC sequence split across two PTY chunks must reach the
///     parser as `chunk_n` followed by `chunk_n+1`;
///   * concurrent execution would let the second chunk overtake the
///     first and corrupt the parser's state machine.
///
/// A serial queue (one per surface) gives both invariants for free
/// without additional locking, while the background QoS keeps the work
/// off the main thread so scrolling and selection stay responsive even
/// under heavy agent output.
///
/// ## Thread safety
///
/// `dispatch(_:)` is safe to call from any thread. The processors run
/// on the dispatcher's own queue, never on the caller's thread. Each
/// processor must itself be safe for that contract — production code
/// passes `@unchecked Sendable` types whose internals are guarded by
/// `NSLock`.
final class SurfaceOutputBackgroundDispatcher: @unchecked Sendable {

    /// Per-call processor closure. Receives the raw PTY chunk on the
    /// dispatcher's serial background queue, in registration order.
    typealias Processor = @Sendable (Data) -> Void

    /// The private serial queue every chunk flows through. `userInteractive`
    /// QoS keeps detection latency low without competing with the render
    /// loop's main-thread work.
    private let queue: DispatchQueue

    /// Processors invoked in registration order for every dispatched
    /// chunk. Captured as a value so the queue closure can run lock-free
    /// once it owns its copy.
    private let processors: [Processor]

    /// Creates a dispatcher with the given processors. The label helps
    /// distinguish different surfaces in profiling traces and stays
    /// stable for the dispatcher's lifetime.
    ///
    /// - Parameters:
    ///   - label: Distinguishing label for the underlying serial queue.
    ///     Production callers pass a per-surface identifier so a
    ///     profile sample can attribute time to the originating split.
    ///   - processors: Closures invoked in registration order for every
    ///     chunk dispatched to the dispatcher. Each closure must be
    ///     thread-safe — it will be invoked from the dispatcher's
    ///     queue, never from the caller's thread.
    init(label: String, processors: [Processor]) {
        self.queue = DispatchQueue(label: label, qos: .userInteractive)
        self.processors = processors
    }

    /// Hands the bytes to the dispatcher and returns immediately. The
    /// processors run later on the serial queue in registration order.
    func dispatch(_ data: Data) {
        queue.async { [processors] in
            for processor in processors {
                processor(data)
            }
        }
    }

    /// Blocks the caller until every chunk dispatched so far has been
    /// processed. Reserved for tests and teardown paths — production
    /// hot paths must avoid the wait so the main thread is not blocked
    /// behind the queue.
    func sync() {
        queue.sync {}
    }
}
