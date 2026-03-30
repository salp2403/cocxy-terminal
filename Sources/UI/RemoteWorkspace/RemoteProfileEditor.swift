// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteProfileEditor.swift - Form for creating and editing SSH connection profiles.

import SwiftUI

// MARK: - Profile Editor View Model

/// Drives the profile creation/editing sheet.
///
/// Initializes fields from an existing profile (edit mode) or with defaults
/// (create mode). Validates required fields and produces a
/// `RemoteConnectionProfile` on save.
@MainActor
final class RemoteProfileEditorViewModel: ObservableObject {

    // MARK: - Published Form State

    @Published var name: String = ""
    @Published var host: String = ""
    @Published var username: String = ""
    @Published var port: String = "22"
    @Published var identityFile: String = ""
    @Published var jumpHosts: [String] = []
    @Published var portForwards: [EditablePortForward] = []
    @Published var group: String = ""
    @Published var environmentVariables: [EditableKeyValue] = []
    @Published var keepAliveInterval: Int = 60
    @Published var autoReconnect: Bool = true
    @Published var isTesting: Bool = false
    @Published var testResult: String?

    // MARK: - Edit Mode

    /// The profile being edited; nil when creating a new profile.
    let existingProfile: RemoteConnectionProfile?

    /// Groups already in use by other profiles, for autocomplete suggestions.
    let existingGroups: [String]

    /// Callback invoked with the saved profile.
    var onSave: ((RemoteConnectionProfile) -> Void)?

    // MARK: - Initialization

    init(
        profile: RemoteConnectionProfile? = nil,
        existingGroups: [String] = []
    ) {
        self.existingProfile = profile
        self.existingGroups = existingGroups

        if let profile {
            name = profile.name
            host = profile.host
            username = profile.user ?? ""
            port = profile.port.map(String.init) ?? "22"
            identityFile = profile.identityFile ?? ""
            jumpHosts = profile.jumpHosts
            portForwards = profile.portForwards.map(EditablePortForward.init)
            group = profile.group ?? ""
            environmentVariables = profile.envVars.map { EditableKeyValue(key: $0.key, value: $0.value) }
            keepAliveInterval = profile.keepAliveInterval
            autoReconnect = profile.autoReconnect
        }
    }

    // MARK: - Computed Properties

    var isEditing: Bool { existingProfile != nil }

    var title: String { isEditing ? "Edit Profile" : "New Profile" }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    func save() {
        guard isValid else { return }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentity = identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)

        let envVars: [String: String] = Dictionary(
            uniqueKeysWithValues: environmentVariables
                .filter { !$0.key.isEmpty }
                .map { ($0.key, $0.value) }
        )

        let profile = RemoteConnectionProfile(
            id: existingProfile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            user: trimmedUsername.isEmpty ? nil : trimmedUsername,
            port: Int(port),
            identityFile: trimmedIdentity.isEmpty ? nil : trimmedIdentity,
            jumpHosts: jumpHosts.filter { !$0.isEmpty },
            portForwards: portForwards.compactMap { $0.toPortForward() },
            group: trimmedGroup.isEmpty ? nil : trimmedGroup,
            envVars: envVars,
            keepAliveInterval: keepAliveInterval,
            autoReconnect: autoReconnect,
            proxyExclusions: existingProfile?.proxyExclusions ?? [],
            relayChannels: existingProfile?.relayChannels ?? []
        )

        onSave?(profile)
    }

    // MARK: - Jump Host Management

    func addJumpHost() {
        jumpHosts.append("")
    }

    func removeJumpHost(at index: Int) {
        guard jumpHosts.indices.contains(index) else { return }
        jumpHosts.remove(at: index)
    }

    // MARK: - Port Forward Management

    func addPortForward() {
        portForwards.append(EditablePortForward())
    }

    func removePortForward(at index: Int) {
        guard portForwards.indices.contains(index) else { return }
        portForwards.remove(at: index)
    }

    // MARK: - Environment Variable Management

    func addEnvironmentVariable() {
        environmentVariables.append(EditableKeyValue())
    }

    func removeEnvironmentVariable(at index: Int) {
        guard environmentVariables.indices.contains(index) else { return }
        environmentVariables.remove(at: index)
    }

    // MARK: - Identity File Picker

    func pickIdentityFile() {
        let panel = NSOpenPanel()
        panel.title = "Select SSH Identity File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let sshDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        panel.directoryURL = sshDirectory

        if panel.runModal() == .OK, let url = panel.url {
            identityFile = url.path
        }
    }
}

// MARK: - Editable Port Forward

/// Mutable representation of a port forward for form editing.
struct EditablePortForward: Identifiable {

    let id = UUID()
    var type: ForwardTypeOption = .local
    var localPort: String = ""
    var remotePort: String = ""

    init() {}

    init(from forward: RemoteConnectionProfile.PortForward) {
        switch forward {
        case let .local(lp, rp, _):
            type = .local
            localPort = String(lp)
            remotePort = String(rp)
        case let .remote(rp, lp, _):
            type = .remote
            localPort = String(lp)
            remotePort = String(rp)
        case let .dynamic(lp):
            type = .dynamic
            localPort = String(lp)
        }
    }

    func toPortForward() -> RemoteConnectionProfile.PortForward? {
        guard let lp = Int(localPort), lp > 0 else { return nil }

        switch type {
        case .local:
            guard let rp = Int(remotePort), rp > 0 else { return nil }
            return .local(localPort: lp, remotePort: rp)
        case .remote:
            guard let rp = Int(remotePort), rp > 0 else { return nil }
            return .remote(remotePort: rp, localPort: lp)
        case .dynamic:
            return .dynamic(localPort: lp)
        }
    }
}

// MARK: - Editable Key-Value

