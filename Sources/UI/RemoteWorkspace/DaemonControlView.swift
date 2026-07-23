// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonControlView.swift - UI for remote daemon management.

import SwiftUI

@MainActor
final class RemoteWorkspaceProfileTaskScope: ObservableObject {
    enum Kind: Hashable {
        case lifecycle
        case sessions
        case forwards
        case sync
    }

    struct Token: Equatable {
        let profileID: UUID
        fileprivate let kind: Kind
        fileprivate let generation: UInt64
        fileprivate let operationID: UUID
    }

    private struct Entry {
        let operationID: UUID
        let task: Task<Void, Never>
    }

    let profileID: UUID
    private var generations: [Kind: UInt64] = [:]
    private var tasks: [Kind: Entry] = [:]

    init(profileID: UUID) {
        self.profileID = profileID
    }

    func start(
        _ kind: Kind,
        operation: @escaping @MainActor (Token) async -> Void
    ) {
        tasks.removeValue(forKey: kind)?.task.cancel()
        generations[kind, default: 0] &+= 1
        let token = Token(
            profileID: profileID,
            kind: kind,
            generation: generations[kind, default: 0],
            operationID: UUID()
        )
        let task = Task { @MainActor [weak self] in
            await operation(token)
            guard let self,
                  self.tasks[kind]?.operationID == token.operationID else { return }
            self.tasks.removeValue(forKey: kind)
        }
        tasks[kind] = Entry(operationID: token.operationID, task: task)
    }

    func isCurrent(_ token: Token) -> Bool {
        !Task.isCancelled
            && token.profileID == profileID
            && generations[token.kind] == token.generation
            && tasks[token.kind]?.operationID == token.operationID
    }

