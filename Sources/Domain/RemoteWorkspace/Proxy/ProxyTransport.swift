// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyTransport.swift - Authenticated proxy credentials and upstream streams.

import CryptoKit
import Foundation

// MARK: - Ephemeral Credentials

/// Per-activation credentials for Cocxy-owned local proxy listeners.
///
/// Credentials live only in memory and rotate whenever the proxy is enabled.
/// The fixed user name improves client compatibility; the 256-bit password is
/// the capability that protects access to the connected SSH session.
struct ProxyCredentials: Equatable, Sendable {
    static let username = "cocxy"

    let password: String

    static func generate() -> ProxyCredentials {
        let key = SymmetricKey(size: .bits256)
        let secret = key.withUnsafeBytes { Data($0) }
        let password = secret.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return ProxyCredentials(password: password)
    }

    var usernameData: Data { Data(Self.username.utf8) }
    var passwordData: Data { Data(password.utf8) }

    var basicAuthorizationValue: String {
        Data("\(Self.username):\(password)".utf8).base64EncodedString()
    }

    func matches(username suppliedUsername: Data, password suppliedPassword: Data) -> Bool {
        let usernameMatches = Self.constantTimeEqual(suppliedUsername, usernameData)
        let passwordMatches = Self.constantTimeEqual(suppliedPassword, passwordData)
        return usernameMatches && passwordMatches
    }

    func matchesBasicAuthorization(_ encodedCredential: String) -> Bool {
        guard let supplied = Data(base64Encoded: encodedCredential, options: []) else {
            return false
        }
        let expected = Data("\(Self.username):\(password)".utf8)
        return Self.constantTimeEqual(supplied, expected)
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        let comparisonLength = max(lhs.count, rhs.count)
        var difference = UInt64(lhs.count ^ rhs.count)
        for index in 0..<comparisonLength {
            let left = index < lhs.count ? lhs[lhs.startIndex + index] : 0
            let right = index < rhs.count ? rhs[rhs.startIndex + index] : 0
            difference |= UInt64(left ^ right)
        }
        return difference == 0
    }
}

// MARK: - Validated Target

enum ProxyTargetError: Error, Equatable, LocalizedError {
    case invalidHost
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Invalid proxy target host"
        case .invalidPort:
            return "Invalid proxy target port"
        }
    }
}

/// A validated host and port for one OpenSSH MUX `direct-tcpip` request.
struct ProxyTarget: Equatable, Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int) throws {
        guard (1...65_535).contains(port) else {
            throw ProxyTargetError.invalidPort
        }
        let normalizedHost: String
        do {
            normalizedHost = try SSHConnectionDestination(user: nil, host: host).host
        } catch {
            throw ProxyTargetError.invalidHost
        }
        self.host = normalizedHost
        self.port = port
    }
}

// MARK: - Upstream Transport

enum ProxyUpstreamTransportError: Error, Equatable, LocalizedError {
    case unavailable
    case closed
    case controlSocketRejected
    case protocolViolation
    case readinessAlreadyPending
    case readinessTimedOut
    case receiveAlreadyPending

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Secure proxy transport is unavailable"
        case .closed:
            return "Secure proxy transport is closed"
        case .controlSocketRejected:
            return "SSH control socket attestation failed"
        case .protocolViolation:
            return "SSH control socket protocol validation failed"
        case .readinessAlreadyPending:
            return "A proxy transport readiness check is already pending"
        case .readinessTimedOut:
            return "Secure proxy transport readiness timed out"
        case .receiveAlreadyPending:
            return "A proxy transport read is already pending"
        }
    }
}

/// Bidirectional byte stream backed by one authorized SSH direct-tcpip channel.
protocol ProxyUpstreamTransport: AnyObject, Sendable {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    var diagnosticOutput: String { get }

    func waitUntilReady() async throws
    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    )
    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    )
    func closeWrite()
    func cancel()
}
