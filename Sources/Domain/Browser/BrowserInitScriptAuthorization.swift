// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserInitScriptAuthorization.swift - Scoped approval records for browser init scripts.

import CryptoKit
import Foundation

enum BrowserInitScriptRequestSource: String, Equatable, Sendable {
    case localCLI
    case agentMode
}

struct BrowserOrigin: Equatable, Hashable, Sendable {
    let scheme: String
    let host: String
    let port: Int?

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        self.init(
            scheme: components.scheme ?? "",
            host: components.host ?? "",
            port: components.port
        )
    }

    init?(scheme rawScheme: String, host rawHost: String, port rawPort: Int?) {
        let scheme = rawScheme.lowercased()
        let host = rawHost.lowercased()
        guard (scheme == "http" || scheme == "https"), !host.isEmpty else {
            return nil
        }

        self.scheme = scheme
        self.host = host
        switch (scheme, rawPort) {
        case ("http", 80), ("https", 443):
            port = nil
        default:
            port = rawPort
        }
    }

    var serialized: String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.string ?? "\(scheme)://\(host)"
    }
}

struct BrowserInitScriptRemoteRouteAuthority: Equatable, Sendable {
    let profileID: UUID
    let connectionProfileID: UUID
    let host: String
    let user: String?
    let sshPort: Int?
    let localForwardedPorts: [Int: Int]
    let socksPort: Int?
    let httpConnectPort: Int?

    init(_ profile: RemoteBrowserProfile) {
        profileID = profile.id
        connectionProfileID = profile.connectionProfileID
        host = profile.host
        user = profile.user
        sshPort = profile.sshPort
        localForwardedPorts = profile.localForwardedPorts
        socksPort = profile.socksPort
        httpConnectPort = profile.httpConnectPort
    }

    var fallbackDisplayTitle: String {
        var destination = ""
        if let user, !user.isEmpty {
            destination = "\(user)@"
        }
        destination += host.contains(":") ? "[\(host)]" : host
        if let sshPort {
            destination += ":\(sshPort)"
        }

        var routes: [String] = []
        if let socksPort {
            routes.append("SOCKS 127.0.0.1:\(socksPort)")
        }
        if let httpConnectPort {
            routes.append("HTTP CONNECT 127.0.0.1:\(httpConnectPort)")
        }
        routes.append(contentsOf: localForwardedPorts.sorted { $0.key < $1.key }.map {
            "\($0.key)->\($0.value)"
        })
        return routes.isEmpty ? destination : "\(destination); \(routes.joined(separator: ", "))"
    }
}

struct BrowserInitScriptContext: Equatable, Sendable {
    let viewModelIdentifier: ObjectIdentifier
    let browserViewID: UUID
    let tabID: UUID
    let origin: BrowserOrigin
    let browserProfileID: UUID?
    let remoteBrowserProfileID: UUID?
    let remoteConnectionProfileID: UUID?
    let remoteRouteAuthority: BrowserInitScriptRemoteRouteAuthority?
}

struct BrowserInitScriptAuthorizationRequest: Equatable, Sendable {
    static let authorizationLifetime: TimeInterval = 10 * 60

    let id: UUID
    let source: BrowserInitScriptRequestSource
    let script: String
    let scriptDigest: String
    let context: BrowserInitScriptContext
    let tabDisplayTitle: String
    let remoteDisplayTitle: String?
    let createdAt: Date
    let expiresAt: Date
    let mainFrameOnly: Bool

    init(
        id: UUID = UUID(),
        source: BrowserInitScriptRequestSource,
        script: String,
        context: BrowserInitScriptContext,
        tabDisplayTitle: String,
        remoteDisplayTitle: String?,
        createdAt: Date = Date(),
        lifetime: TimeInterval = authorizationLifetime
    ) {
        self.id = id
        self.source = source
        self.script = script
        scriptDigest = BrowserInitScriptSecurity.digest(script)
        self.context = context
        self.tabDisplayTitle = tabDisplayTitle
        self.remoteDisplayTitle = remoteDisplayTitle
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(lifetime)
        mainFrameOnly = true
    }

