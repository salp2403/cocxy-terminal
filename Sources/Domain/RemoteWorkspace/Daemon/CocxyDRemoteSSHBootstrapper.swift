// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyDRemoteSSHBootstrapper.swift - Prepares verified cocxyd-remote SSH sessions.

import Foundation

enum CocxyDRemoteSSHBootstrapError: Error, Equatable, CustomStringConvertible {
    case invalidDestination

    var description: String {
        switch self {
        case .invalidDestination:
            return "invalidDestination"
        }
    }
}

enum CocxyDRemoteSSHBootstrapMode: Equatable, Sendable {
    case daemonReady(uploaded: Bool, remotePath: String)
    case fallback(reason: String)
}

struct CocxyDRemoteSSHBootstrapPlan: Equatable, Sendable {
    let profile: RemoteConnectionProfile
    let directSSHCommand: String
}

struct CocxyDRemoteSSHBootstrapResult: Equatable, Sendable {
    let profile: RemoteConnectionProfile?
    let mode: CocxyDRemoteSSHBootstrapMode
    let directSSHCommand: String
    let daemonStdioCommand: String
}

@MainActor
protocol CocxyDRemoteConnectionManaging: AnyObject {
    func connect(profile: RemoteConnectionProfile) async
    func connectionState(profileID: UUID) -> RemoteConnectionManager.ConnectionState?
}

@MainActor
protocol CocxyDRemotePlatformDetecting: AnyObject {
    func detectPlatform(profileID: UUID) async throws -> RemotePlatform
}

@MainActor
protocol CocxyDRemoteBinaryUploading: AnyObject {
    func uploadIfNeeded(
        _ binary: CocxyDRemoteBinaryCandidate,
        profileID: UUID
    ) async throws -> CocxyDRemoteUploadResult
}

@MainActor
final class CocxyDRemoteSSHBootstrapper {
    typealias BinaryCandidateResolver = @MainActor (RemotePlatform) throws -> CocxyDRemoteBinaryCandidate

    private let profileStore: any RemoteProfileStoring
    private let connectionManager: any CocxyDRemoteConnectionManaging
    private let platformDetector: any CocxyDRemotePlatformDetecting
    private let uploader: any CocxyDRemoteBinaryUploading
    private let binaryCandidateResolver: BinaryCandidateResolver

    init(
        profileStore: any RemoteProfileStoring,
        connectionManager: any CocxyDRemoteConnectionManaging,
        platformDetector: any CocxyDRemotePlatformDetecting,
        uploader: any CocxyDRemoteBinaryUploading,
        binaryCandidateResolver: @escaping BinaryCandidateResolver = { platform in
            try CocxyDRemoteUploader.bundledBinaryCandidate(for: platform)
        }
    ) {
        self.profileStore = profileStore
        self.connectionManager = connectionManager
        self.platformDetector = platformDetector
        self.uploader = uploader
        self.binaryCandidateResolver = binaryCandidateResolver
    }

    func bootstrap(
        destination: String,
        port: Int?,
        identityFile: String?
    ) async -> CocxyDRemoteSSHBootstrapResult {
        do {
            let plan = try Self.makeProfile(
                destination: destination,
                port: port,
                identityFile: identityFile
            )
            let fallback = Self.fallbackResult(profile: plan.profile, directSSHCommand: plan.directSSHCommand)

            do {
                try profileStore.save(plan.profile)
            } catch {
                return fallback.withReason("profile save failed: \(String(describing: error))")
            }

            await connectionManager.connect(profile: plan.profile)
            guard case .connected = connectionManager.connectionState(profileID: plan.profile.id) else {
                let state = connectionManager.connectionState(profileID: plan.profile.id)
                return fallback.withReason(Self.connectionFailureReason(from: state))
            }

            do {
                let platform = try await platformDetector.detectPlatform(profileID: plan.profile.id)
                let binary = try binaryCandidateResolver(platform)
                let upload = try await uploader.uploadIfNeeded(binary, profileID: plan.profile.id)
                return CocxyDRemoteSSHBootstrapResult(
                    profile: plan.profile,
                    mode: .daemonReady(uploaded: upload.uploaded, remotePath: upload.remotePath),
                    directSSHCommand: plan.directSSHCommand,
                    daemonStdioCommand: Self.daemonStdioCommand(
                        directSSHCommand: plan.directSSHCommand,
                        remotePath: upload.remotePath
                    )
                )
            } catch {
                return fallback.withReason(String(describing: error))
            }
        } catch {
            let direct = Self.directSSHCommand(destination: destination, port: port, identityFile: identityFile)
            return CocxyDRemoteSSHBootstrapResult(
                profile: nil,
                mode: .fallback(reason: String(describing: error)),
                directSSHCommand: direct,
                daemonStdioCommand: Self.daemonStdioCommand(
                    directSSHCommand: direct,
                    remotePath: "~/.cocxy/bin/cocxyd-remote"
                )
            )
        }
    }

