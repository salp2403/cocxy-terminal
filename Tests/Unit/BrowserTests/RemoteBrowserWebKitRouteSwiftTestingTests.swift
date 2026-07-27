// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteBrowserWebKitRouteSwiftTestingTests.swift - Live WebKit-to-broker routing smoke.

import Darwin
import Foundation
import Network
import Testing
import WebKit
@testable import CocxyTerminal

private final class BrowserRouteHTTPTransport: ProxyUpstreamTransport, @unchecked Sendable {
    let processIdentifier: Int32 = 42
    private(set) var isRunning = true
    let diagnosticOutput = ""

    private let lock = NSLock()
    private var response = Data()
    private var pendingReceive: ((Result<Data?, any Error>) -> Void)?
    private var didFinishResponse = false

    func waitUntilReady() async throws {}

    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        var receive: ((Result<Data?, any Error>) -> Void)?
        lock.lock()
        if response.isEmpty, data.range(of: Data("\r\n\r\n".utf8)) != nil {
            let body = "brokered-route"
            response = Data("""
            HTTP/1.1 200 OK\r
            Content-Type: text/plain\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """.utf8)
            receive = pendingReceive
            pendingReceive = nil
        }
        let payload = response
        if receive != nil {
            response.removeAll()
            didFinishResponse = true
        }
        lock.unlock()
        completion(.success(()))
        receive?(.success(payload))
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    ) {
        _ = maximumLength
        lock.lock()
        if !response.isEmpty {
            let payload = response
            response.removeAll()
            didFinishResponse = true
            lock.unlock()
            completion(.success(payload))
            return
        }
        if didFinishResponse || !isRunning {
            lock.unlock()
            completion(.success(nil))
            return
        }
        pendingReceive = completion
        lock.unlock()
    }

    func closeWrite() {}

    func cancel() {
        var receive: ((Result<Data?, any Error>) -> Void)?
        lock.lock()
        isRunning = false
        receive = pendingReceive
        pendingReceive = nil
        lock.unlock()
        receive?(.success(nil))
    }
}

@MainActor
private final class BrowserRouteForwarder: PortForwarding {
    let leaseID = UUID()
    private(set) var openedTargets: [ProxyTarget] = []
    private var transports: [BrowserRouteHTTPTransport] = []

    func connectionLeaseID(for profileID: UUID) -> UUID? { leaseID }
    func forwardPort(_ forward: RemoteConnectionProfile.PortForward, for profileID: UUID) throws {}
    func cancelForward(_ forward: RemoteConnectionProfile.PortForward, for profileID: UUID) throws {}

    func openProxyTransport(
        to target: ProxyTarget,
        for profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> any ProxyUpstreamTransport {
        guard expectedConnectionLeaseID == leaseID else {
            throw SSHMultiplexerError.notConnected
        }
        let transport = BrowserRouteHTTPTransport()
        openedTargets.append(target)
        transports.append(transport)
        return transport
    }
}

@MainActor
private final class BrowserRouteNavigationDelegate: NSObject, WKNavigationDelegate {
    var completion: ((Result<Void, any Error>) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failure(error))
    }

    func finish(_ result: Result<Void, any Error>) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

@MainActor
private final class BrowserRouteLoopbackProbe {
    private let listeners: LoopbackTCPListenerGroup
    private(set) var acceptedConnectionCount = 0

