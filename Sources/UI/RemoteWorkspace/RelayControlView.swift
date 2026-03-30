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
                    .fill(Color.green)
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
            }

            HStack(spacing: 8) {
                Button("Rotate Token") {
                    relayManager.rotateToken(channelID: channel.id)
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(Color(nsColor: CocxyColors.mauve))

                Text(verbatim: "\(channel.connectionCount) conn")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.5))
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
