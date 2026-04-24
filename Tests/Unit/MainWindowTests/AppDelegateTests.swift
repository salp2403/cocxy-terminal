// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateTests.swift - Tests for AppDelegate lifecycle management.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - AppDelegate Bridge Initialization Tests

/// Tests that the AppDelegate exposes bridge lifecycle state correctly.
@MainActor
final class AppDelegateBridgeTests: XCTestCase {

    func testAppDelegateHasBridgeProperty() {
        let delegate = AppDelegate()
        // Bridge is nil before applicationDidFinishLaunching.
        XCTAssertNil(
            delegate.bridge,
            "Bridge must be nil before app launch"
        )
    }

    func testAppDelegateHasWindowControllerProperty() {
        let delegate = AppDelegate()
        // Window controller is nil before applicationDidFinishLaunching.
        XCTAssertNil(
            delegate.windowController,
            "WindowController must be nil before app launch"
        )
    }

    func testFirstLaunchSetupPrefersInstalledAppForTemporaryBundle() {
        let path = AppDelegate.persistentCLIPathForFirstLaunchSetup(
            bundleCLIPath: "/private/tmp/CocxyTerminalSmoke.app/Contents/Resources/cocxy",
            fileExists: { $0 == AppDelegate.installedAppCLIPath }
        )

        XCTAssertEqual(path, AppDelegate.installedAppCLIPath)
    }

    func testFirstLaunchSetupSkipsTemporaryBundleWithoutInstalledApp() {
        let path = AppDelegate.persistentCLIPathForFirstLaunchSetup(
            bundleCLIPath: "/private/tmp/CocxyTerminalSmoke.app/Contents/Resources/cocxy",
            fileExists: { _ in false }
        )

        XCTAssertNil(path)
    }

    func testFirstLaunchSetupRejectsTemporaryHookCommands() {
        XCTAssertFalse(
            AppDelegate.isAcceptableInstalledHookCommand(
                "'/private/tmp/CocxyTerminalSmoke.app/Contents/Resources/cocxy' hook-handler",
                expectedCommand: "'/Applications/Cocxy Terminal.app/Contents/Resources/cocxy' hook-handler"
            )
        )
    }

    func testFirstLaunchSetupPreservesCustomHookWrappers() {
        XCTAssertTrue(
            AppDelegate.isAcceptableInstalledHookCommand(
                "/usr/local/bin/cocxy-wrapper hook-handler",
                expectedCommand: "'/Applications/Cocxy Terminal.app/Contents/Resources/cocxy' hook-handler"
            )
        )
    }

    func testFirstLaunchSetupReconciliationPreservesCustomWrapperDuringRepair() {
        let wrapperCommand = "/usr/local/bin/cocxy-wrapper hook-handler"
        let staleCommand = "'/private/tmp/CocxyTerminalSmoke.app/Contents/Resources/cocxy' hook-handler"
        let desiredCommand = "'/Applications/Cocxy Terminal.app/Contents/Resources/cocxy' hook-handler"
        let wrapperEntry: [String: Any] = [
            "matcher": "",
            "hooks": [
                ["type": "command", "command": wrapperCommand]
            ]
        ]
        let staleEntry: [String: Any] = [
            "matcher": "",
            "hooks": [
                ["type": "command", "command": staleCommand]
            ]
        ]
        let desiredEntry: [String: Any] = [
            "matcher": "",
            "hooks": [
                ["type": "command", "command": desiredCommand]
            ]
        ]

        let result = AppDelegate.reconciledHookEntries(
            [wrapperEntry, staleEntry],
            desiredEntry: desiredEntry,
            expectedCommand: desiredCommand
        )

        XCTAssertTrue(result.modified)
        XCTAssertEqual(result.entries.count, 1)
        let commands = result.entries[0]["hooks"] as? [[String: Any]]
        XCTAssertEqual(commands?.first?["command"] as? String, wrapperCommand)
    }
}
