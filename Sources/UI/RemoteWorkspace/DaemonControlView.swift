// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonControlView.swift - UI for remote daemon management.

import SwiftUI

// MARK: - Daemon Control View

/// Sub-panel for managing the remote cocxyd daemon.
///
/// Connected to `DaemonManagerImpl` for real deployment and session operations.
/// Shows daemon status, deploy/start/stop buttons, session list, forward list,
/// and file sync watchers.
struct DaemonControlView: View {

    let profileID: UUID
    @ObservedObject var viewModel: RemoteConnectionViewModel
    @ObservedObject var daemonManager: DaemonManagerImpl

    @State private var errorMessage: String?
    @State private var isDeploying = false
    @State private var sessions: [DaemonSessionInfo] = []
    @State private var isLoadingSessions = false
    @State private var newSessionTitle = ""
    @State private var newForwardSpec = ""
    @State private var newSyncPath = ""
    @State private var forwards: [[String: Any]] = []
    @State private var syncChanges: [[String: Any]] = []

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                connectionGate
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var connectionGate: some View {
        if viewModel.isConnected(profileID) {
            statusSection
            Divider()
            controlSection
            Divider()
            sessionsSection
            Divider()
            forwardsSection
            Divider()
            syncSection
            if let errorMessage {
                Divider()
                errorSection(errorMessage)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "server.rack")
                    .font(.system(size: 24))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text("Connect to the profile first to manage the daemon")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Spacer()
        }
    }

    private var stateColor: Color {
        switch daemonManager.state {
        case .notDeployed: return Color(nsColor: CocxyColors.overlay1)
        case .deploying, .upgrading: return Color.yellow
        case .running: return Color.green
        case .stopped: return Color.orange
        case .unreachable: return Color.red
        }
    }

