// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalByteWriteCompleter.swift - Exact bounded completion of partial terminal writes.

public enum TerminalByteWriteCompleter {
    public static func writeAll(
        byteCount: Int,
        writer: (_ offset: Int, _ remaining: Int) -> Int
    ) -> Int {
        guard byteCount > 0 else { return 0 }
        var offset = 0
        while offset < byteCount {
            let remaining = byteCount - offset
            let written = writer(offset, remaining)
            guard written > 0, written <= remaining else { return offset }
            offset += written
        }
        return offset
    }
}
