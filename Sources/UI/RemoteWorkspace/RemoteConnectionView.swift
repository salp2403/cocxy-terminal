// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionView.swift - Main panel for remote workspace management.

import SwiftUI
import Combine

// MARK: - Remote Connection View Model

/// Drives the main Remote Workspaces panel.
///
/// Coordinates profile listing, connection state, and sub-panel selection.
/// Profiles are loaded from the `RemoteProfileStore` and grouped by their
/// optional `group` property. Connection states come from the
/// `RemoteConnectionManager`.
@MainActor
final class RemoteConnectionViewModel: ObservableObject {

    // MARK: - Sub-Panel Selection

    enum SubPanel: String, CaseIterable, Identifiable {
        case sessions
        case tunnels
        case proxy
        case relay
        case daemon
        case keys
        case sftp

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sessions: return "Sessions"
            case .tunnels: return "Tunnels"
            case .proxy: return "Proxy"
            case .relay: return "Relay"
            case .daemon: return "Daemon"
            case .keys: return "Keys"
            case .sftp: return "SFTP"
            }
        }

        var icon: String {
            switch self {
            case .sessions: return "terminal"
            case .tunnels: return "arrow.left.arrow.right"
            case .proxy: return "network.badge.shield.half.filled"
            case .relay: return "point.3.connected.trianglepath.dotted"
            case .daemon: return "server.rack"
            case .keys: return "key"
            case .sftp: return "folder"
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var profiles: [RemoteConnectionProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var selectedSubPanel: SubPanel = .sessions
    @Published var quickConnectText: String = ""
    @Published var isEditorPresented = false
    @Published var editingProfile: RemoteConnectionProfile?
    @Published private(set) var collapsedGroups: Set<String> = []

    // MARK: - Dependencies

    let connectionManager: RemoteConnectionManager
    let tunnelManager: SSHTunnelManager
    private let profileStore: RemoteProfileStore

    // MARK: - Initialization

    init(
        profileStore: RemoteProfileStore,
        connectionManager: RemoteConnectionManager,
        tunnelManager: SSHTunnelManager
    ) {
        self.profileStore = profileStore
        self.connectionManager = connectionManager
        self.tunnelManager = tunnelManager
    }

    // MARK: - Computed Properties

    /// Profiles organized by group. Ungrouped profiles use the empty string key.
    var groupedProfiles: [(group: String, profiles: [RemoteConnectionProfile])] {
        let grouped = Dictionary(grouping: profiles) { $0.group ?? "" }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, profiles: $0.value.sorted { $0.name < $1.name }) }
    }

    /// All unique group names currently in use.
    var existingGroups: [String] {
        Array(Set(profiles.compactMap { $0.group })).sorted()
    }

    /// Returns the connection state for a given profile.
    func connectionState(for profileID: UUID) -> RemoteConnectionManager.ConnectionState {
        connectionManager.connections[profileID] ?? .disconnected
    }

    /// Whether a profile is currently connected.
    func isConnected(_ profileID: UUID) -> Bool {
        if case .connected = connectionState(for: profileID) {
            return true
        }
        return false
    }

    // MARK: - Actions

    func loadProfiles() {
        do {
            profiles = try profileStore.loadAll()
        } catch {
            profiles = []
        }
    }

    func connect(profile: RemoteConnectionProfile) {
        Task {
            await connectionManager.connect(profile: profile)
        }
    }

    func disconnect(profileID: UUID) {
        Task {
            await connectionManager.disconnect(profileID: profileID)
        }
    }

    func toggleConnection(for profile: RemoteConnectionProfile) {
        if isConnected(profile.id) {
            disconnect(profileID: profile.id)
        } else {
            connect(profile: profile)
        }
    }

    func quickConnect() {
        let input = quickConnectText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let parsed = parseQuickConnect(input)
        let profile = RemoteConnectionProfile(
            name: input,
            host: parsed.host,
            user: parsed.user,
            port: parsed.port
        )

        connect(profile: profile)
        quickConnectText = ""
    }

    func toggleGroupCollapse(_ group: String) {
        if collapsedGroups.contains(group) {
            collapsedGroups.remove(group)
        } else {
            collapsedGroups.insert(group)
        }
    }

    func presentNewProfile() {
        editingProfile = nil
        isEditorPresented = true
    }

    func presentEditProfile(_ profile: RemoteConnectionProfile) {
        editingProfile = profile
        isEditorPresented = true
    }

    func saveProfile(_ profile: RemoteConnectionProfile) {
        do {
            try profileStore.save(profile)
            loadProfiles()
        } catch {
            // Profile save failures are handled silently for now.
        }
    }

    func deleteProfile(_ profile: RemoteConnectionProfile) {
        do {
            try profileStore.delete(id: profile.id)
            loadProfiles()
        } catch {
            // Profile delete failures are handled silently for now.
        }
    }

    func duplicateProfile(_ profile: RemoteConnectionProfile) {
        let copy = RemoteConnectionProfile(
            name: "\(profile.name) (copy)",
            host: profile.host,
            user: profile.user,
            port: profile.port,
            identityFile: profile.identityFile,
            jumpHosts: profile.jumpHosts,
            portForwards: profile.portForwards,
            group: profile.group,
            envVars: profile.envVars,
            keepAliveInterval: profile.keepAliveInterval,
            autoReconnect: profile.autoReconnect,
            proxyExclusions: profile.proxyExclusions,
            relayChannels: profile.relayChannels
        )
        saveProfile(copy)
    }

    // MARK: - Quick Connect Parsing

    /// Parses "user@host:port" or "host:port" or "user@host" or "host".
    private func parseQuickConnect(_ input: String) -> (user: String?, host: String, port: Int?) {
        var remaining = input
        var user: String?

        if let atIndex = remaining.firstIndex(of: "@") {
            user = String(remaining[remaining.startIndex..<atIndex])
            remaining = String(remaining[remaining.index(after: atIndex)...])
        }

        var host = remaining
        var port: Int?

        if let colonIndex = remaining.lastIndex(of: ":") {
            let portString = String(remaining[remaining.index(after: colonIndex)...])
            if let parsedPort = Int(portString), parsedPort > 0, parsedPort <= 65535 {
                port = parsedPort
                host = String(remaining[remaining.startIndex..<colonIndex])
            }
        }

        return (user: user, host: host, port: port)
    }
}

