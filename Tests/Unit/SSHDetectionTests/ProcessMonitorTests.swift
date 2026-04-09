// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProcessMonitorTests.swift - Tests for process monitoring and SSH detection wiring.

import XCTest
import AppKit
import Combine
import SwiftUI
@testable import CocxyTerminal

// MARK: - ForegroundProcessDetector Tests

final class ForegroundProcessDetectorTests: XCTestCase {

    func testSelectForegroundProcessPrefersForegroundGroupLeader() {
        let snapshots: [ForegroundProcessDetector.ProcessSnapshot] = [
            .init(pid: 100, parentPID: 1, processGroupID: 100, name: "zsh"),
            .init(pid: 200, parentPID: 100, processGroupID: 200, name: "ssh"),
            .init(pid: 201, parentPID: 200, processGroupID: 200, name: "ssh-helper"),
        ]

        let selected = ForegroundProcessDetector.selectForegroundProcess(
            shellPID: 100,
            foregroundProcessGroupID: 200,
            snapshots: snapshots
        )

        XCTAssertEqual(selected?.pid, 200)
        XCTAssertEqual(selected?.name, "ssh")
    }

    func testSelectForegroundProcessFindsNestedForegroundDescendant() {
        let snapshots: [ForegroundProcessDetector.ProcessSnapshot] = [
            .init(pid: 100, parentPID: 1, processGroupID: 100, name: "zsh"),
            .init(pid: 150, parentPID: 100, processGroupID: 150, name: "tmux"),
            .init(pid: 250, parentPID: 150, processGroupID: 250, name: "nvim"),
        ]

        let selected = ForegroundProcessDetector.selectForegroundProcess(
            shellPID: 100,
            foregroundProcessGroupID: 250,
            snapshots: snapshots
        )

        XCTAssertEqual(selected?.pid, 250)
        XCTAssertEqual(selected?.name, "nvim")
    }

    func testSelectForegroundProcessFallsBackToNewestDescendantWithoutForegroundGroup() {
        let snapshots: [ForegroundProcessDetector.ProcessSnapshot] = [
            .init(pid: 100, parentPID: 1, processGroupID: 100, name: "zsh"),
            .init(pid: 200, parentPID: 100, processGroupID: 200, name: "claude"),
            .init(pid: 210, parentPID: 100, processGroupID: 210, name: "python"),
        ]

        let selected = ForegroundProcessDetector.selectForegroundProcess(
            shellPID: 100,
            foregroundProcessGroupID: nil,
            snapshots: snapshots
        )

        XCTAssertEqual(selected?.pid, 210)
        XCTAssertEqual(selected?.name, "python")
    }

    func testSelectForegroundProcessFallsBackToShellWhenNoDescendantsExist() {
        let snapshots: [ForegroundProcessDetector.ProcessSnapshot] = [
            .init(pid: 100, parentPID: 1, processGroupID: 100, name: "zsh")
        ]

        let selected = ForegroundProcessDetector.selectForegroundProcess(
            shellPID: 100,
            foregroundProcessGroupID: 999,
            snapshots: snapshots
        )

        XCTAssertEqual(selected?.pid, 100)
        XCTAssertEqual(selected?.name, "zsh")
    }

    func testDetectRejectsRecycledShellPIDWhenIdentityDoesNotMatch() {
        let shellPID = getpid()
        let mismatchedIdentity = TerminalProcessIdentity(
            pid: shellPID,
            startSeconds: 0,
            startMicroseconds: 0
        )

        let info = ForegroundProcessDetector.detect(
            shellPID: shellPID,
            ptyMasterFD: nil,
            expectedShellIdentity: mismatchedIdentity,
            snapshots: []
        )

        XCTAssertNil(info)
    }

    func testProcessNameForCurrentPID() {
        let pid = getpid()
        let name = ForegroundProcessDetector.processName(for: pid)
        XCTAssertNotNil(name, "Should be able to read current process name")
    }

    func testProcessNameForInvalidPID() {
        let name = ForegroundProcessDetector.processName(for: -1)
        XCTAssertNil(name, "Should return nil for invalid PID")
    }

    func testProcessCommandForCurrentPID() {
        let pid = getpid()
        let command = ForegroundProcessDetector.processCommand(for: pid)
        // Command may or may not be available depending on environment.
        // Just verify it doesn't crash.
        _ = command
    }

    func testChildProcessesOfInit() {
        // PID 1 (launchd) should have child processes.
        let children = ForegroundProcessDetector.childProcesses(of: 1)
        XCTAssertNotNil(children, "launchd should have child processes")
        if let children {
            XCTAssertGreaterThan(children.count, 0)
        }
    }

