// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHProcessResult.swift - Bounded SSH process execution result.

enum SSHPostExecutionConnectionState: Sendable, Equatable {
    case verified
    case unavailable
}

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
    let postExecutionConnectionState: SSHPostExecutionConnectionState

    init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        timedOut: Bool = false,
        postExecutionConnectionState: SSHPostExecutionConnectionState = .verified
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.postExecutionConnectionState = postExecutionConnectionState
    }
}
