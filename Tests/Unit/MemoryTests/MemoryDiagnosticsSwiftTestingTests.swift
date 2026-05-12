// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MemoryDiagnostics")
struct MemoryDiagnosticsSwiftTestingTests {

    @Test("formatBytes uses MiB below one GiB and GiB above it")
    func formatBytesUsesStableUnits() {
        #expect(MemoryDiagnostics.formatBytes(128 * 1_048_576) == "128.0 MiB")
        #expect(MemoryDiagnostics.formatBytes(3 * 1_073_741_824) == "3.00 GiB")
    }

    @Test("current snapshot reports local process memory without network or persistence")
    func currentSnapshotReportsProcessMemory() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = MemoryDiagnostics.current(capturedAt: capturedAt)

        #expect(snapshot.capturedAt == capturedAt)
        #expect(snapshot.residentBytes > 0)
        #expect(snapshot.virtualBytes > 0)
        #expect(!snapshot.formattedResident.isEmpty)
        #expect(!snapshot.formattedVirtual.isEmpty)
        #expect(!snapshot.formattedPhysicalFootprint.isEmpty)
    }
}
