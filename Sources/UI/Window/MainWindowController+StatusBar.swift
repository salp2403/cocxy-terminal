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
    ///
    /// Every tab is resolved through `resolveSurfaceAgentState(for:)`
    /// so splits running independent agents contribute via their most
    /// relevant surface (focused > primary > any active > `.idle`).
    /// An idle tab produces no counter increment, so the summary stays
    /// accurate whether the per-surface store is populated or not.
    func computeAgentSummary() -> AgentSummary {
        var summary = AgentSummary()
        for tab in tabManager.tabs {
            let resolved = resolveSurfaceAgentState(for: tab.id)
            switch AgentStatusTextFormatter.counterBucket(for: resolved.agentState) {
            case .working?:
                summary.working += 1
            case .waiting?:
                summary.waiting += 1
            case .errors?:
                summary.errors += 1
            case .finished?:
                summary.finished += 1
            case nil:
                break
            }
        }

        if let activeTab = tabManager.activeTab {
            let resolved = resolveSurfaceAgentState(for: activeTab.id)

            // `processName` stays on the Tab fallback path during Fase 3
            // because foreground-process tracking is not mirrored into
            // the per-surface store in this phase. Using the resolved
            // detected agent first keeps the label synced with whichever
            // split the resolver picked.
            let agentName = resolved.detectedAgent?.displayName
                ?? activeTab.processName
                ?? "Agent"

            summary.activeAgentText = AgentStatusTextFormatter.activeAgentStatusText(
                state: resolved.agentState,
                agentName: agentName,
                agentActivity: resolved.agentActivity
            )
            summary.activeToolCount = resolved.agentToolCount
            summary.activeErrorCount = resolved.agentErrorCount

            switch resolved.agentState {
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
