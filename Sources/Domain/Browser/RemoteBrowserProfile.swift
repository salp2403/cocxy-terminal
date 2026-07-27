// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteBrowserProfile.swift - Remote workspace context for browser profiles.

import Foundation

/// Remote workspace routing metadata attached to a browser profile.
///
/// This model is intentionally descriptive only. It does not enable proxies,
/// mutate SSH configuration, or start tunnels by itself. Runtime services can
/// use it to bind a visible browser profile to an already-approved remote
/// workspace and its user-owned local forwards.
struct RemoteBrowserProfile: Codable, Equatable, Sendable {
    let id: UUID
    let connectionProfileID: UUID
    var name: String
    var host: String
    var user: String?
    var sshPort: Int?
    var localForwardedPorts: [Int: Int]
    var socksPort: Int?
    var httpConnectPort: Int?
    var proxyHealth: RemoteBrowserProxyHealth
    let createdAt: Date

    init(
        id: UUID = UUID(),
        connectionProfileID: UUID,
        name: String,
        host: String,
        user: String? = nil,
        sshPort: Int? = nil,
        localForwardedPorts: [Int: Int] = [:],
        socksPort: Int? = nil,
        httpConnectPort: Int? = nil,
        proxyHealth: RemoteBrowserProxyHealth = .disconnected,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.connectionProfileID = connectionProfileID
        self.name = name
        self.host = host
        self.user = user
        self.sshPort = sshPort
        self.localForwardedPorts = localForwardedPorts
        self.socksPort = socksPort
        self.httpConnectPort = httpConnectPort
        self.proxyHealth = proxyHealth
        self.createdAt = createdAt
    }

    init(
        remoteConnectionProfile: RemoteConnectionProfile,
        localForwardedPorts: [Int: Int] = [:],
        socksPort: Int? = nil,
        httpConnectPort: Int? = nil,
        proxyHealth: RemoteBrowserProxyHealth = .disconnected,
        createdAt: Date = Date()
    ) {
        self.init(
            connectionProfileID: remoteConnectionProfile.id,
            name: remoteConnectionProfile.name,
            host: remoteConnectionProfile.host,
            user: remoteConnectionProfile.user,
            sshPort: remoteConnectionProfile.port,
            localForwardedPorts: localForwardedPorts,
            socksPort: socksPort,
            httpConnectPort: httpConnectPort,
            proxyHealth: proxyHealth,
            createdAt: createdAt
        )
    }

    init(
        remoteConnectionProfile: RemoteConnectionProfile,
        localForwardedPorts: [Int: Int] = [:],
        proxyState: ProxyState,
        createdAt: Date = Date()
    ) {
        let socksPort: Int?
        let httpConnectPort: Int?
        switch proxyState {
        case .active(let profileID, let socks, let http)
            where profileID == remoteConnectionProfile.id:
            socksPort = socks
            httpConnectPort = http
        default:
            socksPort = nil
            httpConnectPort = nil
        }
        self.init(
            remoteConnectionProfile: remoteConnectionProfile,
            localForwardedPorts: localForwardedPorts,
            socksPort: socksPort,
            httpConnectPort: httpConnectPort,
            proxyHealth: RemoteBrowserProxyHealth(
                proxyState: proxyState,
                for: remoteConnectionProfile.id
            ),
            createdAt: createdAt
        )
    }
}

enum RemoteBrowserProxyHealth: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case active
    case degraded
    case failed

    init(proxyState: ProxyState, for profileID: UUID? = nil) {
        switch proxyState {
        case .off:
            self = .disconnected
        case .starting(let owner), .failover(let owner):
            self = profileID.map { $0 == owner } ?? true ? .connecting : .disconnected
        case .active(let owner, _, _):
            self = profileID.map { $0 == owner } ?? true ? .active : .disconnected
        case .failing(let owner, _):
            self = profileID.map { owner == nil || $0 == owner } ?? true ? .failed : .disconnected
        }
    }

    var needsAttention: Bool {
        switch self {
        case .connecting, .degraded, .failed:
            return true
        case .disconnected, .active:
            return false
        }
    }
}

struct RemoteBrowserRoute: Equatable, Sendable {
    let profile: RemoteBrowserProfile
    let remotePort: Int
    let localURL: URL

    var remoteAddress: String {
        "\(profile.host):\(remotePort)"
    }
}

extension RemoteBrowserProfile {
    var displayTitle: String {
        var destination = ""
        if let user, !user.isEmpty {
            destination += "\(user)@"
        }
        destination += host
        if let sshPort, sshPort != 22 {
            destination += ":\(sshPort)"
        }
        return "\(name) (\(destination))"
    }

    var routingSummary: String {
        var parts: [String] = ["health=\(proxyHealth.rawValue)"]
        if let socksPort {
            parts.append("socks=127.0.0.1:\(socksPort)")
        }
        if let httpConnectPort {
            parts.append("http-connect=127.0.0.1:\(httpConnectPort)")
        }
        if !localForwardedPorts.isEmpty {
            let forwards = localForwardedPorts
                .sorted { $0.key < $1.key }
                .map { "\($0.key)->\($0.value)" }
                .joined(separator: ",")
            parts.append("forwards=\(forwards)")
        }
        return parts.joined(separator: " ")
    }

    func localURL(forRemotePort remotePort: Int, scheme: String = "http", path: String = "/") -> URL? {
        guard let localPort = localForwardedPorts[remotePort] else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "127.0.0.1"
        components.port = localPort
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        return components.url
    }

    func route(forRemotePort remotePort: Int, scheme: String = "http", path: String = "/") -> RemoteBrowserRoute? {
        guard let localURL = localURL(forRemotePort: remotePort, scheme: scheme, path: path) else {
            return nil
        }
        return RemoteBrowserRoute(profile: self, remotePort: remotePort, localURL: localURL)
    }

    mutating func apply(proxyState: ProxyState) {
        switch proxyState {
        case .active(let profileID, let socks, let http)
            where profileID == connectionProfileID:
            socksPort = socks
            httpConnectPort = http
        default:
            socksPort = nil
            httpConnectPort = nil
        }
        proxyHealth = RemoteBrowserProxyHealth(
            proxyState: proxyState,
            for: connectionProfileID
        )
    }

    func applying(proxyState: ProxyState) -> RemoteBrowserProfile {
        var copy = self
        copy.apply(proxyState: proxyState)
        return copy
    }
}
