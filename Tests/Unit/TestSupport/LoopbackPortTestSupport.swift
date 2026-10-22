// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation

enum LoopbackTestPortAllocator {
    private static let candidatePorts = 20_000..<49_152

    private final class PortHistory: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed: Set<Int> = []

        func claim(_ port: Int) -> Bool {
            lock.withLock { claimed.insert(port).inserted }
        }
    }

    private static let history = PortHistory()

    static func freshPort() throws -> Int {
        let start = Int.random(in: candidatePorts)
        for offset in 0..<128 {
            let candidate = candidatePorts.lowerBound
                + ((start - candidatePorts.lowerBound + offset) % candidatePorts.count)
            guard history.claim(candidate) else { continue }
            do {
                try verifyDualStackAvailability(port: candidate)
                return candidate
            } catch let error as POSIXError where error.code == .EADDRINUSE {
                continue
            }
        }
        throw POSIXError(.EADDRNOTAVAIL)
    }

    private static func verifyDualStackAvailability(port: Int) throws {
        let ipv4Descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard ipv4Descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(ipv4Descriptor) }

        var ipv4Address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: UInt16(port).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        let ipv4Bound = withUnsafePointer(to: &ipv4Address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    ipv4Descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard ipv4Bound == 0 else { throw currentPOSIXError() }

        let ipv6Descriptor = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        guard ipv6Descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(ipv6Descriptor) }
        var ipv6Only: Int32 = 1
        guard Darwin.setsockopt(
            ipv6Descriptor,
            IPPROTO_IPV6,
            IPV6_V6ONLY,
            &ipv6Only,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw currentPOSIXError()
        }
        var ipv6Address = sockaddr_in6(
            sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
            sin6_family: sa_family_t(AF_INET6),
            sin6_port: UInt16(port).bigEndian,
            sin6_flowinfo: 0,
            sin6_addr: in6addr_loopback,
            sin6_scope_id: 0
        )
        let ipv6Bound = withUnsafePointer(to: &ipv6Address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    ipv6Descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in6>.size)
                )
            }
        }
        guard ipv6Bound == 0 else { throw currentPOSIXError() }
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
