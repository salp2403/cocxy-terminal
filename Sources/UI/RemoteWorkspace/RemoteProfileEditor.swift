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
    @Published private(set) var saveErrorMessage: String?

    // MARK: - Edit Mode

    /// The profile being edited; nil when creating a new profile.
    let existingProfile: RemoteConnectionProfile?

    /// Groups already in use by other profiles, for autocomplete suggestions.
    let existingGroups: [String]

    /// Callback invoked with the saved profile.
    var onSave: ((RemoteConnectionProfile) throws -> Void)?

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

    func localizedTitle(using localizer: AppLocalizer) -> String {
        if isEditing {
            return localizer.string("remoteWorkspace.profileEditor.title.edit", fallback: "Edit Profile")
        }
        return localizer.string("remoteWorkspace.profileEditor.title.new", fallback: "New Profile")
    }

    var isValid: Bool {
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let portIsValid = trimmedPort.isEmpty
            || Int(trimmedPort).map { (1...65_535).contains($0) } == true
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && portIsValid
            && invalidPortForwardIDs.isEmpty
            && invalidEnvironmentVariableIDs.isEmpty
            && duplicateEnvironmentVariableIDs.isEmpty
    }

    var invalidPortForwardIDs: Set<UUID> {
        Set(portForwards.filter { !$0.isValid }.map(\.id))
    }

    var invalidEnvironmentVariableIDs: Set<UUID> {
        Set(environmentVariables.compactMap { variable in
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = variable.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty && !value.isEmpty ? variable.id : nil
        })
    }

    var duplicateEnvironmentVariableIDs: Set<UUID> {
        let keyedVariables = Dictionary(grouping: environmentVariables) { variable in
            variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let duplicateGroups = keyedVariables.filter { key, variables in
            !key.isEmpty && variables.count > 1
        }
        return Set(duplicateGroups.values.flatMap { variables in variables.map(\.id) })
    }

    // MARK: - Actions

    @discardableResult
    func save() -> Bool {
        guard isValid else { return false }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentity = identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)

        var envVars: [String: String] = [:]
        for variable in environmentVariables {
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                envVars[key] = variable.value
            }
        }

        var savedPortForwards: [RemoteConnectionProfile.PortForward] = []
        for editableForward in portForwards {
            guard let forward = editableForward.toPortForward() else { return false }
            savedPortForwards.append(forward)
        }
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)

        let profile = RemoteConnectionProfile(
            id: existingProfile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            user: trimmedUsername.isEmpty ? nil : trimmedUsername,
            port: trimmedPort.isEmpty ? nil : Int(trimmedPort),
            identityFile: trimmedIdentity.isEmpty ? nil : trimmedIdentity,
            jumpHosts: jumpHosts.filter { !$0.isEmpty },
            portForwards: savedPortForwards,
            group: trimmedGroup.isEmpty ? nil : trimmedGroup,
            envVars: envVars,
            keepAliveInterval: keepAliveInterval,
            strictHostKeyChecking: existingProfile?.strictHostKeyChecking,
            knownHostsFile: existingProfile?.knownHostsFile,
            batchMode: existingProfile?.batchMode,
            autoReconnect: autoReconnect,
            proxyExclusions: existingProfile?.proxyExclusions ?? [],
            relayChannels: existingProfile?.relayChannels ?? []
        )

        do {
            try onSave?(profile)
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
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

    func pickIdentityFile(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        let panel = NSOpenPanel()
        panel.title = localizer.string(
            "remoteWorkspace.profileEditor.identityPanel.title",
            fallback: "Select SSH Identity File"
        )
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
    var localHost: String = "localhost"
    var remoteHost: String = "localhost"

    init() {}

    init(from forward: RemoteConnectionProfile.PortForward) {
        switch forward {
        case let .local(lp, rp, remoteHost):
            type = .local
            localPort = String(lp)
            remotePort = String(rp)
            self.remoteHost = remoteHost
        case let .remote(rp, lp, localHost):
            type = .remote
            localPort = String(lp)
            remotePort = String(rp)
            self.localHost = localHost
        case let .dynamic(lp):
            type = .dynamic
            localPort = String(lp)
        }
    }

    var isValid: Bool { toPortForward() != nil }

    func toPortForward() -> RemoteConnectionProfile.PortForward? {
        let trimmedLocalPort = localPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lp = Int(trimmedLocalPort), (1...65_535).contains(lp) else { return nil }

        switch type {
        case .local:
            let targetHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedRemotePort = remotePort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetHost.isEmpty,
                  let rp = Int(trimmedRemotePort),
                  (1...65_535).contains(rp)
            else { return nil }
            return .local(localPort: lp, remotePort: rp, remoteHost: targetHost)
        case .remote:
            let targetHost = localHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedRemotePort = remotePort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetHost.isEmpty,
                  let rp = Int(trimmedRemotePort),
                  (1...65_535).contains(rp)
            else { return nil }
            return .remote(remotePort: rp, localPort: lp, localHost: targetHost)
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
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
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
            if let saveErrorMessage = viewModel.saveErrorMessage {
                Divider()
                saveErrorSection(saveErrorMessage)
            }
            Divider()
            footerButtons
        }
        .frame(width: 420, height: 500)
        .glassPanelBackground()
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(viewModel.localizedTitle(using: localizer))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(nsColor: CocxyColors.text))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    // MARK: - Connection Fields

    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            editorField(
                label: localized("remoteWorkspace.profileEditor.field.name", fallback: "Name"),
                placeholder: localized("remoteWorkspace.profileEditor.placeholder.name", fallback: "production-web"),
                text: $viewModel.name
            )

            editorField(
                label: localized("remoteWorkspace.profileEditor.field.host", fallback: "Host"),
                placeholder: localized("remoteWorkspace.profileEditor.placeholder.host", fallback: "192.168.1.100 or host.example.com"),
                text: $viewModel.host
            )

            editorField(
                label: localized("remoteWorkspace.profileEditor.field.username", fallback: "Username"),
                placeholder: localized("remoteWorkspace.profileEditor.placeholder.username", fallback: "deploy"),
                text: $viewModel.username
            )

            editorField(
                label: localized("remoteWorkspace.profileEditor.field.port", fallback: "Port"),
                placeholder: localized("remoteWorkspace.profileEditor.placeholder.port", fallback: "22"),
                text: $viewModel.port
            )
                .frame(width: 100)

            identityFileField
        }
    }

    // MARK: - Identity File

    private var identityFileField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("remoteWorkspace.profileEditor.field.identityFile", fallback: "Identity File"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

            HStack(spacing: 6) {
                TextField("~/.ssh/id_ed25519", text: $viewModel.identityFile)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button(action: { viewModel.pickIdentityFile(localizer: localizer) }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(Color(nsColor: CocxyColors.surface0))
                .cornerRadius(6)
                .accessibilityLabel(localized("remoteWorkspace.profileEditor.identity.browse.accessibility", fallback: "Browse for identity file"))
            }
        }
    }

    // MARK: - Group Field

    private var groupField: some View {
        VStack(alignment: .leading, spacing: 4) {
            editorField(
                label: localized("remoteWorkspace.profileEditor.field.group", fallback: "Group"),
                placeholder: localized("remoteWorkspace.profileEditor.placeholder.group", fallback: "production, staging, personal..."),
                text: $viewModel.group
            )

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
            title: localized("remoteWorkspace.profileEditor.section.jumpHosts", fallback: "Jump Hosts"),
            count: viewModel.jumpHosts.count,
            onAdd: { viewModel.addJumpHost() }
        ) {
            ForEach(viewModel.jumpHosts.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    TextField(
                        Self.localizedJumpHostPlaceholder(using: localizer),
                        text: $viewModel.jumpHosts[index]
                    )
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
            title: localized("remoteWorkspace.profileEditor.section.portForwards", fallback: "Port Forwards"),
            count: viewModel.portForwards.count,
            onAdd: { viewModel.addPortForward() }
        ) {
            ForEach(viewModel.portForwards.indices, id: \.self) { index in
                if viewModel.portForwards[index].type == .dynamic {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(Color(nsColor: CocxyColors.yellow))
                        Text(localized(
                            "remoteWorkspace.profileEditor.dynamicDisabled",
                            fallback: "Legacy dynamic forward disabled; use Proxy"
                        ))
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                        Spacer()
                        removeButton { viewModel.removePortForward(at: index) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Picker(
                                localized("remoteWorkspace.portForward.type", fallback: "Type"),
                                selection: $viewModel.portForwards[index].type
                            ) {
                                ForEach(ForwardTypeOption.creatableCases) { option in
                                    Text(option.localizedLabel(using: localizer)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 170)
                            .labelsHidden()
                            .accessibilityLabel(localized("remoteWorkspace.portForward.type", fallback: "Type"))

                            Spacer()
                            removeButton { viewModel.removePortForward(at: index) }
                        }

                        portForwardEndpointFields(at: index)

                        if viewModel.invalidPortForwardIDs.contains(viewModel.portForwards[index].id) {
                            validationMessage(
                                localized(
                                    "remoteWorkspace.profileEditor.validation.portForward",
                                    fallback: "Enter valid ports and a destination host."
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func portForwardEndpointFields(at index: Int) -> some View {
        let type = viewModel.portForwards[index].type

        VStack(alignment: .leading, spacing: 6) {
            if type == .local {
                portField(
                    localized("remoteWorkspace.portForward.localPort", fallback: "Local Port"),
                    text: $viewModel.portForwards[index].localPort
                )

                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right")
                        .frame(width: 14)
                        .accessibilityHidden(true)

                    hostField(
                        localized("remoteWorkspace.profileEditor.portForward.remoteHost", fallback: "Remote host"),
                        text: $viewModel.portForwards[index].remoteHost
                    )

                    portField(
                        localized("remoteWorkspace.portForward.remotePort", fallback: "Remote Port"),
                        text: $viewModel.portForwards[index].remotePort
                    )
                }
            } else {
                portField(
                    localized("remoteWorkspace.portForward.remotePort", fallback: "Remote Port"),
                    text: $viewModel.portForwards[index].remotePort
                )

                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right")
                        .frame(width: 14)
                        .accessibilityHidden(true)

                    hostField(
                        localized("remoteWorkspace.profileEditor.portForward.localHost", fallback: "Local host"),
                        text: $viewModel.portForwards[index].localHost
                    )

                    portField(
                        localized("remoteWorkspace.portForward.localPort", fallback: "Local Port"),
                        text: $viewModel.portForwards[index].localPort
                    )
                }
            }
        }
    }

    private func portField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 116)
            .accessibilityLabel(placeholder)
    }

    private func hostField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .accessibilityLabel(placeholder)
    }

    // MARK: - Environment Variables

    private var environmentSection: some View {
        listSection(
            title: localized("remoteWorkspace.profileEditor.section.environment", fallback: "Environment Variables"),
            count: viewModel.environmentVariables.count,
            onAdd: { viewModel.addEnvironmentVariable() }
        ) {
            ForEach(viewModel.environmentVariables.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField(
                            Self.localizedEnvironmentKeyPlaceholder(using: localizer),
                            text: $viewModel.environmentVariables[index].key
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 100)

                        Text("=")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))

                        TextField(
                            Self.localizedEnvironmentValuePlaceholder(using: localizer),
                            text: $viewModel.environmentVariables[index].value
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                        removeButton { viewModel.removeEnvironmentVariable(at: index) }
                    }

                    if viewModel.duplicateEnvironmentVariableIDs.contains(viewModel.environmentVariables[index].id) {
                        validationMessage(
                            localized(
                                "remoteWorkspace.profileEditor.validation.duplicateEnvironment",
                                fallback: "Environment variable keys must be unique."
                            )
                        )
                    } else if viewModel.invalidEnvironmentVariableIDs.contains(viewModel.environmentVariables[index].id) {
                        validationMessage(
                            localized(
                                "remoteWorkspace.profileEditor.validation.environmentKey",
                                fallback: "Enter a key or remove this row."
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("remoteWorkspace.profileEditor.section.advanced", fallback: "Advanced"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

            HStack {
                Text(localized("remoteWorkspace.profileEditor.keepAlive", fallback: "Keep Alive Interval"))
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
                Text(localized("remoteWorkspace.profileEditor.autoReconnect", fallback: "Auto Reconnect"))
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

            Button(localized("common.cancel", fallback: "Cancel")) { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

            Button(viewModel.isEditing
                ? localized("common.save", fallback: "Save")
                : localized("remoteWorkspace.profileEditor.create", fallback: "Create")
            ) {
                if viewModel.save() {
                    dismiss()
                }
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
        .accessibilityLabel(localized("remoteWorkspace.profileEditor.remove.accessibility", fallback: "Remove"))
    }

    private func saveErrorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(
                String(
                    format: localized(
                        "remoteWorkspace.profileEditor.saveFailed",
                        fallback: "Could not save profile: %@"
                    ),
                    message
                )
            )
            .font(.system(size: 10))
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(Color(nsColor: CocxyColors.red))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func validationMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 9))
            .foregroundColor(Color(nsColor: CocxyColors.red))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func localizedJumpHostPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string(
            "remoteWorkspace.profileEditor.placeholder.jumpHost",
            fallback: "bastion.example.com"
        )
    }

    static func localizedEnvironmentKeyPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string(
            "remoteWorkspace.profileEditor.placeholder.environmentKey",
            fallback: "KEY"
        )
    }

    static func localizedEnvironmentValuePlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string(
            "remoteWorkspace.profileEditor.placeholder.environmentValue",
            fallback: "value"
        )
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
