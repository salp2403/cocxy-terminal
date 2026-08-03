// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorWebLocalization.swift - Immutable phone-client localization payload.

import Foundation

struct MobileMirrorWebLocalization: Equatable, Sendable {
    let locale: String
    let direction: String
    let catalog: [String: String]

    init(localizer: AppLocalizer) {
        locale = localizer.resolvedLanguage.rawValue
        direction = localizer.isRightToLeft ? "rtl" : "ltr"
        catalog = Dictionary(uniqueKeysWithValues: Self.entries.map { entry in
            (entry.key, localizer.string(entry.key, fallback: entry.fallback))
        })
    }

    init(locale: String, direction: String, catalog: [String: String]) {
        self.locale = locale
        self.direction = direction == "rtl" ? "rtl" : "ltr"
        self.catalog = catalog
    }

    func text(_ key: String) -> String {
        catalog[key] ?? Self.fallbackCatalog[key] ?? key
    }

    static let english = MobileMirrorWebLocalization(
        locale: "en",
        direction: "ltr",
        catalog: fallbackCatalog
    )

    private static let fallbackCatalog = Dictionary(uniqueKeysWithValues: entries.map {
        ($0.key, $0.fallback)
    })

    private static let entries: [(key: String, fallback: String)] = [
        ("common.close", "Close"),
        ("common.create", "Create"),
        ("agent.panel.approval.response.placeholder", "Response"),
        ("agent.panel.approval.send", "Send"),
        ("agent.panel.approval.approve", "Approve"),
        ("agent.panel.approval.reject", "Reject"),
        ("agent.panel.message.agent", "Agent"),
        ("agentDashboard.state.idle", "Idle"),
        ("agentDashboard.state.launching", "Launching"),
        ("agentDashboard.state.working", "Working"),
        ("agentDashboard.state.waitingForInput", "Waiting for input"),
        ("agentDashboard.state.finished", "Finished"),
        ("agentDashboard.state.error", "Error"),
        ("quickSwitch.kind.project", "Project"),
        ("preferences.section.notifications", "Notifications"),
        ("preferences.section.terminal", "Terminal"),
        ("remoteWorkspace.status.connected", "Connected"),
        ("remoteWorkspace.status.connecting", "Connecting"),
        ("remoteWorkspace.status.disconnected", "Disconnected"),
        ("mobile.mirror.confirm.title", "Confirm this phone"),
        ("mobile.mirror.status.confirmation", "Desktop confirmation required"),
        ("mobile.mirror.status.denied", "Pairing denied"),
        ("mobile.web.projects.open", "Open projects"),
        ("mobile.web.notifications.enable", "Enable local notifications"),
        ("mobile.web.notifications.enabled", "Local notifications enabled"),
        ("mobile.web.notifications.blocked", "Notifications are blocked in this browser"),
        ("mobile.web.notifications.unavailable", "Notifications are unavailable"),
        ("mobile.web.projects.accessibility", "Projects and agents"),
        ("mobile.web.projects.title", "Projects"),
        ("mobile.web.projects.liveSessions", "Live local sessions"),
        ("mobile.web.approvals.title", "Approvals"),
        ("mobile.web.project.new", "New project"),
        ("mobile.web.project.name", "Project name"),
        ("mobile.web.project.creationUnavailable", "Choose a creation folder on the Mac first."),
        ("mobile.web.terminal.localSession", "Local session"),
        ("mobile.web.terminal.keys", "Terminal keys"),
        ("mobile.web.terminal.input", "Type in terminal"),
        ("mobile.web.direction.left", "Left"),
        ("mobile.web.direction.up", "Up"),
        ("mobile.web.direction.down", "Down"),
        ("mobile.web.direction.right", "Right"),
        ("mobile.web.status.authenticationFailed", "Authentication failed"),
        ("mobile.web.status.inputRejected", "Input rejected"),
        ("mobile.web.status.syncing", "Syncing..."),
        ("mobile.web.status.unavailable", "Web terminal unavailable"),
        ("mobile.web.projects.empty", "No local projects or live agents"),
        ("mobile.web.agents.empty", "No live agents"),
        ("mobile.web.agent.reply", "Reply"),
        ("mobile.web.notification.agentUpdate", "Agent update"),
        ("mobile.web.notification.stateChanged", "Agent state changed"),
        ("mobile.web.notification.approvalRequested", "Approval requested"),
        ("mobile.web.approval.title", "Approval"),
        ("mobile.web.error.signedInputUnavailable", "Signed mobile input is unavailable"),
        ("mobile.web.error.actionRejected", "Mobile action was rejected"),
        ("mobile.web.error.noTerminal", "No terminal session is selected"),
        ("mobile.web.error.stateUnavailable", "Mobile state is unavailable"),
    ]
}
