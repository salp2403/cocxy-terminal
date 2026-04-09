// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProcessMonitorService.swift - Periodically monitors foreground processes in tabs.

import Foundation
import Combine

// MARK: - Process Monitor Service

/// Periodically checks the foreground process of each terminal tab.
///
/// Runs a timer that queries the PTY's foreground process group every
/// `pollInterval` seconds. When the process changes, it updates:
/// - `Tab.processName` with the new process name.
/// - `Tab.sshSession` with parsed SSH connection info (if SSH is detected).
///
/// ## Architecture
///
/// The monitor runs on the main actor and publishes process changes via
/// Combine. `MainWindowController` subscribes to these changes and updates
/// the tab bar accordingly.
///
/// ## Poll Interval
///
/// The default interval is 2 seconds, which balances responsiveness with
/// CPU overhead. Process detection uses `sysctl` which is lightweight.
///
/// - SeeAlso: `ForegroundProcessDetector` for the detection mechanism.
/// - SeeAlso: `SSHSessionDetector` for SSH command parsing.
@MainActor
final class ProcessMonitorService: ObservableObject {

    struct TabProcessRegistration: Equatable, Sendable {
        let shellPID: pid_t
        let ptyMasterFD: Int32?
        let shellIdentity: TerminalProcessIdentity?
    }

    // MARK: - Published State

    /// Emits when a process change is detected for a tab.
    let processChanged = PassthroughSubject<ProcessChangeEvent, Never>()

    // MARK: - Properties

    /// The interval between process checks.
    let pollInterval: TimeInterval

    /// Maps tab IDs to the PTY/shell metadata needed for process monitoring.
    private var tabRegistrations: [TabID: TabProcessRegistration] = [:]

    /// Last known process name per tab (to detect changes).
    private var lastKnownProcess: [TabID: String] = [:]

    /// The polling timer.
    private var timer: Timer?

    /// Whether the monitor is currently running.
    private(set) var isRunning: Bool = false

    // MARK: - Initialization

    init(pollInterval: TimeInterval = 2.0) {
        self.pollInterval = pollInterval
    }

    // MARK: - Lifecycle

    /// Starts monitoring foreground processes.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self?.pollProcesses()
            }
        }
    }

    /// Stops monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    // MARK: - Tab Registration

    /// Registers a tab for process monitoring.
    ///
    /// - Parameters:
    ///   - tabID: The tab to monitor.
    ///   - shellPID: The PID of the shell running in this tab's PTY.
    ///   - ptyMasterFD: The master PTY file descriptor, when available.
    func registerTab(
        _ tabID: TabID,
        shellPID: pid_t,
        ptyMasterFD: Int32? = nil,
        shellIdentity: TerminalProcessIdentity? = nil
    ) {
        tabRegistrations[tabID] = TabProcessRegistration(
            shellPID: shellPID,
            ptyMasterFD: ptyMasterFD,
            shellIdentity: shellIdentity
        )
        lastKnownProcess[tabID] = nil
    }

    /// Unregisters a tab from monitoring.
    func unregisterTab(_ tabID: TabID) {
        tabRegistrations.removeValue(forKey: tabID)
        lastKnownProcess.removeValue(forKey: tabID)
    }

    // MARK: - Polling

    private func pollProcesses() {
        let snapshots = ForegroundProcessDetector.processSnapshots() ?? []

        for (tabID, registration) in tabRegistrations {
            guard let processInfo = ForegroundProcessDetector.detect(
                shellPID: registration.shellPID,
                ptyMasterFD: registration.ptyMasterFD,
                expectedShellIdentity: registration.shellIdentity,
                snapshots: snapshots
            ) else {
                continue
            }

            let previousName = lastKnownProcess[tabID]

            // Only emit if the process name changed.
            if processInfo.name != previousName {
                lastKnownProcess[tabID] = processInfo.name

                // Detect SSH session if the process is SSH.
                var sshSession: SSHSessionInfo?
                if SSHSessionDetector.isSSHProcess(processInfo.name) {
                    if let command = processInfo.command {
                        sshSession = SSHSessionDetector.detect(from: command)
                    }
                }

                processChanged.send(ProcessChangeEvent(
                    tabID: tabID,
                    processName: processInfo.name,
                    pid: processInfo.pid,
                    sshSession: sshSession
                ))
            }
        }
    }
}

// MARK: - Process Change Event

/// Event emitted when a tab's foreground process changes.
struct ProcessChangeEvent: Sendable {
    /// The tab whose process changed.
    let tabID: TabID
    /// The new process name.
    let processName: String
    /// PID of the detected foreground process.
    let pid: pid_t
    /// SSH session info, if the new process is an SSH client.
    let sshSession: SSHSessionInfo?
}
