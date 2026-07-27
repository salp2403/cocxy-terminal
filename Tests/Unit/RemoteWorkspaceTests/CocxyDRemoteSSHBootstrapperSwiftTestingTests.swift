// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyDRemoteSSHBootstrapper")
struct CocxyDRemoteSSHBootstrapperSwiftTestingTests {

    @Test("builds direct ssh command and parses user host profile")
    @MainActor func buildsDirectCommandAndProfile() throws {
        let parsed = try CocxyDRemoteSSHBootstrapper.makeProfile(
            destination: "deploy@example.test",
            port: 2222,
            identityFile: "~/.ssh/deploy"
        )

        #expect(parsed.profile.user == "deploy")
        #expect(parsed.profile.host == "example.test")
        #expect(parsed.profile.port == 2222)
        #expect(parsed.profile.identityFile == "~/.ssh/deploy")
        #expect(parsed.profile.autoReconnect == false)
        #expect(parsed.directSSHCommand == "ssh -p 2222 -i ~/.ssh/deploy -- deploy@example.test")
    }

    @Test("rejects empty destination")
    @MainActor func rejectsEmptyDestination() {
        #expect(throws: CocxyDRemoteSSHBootstrapError.invalidDestination) {
            _ = try CocxyDRemoteSSHBootstrapper.makeProfile(destination: "   ", port: nil, identityFile: nil)
        }
    }

    @Test(
        "rejects unsafe or ambiguous destinations",
        arguments: [
            "-oProxyCommand=/bin/true",
            "user@-oProxyCommand=/bin/true",
            "example.test with-space",
            " example.test",
            "example.test\nother",
            "first@second@example.test",
            "@example.test",
            "user@",
            "999.1.1.1",
            "example.test:22",
        ]
    )
    @MainActor func rejectsUnsafeOrAmbiguousDestination(_ destination: String) {
        #expect(throws: CocxyDRemoteSSHBootstrapError.invalidDestination) {
            _ = try CocxyDRemoteSSHBootstrapper.makeProfile(
                destination: destination,
                port: nil,
                identityFile: nil
            )
        }
    }

    @Test("accepts host aliases and canonical IP literals")
    @MainActor func acceptsAliasesAndIPAddresses() throws {
        let alias = try CocxyDRemoteSSHBootstrapper.makeProfile(
            destination: "deploy@prod_web+blue",
            port: nil,
            identityFile: nil
        )
        let ipv4 = try CocxyDRemoteSSHBootstrapper.makeProfile(
            destination: "192.0.2.10",
            port: nil,
            identityFile: nil
        )
        let ipv6 = try CocxyDRemoteSSHBootstrapper.makeProfile(
            destination: "deploy@[2001:db8::10]",
            port: nil,
            identityFile: nil
        )

        #expect(alias.profile.user == "deploy")
        #expect(alias.profile.host == "prod_web+blue")
        #expect(ipv4.profile.host == "192.0.2.10")
        #expect(ipv6.profile.user == "deploy")
        #expect(ipv6.profile.host == "2001:db8::10")
        #expect(ipv6.directSSHCommand == "ssh -- deploy@2001:db8::10")
    }

    @Test("invalid destination is not persisted or connected")
    @MainActor func invalidDestinationHasNoSideEffects() async {
        let profileStore = MockRemoteProfileStore()
        let connectionManager = MockCocxyDRemoteConnectionManager()
        let platformDetector = MockCocxyDRemotePlatformDetector()
        let uploader = MockCocxyDRemoteBinaryUploader()
        let bootstrapper = CocxyDRemoteSSHBootstrapper(
            profileStore: profileStore,
            connectionManager: connectionManager,
            platformDetector: platformDetector,
            uploader: uploader
        )

        let result = await bootstrapper.bootstrap(
            destination: "-oProxyCommand=/bin/true",
            port: nil,
            identityFile: nil
        )

        #expect(result.profile == nil)
        #expect(result.mode == .fallback(reason: "invalidDestination"))
        #expect(result.directSSHCommand == "ssh -- -oProxyCommand=/bin/true")
        #expect(profileStore.profiles.isEmpty)
        #expect(connectionManager.connectedProfiles.isEmpty)
        #expect(platformDetector.detectedProfileIDs.isEmpty)
        #expect(uploader.uploadedProfileIDs.isEmpty)
    }

    @Test("connects, detects platform, verifies upload, and returns daemon ready")
    @MainActor func bootstrapDaemonReady() async throws {
        let profileStore = MockRemoteProfileStore()
        let connectionManager = MockCocxyDRemoteConnectionManager()
        let platformDetector = MockCocxyDRemotePlatformDetector()
        let uploader = MockCocxyDRemoteBinaryUploader()
        let bootstrapper = CocxyDRemoteSSHBootstrapper(
            profileStore: profileStore,
            connectionManager: connectionManager,
            platformDetector: platformDetector,
            uploader: uploader,
            binaryCandidateResolver: { platform in
                #expect(platform.os == "Linux")
                return Self.fixtureBinary(sha256: "expected")
            }
        )

        let result = await bootstrapper.bootstrap(
            destination: "dev@example.test",
            port: nil,
            identityFile: nil
        )

        #expect(profileStore.profiles.count == 1)
        #expect(connectionManager.connectedProfiles.count == 1)
        #expect(platformDetector.detectedProfileIDs == [profileStore.profiles[0].id])
        #expect(uploader.uploadedProfileIDs == [profileStore.profiles[0].id])
        #expect(result.mode == .daemonReady(uploaded: true, remotePath: "~/.cocxy/bin/cocxyd-remote"))
        #expect(result.directSSHCommand == "ssh -- dev@example.test")
        #expect(result.daemonStdioCommand == "ssh -- dev@example.test ~/.cocxy/bin/cocxyd-remote serve --stdio")
    }

    @Test("falls back to direct ssh when control connection fails")
    @MainActor func fallbackWhenConnectionFails() async {
        let profileStore = MockRemoteProfileStore()
        let connectionManager = MockCocxyDRemoteConnectionManager()
        connectionManager.stateAfterConnect = .failed("auth failed")
        let platformDetector = MockCocxyDRemotePlatformDetector()
        let uploader = MockCocxyDRemoteBinaryUploader()
        let bootstrapper = CocxyDRemoteSSHBootstrapper(
            profileStore: profileStore,
            connectionManager: connectionManager,
            platformDetector: platformDetector,
            uploader: uploader,
            binaryCandidateResolver: { _ in Self.fixtureBinary(sha256: "expected") }
        )

        let result = await bootstrapper.bootstrap(destination: "example.test", port: 2200, identityFile: nil)

        #expect(result.mode == .fallback(reason: "auth failed"))
        #expect(result.directSSHCommand == "ssh -p 2200 -- example.test")
        #expect(platformDetector.detectedProfileIDs.isEmpty)
        #expect(uploader.uploadedProfileIDs.isEmpty)
    }

    @Test("falls back to direct ssh when binary upload cannot be verified")
    @MainActor func fallbackWhenUploadFails() async {
        let bootstrapper = CocxyDRemoteSSHBootstrapper(
            profileStore: MockRemoteProfileStore(),
            connectionManager: MockCocxyDRemoteConnectionManager(),
            platformDetector: MockCocxyDRemotePlatformDetector(),
            uploader: ThrowingCocxyDRemoteBinaryUploader(),
            binaryCandidateResolver: { _ in Self.fixtureBinary(sha256: "expected") }
        )

        let result = await bootstrapper.bootstrap(destination: "example.test", port: nil, identityFile: nil)

        if case .fallback(let reason) = result.mode {
            #expect(reason.contains("postUploadChecksumMismatch"))
        } else {
            Issue.record("Expected fallback after upload verification failure")
        }
    }

    private static func fixtureBinary(sha256: String) -> CocxyDRemoteBinaryCandidate {
        CocxyDRemoteBinaryCandidate(
            localPath: "/local/cocxyd-remote",
            remotePath: "~/.cocxy/bin/cocxyd-remote",
            manifest: CocxyDRemoteManifest(
                version: "1.0.0",
                platform: RemotePlatform(os: "Linux", arch: "x86_64"),
                sha256: sha256,
                sizeBytes: 128,
                capabilities: ["session", "proxy", "cli-relay"]
            )
        )
    }
}