/// Mutable key-value pair for environment variables.
struct EditableKeyValue: Identifiable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}

// MARK: - Remote Profile Editor View

/// Sheet-presented form for creating or editing an SSH connection profile.
///
/// ## Layout
///
/// ```
/// +-- New Profile / Edit Profile -----------------+
/// |                                               |
/// | Name:       [________________________]        |
/// | Host:       [________________________] *      |
/// | Username:   [________________________]        |
/// | Port:       [22_____]                         |
/// | Identity:   [________________] [Browse]       |
/// | Group:      [________________________]        |
/// |                                               |
/// | Jump Hosts  [+]                               |
/// |   [host1_________________] [-]                |
/// |                                               |
/// | Port Forwards  [+]                            |
/// |   Local [8080] -> [8080]  [-]                 |
/// |                                               |
/// | Environment Variables  [+]                    |
/// |   [KEY] = [VALUE]  [-]                        |
/// |                                               |
/// | Keep Alive: [60]s                             |
/// | Auto Reconnect: [toggle]                      |
/// |                                               |
/// |              [Cancel]  [Save]                  |
/// +-----------------------------------------------+
/// ```
///
/// - SeeAlso: `RemoteProfileEditorViewModel`
struct RemoteProfileEditor: View {

    @ObservedObject var viewModel: RemoteProfileEditorViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    connectionFields
                    groupField
                    jumpHostsSection
                    portForwardsSection
                    environmentSection
                    advancedSection
                }
                .padding(16)
            }
            Divider()
            footerButtons
        }
        .frame(width: 420, height: 500)
        .background(Color(nsColor: CocxyColors.mantle))
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(viewModel.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(nsColor: CocxyColors.text))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    // MARK: - Connection Fields

    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            editorField(label: "Name", placeholder: "production-web", text: $viewModel.name)

            editorField(label: "Host", placeholder: "192.168.1.100 or host.example.com", text: $viewModel.host)

            editorField(label: "Username", placeholder: "deploy", text: $viewModel.username)

            editorField(label: "Port", placeholder: "22", text: $viewModel.port)
                .frame(width: 100)

            identityFileField
        }
    }

    // MARK: - Identity File

    private var identityFileField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Identity File")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

            HStack(spacing: 6) {
                TextField("~/.ssh/id_ed25519", text: $viewModel.identityFile)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button(action: { viewModel.pickIdentityFile() }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(Color(nsColor: CocxyColors.surface0))
                .cornerRadius(6)
                .accessibilityLabel("Browse for identity file")
            }
        }
    }

    // MARK: - Group Field

    private var groupField: some View {
        VStack(alignment: .leading, spacing: 4) {
            editorField(label: "Group", placeholder: "production, staging, personal...", text: $viewModel.group)

            if !viewModel.existingGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(viewModel.existingGroups, id: \.self) { groupName in
                            Button(action: { viewModel.group = groupName }) {
                                Text(groupName)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: CocxyColors.surface0))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Jump Hosts

    private var jumpHostsSection: some View {
        listSection(
            title: "Jump Hosts",
            count: viewModel.jumpHosts.count,
            onAdd: { viewModel.addJumpHost() }
        ) {
            ForEach(viewModel.jumpHosts.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    TextField("bastion.example.com", text: $viewModel.jumpHosts[index])
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    removeButton { viewModel.removeJumpHost(at: index) }
                }
            }
        }
    }

    // MARK: - Port Forwards

    private var portForwardsSection: some View {
        listSection(
            title: "Port Forwards",
            count: viewModel.portForwards.count,
            onAdd: { viewModel.addPortForward() }
        ) {
            ForEach(viewModel.portForwards.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Picker("", selection: $viewModel.portForwards[index].type) {
                        Text("L").tag(ForwardTypeOption.local)
                        Text("R").tag(ForwardTypeOption.remote)
                        Text("D").tag(ForwardTypeOption.dynamic)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .labelsHidden()

                    TextField("Local", text: $viewModel.portForwards[index].localPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 60)

                    if viewModel.portForwards[index].type != .dynamic {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))

                        TextField("Remote", text: $viewModel.portForwards[index].remotePort)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 60)
                    }

                    Spacer()
                    removeButton { viewModel.removePortForward(at: index) }
                }
            }
        }
    }

    // MARK: - Environment Variables

    private var environmentSection: some View {
        listSection(
            title: "Environment Variables",
            count: viewModel.environmentVariables.count,
            onAdd: { viewModel.addEnvironmentVariable() }
        ) {
            ForEach(viewModel.environmentVariables.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    TextField("KEY", text: $viewModel.environmentVariables[index].key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 100)

                    Text("=")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))

                    TextField("value", text: $viewModel.environmentVariables[index].value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    removeButton { viewModel.removeEnvironmentVariable(at: index) }
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Advanced")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

            HStack {
                Text("Keep Alive Interval")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Stepper(
                    "\(viewModel.keepAliveInterval)s",
                    value: $viewModel.keepAliveInterval,
                    in: 0...300,
                    step: 10
                )
                .font(.system(size: 11, design: .monospaced))
            }

            HStack {
                Text("Auto Reconnect")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Toggle("", isOn: $viewModel.autoReconnect)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack {
            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

            Button(viewModel.isEditing ? "Save" : "Create") {
                viewModel.save()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: CocxyColors.blue))
            .disabled(!viewModel.isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Reusable Components

    private func editorField(
        label: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private func listSection<Content: View>(
        title: String,
        count: Int,
        onAdd: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(nsColor: CocxyColors.crust))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: CocxyColors.overlay0))
                        .cornerRadius(4)
                }

                Spacer()

                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: CocxyColors.blue))
                }
                .buttonStyle(.plain)
            }

            content()
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: CocxyColors.red).opacity(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }
}