    private var stateText: String {
        switch daemonManager.state {
        case .notDeployed: return "Not Deployed"
        case .deploying: return "Deploying..."
        case .running(let version, let uptime):
            let uptimeStr = formatUptime(uptime)
            return "Running v\(version) (\(uptimeStr))"
        case .stopped: return "Stopped"
        case .upgrading: return "Upgrading..."
        case .unreachable: return "Unreachable"
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Controls")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            HStack(spacing: 8) {
                switch daemonManager.state {
                case .notDeployed, .stopped, .unreachable:
                    actionButton("Deploy & Start", icon: "arrow.up.circle", action: deployDaemon)
                case .running:
                    actionButton("Stop", icon: "stop.circle", action: stopDaemon)
                    actionButton("Upgrade", icon: "arrow.triangle.2.circlepath", action: upgradeDaemon)
                case .deploying, .upgrading:
                    ProgressView()
                        .controlSize(.small)
                    Text("Please wait...")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(Color(nsColor: CocxyColors.mauve))
        .disabled(isDeploying)
    }

    // MARK: - Sessions Section

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Remote Sessions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                if isDaemonRunning {
                    Button(action: refreshSessions) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: CocxyColors.mauve))
                    .disabled(isLoadingSessions)
                }
            }

            if isDaemonRunning {
                // Create session form.
                HStack(spacing: 4) {
                    TextField("Session name", text: $newSessionTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .frame(maxWidth: 120)
                    Button(action: createSession) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: CocxyColors.green))
                    .disabled(isLoadingSessions)
                }

                if isLoadingSessions {
                    ProgressView()
                        .controlSize(.small)
                } else if sessions.isEmpty {
                    Text("No active sessions")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                } else {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            } else {
                Text("Deploy the daemon to manage persistent sessions.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }
        }
    }

    private func sessionRow(_ session: DaemonSessionInfo) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.status == "running" ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(session.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Text("PID \(session.pid)")
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            Spacer()
            Button(action: { killSession(session.id) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: CocxyColors.red))
        }
    }

    // MARK: - Forwards Section

    private var forwardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Persistent Forwards")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                if isDaemonRunning {
                    Button(action: refreshForwards) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: CocxyColors.mauve))
                }
            }

            if isDaemonRunning {
                HStack(spacing: 4) {
                    TextField("local:remote", text: $newForwardSpec)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .frame(maxWidth: 120)
                    Button(action: addForward) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: CocxyColors.green))
                    .disabled(newForwardSpec.isEmpty)
                }

                if forwards.isEmpty {
                    Text("No persistent forwards")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                } else {
                    ForEach(Array(forwards.enumerated()), id: \.offset) { _, fwd in
                        forwardRow(fwd)
                    }
                }
            } else {
                Text("Deploy the daemon to manage persistent forwards.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }
        }
    }

    private func forwardRow(_ fwd: [String: Any]) -> some View {
        let local = fwd["local"] as? Int ?? 0
        let remote = fwd["remote"] as? Int ?? 0
        let host = fwd["host"] as? String ?? "localhost"
        return HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.blue))
            Text(verbatim: "\(local) → \(remote)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Text(host)
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            Spacer()
            Button(action: { removeForward("\(local):\(remote)") }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: CocxyColors.red))
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("File Sync Watch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                if isDaemonRunning {
                    Button(action: checkSyncChanges) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: CocxyColors.mauve))
                }
            }

            if isDaemonRunning {
                HStack(spacing: 4) {
                    TextField("Remote path to watch", text: $newSyncPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .frame(maxWidth: 180)
                    Button(action: addSyncWatch) {
                        Image(systemName: "eye")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(nsColor: CocxyColors.green))
                    .disabled(newSyncPath.isEmpty)
                }

                if syncChanges.isEmpty {
                    Text("No recent changes detected")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                } else {
                    ForEach(Array(syncChanges.prefix(10).enumerated()), id: \.offset) { _, change in
                        syncChangeRow(change)
                    }
                }
            } else {
                Text("Deploy the daemon to use file sync.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }
        }
    }

    private func syncChangeRow(_ change: [String: Any]) -> some View {
        let path = change["path"] as? String ?? "unknown"
        let type = change["type"] as? String ?? "modified"
        let icon = type == "created" ? "doc.badge.plus" : type == "deleted" ? "trash" : "pencil"
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.yellow))
            Text(path)
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Error Section

    private func errorSection(_ message: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.red)
                .lineLimit(3)
        }
    }

    // MARK: - Helpers

    private var isDaemonRunning: Bool {
        if case .running = daemonManager.state { return true }
        return false
    }

    // MARK: - Actions

    private func deployDaemon() {
        isDeploying = true
        errorMessage = nil
        Task {
            do {
                try await daemonManager.deploy(profileID: profileID)
                refreshSessions()
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeploying = false
        }
    }

    private func stopDaemon() {
        errorMessage = nil
        Task {
            do {
                try await daemonManager.stop(profileID: profileID)
                sessions = []
                forwards = []
                syncChanges = []
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func upgradeDaemon() {
        isDeploying = true
        errorMessage = nil
        Task {
            do {
                try await daemonManager.upgrade(profileID: profileID)
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeploying = false
        }
    }

    private func refreshSessions() {
        guard isDaemonRunning else { return }
        isLoadingSessions = true
        Task {
            do {
                let bridge = DaemonSessionBridge(connection: daemonManager.connection)
                sessions = try await bridge.listSessions()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingSessions = false
        }
    }

    private func createSession() {
        let title = newSessionTitle.isEmpty ? "cocxy-session" : newSessionTitle
        Task {
            do {
                let bridge = DaemonSessionBridge(connection: daemonManager.connection)
                _ = try await bridge.createAndAttach(title: title)
                newSessionTitle = ""
                refreshSessions()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func killSession(_ sessionID: String) {
        Task {
            do {
                let bridge = DaemonSessionBridge(connection: daemonManager.connection)
                try await bridge.killSession(sessionID: sessionID)
                refreshSessions()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshForwards() {
        guard isDaemonRunning else { return }
        Task {
            do {
                let response = try await daemonManager.connection.send(
                    cmd: DaemonCommand.forwardList.rawValue
                )
                if let data = response.data,
                   let fwds = data["forwards"] as? [[String: Any]] {
                    forwards = fwds
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addForward() {
        guard !newForwardSpec.isEmpty else { return }
        Task {
            do {
                _ = try await daemonManager.connection.send(
                    cmd: DaemonCommand.forwardAdd.rawValue,
                    args: ["spec": newForwardSpec]
                )
                newForwardSpec = ""
                refreshForwards()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeForward(_ spec: String) {
        Task {
            do {
                _ = try await daemonManager.connection.send(
                    cmd: DaemonCommand.forwardRemove.rawValue,
                    args: ["spec": spec]
                )
                refreshForwards()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addSyncWatch() {
        guard !newSyncPath.isEmpty else { return }
        Task {
            do {
                _ = try await daemonManager.connection.send(
                    cmd: DaemonCommand.syncWatch.rawValue,
                    args: ["path": newSyncPath]
                )
                newSyncPath = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func checkSyncChanges() {
        guard isDaemonRunning else { return }
        Task {
            do {
                let response = try await daemonManager.connection.send(
                    cmd: DaemonCommand.syncChanges.rawValue
                )
                if let data = response.data,
                   let changes = data["changes"] as? [[String: Any]] {
                    syncChanges = changes
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
