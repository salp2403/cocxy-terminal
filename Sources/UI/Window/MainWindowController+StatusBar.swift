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

        if let activeTab = tabManager.activeTab,
           activeTab.agentState != .idle {
            let agentName = activeTab.detectedAgent?.name
                ?? activeTab.processName
                ?? "Agent"
            let statusText: String
            switch activeTab.agentState {
            case .launched:
                statusText = "\(agentName) starting..."
            case .working:
                statusText = activeTab.agentActivity ?? "\(agentName) working"
            case .waitingInput:
                statusText = "\(agentName) waiting for input"
            case .finished:
                statusText = "\(agentName) finished"
            case .error:
                statusText = "\(agentName) error"
            case .idle:
                statusText = ""
            }

            summary.activeAgentText = statusText.isEmpty ? nil : statusText
            summary.activeToolCount = activeTab.agentToolCount
            summary.activeErrorCount = activeTab.agentErrorCount

            switch activeTab.agentState {
            case .working, .launched:
                summary.activeAgentColor = CocxyColors.blue
            case .waitingInput:
                summary.activeAgentColor = CocxyColors.yellow
            case .finished:
                summary.activeAgentColor = CocxyColors.green
            case .error:
                summary.activeAgentColor = CocxyColors.red
            case .idle:
                summary.activeAgentColor = CocxyColors.overlay1
            }
        }

        return summary
    }

    /// Refreshes the status bar content.
    func refreshStatusBar() {
        let activeTab = tabManager.activeTab
        let isTransparent = configService?.current.appearance.backgroundOpacity ?? 1.0 < 1.0
        var statusBar = StatusBarView(
            hostname: currentHostname(),
            gitBranch: activeTab?.gitBranch,
            agentSummary: computeAgentSummary(),
            activePorts: portScanner?.activePorts ?? [],
            sshSession: activeTab?.sshSession,
            lastCommandDuration: activeTab?.lastCommandDuration,
            lastCommandExitCode: activeTab?.lastCommandExitCode,
            isCommandRunning: activeTab?.isCommandRunning ?? false
        )
        statusBar.useVibrancy = isTransparent
        statusBarHostingView?.rootView = statusBar
    }
}