// MARK: - Remote Connection View

/// The main panel for remote workspace management.
///
/// ## Layout
///
/// ```
/// +-- Remote Workspaces --------[+] [x]--+
/// | [Quick Connect...]                    |
/// +---------------------------------------+
/// | > servers (2)                         |
/// |   [green] production   connected      |
/// |   [gray]  staging      disconnected   |
/// | > personal (1)                        |
/// |   [green] homelab      connected      |
/// +---------------------------------------+
/// | [Tunnels] [Keys] [SFTP]              |
/// +---------------------------------------+
/// | (sub-panel content)                   |
/// +---------------------------------------+
/// ```
///
/// ## Behavior
///
/// - Quick connect: type `user@host:port` and press Enter.
/// - Profiles grouped by `group` property with collapsible headers.
/// - Bottom tab picker switches between Tunnels, Keys, and SFTP sub-panels.
/// - Toggle with Cmd+Shift+R.
///
/// - SeeAlso: `RemoteConnectionViewModel`
/// - SeeAlso: `PortForwardingView`, `SSHKeyManagerView`, `SFTPBrowserView`
struct RemoteConnectionView: View {

    @ObservedObject var viewModel: RemoteConnectionViewModel
    var onDismiss: () -> Void

    /// Injected SSH key manager for the keys sub-panel.
    var sshKeyManager: SSHKeyManager?

    /// Injected SFTP executor for the file browser sub-panel.
    var sftpExecutor: (any SFTPExecutor)?

    /// Sub-panel view models created lazily and retained for the panel lifetime.
    @State private var keyManagerVM: SSHKeyManagerViewModel?
    @State private var sftpBrowserVM: SFTPBrowserViewModel?

    static let panelWidth: CGFloat = 320

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            quickConnectField
            Divider()
            profileListView
            Divider()
            subPanelPicker
            Divider()
            subPanelContent
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .onAppear { viewModel.loadProfiles() }
        .onChange(of: viewModel.selectedProfileID) { _ in
            sftpBrowserVM = nil
        }
        .sheet(isPresented: $viewModel.isEditorPresented) {
            editorSheet
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Remote Workspaces")
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Remote Workspaces")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: { viewModel.presentNewProfile() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: CocxyColors.blue))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Add new remote profile")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close remote workspaces panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Quick Connect

