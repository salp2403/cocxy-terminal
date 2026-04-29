// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonLineWriter.swift - Thread-safe JSONL output for cocxyd.

import Foundation
import CocxyShared

final class PTYDaemonLineWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()

    init(handle: FileHandle = .standardOutput) {
        self.handle = handle
    }

    func write<T: Encodable>(_ value: T) {
        guard let data = try? PTYDaemonLineCodec.encode(value) else { return }
        lock.lock()
        defer { lock.unlock() }
        handle.write(data)
    }
}