    func matches(
        script candidateScript: String,
        context candidateContext: BrowserInitScriptContext,
        at date: Date
    ) -> Bool {
        date < expiresAt
            && candidateScript == script
            && BrowserInitScriptSecurity.digest(candidateScript) == scriptDigest
            && candidateContext == context
            && mainFrameOnly
    }
}

struct BrowserInitScript: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: String
    let scriptDigest: String
    let browserViewID: UUID
    let tabID: UUID
    let origin: BrowserOrigin
    let browserProfileID: UUID?
    let remoteBrowserProfileID: UUID?
    let remoteConnectionProfileID: UUID?
    let remoteRouteAuthority: BrowserInitScriptRemoteRouteAuthority?
    let createdAt: Date
    let expiresAt: Date
    let mainFrameOnly: Bool

    init(
        id: UUID = UUID(),
        authorization: BrowserInitScriptAuthorizationRequest,
        approvedAt: Date,
        lifetime: TimeInterval = BrowserInitScriptAuthorizationRequest.authorizationLifetime
    ) {
        self.id = id
        source = authorization.script
        scriptDigest = authorization.scriptDigest
        browserViewID = authorization.context.browserViewID
        tabID = authorization.context.tabID
        origin = authorization.context.origin
        browserProfileID = authorization.context.browserProfileID
        remoteBrowserProfileID = authorization.context.remoteBrowserProfileID
        remoteConnectionProfileID = authorization.context.remoteConnectionProfileID
        remoteRouteAuthority = authorization.context.remoteRouteAuthority
        createdAt = approvedAt
        expiresAt = approvedAt.addingTimeInterval(lifetime)
        mainFrameOnly = authorization.mainFrameOnly
    }

    var length: Int {
        source.count
    }

    func isAuthorized(
        browserViewID candidateBrowserViewID: UUID,
        tabID candidateTabID: UUID,
        origin candidateOrigin: BrowserOrigin,
        browserProfileID candidateBrowserProfileID: UUID?,
        remoteBrowserProfileID candidateRemoteBrowserProfileID: UUID?,
        remoteConnectionProfileID candidateRemoteConnectionProfileID: UUID?,
        remoteRouteAuthority candidateRemoteRouteAuthority: BrowserInitScriptRemoteRouteAuthority?,
        isMainFrame: Bool,
        at date: Date
    ) -> Bool {
        date < expiresAt
            && isMainFrame
            && mainFrameOnly
            && candidateBrowserViewID == browserViewID
            && candidateTabID == tabID
            && candidateOrigin == origin
            && candidateBrowserProfileID == browserProfileID
            && candidateRemoteBrowserProfileID == remoteBrowserProfileID
            && candidateRemoteConnectionProfileID == remoteConnectionProfileID
            && candidateRemoteRouteAuthority == remoteRouteAuthority
            && BrowserInitScriptSecurity.digest(source) == scriptDigest
    }
}

enum BrowserInitScriptRegistrationError: Error, Equatable {
    case invalidSource
    case authorizationConsumed
    case contextChanged
    case capacityReached
    case bridgeUnavailable
    case synchronizationFailed(String)
}

enum BrowserInitScriptSecurity {
    static let maximumActiveScripts = 50
    static let maximumSourceByteCount = 10_000

    static func isValidSource(_ source: String) -> Bool {
        !source.isEmpty && source.utf8.count <= maximumSourceByteCount
    }

    static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func approvalPreview(_ source: String) -> String {
        escapedPreview(source, preservingNewlines: true, maximumScalars: nil)
    }

    static func approvalMetadataPreview(_ value: String) -> String {
        escapedPreview(value, preservingNewlines: false, maximumScalars: 512)
    }

    private static func escapedPreview(
        _ value: String,
        preservingNewlines: Bool,
        maximumScalars: Int?
    ) -> String {
        var preview = ""
        var scalarCount = 0
        for scalar in value.unicodeScalars {
            if let maximumScalars, scalarCount >= maximumScalars {
                preview += "..."
                break
            }
            scalarCount += 1

            if scalar == "\\" {
                preview += "\\\\"
            } else if preservingNewlines, scalar == "\n" {
                preview.unicodeScalars.append(scalar)
            } else {
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    preview += String(format: "\\u{%04X}", scalar.value)
                default:
                    preview.unicodeScalars.append(scalar)
                }
            }
        }
        return preview
    }
}