    func invalidate() {
        for task in tasks.values {
            task.task.cancel()
        }
        tasks.removeAll()
        for kind in [Kind.lifecycle, .sessions, .forwards, .sync] {
            generations[kind, default: 0] &+= 1
        }
    }
}

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
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    @StateObject private var operationScope: RemoteWorkspaceProfileTaskScope

    @State private var errorMessage: String?
    @State private var isDeploying = false
    @State private var sessions: [DaemonSessionInfo] = []
    @State private var isLoadingSessions = false
    @State private var newSessionTitle = ""
    @State private var newForwardSpec = ""
    @State private var newSyncPath = ""
    @State private var forwards: [[String: Any]] = []
    @State private var syncChanges: [[String: Any]] = []

    init(
        profileID: UUID,
        viewModel: RemoteConnectionViewModel,
        daemonManager: DaemonManagerImpl,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.profileID = profileID
        self.viewModel = viewModel
        self.daemonManager = daemonManager
        self.localizer = localizer
        _operationScope = StateObject(
            wrappedValue: RemoteWorkspaceProfileTaskScope(profileID: profileID)
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                connectionGate
            }
            .padding(12)
        }
        .onDisappear {
            operationScope.invalidate()
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
                Text(localized("remoteWorkspace.daemon.connectFirst", fallback: "Connect to the profile first to manage the daemon"))
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
        switch daemonState {
        case .notDeployed: return Color(nsColor: CocxyColors.overlay1)
        case .deploying, .upgrading: return Color.yellow
        case .running: return Color.green
        case .stopped: return Color.orange
        case .unreachable: return Color.red
        }
    }

    private var stateText: String {
        switch daemonState {
        case .notDeployed: return localized("remoteWorkspace.daemon.status.notDeployed", fallback: "Not Deployed")
        case .deploying: return localized("remoteWorkspace.daemon.status.deploying", fallback: "Deploying...")
        case .running(let version, let uptime):
            let uptimeStr = formatUptime(uptime)
            return String(
                format: localized("remoteWorkspace.daemon.status.running", fallback: "Running v%@ (%@)"),
                version,
                uptimeStr
            )
        case .stopped: return localized("remoteWorkspace.daemon.status.stopped", fallback: "Stopped")
        case .upgrading: return localized("remoteWorkspace.daemon.status.upgrading", fallback: "Upgrading...")
        case .unreachable: return localized("remoteWorkspace.daemon.status.unreachable", fallback: "Unreachable")
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("remoteWorkspace.daemon.controls", fallback: "Controls"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            HStack(spacing: 8) {
                switch daemonState {
                case .notDeployed, .stopped, .unreachable:
                    actionButton(localized("remoteWorkspace.daemon.deployStart", fallback: "Deploy & Start"), icon: "arrow.up.circle", action: deployDaemon)
                case .running:
                    actionButton(localized("remoteWorkspace.daemon.stop", fallback: "Stop"), icon: "stop.circle", action: stopDaemon)
                    actionButton(localized("remoteWorkspace.daemon.upgrade", fallback: "Upgrade"), icon: "arrow.triangle.2.circlepath", action: upgradeDaemon)
                case .deploying, .upgrading:
                    ProgressView()
                        .controlSize(.small)
                    Text(localized("remoteWorkspace.daemon.pleaseWait", fallback: "Please wait..."))
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
                Text(localized("remoteWorkspace.daemon.remoteSessions", fallback: "Remote Sessions"))
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
                    TextField(localized("remoteWorkspace.sessions.name.placeholder", fallback: "Session name"), text: $newSessionTitle)
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
                    Text(localized("remoteWorkspace.sessions.empty.title", fallback: "No active sessions"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                } else {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            } else {
                Text(localized("remoteWorkspace.daemon.deploySessions", fallback: "Deploy the daemon to manage persistent sessions."))
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
            Text(String(format: localized("remoteWorkspace.daemon.pid", fallback: "PID %d"), session.pid))
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
                Text(localized("remoteWorkspace.daemon.persistentForwards", fallback: "Persistent Forwards"))
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
                    TextField(
                        Self.localizedForwardSpecPlaceholder(using: localizer),
                        text: $newForwardSpec
                    )
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
                    Text(localized("remoteWorkspace.daemon.noPersistentForwards", fallback: "No persistent forwards"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                } else {
                    ForEach(Array(forwards.enumerated()), id: \.offset) { _, fwd in
                        forwardRow(fwd)
                    }
                }
            } else {
                Text(localized("remoteWorkspace.daemon.deployForwards", fallback: "Deploy the daemon to manage persistent forwards."))
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
                Text(localized("remoteWorkspace.daemon.fileSyncWatch", fallback: "File Sync Watch"))
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
                    TextField(localized("remoteWorkspace.daemon.syncPath.placeholder", fallback: "Remote path to watch"), text: $newSyncPath)
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
                    Text(localized("remoteWorkspace.daemon.noRecentChanges", fallback: "No recent changes detected"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                } else {
                    ForEach(Array(syncChanges.prefix(10).enumerated()), id: \.offset) { _, change in
                        syncChangeRow(change)
                    }
                }
            } else {
                Text(localized("remoteWorkspace.daemon.deploySync", fallback: "Deploy the daemon to use file sync."))
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
        if case .running = daemonState { return true }
        return false
    }

    private var daemonState: DaemonState {
        daemonManager.state(for: profileID)
    }

    // MARK: - Actions

    private func deployDaemon() {
        let expectedProfileID = profileID
        isDeploying = true
        errorMessage = nil
        operationScope.start(.lifecycle) { token in
            do {
                try await daemonManager.deploy(profileID: expectedProfileID)
                guard operationScope.isCurrent(token) else { return }
                refreshSessions()
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
            guard operationScope.isCurrent(token) else { return }
            isDeploying = false
        }
    }

    private func stopDaemon() {
        let expectedProfileID = profileID
        errorMessage = nil
        operationScope.start(.lifecycle) { token in
            do {
                try await daemonManager.stop(profileID: expectedProfileID)
                guard operationScope.isCurrent(token) else { return }
                sessions = []
                forwards = []
                syncChanges = []
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func upgradeDaemon() {
        let expectedProfileID = profileID
        isDeploying = true
        errorMessage = nil
        operationScope.start(.lifecycle) { token in
            do {
                try await daemonManager.upgrade(profileID: expectedProfileID)
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
            guard operationScope.isCurrent(token) else { return }
            isDeploying = false
        }
    }

    private func refreshSessions() {
        guard isDaemonRunning else { return }
        let expectedProfileID = profileID
        isLoadingSessions = true
        operationScope.start(.sessions) { token in
            do {
                let bridge = DaemonSessionBridge(
                    connection: try daemonManager.connection(for: expectedProfileID)
                )
                let refreshedSessions = try await bridge.listSessions()
                guard operationScope.isCurrent(token) else { return }
                sessions = refreshedSessions
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
            guard operationScope.isCurrent(token) else { return }
            isLoadingSessions = false
        }
    }

    private func createSession() {
        let expectedProfileID = profileID
        let title = newSessionTitle.isEmpty ? "cocxy-session" : newSessionTitle
        operationScope.start(.sessions) { token in
            do {
                let bridge = DaemonSessionBridge(
                    connection: try daemonManager.connection(for: expectedProfileID)
                )
                _ = try await bridge.createAndAttach(title: title)
                guard operationScope.isCurrent(token) else { return }
                newSessionTitle = ""
                refreshSessions()
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func killSession(_ sessionID: String) {
        let expectedProfileID = profileID
        operationScope.start(.sessions) { token in
            do {
                let bridge = DaemonSessionBridge(
                    connection: try daemonManager.connection(for: expectedProfileID)
                )
                try await bridge.killSession(sessionID: sessionID)
                guard operationScope.isCurrent(token) else { return }
                refreshSessions()
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshForwards() {
        guard isDaemonRunning else { return }
        let expectedProfileID = profileID
        operationScope.start(.forwards) { token in
            do {
                let response = try await daemonManager.send(
                    profileID: expectedProfileID,
                    cmd: DaemonCommand.forwardList.rawValue
                )
                guard operationScope.isCurrent(token) else { return }
                if let data = response.data,
                   let fwds = data["forwards"] as? [[String: Any]] {
                    forwards = fwds
                }
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addForward() {
        guard !newForwardSpec.isEmpty else { return }
        let expectedProfileID = profileID
        let expectedForwardSpec = newForwardSpec
        operationScope.start(.forwards) { token in
            do {
                _ = try await daemonManager.send(
                    profileID: expectedProfileID,
                    cmd: DaemonCommand.forwardAdd.rawValue,
                    args: ["spec": expectedForwardSpec]
                )
                guard operationScope.isCurrent(token) else { return }
                newForwardSpec = ""
                refreshForwards()
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeForward(_ spec: String) {
        let expectedProfileID = profileID
        operationScope.start(.forwards) { token in
            do {
                _ = try await daemonManager.send(
                    profileID: expectedProfileID,
                    cmd: DaemonCommand.forwardRemove.rawValue,
                    args: ["spec": spec]
                )
                guard operationScope.isCurrent(token) else { return }
                refreshForwards()
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addSyncWatch() {
        guard !newSyncPath.isEmpty else { return }
        let expectedProfileID = profileID
        let expectedSyncPath = newSyncPath
        operationScope.start(.sync) { token in
            do {
                _ = try await daemonManager.send(
                    profileID: expectedProfileID,
                    cmd: DaemonCommand.syncWatch.rawValue,
                    args: ["path": expectedSyncPath]
                )
                guard operationScope.isCurrent(token) else { return }
                newSyncPath = ""
            } catch {
                guard operationScope.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func checkSyncChanges() {
        guard isDaemonRunning else { return }
        let expectedProfileID = profileID
        operationScope.start(.sync) { token in
            do {
                let response = try await daemonManager.send(
                    profileID: expectedProfileID,
                    cmd: DaemonCommand.syncChanges.rawValue
                )
                guard operationScope.isCurrent(token) else { return }
                if let data = response.data,
                   let changes = data["changes"] as? [[String: Any]] {
                    syncChanges = changes
                }
            } catch {
                guard operationScope.isCurrent(token) else { return }
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

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    static func localizedForwardSpecPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("remoteWorkspace.daemon.forwardSpec.placeholder", fallback: "local:remote")
    }
}
