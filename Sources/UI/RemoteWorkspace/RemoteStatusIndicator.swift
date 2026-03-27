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

    /// Diameter of the indicator circle.
    private let diameter: CGFloat

    /// Controls the pulse animation for transient states.
    @State private var isPulsing = false

    init(state: RemoteConnectionManager.ConnectionState, diameter: CGFloat = 8) {
        self.state = state
        self.diameter = diameter
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
                return "Connected, latency \(ms)ms"
            }
            return "Connected"
        case .connecting:
            return "Connecting"
        case .reconnecting(let attempt):
            return "Reconnecting, attempt \(attempt)"
        case .disconnected:
            return "Disconnected"
        case .failed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}
