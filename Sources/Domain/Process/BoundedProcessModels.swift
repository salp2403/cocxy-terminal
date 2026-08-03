// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BoundedProcessModels.swift - Shared bounded process result and errors.

import Darwin
import Foundation

enum BoundedProcessRunnerError: Error, LocalizedError, Equatable, Sendable {
    case invalidInvocation
    case systemCallFailed(operation: String, code: Int32)
    case launchdCommandFailed(operation: String, exitCode: Int32)
    case secureBrokerFailed(String)
    case secureCleanupUnverified(String)
    case secureContainmentUnavailable
    case secureContainmentVerificationFailed
    case processTreeDidNotTerminate
    case outputDrainDidNotFinish

    var errorDescription: String? {
        switch self {
        case .invalidInvocation:
            return "The process invocation is invalid."
        case .systemCallFailed(let operation, let code):
            return "Process operation \(operation) failed: \(Self.message(for: code))."
        case .launchdCommandFailed:
            return "Secure local execution could not be started."
        case .secureBrokerFailed:
            return "Secure local execution failed and was stopped."
        case .secureCleanupUnverified:
            return "Cocxy stopped the command but could not verify complete cleanup. Restart Cocxy before running more local code."
        case .secureContainmentUnavailable:
            return "Secure process containment is unavailable."
        case .secureContainmentVerificationFailed:
            return "Secure process containment could not be verified."
        case .processTreeDidNotTerminate:
            return "The process tree did not terminate cleanly."
        case .outputDrainDidNotFinish:
            return "The process output did not close after teardown."
        }
    }

    var diagnosticDescription: String {
        if case .secureBrokerFailed(let reason) = self { return reason }
        if case .secureCleanupUnverified(let reason) = self { return reason }
        if case .launchdCommandFailed(let operation, let exitCode) = self {
            return "\(operation) failed with exit code \(exitCode)"
        }
        return errorDescription ?? String(describing: self)
    }

    static func contextual(_ operation: String, error: Error) -> BoundedProcessRunnerError {
        if let bounded = error as? BoundedProcessRunnerError {
            switch bounded {
            case .secureCleanupUnverified:
                return .secureCleanupUnverified(
                    "\(operation): \(bounded.diagnosticDescription)"
                )
            case .secureContainmentUnavailable:
                return .secureContainmentUnavailable
            default:
                break
            }
        }
        let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
            ?? error.localizedDescription
        return .secureBrokerFailed("\(operation): \(detail)")
    }

    private static func message(for code: Int32) -> String {
        guard let message = strerror(code) else { return "POSIX error \(code)" }
        return String(cString: message)
    }
}

struct BoundedProcessResult: Codable, Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let stdoutWasTruncated: Bool
    let stderrWasTruncated: Bool
    let timedOut: Bool

    static func timeoutResult(
        diagnostic: String?,
        maximumRetainedBytesPerStream: Int
    ) -> BoundedProcessResult {
        let stderrCapture = BoundedCapturedStream(
            limit: maximumRetainedBytesPerStream
        )
        return BoundedProcessResult(
            exitCode: 124,
            stdout: "",
            stderr: stderrCapture.rendered(diagnostic: diagnostic),
            stdoutWasTruncated: false,
            stderrWasTruncated: stderrCapture.renderedWasTruncated(
                diagnostic: diagnostic
            ),
            timedOut: true
        )
    }
}