    static func makeProfile(
        destination: String,
        port: Int?,
        identityFile: String?
    ) throws -> CocxyDRemoteSSHBootstrapPlan {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CocxyDRemoteSSHBootstrapError.invalidDestination
        }

        let (user, host) = try splitDestination(trimmed)
        let display = user.map { "\($0)@\(host)" } ?? host
        let profile = RemoteConnectionProfile(
            name: display,
            host: host,
            user: user,
            port: port,
            identityFile: identityFile,
            autoReconnect: false
        )
        return CocxyDRemoteSSHBootstrapPlan(
            profile: profile,
            directSSHCommand: directSSHCommand(destination: display, port: port, identityFile: identityFile)
        )
    }

    static func directSSHCommand(destination: String, port: Int?, identityFile: String?) -> String {
        var parts = ["ssh"]
        if let port {
            parts.append(contentsOf: ["-p", "\(port)"])
        }
        if let identityFile, !identityFile.isEmpty {
            parts.append(contentsOf: ["-i", identityFile])
        }
        parts.append(destination.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.map(shellToken).joined(separator: " ")
    }

    private static func daemonStdioCommand(directSSHCommand: String, remotePath: String) -> String {
        "\(directSSHCommand) \(remotePath) serve --stdio"
    }

    private static func fallbackResult(
        profile: RemoteConnectionProfile,
        directSSHCommand: String
    ) -> CocxyDRemoteSSHBootstrapResult {
        CocxyDRemoteSSHBootstrapResult(
            profile: profile,
            mode: .fallback(reason: "daemon bootstrap not attempted"),
            directSSHCommand: directSSHCommand,
            daemonStdioCommand: daemonStdioCommand(
                directSSHCommand: directSSHCommand,
                remotePath: "~/.cocxy/bin/cocxyd-remote"
            )
        )
    }

    private static func connectionFailureReason(
        from state: RemoteConnectionManager.ConnectionState?
    ) -> String {
        switch state {
        case .failed(let message):
            return message
        case .disconnected:
            return "connection disconnected"
        case .connecting:
            return "connection still connecting"
        case .reconnecting(let attempt):
            return "connection reconnecting attempt \(attempt)"
        case .connected:
            return "connected"
        case nil:
            return "connection state unavailable"
        }
    }

    private static func splitDestination(_ destination: String) throws -> (user: String?, host: String) {
        guard let at = destination.lastIndex(of: "@") else {
            guard !destination.isEmpty else { throw CocxyDRemoteSSHBootstrapError.invalidDestination }
            return (nil, destination)
        }
        let user = String(destination[..<at])
        let host = String(destination[destination.index(after: at)...])
        guard !user.isEmpty, !host.isEmpty else {
            throw CocxyDRemoteSSHBootstrapError.invalidDestination
        }
        return (user, host)
    }

    private static func shellToken(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+-./:@=~")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension CocxyDRemoteSSHBootstrapResult {
    func withReason(_ reason: String) -> CocxyDRemoteSSHBootstrapResult {
        CocxyDRemoteSSHBootstrapResult(
            profile: profile,
            mode: .fallback(reason: reason),
            directSSHCommand: directSSHCommand,
            daemonStdioCommand: daemonStdioCommand
        )
    }
}

extension RemoteConnectionManager: CocxyDRemoteConnectionManaging {
    func connectionState(profileID: UUID) -> RemoteConnectionManager.ConnectionState? {
        connections[profileID]
    }
}

extension DaemonDeployer: CocxyDRemotePlatformDetecting {}

extension CocxyDRemoteUploader: CocxyDRemoteBinaryUploading {}