@MainActor
private final class MockCocxyDRemoteConnectionManager: CocxyDRemoteConnectionManaging {
    var stateAfterConnect: RemoteConnectionManager.ConnectionState = .connected(latencyMs: nil)
    var connectedProfiles: [RemoteConnectionProfile] = []

    func connect(profile: RemoteConnectionProfile) async {
        connectedProfiles.append(profile)
    }

    func connectionState(profileID: UUID) -> RemoteConnectionManager.ConnectionState? {
        stateAfterConnect
    }
}

@MainActor
private final class MockCocxyDRemotePlatformDetector: CocxyDRemotePlatformDetecting {
    var detectedProfileIDs: [UUID] = []
    var platform = RemotePlatform(os: "Linux", arch: "x86_64")

    func detectPlatform(profileID: UUID) async throws -> RemotePlatform {
        detectedProfileIDs.append(profileID)
        return platform
    }
}

@MainActor
private final class MockCocxyDRemoteBinaryUploader: CocxyDRemoteBinaryUploading {
    var uploadedProfileIDs: [UUID] = []

    func uploadIfNeeded(
        _ binary: CocxyDRemoteBinaryCandidate,
        profileID: UUID
    ) async throws -> CocxyDRemoteUploadResult {
        uploadedProfileIDs.append(profileID)
        return CocxyDRemoteUploadResult(
            uploaded: true,
            verified: true,
            remotePath: binary.remotePath,
            reason: .missing
        )
    }
}

@MainActor
private final class ThrowingCocxyDRemoteBinaryUploader: CocxyDRemoteBinaryUploading {
    func uploadIfNeeded(
        _ binary: CocxyDRemoteBinaryCandidate,
        profileID: UUID
    ) async throws -> CocxyDRemoteUploadResult {
        throw CocxyDRemoteUploadError.postUploadChecksumMismatch(remote: "bad", expected: binary.manifest.sha256)
    }
}
