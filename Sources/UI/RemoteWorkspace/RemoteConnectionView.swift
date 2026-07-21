// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionView.swift - Main panel for remote workspace management.

import AppKit
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

        var detail: String {
            switch self {
            case .sessions: return "Persistent shell sessions"
            case .tunnels: return "Forward local and remote ports"
            case .proxy: return "Authenticated local proxy"
            case .relay: return "Relay channels"
            case .daemon: return "Remote helper daemon"
            case .keys: return "SSH identities"
            case .sftp: return "Remote file browser"
            }
        }

        func localizedLabel(using localizer: AppLocalizer) -> String {
            localizer.string("remoteWorkspace.subPanel.\(rawValue)", fallback: label)
        }

        func localizedDetail(using localizer: AppLocalizer) -> String {
            localizer.string("remoteWorkspace.subPanel.\(rawValue).detail", fallback: detail)
        }
    }

    // MARK: - Published State

    @Published private(set) var profiles: [RemoteConnectionProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var selectedSubPanel: SubPanel = .sessions
    @Published var quickConnectText: String = ""
    @Published var isEditorPresented = false
    @Published var editingProfile: RemoteConnectionProfile?
    @Published private(set) var profileEditorViewModel: RemoteProfileEditorViewModel?
    @Published private(set) var collapsedGroups: Set<String> = []
    @Published private(set) var profileActionErrorMessage: String?
    @Published private(set) var connectionStates: [UUID: RemoteConnectionManager.ConnectionState] = [:]

    // MARK: - Dependencies

    let connectionManager: RemoteConnectionManager
    let tunnelManager: SSHTunnelManager
    private let profileStore: any RemoteProfileStoring
    private var localizer: AppLocalizer
    private var transientProfileIDs: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Initialization

    init(
        profileStore: any RemoteProfileStoring,
        connectionManager: RemoteConnectionManager,
        tunnelManager: SSHTunnelManager,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.profileStore = profileStore
        self.connectionManager = connectionManager
        self.tunnelManager = tunnelManager
        self.localizer = localizer
        self.connectionStates = connectionManager.connections

        connectionManager.$connections
            .sink { [weak self] states in
                self?.connectionStates = states
            }
            .store(in: &cancellables)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
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
        connectionStates[profileID] ?? .disconnected
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
            let savedProfiles = try profileStore.loadAll()
            let transientProfiles = profiles.filter { transientProfileIDs.contains($0.id) }
            var seenIDs = Set(savedProfiles.map(\.id))
            profiles = savedProfiles + transientProfiles.filter { seenIDs.insert($0.id).inserted }
        } catch {
            profiles = profiles.filter { transientProfileIDs.contains($0.id) }
        }
        selectConnectedProfileIfNeeded()
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
        selectedProfileID = profile.id
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

        transientProfileIDs.insert(profile.id)
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        selectedProfileID = profile.id
        selectedSubPanel = .tunnels
        connect(profile: profile)
        quickConnectText = ""
    }

    private func selectConnectedProfileIfNeeded() {
        if let selectedProfileID,
           profiles.contains(where: { $0.id == selectedProfileID }) {
            return
        }

        guard let connectedProfile = profiles.first(where: { isConnected($0.id) }) else {
            if let selectedProfileID,
               !profiles.contains(where: { $0.id == selectedProfileID }) {
                self.selectedProfileID = nil
            }
            return
        }

        selectedProfileID = connectedProfile.id
        selectedSubPanel = .tunnels
    }

    func toggleGroupCollapse(_ group: String) {
        if collapsedGroups.contains(group) {
            collapsedGroups.remove(group)
        } else {
            collapsedGroups.insert(group)
        }
    }

    func presentNewProfile() {
        presentProfileEditor(profile: nil)
    }

    func presentEditProfile(_ profile: RemoteConnectionProfile) {
        presentProfileEditor(profile: profile)
    }

    private func presentProfileEditor(profile: RemoteConnectionProfile?) {
        editingProfile = profile
        let editorViewModel = RemoteProfileEditorViewModel(
            profile: profile,
            existingGroups: existingGroups
        )
        editorViewModel.onSave = { [weak self] profile in
            guard let self else { return }
            try self.saveProfile(profile)
        }
        profileEditorViewModel = editorViewModel
        isEditorPresented = true
    }

    func saveProfile(_ profile: RemoteConnectionProfile) throws {
        try profileStore.save(profile)
        loadProfiles()
    }

    func deleteProfile(_ profile: RemoteConnectionProfile) {
        do {
            try profileStore.delete(id: profile.id)
            loadProfiles()
        } catch {
            // Profile delete failures are handled silently for now.
        }
    }

    @discardableResult
    func duplicateProfile(_ profile: RemoteConnectionProfile) -> Bool {
        let copy = RemoteConnectionProfile(
            name: "\(profile.name) (\(localizer.string("remoteWorkspace.profile.copySuffix", fallback: "copy")))",
            host: profile.host,
            user: profile.user,
            port: profile.port,
            identityFile: profile.identityFile,
            jumpHosts: profile.jumpHosts,
            portForwards: profile.portForwards,
            group: profile.group,
            envVars: profile.envVars,
            keepAliveInterval: profile.keepAliveInterval,
            strictHostKeyChecking: profile.strictHostKeyChecking,
            knownHostsFile: profile.knownHostsFile,
            batchMode: profile.batchMode,
            autoReconnect: profile.autoReconnect,
            proxyExclusions: profile.proxyExclusions,
            relayChannels: profile.relayChannels
        )
        do {
            try saveProfile(copy)
            profileActionErrorMessage = nil
            return true
        } catch {
            let format = localizer.string(
                "remoteWorkspace.profile.duplicateFailed",
                fallback: "Could not duplicate \"%@\": %@"
            )
            profileActionErrorMessage = String(
                format: format,
                profile.name,
                profileStoreErrorDescription(error)
            )
            return false
        }
    }

    func dismissProfileActionError() {
        profileActionErrorMessage = nil
    }

    private func profileStoreErrorDescription(_ error: Error) -> String {
        guard let storeError = error as? RemoteProfileStoreError else {
            return error.localizedDescription
        }

        switch storeError {
        case let .saveFailed(message), let .deleteFailed(message), let .loadFailed(message):
            return message
        case .profileNotFound:
            return localizer.string(
                "remoteWorkspace.profile.error.notFound",
                fallback: "The profile no longer exists."
            )
        }
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
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    /// Injected SSH key manager for the keys sub-panel.
    var sshKeyManager: SSHKeyManager?

    /// Injected SFTP executor for the file browser sub-panel.
    var sftpExecutor: (any SFTPExecutor)?

    /// Remote dev-server scanner used to offer browser open suggestions.
    var remotePortScanner: RemotePortScanner?

    /// Opens a detected remote dev server in the browser.
    var onOpenRemoteBrowser: ((RemoteConnectionProfile, RemoteBrowserOpenSuggestion) -> Bool)?

    /// Forced `NSAppearance` for the translucent panel background.
    ///
    /// `nil` preserves the legacy inherit-from-window behaviour; non-nil
    /// values pin the vibrancy view so the remote workspace panel
    /// matches the rest of the chrome when the user forces a
    /// transparency theme.
    var vibrancyAppearanceOverride: NSAppearance?

    /// Sub-panel view models created lazily and retained for the panel lifetime.
    @State private var keyManagerVM: SSHKeyManagerViewModel?
    @State private var sftpBrowserVM: SFTPBrowserViewModel?

    static let panelWidth: CGFloat = 380
    static let subPanelPickerMinimumItemWidth: CGFloat = 78
    static let subPanelPickerSpacing: CGFloat = 8

    static func subPanelPickerColumnCount(for width: CGFloat) -> Int {
        let contentWidth = max(0, width - 24)
        let itemWithSpacing = subPanelPickerMinimumItemWidth + subPanelPickerSpacing
        guard itemWithSpacing > 0 else { return 1 }
        return max(1, Int((contentWidth + subPanelPickerSpacing) / itemWithSpacing))
    }

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
        .glassPanelBackground()
        .onAppear {
            viewModel.updateLocalizer(localizer)
            viewModel.loadProfiles()
        }
        .onChange(of: localizer.resolvedLanguage) { _, _ in
            viewModel.updateLocalizer(localizer)
        }
        .onChange(of: viewModel.selectedProfileID) { _, _ in
            sftpBrowserVM = nil
        }
        .sheet(isPresented: $viewModel.isEditorPresented) {
            editorSheet
        }
        .alert(
            localized("remoteWorkspace.profile.actionFailed.title", fallback: "Profile action failed"),
            isPresented: Binding(
                get: { viewModel.profileActionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissProfileActionError()
                    }
                }
            )
        ) {
            Button(localized("common.ok", fallback: "OK"), role: .cancel) {
                viewModel.dismissProfileActionError()
            }
        } message: {
            Text(viewModel.profileActionErrorMessage ?? "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("remoteWorkspace.accessibility", fallback: "Remote Workspaces"))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(localized("remoteWorkspace.title", fallback: "Remote Workspaces"))
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
            .accessibilityLabel(localized("remoteWorkspace.addProfile.accessibility", fallback: "Add new remote profile"))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel(localized("remoteWorkspace.closePanel.accessibility", fallback: "Close remote workspaces panel"))
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

            TextField(
                localized("remoteWorkspace.quickConnect.placeholder", fallback: "Quick Connect (user@host:port)"),
                text: $viewModel.quickConnectText
            )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { viewModel.quickConnect() }

            Button(action: { viewModel.quickConnect() }) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        viewModel.quickConnectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(nsColor: CocxyColors.overlay0)
                            : Color(nsColor: CocxyColors.blue)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.quickConnectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(localized("remoteWorkspace.quickConnect.connect.accessibility", fallback: "Connect to quick connect host"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: CocxyColors.crust).opacity(0.5))
        .help(localized("remoteWorkspace.quickConnect.help", fallback: "Type user@host:port, then press Return or the arrow to connect."))
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
        let displayName = group.isEmpty
            ? localized("remoteWorkspace.group.ungrouped", fallback: "ungrouped")
            : group
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
                        onDelete: { viewModel.deleteProfile(profile) },
                        localizer: localizer
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
        .accessibilityLabel(
            String(
                format: localized("remoteWorkspace.group.accessibility", fallback: "%@, %d profiles"),
                displayName,
                count
            )
        )
    }

    // MARK: - Profile Empty State

    private var profileEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "network")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(localized("remoteWorkspace.empty.title", fallback: "No remote profiles yet"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(
                localized(
                    "remoteWorkspace.empty.message",
                    fallback: "Save SSH hosts for repeat work, or use Quick Connect above for a one-off connection."
                )
            )
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 24)

            Button(action: { viewModel.presentNewProfile() }) {
                Label(localized("remoteWorkspace.empty.addProfile", fallback: "Add Profile"), systemImage: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: CocxyColors.blue).opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: CocxyColors.blue))
            .accessibilityLabel(localized("remoteWorkspace.empty.addProfile.accessibility", fallback: "Add remote profile"))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Sub-Panel Picker

    private var subPanelPicker: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: Self.subPanelPickerMinimumItemWidth),
                    spacing: Self.subPanelPickerSpacing
                )
            ],
            alignment: .leading,
            spacing: Self.subPanelPickerSpacing
        ) {
            ForEach(RemoteConnectionViewModel.SubPanel.allCases) { panel in
                subPanelTab(panel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 84)
        .background(Color(nsColor: CocxyColors.crust).opacity(0.35))
    }

    private func subPanelTab(_ panel: RemoteConnectionViewModel.SubPanel) -> some View {
        let isSelected = viewModel.selectedSubPanel == panel
        return Button(action: { viewModel.selectedSubPanel = panel }) {
            HStack(spacing: 6) {
                Image(systemName: panel.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(panel.localizedLabel(using: localizer))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(
                isSelected
                    ? Color(nsColor: CocxyColors.text)
                    : Color(nsColor: CocxyColors.overlay1)
            )
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(isSelected ? Color(nsColor: CocxyColors.surface0) : Color(nsColor: CocxyColors.base).opacity(0.35))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color(nsColor: CocxyColors.blue).opacity(0.45) : Color(nsColor: CocxyColors.surface1).opacity(0.55),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: localized("remoteWorkspace.subPanel.accessibility", fallback: "%@ sub-panel"),
                panel.localizedLabel(using: localizer)
            )
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(panel.localizedDetail(using: localizer))
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
                    ),
                    localizer: localizer
                )
            } else {
                selectProfilePlaceholder(
                    icon: "terminal",
                    text: localized("remoteWorkspace.placeholder.sessions", fallback: "Select a profile to manage persistent sessions")
                )
            }
        }
    }

    private var tunnelsSubPanel: some View {
        Group {
            if let profileID = viewModel.selectedProfileID,
               let profile = viewModel.profiles.first(where: { $0.id == profileID }) {
                VStack(alignment: .leading, spacing: 0) {
                    PortForwardingView(
                        tunnelManager: viewModel.tunnelManager,
                        profileID: profileID,
                        onForwardPort: { forward, profID in
                            try viewModel.connectionManager.forwardPort(forward, for: profID)
                        },
                        onCancelForward: { forward, profID in
                            try viewModel.connectionManager.cancelForward(forward, for: profID)
                        },
                        localizer: localizer
                    )
                    .id(profileID)
                    if let remotePortScanner {
                        RemoteBrowserSuggestionsSection(
                            scanner: remotePortScanner,
                            profile: profile,
                            isConnected: viewModel.isConnected(profileID),
                            onOpenRemoteBrowser: onOpenRemoteBrowser,
                            localizer: localizer
                        )
                    }
                }
            } else {
                selectProfilePlaceholder(
                    icon: "arrow.left.arrow.right",
                    text: localized("remoteWorkspace.placeholder.tunnels", fallback: "Select a profile to manage tunnels")
                )
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
                    proxyManager: proxyManager,
                    localizer: localizer
                )
                .id(profileID)
            } else {
                selectProfilePlaceholder(
                    icon: "network.badge.shield.half.filled",
                    text: localized("remoteWorkspace.placeholder.proxy", fallback: "Select a profile to manage proxy")
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
                    relayManager: relayManager,
                    localizer: localizer
                )
            } else {
                selectProfilePlaceholder(
                    icon: "point.3.connected.trianglepath.dotted",
                    text: localized("remoteWorkspace.placeholder.relay", fallback: "Select a profile to manage relay channels")
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
                    daemonManager: daemonManager,
                    localizer: localizer
                )
            } else {
                selectProfilePlaceholder(
                    icon: "server.rack",
                    text: localized("remoteWorkspace.placeholder.daemon", fallback: "Select a profile to manage remote daemon")
                )
            }
        }
    }

    private var keysSubPanel: some View {
        Group {
            if let vm = keyManagerVM {
                SSHKeyManagerView(viewModel: vm, localizer: localizer)
            } else if let keyManager = sshKeyManager {
                Color.clear.onAppear {
                    keyManagerVM = SSHKeyManagerViewModel(keyManager: keyManager, localizer: localizer)
                    keyManagerVM?.loadKeys()
                }
            } else {
                selectProfilePlaceholder(icon: "key", text: localized("remoteWorkspace.placeholder.keys", fallback: "SSH key management"))
            }
        }
    }

    private var sftpSubPanel: some View {
        Group {
            if let vm = sftpBrowserVM {
                SFTPBrowserView(viewModel: vm, localizer: localizer)
            } else if let profileID = viewModel.selectedProfileID,
                      let profile = viewModel.profiles.first(where: { $0.id == profileID }),
                      let executor = sftpExecutor {
                Color.clear.onAppear {
                    let client = SFTPClient(executor: executor)
                    let vm = SFTPBrowserViewModel(
                        sftpClient: client,
                        profile: profile,
                        localizer: localizer
                    )
                    sftpBrowserVM = vm
                    vm.loadDirectory()
                }
            } else {
                selectProfilePlaceholder(
                    icon: "folder",
                    text: localized("remoteWorkspace.placeholder.sftp", fallback: "Select a connected profile to browse files")
                )
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
        Group {
            if let editorViewModel = viewModel.profileEditorViewModel {
                RemoteProfileEditor(viewModel: editorViewModel, localizer: localizer)
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

// MARK: - Remote Browser Suggestions

private struct RemoteBrowserSuggestionsSection: View {
    @ObservedObject var scanner: RemotePortScanner
    let profile: RemoteConnectionProfile
    let isConnected: Bool
    let onOpenRemoteBrowser: ((RemoteConnectionProfile, RemoteBrowserOpenSuggestion) -> Bool)?
    var localizer: AppLocalizer

    @State private var errorMessage: String?
    @State private var isSwitchConfirmationPresented = false

    private var isActiveProfile: Bool {
        scanner.isScanning && scanner.scanningProfileID == profile.id
    }

    private var visibleRemotePorts: [Int] {
        Set(scanner.detectedPorts.map(\.port))
            .union(scanner.forwardedPortMappings.keys)
            .sorted()
    }

    var body: some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: CocxyColors.crust).opacity(0.35))
        .confirmationDialog(
            localized(
                "remoteWorkspace.browserSuggestions.switch.title",
                fallback: "Switch Remote Browser connection?"
            ),
            isPresented: $isSwitchConfirmationPresented
        ) {
            Button(
                localized(
                    "remoteWorkspace.browserSuggestions.switch.action",
                    fallback: "Stop current forwards and switch"
                ),
                role: .destructive,
                action: activateScan
            )
            Button(localized("common.cancel", fallback: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                localized(
                    "remoteWorkspace.browserSuggestions.switch.message",
                    fallback: "Remote Browser forwards on the other connection will be stopped."
                )
            )
        }
        .alert(
            localized("remoteWorkspace.browserSuggestions.error.title", fallback: "Remote Browser failed"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(localized("common.ok", fallback: "OK"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.blue))
            Text(localized("remoteWorkspace.browserSuggestions.title", fallback: "Remote Browser"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Spacer()

            if isActiveProfile {
                if scanner.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                        .accessibilityLabel(
                            localized("remoteWorkspace.browserSuggestions.scanning", fallback: "Scanning remote ports")
                        )
                } else {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .foregroundColor(Color(nsColor: CocxyColors.blue))
                    .accessibilityLabel(
                        localized("remoteWorkspace.browserSuggestions.refresh.accessibility", fallback: "Refresh remote ports")
                    )
                    .help(localized("remoteWorkspace.browserSuggestions.refresh", fallback: "Refresh Ports"))
                }
            } else {
                Button(action: requestScan) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .foregroundColor(
                    isConnected
                        ? Color(nsColor: CocxyColors.blue)
                        : Color(nsColor: CocxyColors.overlay0)
                )
                .disabled(!isConnected)
                .accessibilityLabel(
                    localized("remoteWorkspace.browserSuggestions.scan.accessibility", fallback: "Scan this remote connection")
                )
                .help(localized("remoteWorkspace.browserSuggestions.scan", fallback: "Scan Connection"))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !isConnected {
            statusRow(
                icon: "bolt.slash",
                text: localized(
                    "remoteWorkspace.browserSuggestions.disconnected",
                    fallback: "Connect this profile to discover services."
                )
            )
        } else if !isActiveProfile {
            statusRow(
                icon: "dot.radiowaves.left.and.right",
                text: localized(
                    "remoteWorkspace.browserSuggestions.inactive",
                    fallback: "Port discovery is inactive for this connection."
                )
            )
        } else if scanner.scanError != nil {
            statusRow(
                icon: "exclamationmark.triangle",
                text: localized(
                    "remoteWorkspace.browserSuggestions.scanFailed",
                    fallback: "Could not scan this connection."
                )
            )
        } else if scanner.isRefreshing && visibleRemotePorts.isEmpty {
            statusRow(
                icon: "magnifyingglass",
                text: localized(
                    "remoteWorkspace.browserSuggestions.scanning",
                    fallback: "Scanning remote ports"
                )
            )
        } else if visibleRemotePorts.isEmpty {
            statusRow(
                icon: "network.slash",
                text: localized(
                    "remoteWorkspace.browserSuggestions.empty",
                    fallback: "No listening ports detected."
                )
            )
        } else {
            ForEach(visibleRemotePorts, id: \.self) { remotePort in
                serviceRow(remotePort: remotePort)
            }
        }
    }

    private func statusRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 10))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
        .padding(.horizontal, 8)
        .frame(minHeight: 34)
    }

    private func serviceRow(remotePort: Int) -> some View {
        let info = scanner.detectedPorts.first { $0.port == remotePort }
        let localPort = scanner.forwardedPortMappings[remotePort]
        let isBusy = scanner.busyPorts.contains(remotePort)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    String(
                        format: localized("remoteWorkspace.browserSuggestions.port", fallback: "Remote :%d"),
                        remotePort
                    )
                )
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))

                Text(
                    info?.process
                        ?? localized("remoteWorkspace.browserSuggestions.unknownProcess", fallback: "remote service")
                )
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Text(localPort.map { "127.0.0.1:\($0)" } ?? (info?.address ?? "--"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                Button(action: { open(remotePort: remotePort) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(nsColor: CocxyColors.blue))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .disabled(onOpenRemoteBrowser == nil)
                .accessibilityLabel(
                    String(
                        format: localized(
                            "remoteWorkspace.browserSuggestions.open.accessibility",
                            fallback: "Open remote port %d in browser"
                        ),
                        remotePort
                    )
                )
                .help(
                    localPort == nil
                        ? localized(
                            "remoteWorkspace.browserSuggestions.forwardAndOpen",
                            fallback: "Forward and Open in Browser"
                        )
                        : localized("remoteWorkspace.browserSuggestions.open", fallback: "Open in Browser")
                )

                if localPort != nil {
                    Button(action: { stopForward(remotePort: remotePort) }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(nsColor: CocxyColors.red))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(
                        String(
                            format: localized(
                                "remoteWorkspace.browserSuggestions.stop.accessibility",
                                fallback: "Stop forwarding remote port %d"
                            ),
                            remotePort
                        )
                    )
                    .help(localized("remoteWorkspace.browserSuggestions.stop", fallback: "Stop Forward"))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: CocxyColors.surface1).opacity(0.55), lineWidth: 1)
        )
    }

    private func requestScan() {
        guard isConnected else { return }
        if scanner.scanningProfileID != nil,
           scanner.scanningProfileID != profile.id,
           !scanner.forwardedPortMappings.isEmpty {
            isSwitchConfirmationPresented = true
        } else {
            activateScan()
        }
    }

    private func activateScan() {
        errorMessage = nil
        scanner.startScanning(profileID: profile.id)
    }

    private func refresh() {
        Task { @MainActor in
            await scanner.refreshNow()
        }
    }

    private func open(remotePort: Int) {
        guard let onOpenRemoteBrowser else {
            errorMessage = localized(
                "remoteWorkspace.browserSuggestions.browserUnavailable",
                fallback: "No browser surface is available."
            )
            return
        }
        Task { @MainActor in
            do {
                _ = try await RemoteBrowserOpeningOperation.open(
                    remotePort: remotePort,
                    profile: profile,
                    scanner: scanner,
                    opener: onOpenRemoteBrowser
                )
            } catch {
                errorMessage = localizedError(error)
            }
        }
    }

    private func stopForward(remotePort: Int) {
        do {
            try scanner.cancelForwardedPort(remotePort)
        } catch {
            errorMessage = localizedError(error)
        }
    }

    private func localizedError(_ error: Error) -> String {
        guard let scannerError = error as? RemotePortScannerError else {
            return localized(
                "remoteWorkspace.browserSuggestions.error.generic",
                fallback: "The remote browser operation could not be completed."
            )
        }
        let key: String
        let fallback: String
        switch scannerError {
        case .inactive:
            key = "remoteWorkspace.browserSuggestions.error.inactive"
            fallback = "Port discovery is not active for this connection."
        case .portNotDetected:
            key = "remoteWorkspace.browserSuggestions.error.notDetected"
            fallback = "The remote service is no longer available."
        case .operationInProgress:
            key = "remoteWorkspace.browserSuggestions.error.inProgress"
            fallback = "Another operation is already in progress for this port."
        case .noAvailableLocalPort:
            key = "remoteWorkspace.browserSuggestions.error.noLocalPort"
            fallback = "No safe local port is available for this service."
        case .forwardingFailed:
            key = "remoteWorkspace.browserSuggestions.error.forwardFailed"
            fallback = "The remote service could not be opened."
        case .cancellationFailed:
            key = "remoteWorkspace.browserSuggestions.error.stopFailed"
            fallback = "The SSH forward could not be stopped."
        case .browserUnavailable:
            key = "remoteWorkspace.browserSuggestions.browserUnavailable"
            fallback = "No browser surface is available."
        case .scanFailed:
            key = "remoteWorkspace.browserSuggestions.scanFailed"
            fallback = "Could not scan this connection."
        }
        return localized(key, fallback: fallback)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
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
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            RemoteStatusIndicator(state: state, localizer: localizer)

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
        .accessibilityLabel(
            String(
                format: localized("remoteWorkspace.profile.accessibility", fallback: "%@, %@"),
                profile.name,
                stateDescription
            )
        )
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
            return String(
                format: localized("remoteWorkspace.profile.action.disconnect", fallback: "Disconnect from %@"),
                profile.name
            )
        case .connecting, .reconnecting:
            return String(
                format: localized("remoteWorkspace.profile.action.cancel", fallback: "Cancel connection to %@"),
                profile.name
            )
        case .disconnected, .failed:
            return String(
                format: localized("remoteWorkspace.profile.action.connect", fallback: "Connect to %@"),
                profile.name
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: onEdit) {
            Label(localized("remoteWorkspace.profile.menu.edit", fallback: "Edit"), systemImage: "pencil")
        }
        Button(action: onDuplicate) {
            Label(localized("remoteWorkspace.profile.menu.duplicate", fallback: "Duplicate"), systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label(localized("remoteWorkspace.profile.menu.delete", fallback: "Delete"), systemImage: "trash")
        }
    }

    // MARK: - State Description

    private var stateDescription: String {
        switch state {
        case .connected(let latencyMs):
            if let ms = latencyMs {
                return String(
                    format: localized("remoteWorkspace.profile.state.connectedLatency", fallback: "connected, %dms"),
                    ms
                )
            }
            return localized("remoteWorkspace.profile.state.connected", fallback: "connected")
        case .connecting:
            return localized("remoteWorkspace.profile.state.connecting", fallback: "connecting")
        case .reconnecting(let attempt):
            return String(
                format: localized("remoteWorkspace.profile.state.reconnecting", fallback: "reconnecting, attempt %d"),
                attempt
            )
        case .disconnected:
            return localized("remoteWorkspace.profile.state.disconnected", fallback: "disconnected")
        case .failed(let reason):
            return String(
                format: localized("remoteWorkspace.profile.state.failed", fallback: "failed: %@"),
                reason
            )
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
