// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
@testable import CocxyTerminal

/// Test doubles use the legacy operations unless a test overrides an exact
/// operation to assert identity-bound behavior explicitly.
extension SSHMultiplexing {
    func disconnectAsync(
        profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        guard expectedControlMaster.controlPath == controlPath(for: profile) else {
            throw SSHMultiplexerError.notConnected
        }
        try await disconnectAsync(profile: profile, executor: executor)
    }

    func forwardPortAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        guard expectedControlMaster.controlPath == controlPath(for: profile) else {
            throw SSHMultiplexerError.notConnected
        }
        try await forwardPortAsync(forward, on: profile, executor: executor)
    }

    func cancelForwardAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        guard expectedControlMaster.controlPath == controlPath(for: profile) else {
            throw SSHMultiplexerError.notConnected
        }
        try await cancelForwardAsync(forward, on: profile, executor: executor)
    }

    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        guard expectedControlMaster.controlPath == controlPath(for: profile) else {
            throw SSHMultiplexerError.notConnected
        }
        return try await executeRemoteCommand(command, on: profile, executor: executor)
    }
}