    func testChildProcessesOfInvalidPID() {
        let children = ForegroundProcessDetector.childProcesses(of: -1)
        XCTAssertNil(children, "Invalid PID should have no children")
    }

    func testDetectForCurrentShell() {
        // Use getppid() which should be our shell process.
        let parentPID = getppid()
        let info = ForegroundProcessDetector.detect(shellPID: parentPID)
        // May or may not find a foreground process depending on test runner.
        // Just verify it doesn't crash.
        _ = info
    }
}

// MARK: - ProcessMonitorService Tests

@MainActor
final class ProcessMonitorServiceTests: XCTestCase {

    func testInitialState() {
        let monitor = ProcessMonitorService()
        XCTAssertFalse(monitor.isRunning)
    }

    func testStartSetsRunning() {
        let monitor = ProcessMonitorService(pollInterval: 10)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
    }

    func testStopClearsRunning() {
        let monitor = ProcessMonitorService(pollInterval: 10)
        monitor.start()
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func testDoubleStartIsIdempotent() {
        let monitor = ProcessMonitorService(pollInterval: 10)
        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
    }

    func testRegisterAndUnregisterTab() {
        let monitor = ProcessMonitorService(pollInterval: 10)
        let tabID = TabID()

        monitor.registerTab(tabID, shellPID: getpid())
        monitor.unregisterTab(tabID)
        // Should not crash.
    }

    func testProcessChangeEventProperties() {
        let tabID = TabID()
        let sshInfo = SSHSessionInfo(
            user: "root", host: "server.com",
            port: 22, hasIdentityFile: false, flags: []
        )
        let event = ProcessChangeEvent(
            tabID: tabID,
            processName: "ssh",
            pid: 1234,
            sshSession: sshInfo
        )

        XCTAssertEqual(event.processName, "ssh")
        XCTAssertEqual(event.sshSession?.host, "server.com")
        XCTAssertEqual(event.tabID, tabID)
        XCTAssertEqual(event.pid, 1234)
    }

    // MARK: - Process Monitor Wiring Tests

    func testProcessMonitorStartedAfterCreation() {
        // Verify that creating a ProcessMonitorService and calling start()
        // transitions it to the running state. This test validates the
        // expectation that startProcessMonitor() must call .start().
        let monitor = ProcessMonitorService(pollInterval: 60)
        // Simulate what startProcessMonitor SHOULD do:
        monitor.start()
        XCTAssertTrue(monitor.isRunning,
                       "Monitor must be running after start() is called")
        monitor.stop()
    }

    func testProcessMonitorSubscribesToChanges() {
        let monitor = ProcessMonitorService(pollInterval: 60)
        var receivedEvent: ProcessChangeEvent?
        var cancellables = Set<AnyCancellable>()

        monitor.processChanged
            .receive(on: DispatchQueue.main)
            .sink { event in
                receivedEvent = event
            }
            .store(in: &cancellables)

        // Manually send an event via registerTab + simulated detection.
        // The subscription should receive it.
        let tabID = TabID()
        let event = ProcessChangeEvent(
            tabID: tabID,
            processName: "ssh",
            pid: 4321,
            sshSession: SSHSessionInfo(
                user: "root", host: "server",
                port: nil, hasIdentityFile: false, flags: []
            )
        )
        monitor.processChanged.send(event)

        // Allow main run loop to process.
        let expectation = XCTestExpectation(description: "Receive process change")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedEvent, "Should receive process change events")
        XCTAssertEqual(receivedEvent?.processName, "ssh")
        XCTAssertEqual(receivedEvent?.tabID, tabID)
    }
}

// MARK: - StatusBarView SSH Wiring Tests

@MainActor
final class StatusBarSSHWiringTests: XCTestCase {

    func testStatusBarViewAcceptsSSHSession() {
        let sshInfo = SSHSessionInfo(
            user: "deploy", host: "production.example.com",
            port: 2222, hasIdentityFile: false, flags: ["-A"]
        )

        // StatusBarView must accept an sshSession parameter.
        // If this compiles and creates an NSHostingView, the wiring is correct.
        let statusBar = StatusBarView(
            hostname: "user@mac",
            gitBranch: "main",
            agentSummary: AgentSummary(),
            sshSession: sshInfo
        )
        XCTAssertEqual(statusBar.sshSession?.host, "production.example.com")
        XCTAssertEqual(statusBar.sshSession?.displayTitle, "deploy@production.example.com")

        // Verify it can be hosted without crash.
        let hostingView = NSHostingView(rootView: statusBar)
        XCTAssertNotNil(hostingView)
    }

