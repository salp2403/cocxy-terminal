// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyControlView.swift - UI for SOCKS5/HTTP CONNECT proxy control.

import SwiftUI
import Combine

// MARK: - Proxy Control View

/// Sub-panel for managing the SOCKS5 and HTTP CONNECT proxy.
///
/// Connected to `ProxyManagerImpl` for real SSH dynamic forward operations.
/// Toggles directly call `enableSOCKS`, `enableHTTPConnect`, and `disable`.
struct ProxyControlView: View {

    let profileID: UUID
    @ObservedObject var viewModel: RemoteConnectionViewModel
    @ObservedObject var proxyManager: ProxyManagerImpl

    @State private var socksPort: String = "1080"
    @State private var httpPort: String = "8888"
    @State private var systemWideEnabled = false
    @State private var newExclusion: String = ""
    @State private var exclusions: [String] = []
    @State private var errorMessage: String?

    /// Persisted across enable/disable calls so savedState survives.
    @State private var systemProxyConfigurator = SystemProxyConfigurator(
        networkConfigurator: SystemNetworkConfigurator(),
        pacWriter: DiskPACFileWriter()
    )

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                connectionGate
            }
            .padding(12)
        }
    }

    // MARK: - Connection Gate

    /// Shows content only when the profile is connected.
    @ViewBuilder
    private var connectionGate: some View {
        if viewModel.isConnected(profileID) {
            statusSection
            Divider()
            socksSection
            Divider()
            httpConnectSection
            Divider()
            systemWideSection
            if isSOCKSActive {
                Divider()
                statsSection
            }
            Divider()
            exclusionsSection
            if let errorMessage {
                Divider()
                errorSection(errorMessage)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 24))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                Text("Connect to the profile first to enable proxy")
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
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Spacer()
        }
    }

    private var statusColor: Color {
        switch proxyManager.state {
        case .off: return Color(nsColor: CocxyColors.overlay1)
        case .starting: return Color.yellow
        case .active: return Color.green
        case .failing: return Color.red
        case .failover: return Color.orange
        }
    }

    private var statusText: String {
        switch proxyManager.state {
        case .off: return "Proxy Off"
        case .starting: return "Starting..."
        case .active(let socks, let http):
            if let http { return "Active — SOCKS5:\(socks) HTTP:\(http)" }
            return "Active — SOCKS5:\(socks)"
        case .failing(let reason): return "Failing: \(reason)"
        case .failover: return "Failover in progress..."
        }
    }

    private var isSOCKSActive: Bool {
        if case .active = proxyManager.state { return true }
        return false
    }

    // MARK: - SOCKS Section

    private var socksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SOCKS5 Proxy")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isSOCKSActive },
                    set: { enabled in
                        if enabled {
                            enableSOCKS()
                        } else {
                            disableProxy()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if isSOCKSActive {
                HStack(spacing: 4) {
                    Text("Port:")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    Text(socksPort)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.text))
                }
            } else {
                HStack(spacing: 4) {
                    Text("Port:")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    TextField("1080", text: $socksPort)
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
        }
    }

    // MARK: - HTTP CONNECT Section

    private var httpConnectSection: some View {
        let httpActive: Bool = {
            if case .active(_, let http) = proxyManager.state { return http != nil }
            return false
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HTTP CONNECT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { httpActive },
                    set: { enabled in
                        if enabled {
                            enableHTTPConnect()
                        }
                        // Disabling HTTP CONNECT requires full proxy disable + re-enable SOCKS.
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isSOCKSActive)
            }

            if !isSOCKSActive {
                Text("Enable SOCKS5 first")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            } else if !httpActive {
                HStack(spacing: 4) {
                    Text("Port:")
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    TextField("8888", text: $httpPort)
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }
        }
    }

    // MARK: - System-Wide Section

    private var systemWideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("System-Wide Proxy")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { systemWideEnabled },
                    set: { enabled in
                        if enabled {
                            enableSystemProxy()
                        } else {
                            disableSystemProxy()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isSOCKSActive)
            }

            if isSOCKSActive {
                Text("Routes all macOS traffic through the SSH tunnel. Requires admin password.")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stats")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            HStack(spacing: 12) {
                statItem(label: "Uptime", value: formatUptime(proxyManager.uptimeSeconds))
                statItem(label: "HTTP Connections", value: "\(proxyManager.httpConnectProxy?.activeConnectionCount ?? 0)")
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(verbatim: value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        if let since = proxyManager.activeSince {
            let elapsed = Date().timeIntervalSince(since)
            let h = Int(elapsed) / 3600
            let m = (Int(elapsed) % 3600) / 60
            let s = Int(elapsed) % 60
            if h > 0 { return "\(h)h \(m)m" }
            return "\(m)m \(s)s"
        }
        return "—"
    }

    // MARK: - Exclusions Section

    private var exclusionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bypass List")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            ForEach(ProxyExclusionList.defaultExclusions, id: \.self) { pattern in
                HStack(spacing: 4) {
                    Image(systemName: "lock")
                        .font(.system(size: 8))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                    Text(pattern)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }
            }

            ForEach(exclusions, id: \.self) { pattern in
                HStack(spacing: 4) {
                    Text(pattern)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.text))
                    Spacer()
                    Button(action: { exclusions.removeAll { $0 == pattern } }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 4) {
                TextField("*.example.com", text: $newExclusion)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Button(action: addExclusion) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(newExclusion.trimmingCharacters(in: .whitespaces).isEmpty)
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
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private func enableSOCKS() {
        guard let port = Int(socksPort), (1...65535).contains(port) else {
            errorMessage = "Invalid port number"
            return
        }
        errorMessage = nil
        Task {
            do {
                try await proxyManager.enableSOCKS(port: port, profileID: profileID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func enableHTTPConnect() {
        guard let port = Int(httpPort), (1...65535).contains(port) else {
            errorMessage = "Invalid HTTP port number"
            return
        }
        errorMessage = nil
        Task {
            do {
                try await proxyManager.enableHTTPConnect(port: port, profileID: profileID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func disableProxy() {
        errorMessage = nil
        Task {
            await proxyManager.disable(profileID: profileID)
        }
    }

    private func enableSystemProxy() {
        errorMessage = nil
        Task {
            do {
                let interface = try SystemNetworkConfigurator().detectActiveInterface()
                let socksPortInt = Int(socksPort) ?? 1080
                let httpActive: Bool = {
                    if case .active(_, let http) = proxyManager.state { return http != nil }
                    return false
                }()
                let httpPortInt = httpActive ? Int(httpPort) : nil
                try systemProxyConfigurator.activateProxy(
                    interface: interface,
                    socksPort: socksPortInt,
                    httpPort: httpPortInt,
                    exclusions: ProxyExclusionList(custom: exclusions)
                )
                systemWideEnabled = true
            } catch {
                errorMessage = "System proxy: \(error.localizedDescription)"
                systemWideEnabled = false
            }
        }
    }

    private func disableSystemProxy() {
        errorMessage = nil
        Task {
            do {
                let interface = try SystemNetworkConfigurator().detectActiveInterface()
                try systemProxyConfigurator.deactivateProxy(interface: interface)
            } catch {
                errorMessage = "System proxy restore: \(error.localizedDescription)"
            }
            systemWideEnabled = false
        }
    }

    private func addExclusion() {
        let trimmed = newExclusion.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !exclusions.contains(trimmed) else { return }
        exclusions.append(trimmed)
        newExclusion = ""
    }
}
