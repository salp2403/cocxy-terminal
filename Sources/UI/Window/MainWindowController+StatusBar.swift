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
    /// Every active surface contributes independently. This is
    /// intentionally broader than `resolveSurfaceAgentState(for:)`,
    /// because that resolver chooses the best single surface for the
    /// primary pill while the status bar summary is an app-wide count.
    /// A tab with Claude in one split and Codex in another must report
    /// two active agents, not whichever split won the resolver priority.
    func computeAgentSummary() -> AgentSummary {
        var summary = AgentSummary()

        func increment(_ state: AgentState) {
            switch AgentStatusTextFormatter.counterBucket(for: state) {
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

        for tab in tabManager.tabs {
            let snapshots = allActiveAgentSnapshots(for: tab.id)
            if snapshots.isEmpty {
                increment(resolveSurfaceAgentState(for: tab.id).agentState)
            } else {
                snapshots.forEach { increment($0.state.agentState) }
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

            // Populate the per-split mini-matrix with every active
            // agent of the active tab (including the surface that
            // drove the primary pill). The status bar view renders
            // the matrix only when two or more snapshots are present
            // so single-split tabs keep the compact layout.
            summary.perSurfaceSnapshots = allActiveAgentSnapshots(for: activeTab.id)
        }

        return summary
    }

    /// Refreshes the status bar content.
    func refreshStatusBar() {
        let activeTab = tabManager.activeTab
        let appearance = configService?.current.appearance
        let isTransparent = (appearance?.backgroundOpacity ?? 1.0) < 1.0
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
        statusBar.vibrancyAppearanceOverride = isTransparent
            ? appearance?.transparencyChromeTheme.vibrancyAppearance
            : nil
        statusBarHostingView?.rootView = statusBar
    }
}