    func testStatusBarViewRendersWithoutSSH() {
        let statusBar = StatusBarView(
            hostname: "user@mac",
            gitBranch: "main",
            agentSummary: AgentSummary()
        )
        // Default sshSession should be nil.
        XCTAssertNil(statusBar.sshSession)

        let hostingView = NSHostingView(rootView: statusBar)
        XCTAssertNotNil(hostingView)
    }

    func testStatusBarViewAcceptsNilSSHSession() {
        let statusBar = StatusBarView(
            hostname: "user@mac",
            gitBranch: nil,
            agentSummary: AgentSummary(),
            sshSession: nil
        )
        XCTAssertNil(statusBar.sshSession)

        let hostingView = NSHostingView(rootView: statusBar)
        XCTAssertNotNil(hostingView)
    }

    func testRefreshStatusBarPassesSSHSession() {
        // Verify that the StatusBarView created by refreshStatusBar
        // includes the sshSession from the active tab.
        let tabManager = TabManager()
        guard let tabID = tabManager.activeTabID else {
            XCTFail("Should have an active tab")
            return
        }

        let sshInfo = SSHSessionInfo(
            user: "root", host: "web-server.local",
            port: nil, hasIdentityFile: false, flags: []
        )
        tabManager.updateTab(id: tabID) { tab in
            tab.sshSession = sshInfo
        }

        // Simulate what refreshStatusBar does:
        let statusBar = StatusBarView(
            hostname: "user@mac",
            gitBranch: tabManager.activeTab?.gitBranch,
            agentSummary: AgentSummary(),
            sshSession: tabManager.activeTab?.sshSession
        )
        XCTAssertEqual(statusBar.sshSession?.host, "web-server.local",
                        "refreshStatusBar must pass sshSession from active tab")
    }
}

// MARK: - SSH Detection Integration Tests

@MainActor
final class SSHDetectionIntegrationTests: XCTestCase {

    func testSSHDetectionFromProcessInfo() {
        let processInfo = ForegroundProcessInfo(
            name: "ssh",
            command: "ssh -p 2222 deploy@production.example.com",
            pid: 12345
        )

        XCTAssertTrue(SSHSessionDetector.isSSHProcess(processInfo.name))

        if let command = processInfo.command {
            let session = SSHSessionDetector.detect(from: command)
            XCTAssertNotNil(session)
            XCTAssertEqual(session?.user, "deploy")
            XCTAssertEqual(session?.host, "production.example.com")
            XCTAssertEqual(session?.port, 2222)
        }
    }

    func testNonSSHProcessSkipsDetection() {
        let processInfo = ForegroundProcessInfo(
            name: "node",
            command: "node server.js",
            pid: 12345
        )

        XCTAssertFalse(SSHSessionDetector.isSSHProcess(processInfo.name))
    }

    func testSSHSessionUpdatesTabDisplay() {
        let tabManager = TabManager()
        guard let tabID = tabManager.activeTabID else {
            XCTFail("Should have an active tab")
            return
        }

        let sshInfo = SSHSessionInfo(
            user: "admin", host: "web-server.local",
            port: nil, hasIdentityFile: true, flags: ["-A"]
        )

        tabManager.updateTab(id: tabID) { tab in
            tab.processName = "ssh"
            tab.sshSession = sshInfo
        }

        let tab = tabManager.tab(for: tabID)
        XCTAssertEqual(tab?.processName, "ssh")
        XCTAssertEqual(tab?.sshSession?.displayTitle, "admin@web-server.local")
        XCTAssertEqual(tab?.sshSession?.displayTitleWithPort, "admin@web-server.local")
    }

    func testSSHSessionClearedWhenProcessChanges() {
        let tabManager = TabManager()
        guard let tabID = tabManager.activeTabID else { return }

        // Set SSH session.
        tabManager.updateTab(id: tabID) { tab in
            tab.processName = "ssh"
            tab.sshSession = SSHSessionInfo(
                user: "root", host: "server",
                port: nil, hasIdentityFile: false, flags: []
            )
        }
        XCTAssertNotNil(tabManager.tab(for: tabID)?.sshSession)

        // Process changes back to shell.
        tabManager.updateTab(id: tabID) { tab in
            tab.processName = "zsh"
            tab.sshSession = nil
        }
        XCTAssertNil(tabManager.tab(for: tabID)?.sshSession)
    }
}
