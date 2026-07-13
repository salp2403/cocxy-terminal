// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayControlView.swift - UI for multi-channel relay management.

import AppKit
import SwiftUI

// MARK: - Relay Control View

/// Sub-panel for managing relay channels.
///
/// Connected to `RelayManagerImpl` for real reverse tunnel operations.
/// Shows channel list, add form, per-channel controls, and token management.
struct RelayControlView: View {

    private enum CopiedItem: Equatable {
        case command(UUID)
        case token(UUID)
    }

    let profileID: UUID
    @ObservedObject var viewModel: RemoteConnectionViewModel
    @ObservedObject var relayManager: RelayManagerImpl
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    @State private var newChannelName: String = ""
    @State private var newLocalPort: String = ""
    @State private var newRemotePort: String = ""
    @State private var errorMessage: String?
    @State private var showingAuditFor: UUID?
    @State private var auditEntries: [String] = []
    @State private var editingACLFor: UUID?
    @State private var aclMaxConn: String = "10"
    @State private var isOpeningChannel = false
    @State private var copiedItem: CopiedItem?

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
        } else if !relayManager.listChannels(profileID: profileID).isEmpty {
            relayStatsSection
            Divider()
            channelListSection
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
                Text(localized("remoteWorkspace.relay.connectFirst", fallback: "Connect to the profile first to manage relay channels"))
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
            Text(localized("remoteWorkspace.relay.activeChannels", fallback: "Relay Channels"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            let channels = relayManager.listChannels(profileID: profileID)

            if channels.isEmpty {
                Text(localized("remoteWorkspace.relay.noActiveChannels", fallback: "No active channels"))
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
                    .fill(channelStatusColor(channel))
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
                .help(localized("remoteWorkspace.relay.close", fallback: "Close relay channel"))
                .accessibilityLabel(
                    localized("remoteWorkspace.relay.close", fallback: "Close relay channel")
                )
            }

            HStack(spacing: 8) {
                Text("\(channel.localHost):\(channel.localPort)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text(
                    String(
                        format: localized("remoteWorkspace.relay.remotePort", fallback: "remote:%d"),
                        channel.remotePort
                    )
                )
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                Spacer()
                Text(
                    String(
                        format: localized("remoteWorkspace.relay.connectionCount", fallback: "%d conn"),
                        channel.connectionCount
                    )
                )
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }

            // Created timestamp.
            Text(
                String(
                    format: localized("remoteWorkspace.relay.created", fallback: "Created %@"),
                    channel.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
            )
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

            if let statusMessage = channelStatusMessage(channel.status) {
                Text(statusMessage)
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // Action buttons.
            HStack(spacing: 8) {
                Button(action: { copyClientCommand(channelID: channel.id) }) {
                    Image(systemName: copiedItem == .command(channel.id) ? "checkmark" : "terminal")
                        .font(.system(size: 9))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.green))
                .disabled(!channel.status.isActive)
                .help(
                    localized(
                        "remoteWorkspace.relay.copyClientCommand",
                        fallback: "Copy authenticated client command"
                    )
                )
                .accessibilityLabel(
                    localized(
                        "remoteWorkspace.relay.copyClientCommand",
                        fallback: "Copy authenticated client command"
                    )
                )

                Button(action: { copyClientToken(channelID: channel.id) }) {
                    Image(systemName: copiedItem == .token(channel.id) ? "checkmark" : "key.horizontal")
                        .font(.system(size: 9))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.yellow))
                .disabled(!channel.status.isActive)
                .help(
                    localized(
                        "remoteWorkspace.relay.copyClientToken",
                        fallback: "Copy relay token"
                    )
                )
                .accessibilityLabel(
                    localized(
                        "remoteWorkspace.relay.copyClientToken",
                        fallback: "Copy relay token"
                    )
                )

                Button {
                    do {
                        try relayManager.rotateToken(channelID: channel.id)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.mauve))
                .disabled(!channel.status.isActive)
                .help(localized("remoteWorkspace.relay.rotateToken", fallback: "Rotate token"))
                .accessibilityLabel(
                    localized("remoteWorkspace.relay.rotateToken", fallback: "Rotate token")
                )

                Button {
                    loadAuditEntries(for: channel.id)
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.blue))
                .help(localized("remoteWorkspace.relay.viewAudit", fallback: "View audit log"))
                .accessibilityLabel(
                    localized("remoteWorkspace.relay.viewAudit", fallback: "View audit log")
                )

                Button {
                    beginEditingACL(channel)
                } label: {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.yellow))
                .disabled(!channel.status.isActive)
                .help(
                    localized(
                        "remoteWorkspace.relay.editACL",
                        fallback: "Edit connection limit"
                    )
                )
                .accessibilityLabel(
                    localized(
                        "remoteWorkspace.relay.editACL",
                        fallback: "Edit connection limit"
                    )
                )
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
        return String(
            format: localized("remoteWorkspace.relay.connectionLimit", fallback: "Max connections: %d"),
            acl.maxConnections
        )
    }

    private func channelStatusColor(_ channel: RelayChannel) -> Color {
        if channel.isExpired { return .orange }
        switch channel.status {
        case .active:
            return .green
        case .closeFailed, .brokerFailed:
            return .red
        }
    }

    private func channelStatusMessage(_ status: RelayChannelStatus) -> String? {
        switch status {
        case .active:
            return nil
        case .closeFailed(let reason):
            return String(
                format: localized(
                    "remoteWorkspace.relay.closeFailed",
                    fallback: "Could not close the SSH listener. Access is blocked locally; retry close. %@"
                ),
                reason
            )
        case .brokerFailed(let reason):
            return String(
                format: localized(
                    "remoteWorkspace.relay.brokerFailed",
                    fallback: "Authentication broker failed and remote forwarding may still exist. Retry close. %@"
                ),
                reason
            )
        }
    }

    // MARK: - Audit Log Viewer

    private func auditLogViewer(channelID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localized("remoteWorkspace.relay.auditLog", fallback: "Audit Log"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Button(action: { showingAuditFor = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .help(
                    localized(
                        "remoteWorkspace.relay.closeAudit",
                        fallback: "Close audit log"
                    )
                )
                .accessibilityLabel(
                    localized(
                        "remoteWorkspace.relay.closeAudit",
                        fallback: "Close audit log"
                    )
                )
            }

            let filtered = auditEntries.filter { $0.contains(channelID.uuidString) }
            if filtered.isEmpty {
                Text(localized("remoteWorkspace.relay.noAuditEntries", fallback: "No audit entries for this channel"))
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
                Text(
                    localized(
                        "remoteWorkspace.relay.editACL",
                        fallback: "Edit Connection Limit"
                    )
                )
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Button(action: { editingACLFor = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .help(
                    localized(
                        "remoteWorkspace.relay.closeLimitEditor",
                        fallback: "Close connection limit editor"
                    )
                )
                .accessibilityLabel(
                    localized(
                        "remoteWorkspace.relay.closeLimitEditor",
                        fallback: "Close connection limit editor"
                    )
                )
            }

            HStack(spacing: 4) {
                Text(localized("remoteWorkspace.relay.max", fallback: "Max:"))
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("10", text: $aclMaxConn)
                    .font(.system(size: 9, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 40)
            }

            Button(localized("remoteWorkspace.relay.saveACL", fallback: "Save Limit")) {
                saveACL(channelID: channelID)
            }
            .font(.system(size: 9, weight: .medium))
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: CocxyColors.green))
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
            Text(localized("remoteWorkspace.relay.newChannel", fallback: "New Channel"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            HStack(spacing: 4) {
                TextField(localized("remoteWorkspace.relay.name.placeholder", fallback: "Name"), text: $newChannelName)
                    .font(.system(size: 10))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 4) {
                Text(localized("remoteWorkspace.relay.local", fallback: "Local:"))
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("3000", text: $newLocalPort)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text(localized("remoteWorkspace.relay.remote", fallback: "Remote:"))
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                TextField("9000", text: $newRemotePort)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            Button(action: addChannel) {
                HStack(spacing: 4) {
                    if isOpeningChannel {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10))
                    }
                    Text(localized("remoteWorkspace.relay.openChannel", fallback: "Open Channel"))
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(Color(nsColor: CocxyColors.mauve))
            .disabled(
                isOpeningChannel
                    || newChannelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || newLocalPort.isEmpty
                    || newRemotePort.isEmpty
            )
        }
    }

    // MARK: - Error Section

    // MARK: - Stats Section

    private var relayStatsSection: some View {
        let channels = relayManager.listChannels(profileID: profileID)
        let totalConnections = channels.reduce(0) { $0 + $1.connectionCount }

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("remoteWorkspace.relay.channels", fallback: "Channels"))
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text(verbatim: "\(channels.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("remoteWorkspace.relay.connections", fallback: "Connections"))
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
        aclMaxConn = "\(channel.acl.maxConnections)"
        editingACLFor = channel.id
    }

    private func saveACL(channelID: UUID) {
        guard let channel = relayManager.channels[channelID] else {
            editingACLFor = nil
            return
        }
        guard let maxConn = Int(aclMaxConn), maxConn > 0 else {
            errorMessage = localized(
                "remoteWorkspace.relay.error.invalidConnectionLimit",
                fallback: "Connection limit must be a positive whole number"
            )
            return
        }

        let newACL = RelayACL(
            allowedProcesses: channel.acl.allowedProcesses,
            maxConnections: maxConn,
            maxBandwidthBytesPerSec: channel.acl.maxBandwidthBytesPerSec,
            allowedRemoteHosts: channel.acl.allowedRemoteHosts
        )
        relayManager.updateACL(channelID: channelID, acl: newACL)
        errorMessage = nil
        editingACLFor = nil
    }

    // MARK: - Channel Actions

    private func copyClientCommand(channelID: UUID) {
        guard let command = relayManager.clientCommand(for: channelID) else { return }
        copySensitiveText(command, item: .command(channelID))
    }

    private func copyClientToken(channelID: UUID) {
        guard let token = relayManager.clientToken(for: channelID) else { return }
        copySensitiveText(token, item: .token(channelID))
    }

    private func copySensitiveText(_ value: String, item: CopiedItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        let changeCount = pasteboard.changeCount
        copiedItem = item

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedItem == item {
                copiedItem = nil
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
        }
    }

    private func addChannel() {
        let channelName = newChannelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelName.isEmpty else {
            errorMessage = localized(
                "remoteWorkspace.relay.error.invalidName",
                fallback: "Channel name is required"
            )
            return
        }
        guard let localPort = Int(newLocalPort), (1...65535).contains(localPort),
              let remotePort = Int(newRemotePort), (1...65535).contains(remotePort)
        else {
            errorMessage = localized("remoteWorkspace.relay.error.invalidPorts", fallback: "Invalid port numbers")
            return
        }

        errorMessage = nil
        let config = RelayChannelConfig(
            name: channelName,
            localPort: localPort,
            remotePort: remotePort
        )

        isOpeningChannel = true
        Task { @MainActor in
            defer { isOpeningChannel = false }
            do {
                try await relayManager.openChannel(config: config, profileID: profileID)
                newChannelName = ""
                newLocalPort = ""
                newRemotePort = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
