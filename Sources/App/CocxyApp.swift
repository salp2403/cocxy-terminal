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
        let delegate = AppDelegate()
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
