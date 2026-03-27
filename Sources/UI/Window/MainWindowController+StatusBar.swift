// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+StatusBar.swift - Status bar content and refresh logic.

import AppKit

// MARK: - Status Bar

/// Extension that manages the bottom status bar content: hostname,
/// git branch, agent summary, and active port indicators.
extension MainWindowController {

    /// Returns the current username@hostname string.
    func currentHostname() -> String {
        let user = NSUserName()
        let host = Host.current().localizedName ?? "mac"
        return "\(user)@\(host)"
    }

    /// Computes agent activity summary across all tabs.
    func computeAgentSummary() -> AgentSummary {
        var summary = AgentSummary()
        for tab in tabManager.tabs {
            switch tab.agentState {
            case .working, .launched:
                summary.working += 1
            case .waitingInput:
                summary.waiting += 1
            case .error:
                summary.errors += 1
            case .finished:
                summary.finished += 1
            case .idle:
                break
            }
        }
        return summary
    }

    /// Refreshes the status bar content.
    func refreshStatusBar() {
        let activeTab = tabManager.activeTab
        let statusBar = StatusBarView(
            hostname: currentHostname(),
            gitBranch: activeTab?.gitBranch,
            agentSummary: computeAgentSummary(),
            activePorts: portScanner?.activePorts ?? [],
            sshSession: activeTab?.sshSession,
            lastCommandDuration: activeTab?.lastCommandDuration,
            lastCommandExitCode: activeTab?.lastCommandExitCode,
            isCommandRunning: activeTab?.isCommandRunning ?? false
        )
        statusBarHostingView?.rootView = statusBar
    }
}
