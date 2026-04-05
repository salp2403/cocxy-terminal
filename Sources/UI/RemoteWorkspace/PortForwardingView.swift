// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PortForwardingView.swift - Sub-panel for active SSH tunnels.

import SwiftUI

// MARK: - Port Forwarding View

/// Sub-panel listing active SSH tunnels for a selected remote connection.
///
/// ## Layout
///
/// ```
/// +-- Type ---- Local ------- Remote ---- Status --+
/// |  Local      3000   ->     3000       [green]   |
/// |  Remote     8080   <-     8080       [green]   |
/// |  Dynamic    1080          SOCKS      [green]   |
/// +------------------------------------------------+
/// | [+ Add Tunnel]                                 |
/// +------------------------------------------------+
/// ```
///
/// Each tunnel row shows its type, local/remote port, direction arrow,
/// and a status indicator with a remove button on hover.
///
/// - SeeAlso: `SSHTunnelManager`
/// - SeeAlso: `ActiveTunnel`
struct PortForwardingView: View {

    /// The tunnel manager providing live tunnel state.
    @ObservedObject var tunnelManager: SSHTunnelManager

    /// The profile ID whose tunnels are displayed.
    let profileID: UUID

    /// Executes the real SSH port forward via ControlMaster.
    /// Called after the tunnel is added to the manager.
    var onForwardPort: ((RemoteConnectionProfile.PortForward, UUID) -> Void)?

    /// Cancels the real SSH port forward via ControlMaster.
    /// Called before the tunnel is removed from the manager.
    var onCancelForward: ((RemoteConnectionProfile.PortForward, UUID) -> Void)?

    /// Whether the inline "add tunnel" form is expanded.
    @State private var isAddFormVisible = false

    /// New tunnel form state.
    @State private var newForwardType: ForwardTypeOption = .local
    @State private var newLocalPort: String = ""
    @State private var newRemotePort: String = ""

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Divider()
            tunnelListContent
            Divider()
            addTunnelSection
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Text("Port Forwards")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            Spacer()

            Text("\(tunnels.count) active")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Tunnel List

    private var tunnels: [ActiveTunnel] {
        tunnelManager.listTunnels(for: profileID)
    }

    private var tunnelListContent: some View {
        Group {
            if tunnels.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tunnels) { tunnel in
                            TunnelRow(
                                tunnel: tunnel,
                                onRemove: {
                                    onCancelForward?(tunnel.forward, profileID)
                                    tunnelManager.removeTunnel(id: tunnel.id)
                                }
                            )
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 24))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("No active tunnels")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("Add a port forward to tunnel\ntraffic through this connection.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Add Tunnel Section

    private var addTunnelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isAddFormVisible {
                addTunnelForm
            } else {
                addTunnelButton
            }
        }
    }

    private var addTunnelButton: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.15)) { isAddFormVisible = true } }) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                Text("Add Tunnel")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Color(nsColor: CocxyColors.blue))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityLabel("Add port forward tunnel")
    }

    private var addTunnelForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Type", selection: $newForwardType) {
                ForEach(ForwardTypeOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Port")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                    TextField("8080", text: $newLocalPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 80)
                }

                if newForwardType != .dynamic {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Port")
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                        TextField("8080", text: $newRemotePort)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 80)
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isAddFormVisible = false
                        resetAddForm()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

                Button("Add") { addTunnel() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: CocxyColors.blue))
                    .font(.system(size: 11))
                    .controlSize(.small)
                    .disabled(!isAddFormValid)
            }
        }
        .padding(12)
        .background(Color(nsColor: CocxyColors.surface0).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Form Validation

    private var isAddFormValid: Bool {
        guard let localPort = Int(newLocalPort), localPort > 0, localPort <= 65535 else {
            return false
        }
        if newForwardType == .dynamic {
            return true
        }
        guard let remotePort = Int(newRemotePort), remotePort > 0, remotePort <= 65535 else {
            return false
        }
        return true
    }

    // MARK: - Actions

    private func addTunnel() {
        guard let localPort = Int(newLocalPort) else { return }

        let forward: RemoteConnectionProfile.PortForward
        switch newForwardType {
        case .local:
            guard let remotePort = Int(newRemotePort) else { return }
            forward = .local(localPort: localPort, remotePort: remotePort)
        case .remote:
            guard let remotePort = Int(newRemotePort) else { return }
            forward = .remote(remotePort: remotePort, localPort: localPort)
        case .dynamic:
            forward = .dynamic(localPort: localPort)
        }

        _ = tunnelManager.addTunnel(forward: forward, for: profileID)
        onForwardPort?(forward, profileID)

        withAnimation(.easeOut(duration: 0.15)) {
            isAddFormVisible = false
            resetAddForm()
        }
    }

    private func resetAddForm() {
        newForwardType = .local
        newLocalPort = ""
        newRemotePort = ""
    }
}

// MARK: - Forward Type Option

/// Picker options for port forward types in the add tunnel form.
enum ForwardTypeOption: String, CaseIterable, Identifiable {
    case local
    case remote
    case dynamic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local"
        case .remote: return "Remote"
        case .dynamic: return "Dynamic"
        }
    }
}

// MARK: - Tunnel Row

/// A single row displaying one active tunnel with status and remove action.
struct TunnelRow: View {

    let tunnel: ActiveTunnel
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            typeIcon
                .frame(width: 24, height: 24)

            portDescription
                .frame(maxWidth: .infinity, alignment: .leading)

            tunnelStatusIndicator

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: CocxyColors.red).opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Remove tunnel")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Type Icon

    private var typeIcon: some View {
        let (icon, color) = typeIconAndColor
        return Image(systemName: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.12))
            .cornerRadius(5)
    }

    private var typeIconAndColor: (String, Color) {
        switch tunnel.forward {
        case .local:
            return ("arrow.right", Color(nsColor: CocxyColors.blue))
        case .remote:
            return ("arrow.left", Color(nsColor: CocxyColors.mauve))
        case .dynamic:
            return ("globe", Color(nsColor: CocxyColors.teal))
        }
    }

    // MARK: - Port Description

    private var portDescription: some View {
        HStack(spacing: 4) {
            switch tunnel.forward {
            case let .local(localPort, remotePort, _):
                portLabel("\(localPort)")
                directionArrow("arrow.right")
                portLabel("\(remotePort)")
            case let .remote(remotePort, localPort, _):
                portLabel("\(localPort)")
                directionArrow("arrow.left")
                portLabel("\(remotePort)")
            case let .dynamic(localPort):
                portLabel("\(localPort)")
                Text("SOCKS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: CocxyColors.teal))
            }
        }
    }

    private func portLabel(_ port: String) -> some View {
        Text(port)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Color(nsColor: CocxyColors.text))
    }

    private func directionArrow(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8))
            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
    }

    // MARK: - Status Indicator

    private var tunnelStatusIndicator: some View {
        Circle()
            .fill(tunnelStatusColor)
            .frame(width: 6, height: 6)
    }

    private var tunnelStatusColor: Color {
        switch tunnel.status {
        case .active:
            return Color(nsColor: CocxyColors.green)
        case .pending:
            return Color(nsColor: CocxyColors.yellow)
        case .failed:
            return Color(nsColor: CocxyColors.red)
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        switch tunnel.forward {
        case let .local(localPort, remotePort, _):
            return "Local forward, port \(localPort) to \(remotePort)"
        case let .remote(remotePort, localPort, _):
            return "Remote forward, port \(remotePort) to \(localPort)"
        case let .dynamic(localPort):
            return "Dynamic SOCKS proxy on port \(localPort)"
        }
    }
}
