// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

enum BoundedDataTail {
    static func append(_ chunk: Data, to capture: inout Data, limit: Int) {
        guard limit > 0 else {
            capture.removeAll(keepingCapacity: false)
            return
        }
        if chunk.count >= limit {
            capture = Data(chunk.suffix(limit))
            return
        }
        let overflow = capture.count + chunk.count - limit
        if overflow > 0 {
            capture.removeFirst(overflow)
        }
        capture.append(chunk)
    }
}