    init(port: Int) {
        listeners = LoopbackTCPListenerGroup(port: port)
        listeners.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            acceptedConnectionCount += 1
            connection.start(queue: .main)
            let body = "direct-loopback"
            let response = Data("""
            HTTP/1.1 200 OK\r
            Content-Type: text/plain\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """.utf8)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    func start() async throws {
        try await listeners.start()
    }

    func stop() {
        listeners.stop()
    }
}

@Suite("Remote browser WebKit route", .serialized)
struct RemoteBrowserWebKitRouteSwiftTestingTests {
    @Test("WebKit uses the scoped broker and blocks direct loopback bypasses")
    @MainActor func webKitUsesAuthenticatedBroker() async throws {
        let proxyPort = try Self.availableLoopbackPort()
        let targetPort = try Self.reservedNonListeningPort()
        let profileID = UUID()
        let forwarder = BrowserRouteForwarder()
        var concreteProxy: SOCKS5Proxy?
        let session = RemoteBrowserProxySession(
            ownerWindowID: WindowID(),
            profileID: profileID,
            remotePort: targetPort.port,
            forwarder: forwarder,
            portCandidates: { [proxyPort] },
            proxyFactory: {
                port, credentials, forwarder, profileID, leaseID, targetMappings in
                let proxy = SOCKS5Proxy(
                    listenPort: port,
                    credentials: credentials,
                    forwarder: forwarder,
                    profileID: profileID,
                    connectionLeaseID: leaseID,
                    allowedTargets: Set(targetMappings.keys),
                    targetMappings: targetMappings
                )
                concreteProxy = proxy
                return proxy
            }
        )
        let capability = try await session.start()
        defer {
            BrowserWebsiteDataStoreFactory.releaseRemoteDataStore(for: capability)
            session.stop()
            Darwin.close(targetPort.descriptor)
        }
        try await BrowserWebsiteDataStoreFactory.prepareRemoteNetworkIsolation(for: capability)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = BrowserWebsiteDataStoreFactory.make(
            profileID: nil,
            remoteCapability: capability
        )
        #expect(BrowserWebsiteDataStoreFactory.installRemoteNetworkIsolation(
            on: configuration,
            capability: capability
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = BrowserRouteNavigationDelegate()
        webView.navigationDelegate = delegate
        let url = try #require(URL(string: "http://\(capability.browserHost):\(targetPort.port)/"))

        let navigationResult: Result<Void, any Error> = await withCheckedContinuation {
            (continuation: CheckedContinuation<Result<Void, any Error>, Never>) in
            delegate.completion = { result in continuation.resume(returning: result) }
            webView.load(URLRequest(url: url))
            // The wait ends on the navigation callback, so this is only the cap
            // that keeps a never-completing navigation from hanging the suite. It
            // has to cover launching the WebKit process pair, the SOCKS5 handshake
            // against the broker and the HTTP round trip, which a loaded CI runner
            // can stretch well past a few seconds; the assertion below still fails
            // when the navigation never completes.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                delegate.finish(.failure(POSIXError(.ETIMEDOUT)))
            }
        }

        #expect(concreteProxy?.acceptedConnectionCount ?? 0 > 0)
        #expect(concreteProxy?.authenticationAttemptCount ?? 0 > 0)
        #expect(concreteProxy?.authenticationFailureCount == 0)
        #expect(concreteProxy?.targetRejectionCount == 0)
        try navigationResult.get()
        let body = try await webView.evaluateJavaScript("document.body.innerText") as? String
        #expect(body == "brokered-route")
        #expect(forwarder.openedTargets.count == 1)
        #expect(forwarder.openedTargets.first?.port == targetPort.port)
        #expect(["localhost", "127.0.0.1", "::1"].contains(
            forwarder.openedTargets.first?.host ?? ""
        ))

        let probePort = try Self.availableLoopbackPort()
        let probe = BrowserRouteLoopbackProbe(port: probePort)
        try await probe.start()
        defer { probe.stop() }
        let brokerConnectionsBeforeBypassAttempt = concreteProxy?.acceptedConnectionCount
        let loopbackURL = try #require(URL(string: "http://localhost:\(probePort)/"))
        let script = """
        const image = new Image();
        image.src = \(String(reflecting: loopbackURL.absoluteString));
        document.body.appendChild(image);
        void 0;
        """
        _ = try await webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(probe.acceptedConnectionCount == 0)
        #expect(concreteProxy?.acceptedConnectionCount == brokerConnectionsBeforeBypassAttempt)
    }

    private static func availableLoopbackPort() throws -> Int {
        let reserved = try reservedNonListeningPort()
        defer { Darwin.close(reserved.descriptor) }
        return reserved.port
    }

    private static func reservedNonListeningPort() throws -> (descriptor: Int32, port: Int) {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: 0,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return (descriptor, Int(UInt16(bigEndian: bound.sin_port)))
    }
}
