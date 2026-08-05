// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Darwin
import Dispatch
import Foundation
import Security
@testable import CocxyTerminal

final class MobileMirrorPinnedTLSDelegate: NSObject, URLSessionDelegate,
    @unchecked Sendable {
    private let expectedFingerprint: String

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let fingerprint = testCertificateFingerprint(
            SecCertificateCopyData(certificate) as Data
        )
        guard fingerprint == expectedFingerprint else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

final class LoopbackConnectionProbe: @unchecked Sendable {
    let port: UInt16

    private let descriptor: Int32
    private let queue = DispatchQueue(label: "dev.cocxy.tests.mobile-relay-probe")
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var acceptedConnection = false

    init() throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var ownsDescriptor = true
        defer { if ownsDescriptor { Darwin.close(descriptor) } }
        var one: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &one,
            socklen_t(MemoryLayout.size(ofValue: one))
        )
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        inet_pton(AF_INET, MobileMirrorGateway.loopbackAddress, &address.sin_addr)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(descriptor, 1) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        var resolvedAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let resolved = withUnsafeMutablePointer(to: &resolvedAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard resolved == 0, resolvedAddress.sin_port != 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        self.descriptor = descriptor
        port = UInt16(bigEndian: resolvedAddress.sin_port)
        ownsDescriptor = false
        start()
    }

    func waitForConnection(timeout: TimeInterval) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if hasAcceptedConnection { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }

    func stop() {
        lock.lock()
        let activeSource = source
        source = nil
        lock.unlock()
        activeSource?.cancel()
    }

    deinit {
        stop()
    }

    private func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAvailableConnections() }
        source.setCancelHandler { [descriptor] in Darwin.close(descriptor) }
        lock.lock()
        self.source = source
        lock.unlock()
        source.resume()
    }

    private var hasAcceptedConnection: Bool {
        lock.lock()
        defer { lock.unlock() }
        return acceptedConnection
    }

    private func acceptAvailableConnections() {
        let client = Darwin.accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        lock.lock()
        acceptedConnection = true
        lock.unlock()
        Darwin.close(client)
    }
}

func testCertificateFingerprint(_ certificateData: Data) -> String {
    Data(SHA256.hash(data: certificateData))
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
