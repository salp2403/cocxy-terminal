// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

struct WebTerminalConfiguration: Equatable, Sendable {
    let bindAddress: String
    let port: UInt16
    let authToken: String
    let maxConnections: UInt16
    let maxFrameRate: UInt32
    let allowsInput: Bool
    let stopAfterFirstConnection: Bool
    let firstConnectionHandler: (@Sendable () -> Void)?

    init(
        bindAddress: String,
        port: UInt16,
        authToken: String,
        maxConnections: UInt16,
        maxFrameRate: UInt32,
        allowsInput: Bool = true,
        stopAfterFirstConnection: Bool = false,
        firstConnectionHandler: (@Sendable () -> Void)? = nil
    ) {
        self.bindAddress = bindAddress
        self.port = port
        self.authToken = authToken
        self.maxConnections = maxConnections
        self.maxFrameRate = maxFrameRate
        self.allowsInput = allowsInput
        self.stopAfterFirstConnection = stopAfterFirstConnection
        self.firstConnectionHandler = firstConnectionHandler
    }

    static let defaultBindAddress = "127.0.0.1"
    static let defaultPort: UInt16 = 7770
    static let defaultMaxConnections: UInt16 = 4
    static let defaultMaxFrameRate: UInt32 = 60
    static let maximumAuthenticationTokenByteCount = 127

    static func normalizedLoopbackBindAddress(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "127.0.0.1", "::1":
            return trimmed
        default:
            return nil
        }
    }

    static func isValidAuthenticationToken(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty,
              bytes.count <= maximumAuthenticationTokenByteCount else {
            return false
        }
        return bytes.allSatisfy { (0x21...0x7E).contains($0) }
    }

    static func == (lhs: WebTerminalConfiguration, rhs: WebTerminalConfiguration) -> Bool {
        lhs.bindAddress == rhs.bindAddress
            && lhs.port == rhs.port
            && lhs.authToken == rhs.authToken
            && lhs.maxConnections == rhs.maxConnections
            && lhs.maxFrameRate == rhs.maxFrameRate
            && lhs.allowsInput == rhs.allowsInput
            && lhs.stopAfterFirstConnection == rhs.stopAfterFirstConnection
    }
}

struct WebTerminalStatus: Equatable, Sendable {
    let running: Bool
    let bindAddress: String
    let port: UInt16
    let connectionCount: UInt16
    let authRequired: Bool
    let maxFrameRate: UInt32
    let allowsInput: Bool
    let oneShot: Bool
    let lastEventType: String?
    let lastEventConnectionID: UInt16?
}
