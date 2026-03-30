// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonControlView.swift - UI for remote daemon management.

import SwiftUI

// MARK: - Daemon Control View

/// Sub-panel for managing the remote cocxyd daemon.
///
/// Connected to `DaemonManagerImpl` for real deployment and session operations.
/// Shows daemon status, deploy/start/stop buttons, session list, and file sync.
struct DaemonControlView: View {

    let profileID: UUID
    @ObservedObject var viewModel: RemoteConnectionViewModel
    @ObservedObject var daemonManager: DaemonManagerImpl

    @State private var errorMessage: String?
    @State private var isDeploying = false

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
            Text("Remote Sessions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            if case .running = daemonManager.state {
                Text("Use the daemon connection to list and manage persistent sessions.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            } else {
                Text("Deploy the daemon to manage persistent sessions.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }
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

    // MARK: - Actions

    private func deployDaemon() {
        isDeploying = true
        errorMessage = nil
        Task {
            do {
                try await daemonManager.deploy(profileID: profileID)
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

    // MARK: - Helpers

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
