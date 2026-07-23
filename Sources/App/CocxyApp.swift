// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyApp.swift - Application entry point.

import AppKit
import Darwin

/// Entry point for Cocxy Terminal.
///
/// Uses `NSApplicationMain`-equivalent approach via `@main` attribute.
/// The `AppDelegate` handles all lifecycle events and window creation.
@main
struct CocxyApp {
    static func main() {
        if let sftpMuxExitCode = SFTPMuxSessionEntry.runIfRequested() {
            exit(sftpMuxExitCode)
        }
        if let brokerExitCode = LaunchdProcessBrokerEntry.runIfRequested() {
            exit(brokerExitCode)
        }
        if let supervisorExitCode = LaunchdProcessSupervisorEntry.runIfRequested() {
            exit(supervisorExitCode)
        }

        if ProcessInfo.processInfo.environment[SSHAskpassContract.environmentKey]
            == SSHAskpassContract.environmentValue {
            var passphrase = Data()
            while passphrase.count <= SSHAskpassContract.maximumPassphraseBytes {
                guard let next = try? FileHandle.standardInput.read(upToCount: 1),
                      let byte = next.first else {
                    exit(EXIT_FAILURE)
                }
                if byte == 0x0A {
                    FileHandle.standardOutput.write(passphrase)
                    FileHandle.standardOutput.write(Data([0x0A]))
                    return
                }
                passphrase.append(byte)
            }
            if passphrase.count > SSHAskpassContract.maximumPassphraseBytes {
                exit(EXIT_FAILURE)
            }
        }

        // When running under XCTest via `swift test`, the test runner loads
        // this module and invokes @main. We must detect this and skip
        // NSApplication.run() which would block the test runner forever.
        //
        // The xctest process name is always "xctest" (set by the runner).
        // CommandLine.arguments[0] also contains "xctest" in the path.
        let executablePath = CommandLine.arguments.first ?? ""
        let isRunningTests = executablePath.contains("xctest")

        if isRunningTests {
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        do {
            try LaunchdProcessArtifacts.reconcileAbandonedExecutions()
        } catch {
            let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
                ?? error.localizedDescription
            do {
                try LaunchdLocalExecutionGate.shared.block(reason: detail)
            } catch let persistenceError {
                let persistenceDetail = (persistenceError as? BoundedProcessRunnerError)?
                    .diagnosticDescription ?? persistenceError.localizedDescription
                fputs(
                    "Cocxy could not persist the local execution safety block: "
                        + "\(persistenceDetail)\n",
                    stderr
                )
            }
            fputs(
                "Cocxy could not verify cleanup of a previous local execution.\n",
                stderr
            )
            let localizer = AppLocalizer(languagePreference: .system)
            let alert = NSAlert()
            alert.messageText = localizer.string(
                "app.localExecution.cleanupFailure.title",
                fallback: "Previous Local Execution Needs Attention"
            )
            alert.informativeText = localizer.string(
                "app.localExecution.cleanupFailure.message",
                fallback: "Cocxy could not verify cleanup from a previous notebook or workflow. Local code execution will remain disabled, but the rest of Cocxy is available. Close other running copies of Cocxy and restart your Mac before trying local execution again."
            )
            alert.alertStyle = .critical
            alert.icon = AppIconGenerator.generatePlaceholderIcon()
            alert.addButton(
                withTitle: localizer.string("app.continue.button", fallback: "Continue")
            )
            alert.addButton(withTitle: localizer.string("app.quit.button", fallback: "Quit"))
            app.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                exit(EXIT_FAILURE)
            }
        }

        let delegate = AppDelegate()
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
