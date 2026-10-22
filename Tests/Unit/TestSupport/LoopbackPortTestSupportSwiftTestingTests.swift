// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing

@Suite("Loopback test port allocation")
struct LoopbackPortTestSupportSwiftTestingTests {
    @Test("allocated ports stay outside the system ephemeral range")
    func allocatedPortsAvoidSystemEphemeralRange() throws {
        let first = try sysctlInteger("net.inet.ip.portrange.first")
        let last = try sysctlInteger("net.inet.ip.portrange.last")
        let port = try LoopbackTestPortAllocator.freshPort()

        #expect(port < first || port > last)
    }

    private func sysctlInteger(_ name: String) throws -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return Int(value)
    }
}
