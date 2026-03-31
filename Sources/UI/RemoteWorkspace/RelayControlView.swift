// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayControlView.swift - UI for multi-channel relay management.

import SwiftUI

// MARK: - Relay Control View

/// Sub-panel for managing relay channels.
///
/// Connected to `RelayManagerImpl` for real reverse tunnel operations.
/// Shows channel list, add form, per-channel controls, and token management.
struct RelayControlView: View {

    let profileID: UUID
    @ObservedObject var viewModel: RemoteConnectionViewModel
    @ObservedObject var relayManager: RelayManagerImpl

    @State private var newChannelName: String = ""
    @State private var newLocalPort: String = ""
    @State private var newRemotePort: String = ""
    @State private var errorMessage: String?
    @State private var showingAuditFor: UUID?
    @State private var auditEntries: [String] = []
    @State private var editingACLFor: UUID?
    @State private var aclProcesses: String = ""
    @State private var aclMaxConn: String = "10"
    @State private var aclHosts: String = "127.0.0.1"

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
            relayStatsSection
            Divider()
            channelListSection
            Divider()
            addChannelSection
            if let errorMessage {
                Divider()
                errorSection(errorMessage)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 24))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text("Connect to the profile first to manage relay channels")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Channel List

    private var channelListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Channels")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            let channels = relayManager.listChannels(profileID: profileID)

            if channels.isEmpty {
                Text("No active channels")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            } else {
                ForEach(channels, id: \.id) { channel in
                    channelRow(channel)
                }
            }
        }
    }

    private func channelRow(_ channel: RelayChannel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(channel.isExpired ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(channel.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Button(action: { relayManager.closeChannel(channelID: channel.id) }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("\(channel.localHost):\(channel.localPort)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text("remote:\(channel.remotePort)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                Spacer()
                Text(verbatim: "\(channel.connectionCount) conn")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }

            // Created timestamp.
            Text("Created \(channel.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 8))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))

            // ACL summary.
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 8))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text(aclSummary(channel.acl))
                    .font(.system(size: 8))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }

            // Action buttons.
            HStack(spacing: 8) {
                Button("Rotate Token") {
                    relayManager.rotateToken(channelID: channel.id)
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.mauve))

                Button("View Audit") {
                    loadAuditEntries(for: channel.id)
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.blue))

                Button("Edit ACL") {
                    beginEditingACL(channel)
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.yellow))
            }

            // Inline audit log viewer.
            if showingAuditFor == channel.id {
                auditLogViewer(channelID: channel.id)
            }

            // Inline ACL editor.
            if editingACLFor == channel.id {
                aclEditor(channelID: channel.id)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.5))
        )
    }

    private func aclSummary(_ acl: RelayACL) -> String {
        let hosts = acl.allowedRemoteHosts.joined(separator: ", ")
        let procs = acl.allowedProcesses.isEmpty ? "all" : acl.allowedProcesses.joined(separator: ", ")
        return "Hosts: \(hosts) | Procs: \(procs) | Max: \(acl.maxConnections)"
    }

    // MARK: - Audit Log Viewer

    private func auditLogViewer(channelID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Audit Log")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Button(action: { showingAuditFor = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }

            let filtered = auditEntries.filter { $0.contains(channelID.uuidString) }
            if filtered.isEmpty {
                Text("No audit entries for this channel")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            } else {
                ForEach(Array(filtered.suffix(10).enumerated()), id: \.offset) { _, entry in
                    Text(formatAuditEntry(entry))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .lineLimit(1)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: CocxyColors.mantle).opacity(0.6))
        )
    }

    // MARK: - ACL Editor

    private func aclEditor(channelID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Edit ACL")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Button(action: { editingACLFor = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }

            HStack(spacing: 4) {
                Text("Hosts:")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("127.0.0.1", text: $aclHosts)
                    .font(.system(size: 9, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 4) {
                Text("Procs:")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("(empty = all)", text: $aclProcesses)
                    .font(.system(size: 9, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 4) {
                Text("Max:")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("10", text: $aclMaxConn)
                    .font(.system(size: 9, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 40)
            }

            HStack(spacing: 8) {
                Button("Save ACL") {
                    saveACL(channelID: channelID)
                }
                .font(.system(size: 9, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.green))

                Text("Changes apply to new connections only.")
                    .font(.system(size: 8))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: CocxyColors.mantle).opacity(0.6))
        )
    }

    // MARK: - Add Channel

    private var addChannelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Channel")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            HStack(spacing: 4) {
                TextField("Name", text: $newChannelName)
                    .font(.system(size: 10))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 4) {
                Text("Local:")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("3000", text: $newLocalPort)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("Remote:")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("9000", text: $newRemotePort)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            Button(action: addChannel) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                    Text("Open Channel")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: CocxyColors.mauve))
            .disabled(newChannelName.isEmpty || newLocalPort.isEmpty || newRemotePort.isEmpty)
        }
    }

    // MARK: - Error Section

    // MARK: - Stats Section

    private var relayStatsSection: some View {
        let channels = relayManager.listChannels(profileID: profileID)
        let totalConnections = channels.reduce(0) { $0 + $1.connectionCount }

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Channels")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text(verbatim: "\(channels.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Connections")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text(verbatim: "\(totalConnections)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
            }
            Spacer()
        }
    }

    private func errorSection(_ message: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    // MARK: - Audit Helpers

    private func loadAuditEntries(for channelID: UUID) {
        if showingAuditFor == channelID {
            showingAuditFor = nil
            return
        }
        let reader = DiskAuditLogWriter()
        auditEntries = (try? reader.readAllLines()) ?? []
        showingAuditFor = channelID
    }

    private func formatAuditEntry(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json }
        let event = dict["event"] as? String ?? "?"
        let ts = dict["timestamp"] as? String ?? ""
        let shortTs = String(ts.suffix(8)) // HH:MM:SSZ
        return "\(shortTs) \(event)"
    }

    // MARK: - ACL Helpers

    private func beginEditingACL(_ channel: RelayChannel) {
        if editingACLFor == channel.id {
            editingACLFor = nil
            return
        }
        aclProcesses = channel.acl.allowedProcesses.joined(separator: ", ")
        aclMaxConn = "\(channel.acl.maxConnections)"
        aclHosts = channel.acl.allowedRemoteHosts.joined(separator: ", ")
        editingACLFor = channel.id
    }

    private func saveACL(channelID: UUID) {
        let hosts = aclHosts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let processes = aclProcesses
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let maxConn = Int(aclMaxConn) ?? 10

        let newACL = RelayACL(
            allowedProcesses: processes,
            maxConnections: max(1, maxConn),
            allowedRemoteHosts: hosts.isEmpty ? ["127.0.0.1"] : hosts
        )
        relayManager.updateACL(channelID: channelID, acl: newACL)
        editingACLFor = nil
    }

    // MARK: - Channel Actions

    private func addChannel() {
        guard let localPort = Int(newLocalPort), (1...65535).contains(localPort),
              let remotePort = Int(newRemotePort), (1...65535).contains(remotePort)
        else {
            errorMessage = "Invalid port numbers"
            return
        }

        errorMessage = nil
        let config = RelayChannelConfig(
            name: newChannelName.trimmingCharacters(in: .whitespaces),
            localPort: localPort,
            remotePort: remotePort
        )

        do {
            try relayManager.openChannel(config: config, profileID: profileID)
            newChannelName = ""
            newLocalPort = ""
            newRemotePort = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
