// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyApp.swift - Application entry point.

import AppKit

/// Entry point for Cocxy Terminal.
///
/// Uses `NSApplicationMain`-equivalent approach via `@main` attribute.
/// The `AppDelegate` handles all lifecycle events and window creation.
@main
struct CocxyApp {
    static func main() {
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
