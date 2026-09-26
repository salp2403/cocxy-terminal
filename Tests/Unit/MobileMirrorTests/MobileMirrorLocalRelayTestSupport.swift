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

final class TemporaryMobileMirrorKeychain {
    private static let lock = NSLock()
    private static let filePrefix = "cocxy-mobile-tests-"
    private static let currentFileVersion = "v2"

    let reference: SecKeychain
    let fileURL: URL

    init() throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        Self.removeStaleFiles()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(Self.filePrefix)\(Self.currentFileVersion).\(getpid()).\(UUID().uuidString).keychain-db"
            )
        let password = UUID().uuidString
        var created: SecKeychain?
        let status = password.withCString { pointer in
            SecKeychainCreate(
                temporaryURL.path,
                UInt32(password.utf8.count),
                pointer,
                false,
                nil,
                &created
            )
        }
        guard status == errSecSuccess, let created else {
            throw CocoaError(.fileWriteUnknown)
        }
        let searchListStatus = Self.removeFromDefaultSearchList(created)
        guard searchListStatus == errSecSuccess else {
            SecKeychainDelete(created)
            try? FileManager.default.removeItem(at: temporaryURL)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(searchListStatus))
        }
        fileURL = temporaryURL
        reference = created
    }

    deinit {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        _ = Self.removeFromDefaultSearchList(reference)
        SecKeychainDelete(reference)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func defaultSearchListPaths() -> Set<String> {
        var searchList: CFArray?
        guard SecKeychainCopySearchList(&searchList) == errSecSuccess,
              let keychains = searchList as? [SecKeychain] else {
            return []
        }
        return Set(keychains.compactMap(keychainPath))
    }

    private static func removeFromDefaultSearchList(_ keychain: SecKeychain) -> OSStatus {
        guard let keychainPath = keychainPath(keychain) else { return errSecParam }
        var searchList: CFArray?
        let copyStatus = SecKeychainCopySearchList(&searchList)
        guard copyStatus == errSecSuccess,
              let keychains = searchList as? [SecKeychain] else {
            return copyStatus == errSecSuccess ? errSecDecode : copyStatus
        }
        let filtered = keychains.filter { candidate in
            Self.keychainPath(candidate) != keychainPath
        }
        guard filtered.count != keychains.count else { return errSecSuccess }
        return SecKeychainSetSearchList(filtered as CFArray)
    }

    private static func removeStaleFiles() {
        let directory = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(filePrefix) {
            guard shouldRemove(entry) else { continue }
            removePathFromDefaultSearchList(entry.path)
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func shouldRemove(_ fileURL: URL) -> Bool {
        let name = fileURL.lastPathComponent
        let currentPrefix = "\(filePrefix)\(currentFileVersion)."
        if name.hasPrefix(currentPrefix) {
            let components = name.dropFirst(currentPrefix.count).split(separator: ".")
            guard let processIdentifier = components.first.flatMap({ pid_t($0) }) else {
                return true
            }
            return !processIsAlive(processIdentifier)
        }
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let modificationDate = values?.contentModificationDate ?? .distantPast
        return modificationDate < Date().addingTimeInterval(-3_600)
    }

    private static func processIsAlive(_ processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0 else { return false }
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func removePathFromDefaultSearchList(_ path: String) {
        let canonicalPath = ProjectPathCanonicalizer.canonicalURL(
            URL(fileURLWithPath: path)
        ).path
        var searchList: CFArray?
        guard SecKeychainCopySearchList(&searchList) == errSecSuccess,
              let keychains = searchList as? [SecKeychain] else {
            return
        }
        let filtered = keychains.filter { keychainPath($0) != canonicalPath }
        if filtered.count != keychains.count {
            SecKeychainSetSearchList(filtered as CFArray)
        }
    }

    private static func keychainPath(_ keychain: SecKeychain) -> String? {
        var length = UInt32(PATH_MAX)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let status = buffer.withUnsafeMutableBufferPointer { storage in
            SecKeychainGetPath(keychain, &length, storage.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }
        return ProjectPathCanonicalizer.canonicalURL(
            URL(fileURLWithPath: String(cString: buffer))
        ).path
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

/// Loopback stand-in for the gateway: answers one relayed request with a
/// fixed body, then half-closes the socket the way the gateway does on stop.
final class LoopbackBulkResponder: @unchecked Sendable {
    let port: UInt16

    private let listener: Int32
    private let payload: Data
    private let written = DispatchSemaphore(value: 0)

    init(payload: Data) throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, MobileMirrorGateway.loopbackAddress, &address.sin_addr)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ready = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, length) == 0
                    && Darwin.listen(descriptor, 1) == 0
                    && Darwin.getsockname(descriptor, $0, &length) == 0
            }
        }
        guard ready, address.sin_port != 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        listener = descriptor
        port = UInt16(bigEndian: address.sin_port)
        self.payload = payload
        Thread.detachNewThread { [self] in serveOnce() }
    }

    deinit {
        Darwin.close(listener)
    }

    /// Returns once every byte and the FIN are queued on the loopback socket.
    func waitUntilWritten(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [written] in
                continuation.resume(returning: written.wait(timeout: .now() + timeout) == .success)
            }
        }
    }

    private func serveOnce() {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while received.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            received.append(buffer, count: count)
        }
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
            + "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        if MobileMirrorGateway.sendAll(Data(head.utf8) + payload, to: client) {
            Darwin.shutdown(client, SHUT_RDWR)
            written.signal()
        }
        Thread.sleep(forTimeInterval: 3)
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

func testCertificateFingerprint(_ certificate: SecCertificate) -> String {
    testCertificateFingerprint(SecCertificateCopyData(certificate) as Data)
}
