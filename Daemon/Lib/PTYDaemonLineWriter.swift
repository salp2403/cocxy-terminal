// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonLineWriter.swift - Thread-safe JSONL output for cocxyd.

import Foundation
import CocxyShared

final class PTYDaemonLineWriter: @unchecked Sendable {
    private let descriptor: Int32
    private let descriptorIsSafe: Bool
    private let lock = NSLock()

    init(handle: FileHandle = .standardOutput) {
        self.descriptor = handle.fileDescriptor
        self.descriptorIsSafe = TerminalProcessBoundary.setNoSigPipe(handle.fileDescriptor)
            && TerminalProcessBoundary.setNonBlocking(handle.fileDescriptor)
    }

    @discardableResult
    func write<T: Encodable>(_ value: T) -> Bool {
        guard descriptorIsSafe,
              let data = try? PTYDaemonLineCodec.encode(value) else { return false }
        lock.lock()
        defer { lock.unlock() }
        return TerminalProcessBoundary.writeAll(
            data,
            to: descriptor,
            maximumWaitMilliseconds: 1_000
        )
    }
}