    private var quickConnectField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))

            TextField("Quick Connect (user@host:port)", text: $viewModel.quickConnectText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { viewModel.quickConnect() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: CocxyColors.crust).opacity(0.5))
    }

    // MARK: - Profile List

    private var profileListView: some View {
        Group {
            if viewModel.profiles.isEmpty {
                profileEmptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.groupedProfiles, id: \.group) { group in
                            profileGroupSection(group: group.group, profiles: group.profiles)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 120)
    }

    // MARK: - Profile Group

    private func profileGroupSection(
        group: String,
        profiles: [RemoteConnectionProfile]
    ) -> some View {
        let displayName = group.isEmpty ? "ungrouped" : group
        let isCollapsed = viewModel.collapsedGroups.contains(group)

        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(displayName: displayName, count: profiles.count, group: group, isCollapsed: isCollapsed)

            if !isCollapsed {
                ForEach(profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        state: viewModel.connectionState(for: profile.id),
                        isSelected: viewModel.selectedProfileID == profile.id,
                        onSelect: { viewModel.selectedProfileID = profile.id },
                        onToggleConnection: { viewModel.toggleConnection(for: profile) },
                        onEdit: { viewModel.presentEditProfile(profile) },
                        onDuplicate: { viewModel.duplicateProfile(profile) },
                        onDelete: { viewModel.deleteProfile(profile) }
                    )
                }
            }
        }
    }

    private func groupHeader(
        displayName: String,
        count: Int,
        group: String,
        isCollapsed: Bool
    ) -> some View {
        Button(action: { viewModel.toggleGroupCollapse(group) }) {
            HStack(spacing: 4) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    .frame(width: 12)

                Text(displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))

                Text("(\(count))")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityLabel("\(displayName), \(count) profiles")
    }

    // MARK: - Profile Empty State

    private var profileEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "network")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("No saved profiles")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("Add a profile or use Quick Connect\nto reach a remote host.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Sub-Panel Picker

    private var subPanelPicker: some View {
        HStack(spacing: 0) {
            ForEach(RemoteConnectionViewModel.SubPanel.allCases) { panel in
                subPanelTab(panel)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func subPanelTab(_ panel: RemoteConnectionViewModel.SubPanel) -> some View {
        let isSelected = viewModel.selectedSubPanel == panel
        return Button(action: { viewModel.selectedSubPanel = panel }) {
            HStack(spacing: 4) {
                Image(systemName: panel.icon)
                    .font(.system(size: 10))
                Text(panel.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(
                isSelected
                    ? Color(nsColor: CocxyColors.text)
                    : Color(nsColor: CocxyColors.overlay1)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color(nsColor: CocxyColors.surface0) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(panel.label) sub-panel")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Sub-Panel Content

    @ViewBuilder
    private var subPanelContent: some View {
        switch viewModel.selectedSubPanel {
        case .sessions:
            sessionsSubPanel
        case .tunnels:
            tunnelsSubPanel
        case .proxy:
            proxySubPanel
        case .relay:
            relaySubPanel
        case .daemon:
            daemonSubPanel
        case .keys:
            keysSubPanel
        case .sftp:
            sftpSubPanel
        }
    }

    private var sessionsSubPanel: some View {
        Group {
            if let profileID = viewModel.selectedProfileID {
                RemoteSessionListView(
                    viewModel: RemoteSessionListViewModel(
                        connectionManager: viewModel.connectionManager,
                        profileID: profileID
                    )
                )
            } else {
                selectProfilePlaceholder(
                    icon: "terminal",
                    text: "Select a profile to manage persistent sessions"
                )
            }
        }
    }

    private var tunnelsSubPanel: some View {
        Group {
            if let profileID = viewModel.selectedProfileID {
                PortForwardingView(
                    tunnelManager: viewModel.tunnelManager,
                    profileID: profileID,
                    onForwardPort: { forward, profID in
                        try? viewModel.connectionManager.forwardPort(forward, for: profID)
                    },
                    onCancelForward: { forward, profID in
                        try? viewModel.connectionManager.cancelForward(forward, for: profID)
                    }
                )
            } else {
                selectProfilePlaceholder(icon: "arrow.left.arrow.right", text: "Select a profile to manage tunnels")
            }
        }
    }

    private var proxySubPanel: some View {
        Group {
            if let profileID = viewModel.selectedProfileID,
               let proxyManager = viewModel.connectionManager.proxyManager {
                ProxyControlView(
                    profileID: profileID,
                    viewModel: viewModel,
                    proxyManager: proxyManager
                )
            } else {
                selectProfilePlaceholder(
                    icon: "network.badge.shield.half.filled",
                    text: "Select a profile to manage proxy"
                )
            }
        }
    }

    private var relaySubPanel: some View {
        Group {
            if let profileID = viewModel.selectedProfileID,
               let relayManager = viewModel.connectionManager.relayManager {
                RelayControlView(
                    profileID: profileID,
                    viewModel: viewModel,
                    relayManager: relayManager
                )
            } else {
                selectProfilePlaceholder(
                    icon: "point.3.connected.trianglepath.dotted",
                    text: "Select a profile to manage relay channels"
                )
            }
        }
    }

    private var daemonSubPanel: some View {
        Group {
            if let profileID = viewModel.selectedProfileID,
               let daemonManager = viewModel.connectionManager.daemonManager {
                DaemonControlView(
                    profileID: profileID,
                    viewModel: viewModel,
                    daemonManager: daemonManager
                )
            } else {
                selectProfilePlaceholder(
                    icon: "server.rack",
                    text: "Select a profile to manage remote daemon"
                )
            }
        }
    }

    private var keysSubPanel: some View {
        Group {
            if let vm = keyManagerVM {
                SSHKeyManagerView(viewModel: vm)
            } else if let keyManager = sshKeyManager {
                Color.clear.onAppear {
                    keyManagerVM = SSHKeyManagerViewModel(keyManager: keyManager)
                    keyManagerVM?.loadKeys()
                }
            } else {
                selectProfilePlaceholder(icon: "key", text: "SSH key management")
            }
        }
    }

    private var sftpSubPanel: some View {
        Group {
            if let vm = sftpBrowserVM {
                SFTPBrowserView(viewModel: vm)
            } else if let profileID = viewModel.selectedProfileID,
                      let profile = viewModel.profiles.first(where: { $0.id == profileID }),
                      let executor = sftpExecutor {
                Color.clear.onAppear {
                    let client = SFTPClient(executor: executor)
                    let vm = SFTPBrowserViewModel(sftpClient: client, profile: profile)
                    sftpBrowserVM = vm
                    vm.loadDirectory()
                }
            } else {
                selectProfilePlaceholder(icon: "folder", text: "Select a connected profile to browse files")
            }
        }
    }

    private func selectProfilePlaceholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Editor Sheet

    private var editorSheet: some View {
        let editorVM = RemoteProfileEditorViewModel(
            profile: viewModel.editingProfile,
            existingGroups: viewModel.existingGroups
        )
        editorVM.onSave = { [weak viewModel] profile in
            viewModel?.saveProfile(profile)
        }
        return RemoteProfileEditor(viewModel: editorVM)
    }
}

// MARK: - Profile Row

/// A single row representing a saved SSH profile with its connection state.
struct ProfileRow: View {

    let profile: RemoteConnectionProfile
    let state: RemoteConnectionManager.ConnectionState
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleConnection: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            RemoteStatusIndicator(state: state)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                    .lineLimit(1)

                Text(profile.displayTitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    .lineLimit(1)
            }

            Spacer()

            latencyBadge

            connectionToggleButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .contextMenu { contextMenuContent }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(stateDescription)")
    }

    // MARK: - Background

    private var rowBackground: Color {
        if isSelected {
            return Color(nsColor: CocxyColors.selectedBackground)
        }
        if isHovered {
            return Color(nsColor: CocxyColors.hoverOnDark)
        }
        return .clear
    }

    // MARK: - Latency Badge

    @ViewBuilder
    private var latencyBadge: some View {
        if case .connected(let latencyMs) = state, let ms = latencyMs {
            Text("\(ms)ms")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.green))
        }
    }

    // MARK: - Connection Toggle

    private var connectionToggleButton: some View {
        Button(action: onToggleConnection) {
            Image(systemName: connectionButtonIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(connectionButtonColor)
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .accessibilityLabel(connectionButtonLabel)
    }

    private var connectionButtonIcon: String {
        switch state {
        case .connected:
            return "stop.circle"
        case .connecting, .reconnecting:
            return "xmark.circle"
        case .disconnected, .failed:
            return "play.circle"
        }
    }

    private var connectionButtonColor: Color {
        switch state {
        case .connected:
            return Color(nsColor: CocxyColors.red).opacity(0.8)
        case .connecting, .reconnecting:
            return Color(nsColor: CocxyColors.yellow)
        case .disconnected, .failed:
            return Color(nsColor: CocxyColors.green)
        }
    }

    private var connectionButtonLabel: String {
        switch state {
        case .connected:
            return "Disconnect from \(profile.name)"
        case .connecting, .reconnecting:
            return "Cancel connection to \(profile.name)"
        case .disconnected, .failed:
            return "Connect to \(profile.name)"
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: onEdit) {
            Label("Edit", systemImage: "pencil")
        }
        Button(action: onDuplicate) {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - State Description

    private var stateDescription: String {
        switch state {
        case .connected(let latencyMs):
            if let ms = latencyMs {
                return "connected, \(ms)ms"
            }
            return "connected"
        case .connecting:
            return "connecting"
        case .reconnecting(let attempt):
            return "reconnecting, attempt \(attempt)"
        case .disconnected:
            return "disconnected"
        case .failed(let reason):
            return "failed: \(reason)"
        }
    }
}
