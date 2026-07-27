// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProxyControlView.swift - Authenticated local proxy controls.

import AppKit
import SwiftUI

enum SensitivePasteboardWriter {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    @discardableResult
    static func write(_ value: String, to pasteboard: NSPasteboard) -> Int? {
        let pasteboardItem = NSPasteboardItem()
        guard pasteboardItem.setString(value, forType: .string),
              pasteboardItem.setData(Data(), forType: concealedType),
              pasteboardItem.setData(Data(), forType: transientType) else {
            return nil
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([pasteboardItem]) else { return nil }
        return pasteboard.changeCount
    }
}

struct ProxyControlView: View {
    private enum CopiedCredential: Equatable {
        case username
        case socksPassword
        case httpConnectPassword
    }

    let profileID: UUID
    @ObservedObject var viewModel: RemoteConnectionViewModel
    @ObservedObject var proxyManager: ProxyManagerImpl
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    @State private var socksPort = "1080"
    @State private var httpPort = "8888"
    @State private var errorMessage: String?
    @State private var isUpdating = false
    @State private var revealsSOCKSPassword = false
    @State private var revealsHTTPConnectPassword = false
    @State private var copiedCredential: CopiedCredential?
    @State private var passwordPasteboardChangeCount: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isConnected(profileID) {
                    statusSection
                    Divider()
                    socksSection
                    if isOwnedSession {
                        Divider()
                        credentialsSection
                        Divider()
                        httpConnectSection
                        Divider()
                        statsSection
                    }
                    Divider()
                    systemIntegrationSection
                    if let errorMessage {
                        Divider()
                        errorSection(errorMessage)
                    }
                } else {
                    disconnectedState
                }
            }
            .padding(12)
        }
        .onChange(of: proxyManager.activeSince) { _, _ in
            resetCredentialPresentation()
        }
        .onChange(of: profileID) { _, _ in
            resetCredentialPresentation()
        }
        .onChange(of: activeHTTPPort) { _, _ in
            resetCredentialPresentation()
        }
        .onDisappear {
            resetCredentialPresentation()
        }
    }

    private var disconnectedState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 24))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(localized(
                "remoteWorkspace.proxy.connectFirst",
                fallback: "Connect to the profile first to enable proxy"
            ))
            .font(.system(size: 11))
            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(2)
            Spacer()
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(localized(
                        "remoteWorkspace.proxy.updating",
                        fallback: "Updating proxy"
                    ))
            }
        }
    }

    private var statusColor: Color {
        guard proxyManager.state.profileID == nil || proxyManager.state.profileID == profileID else {
            return Color(nsColor: CocxyColors.overlay1)
        }
        switch proxyManager.state {
        case .off: return Color(nsColor: CocxyColors.overlay1)
        case .starting: return .yellow
        case .active: return .green
        case .failing: return .red
        case .failover: return .orange
        }
    }

    private var statusText: String {
        guard proxyManager.state.profileID == nil || proxyManager.state.profileID == profileID else {
            return localized(
                "remoteWorkspace.proxy.status.otherProfile",
                fallback: "Proxy session belongs to another profile"
            )
        }
        switch proxyManager.state {
        case .off:
            return localized("remoteWorkspace.proxy.status.off", fallback: "Proxy Off")
        case .starting:
            return localized("remoteWorkspace.proxy.status.starting", fallback: "Starting...")
        case .active(_, let socks, let http):
            if let http {
                return String(
                    format: localized(
                        "remoteWorkspace.proxy.status.active.socksHttp",
                        fallback: "Active - SOCKS5:%d HTTP:%d"
                    ),
                    socks,
                    http
                )
            }
            return String(
                format: localized(
                    "remoteWorkspace.proxy.status.active.socks",
                    fallback: "Active - SOCKS5:%d"
                ),
                socks
            )
        case .failing(_, let reason):
            return String(
                format: localized(
                    "remoteWorkspace.proxy.status.failing",
                    fallback: "Failing: %@"
                ),
                reason
            )
        case .failover:
            return localized(
                "remoteWorkspace.proxy.status.failover",
                fallback: "Failover in progress..."
            )
        }
    }

    private var socksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(localized("remoteWorkspace.proxy.socksTitle", fallback: "SOCKS5 Proxy"))
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Toggle(
                    localized("remoteWorkspace.proxy.socksTitle", fallback: "SOCKS5 Proxy"),
                    isOn: Binding(
                        get: { isOwnedSession },
                        set: { enabled in
                            enabled ? enableSOCKS() : disableProxy()
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isUpdating)
                .accessibilityLabel(localized(
                    "remoteWorkspace.proxy.socksToggle",
                    fallback: "Authenticated SOCKS5 proxy"
                ))
            }

            if let activePort = activeSOCKSPort {
                endpointRow(label: localized("remoteWorkspace.proxy.port", fallback: "Port:"), value: "127.0.0.1:\(activePort)")
            } else {
                HStack(spacing: 6) {
                    Text(localized("remoteWorkspace.proxy.port", fallback: "Port:"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    TextField("1080", text: $socksPort)
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .accessibilityLabel(localized(
                            "remoteWorkspace.proxy.socksPort",
                            fallback: "SOCKS5 port"
                        ))
                }
            }

            if proxyManager.activeProfileID != nil && !isOwnedSession {
                Text(localized(
                    "remoteWorkspace.proxy.otherProfileDetail",
                    fallback: "Enabling here replaces the proxy session on the other profile."
                ))
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(localized(
                    "remoteWorkspace.proxy.credentials",
                    fallback: "Client Credentials"
                ))
            } icon: {
                Image(systemName: "key.horizontal")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(nsColor: CocxyColors.text))

            credentialRow(
                label: localized("remoteWorkspace.proxy.username", fallback: "Username"),
                value: ProxyCredentials.username,
                displayValue: ProxyCredentials.username,
                item: .username,
                copyLabel: localized(
                    "remoteWorkspace.proxy.copyUsername",
                    fallback: "Copy proxy username"
                )
            )

            if let credentials = proxyManager.credentials(for: profileID) {
                passwordCredentialRow(
                    label: localized(
                        "remoteWorkspace.proxy.socksPassword",
                        fallback: "SOCKS Password"
                    ),
                    credentials: credentials,
                    item: .socksPassword,
                    revealsPassword: $revealsSOCKSPassword,
                    copyLabel: localized(
                        "remoteWorkspace.proxy.copySOCKSPassword",
                        fallback: "Copy SOCKS password"
                    )
                )
            }

            if let credentials = proxyManager.httpConnectCredentials(for: profileID) {
                passwordCredentialRow(
                    label: localized(
                        "remoteWorkspace.proxy.httpPassword",
                        fallback: "HTTP Password"
                    ),
                    credentials: credentials,
                    item: .httpConnectPassword,
                    revealsPassword: $revealsHTTPConnectPassword,
                    copyLabel: localized(
                        "remoteWorkspace.proxy.copyHTTPPassword",
                        fallback: "Copy HTTP password"
                    )
                )
            }
        }
    }

    private func credentialRow(
        label: String,
        value: String,
        displayValue: String,
        item: CopiedCredential,
        copyLabel: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .frame(width: 84, alignment: .leading)
            Text(displayValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Spacer()
            copyButton(value: value, item: item, label: copyLabel)
        }
    }

    private func passwordCredentialRow(
        label: String,
        credentials: ProxyCredentials,
        item: CopiedCredential,
        revealsPassword: Binding<Bool>,
        copyLabel: String
    ) -> some View {
        let visibilityLabel = localized(
            revealsPassword.wrappedValue
                ? "remoteWorkspace.proxy.hidePassword"
                : "remoteWorkspace.proxy.revealPassword",
            fallback: revealsPassword.wrappedValue
                ? "Hide password"
                : "Reveal password"
        )
        let passwordVisibilityLabel = "\(visibilityLabel): \(label)"

        return HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .frame(width: 84, alignment: .leading)
                .lineLimit(2)
            Text(
                revealsPassword.wrappedValue
                    ? credentials.password
                    : String(repeating: "*", count: 16)
            )
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.disabled)
            Spacer(minLength: 4)
            Button(action: { revealsPassword.wrappedValue.toggle() }) {
                Image(systemName: revealsPassword.wrappedValue ? "eye.slash" : "eye")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(passwordVisibilityLabel)
            .accessibilityLabel(passwordVisibilityLabel)
            copyButton(
                value: credentials.password,
                item: item,
                label: copyLabel
            )
        }
    }

    private func copyButton(
        value: String,
        item: CopiedCredential,
        label: String
    ) -> some View {
        Button(action: { copySensitiveText(value, item: item) }) {
            Image(systemName: copiedCredential == item ? "checkmark" : "doc.on.doc")
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var httpConnectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(localized("remoteWorkspace.proxy.httpTitle", fallback: "HTTP CONNECT"))
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                Spacer()
                Toggle(
                    localized("remoteWorkspace.proxy.httpTitle", fallback: "HTTP CONNECT"),
                    isOn: Binding(
                        get: { activeHTTPPort != nil },
                        set: { enabled in
                            enabled ? enableHTTPConnect() : disableHTTPConnect()
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isUpdating)
                .accessibilityLabel(localized(
                    "remoteWorkspace.proxy.httpToggle",
                    fallback: "Authenticated HTTP CONNECT proxy"
                ))
            }

            if let activePort = activeHTTPPort {
                endpointRow(label: localized("remoteWorkspace.proxy.port", fallback: "Port:"), value: "127.0.0.1:\(activePort)")
            } else {
                HStack(spacing: 6) {
                    Text(localized("remoteWorkspace.proxy.port", fallback: "Port:"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    TextField("8888", text: $httpPort)
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .accessibilityLabel(localized(
                            "remoteWorkspace.proxy.httpPort",
                            fallback: "HTTP CONNECT port"
                        ))
                }
            }
        }
    }

    private func endpointRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("remoteWorkspace.proxy.stats", fallback: "Stats"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            SwiftUI.TimelineView(.periodic(from: Date.now, by: 1.0)) { context in
                HStack(spacing: 16) {
                    statItem(
                        label: localized("remoteWorkspace.proxy.stats.uptime", fallback: "Uptime"),
                        value: formatUptime(at: context.date)
                    )
                    statItem(
                        label: localized(
                            "remoteWorkspace.proxy.stats.connections",
                            fallback: "Connections"
                        ),
                        value: "\((proxyManager.socksProxy?.activeConnectionCount ?? 0) + (proxyManager.httpConnectProxy?.activeConnectionCount ?? 0))"
                    )
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.text))
        }
    }

    private var systemIntegrationSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            VStack(alignment: .leading, spacing: 3) {
                Text(localized(
                    "remoteWorkspace.proxy.systemWideTitle",
                    fallback: "System Proxy"
                ))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                Text(localized(
                    "remoteWorkspace.proxy.systemWide.secureUnavailable",
                    fallback: "Unavailable for authenticated proxy sessions"
                ))
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isOwnedSession: Bool {
        proxyManager.activeProfileID == profileID
    }

    private var activeSOCKSPort: Int? {
        guard case .active(let owner, let port, _) = proxyManager.state,
              owner == profileID else { return nil }
        return port
    }

    private var activeHTTPPort: Int? {
        guard case .active(let owner, _, let port) = proxyManager.state,
              owner == profileID else { return nil }
        return port
    }

    private func enableSOCKS() {
        guard let port = Int(socksPort), (1...65_535).contains(port) else {
            errorMessage = localized(
                "remoteWorkspace.proxy.error.invalidPort",
                fallback: "Invalid port number"
            )
            return
        }
        runProxyAction {
            try await proxyManager.enableSOCKS(port: port, profileID: profileID)
        }
    }

    private func enableHTTPConnect() {
        guard let port = Int(httpPort), (1...65_535).contains(port) else {
            errorMessage = localized(
                "remoteWorkspace.proxy.error.invalidHTTPPort",
                fallback: "Invalid HTTP port number"
            )
            return
        }
        runProxyAction {
            try await proxyManager.enableHTTPConnect(port: port, profileID: profileID)
        }
    }

    private func disableHTTPConnect() {
        runProxyAction {
            await proxyManager.disableHTTPConnect(profileID: profileID)
        }
    }

    private func disableProxy() {
        runProxyAction {
            await proxyManager.disable(profileID: profileID)
        }
    }

    private func runProxyAction(
        _ action: @escaping @MainActor () async throws -> Void
    ) {
        guard !isUpdating else { return }
        errorMessage = nil
        isUpdating = true
        Task { @MainActor in
            defer { isUpdating = false }
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copySensitiveText(_ value: String, item: CopiedCredential) {
        let pasteboard = NSPasteboard.general
        guard let changeCount = SensitivePasteboardWriter.write(value, to: pasteboard) else {
            errorMessage = localized(
                "remoteWorkspace.proxy.error.copyFailed",
                fallback: "Could not copy the credential"
            )
            return
        }
        passwordPasteboardChangeCount = item == .username ? nil : changeCount
        copiedCredential = item

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedCredential == item { copiedCredential = nil }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            if passwordPasteboardChangeCount == changeCount {
                passwordPasteboardChangeCount = nil
            }
        }
    }

    private func resetCredentialPresentation() {
        revealsSOCKSPassword = false
        revealsHTTPConnectPassword = false
        copiedCredential = nil
        guard let changeCount = passwordPasteboardChangeCount else { return }
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == changeCount {
            pasteboard.clearContents()
        }
        passwordPasteboardChangeCount = nil
    }

    private func formatUptime(at date: Date) -> String {
        guard let activeSince = proxyManager.activeSince else { return "-" }
        let elapsed = max(0, Int(date.timeIntervalSince(activeSince)))
        let hours = elapsed / 3_600
        let minutes = (elapsed % 3_600) / 60
        let seconds = elapsed % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(seconds)s"
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
