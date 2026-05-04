// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteStatusIndicator.swift - Connection state indicator for tab bar and status bar.

import SwiftUI

// MARK: - Remote Status Indicator

/// A small colored circle that represents the current state of an SSH connection.
///
/// ## States
///
/// | State         | Color   | Animation        |
/// |---------------|---------|------------------|
/// | connected     | green   | none             |
/// | connecting    | yellow  | pulse            |
/// | reconnecting  | yellow  | pulse            |
/// | disconnected  | gray    | none             |
/// | failed        | red     | none             |
///
/// ## Usage
///
/// Place in tab bar rows or the status bar to indicate connection health at a glance.
///
/// - SeeAlso: `RemoteConnectionManager.ConnectionState`
struct RemoteStatusIndicator: View {

    /// The current connection state to represent visually.
    let state: RemoteConnectionManager.ConnectionState
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    /// Diameter of the indicator circle.
    private let diameter: CGFloat

    /// Controls the pulse animation for transient states.
    @State private var isPulsing = false

    init(
        state: RemoteConnectionManager.ConnectionState,
        diameter: CGFloat = 8,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.state = state
        self.diameter = diameter
        self.localizer = localizer
    }

    // MARK: - Body

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: diameter, height: diameter)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(pulseAnimation, value: isPulsing)
            .onAppear { startPulseIfNeeded() }
            .onChange(of: state) { startPulseIfNeeded() }
            .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch state {
        case .connected:
            return Color(nsColor: CocxyColors.green)
        case .connecting, .reconnecting:
            return Color(nsColor: CocxyColors.yellow)
        case .disconnected:
            return Color(nsColor: CocxyColors.overlay0)
        case .failed:
            return Color(nsColor: CocxyColors.red)
        }
    }

    // MARK: - Pulse Animation

    private var pulseAnimation: Animation? {
        switch state {
        case .connecting, .reconnecting:
            return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        default:
            return nil
        }
    }

    private func startPulseIfNeeded() {
        switch state {
        case .connecting, .reconnecting:
            isPulsing = true
        default:
            isPulsing = false
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        switch state {
        case .connected(let latencyMs):
            if let ms = latencyMs {
                return String(
                    format: localized("remoteWorkspace.status.connectedLatency", fallback: "Connected, latency %dms"),
                    ms
                )
            }
            return localized("remoteWorkspace.status.connected", fallback: "Connected")
        case .connecting:
            return localized("remoteWorkspace.status.connecting", fallback: "Connecting")
        case .reconnecting(let attempt):
            return String(
                format: localized("remoteWorkspace.status.reconnecting", fallback: "Reconnecting, attempt %d"),
                attempt
            )
        case .disconnected:
            return localized("remoteWorkspace.status.disconnected", fallback: "Disconnected")
        case .failed(let reason):
            return String(
                format: localized("remoteWorkspace.status.failed", fallback: "Connection failed: %@"),
                reason
            )
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
