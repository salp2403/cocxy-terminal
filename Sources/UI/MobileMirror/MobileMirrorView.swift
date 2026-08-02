// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorView.swift - Native pairing, consent, and revocation surface.

import CoreImage
import SwiftUI

struct MobileMirrorView: View {
    @ObservedObject var coordinator: MobileMirrorCoordinator
    let localizer: AppLocalizer

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    statusSection
                    pairingSection
                    projectSection
                }
                .padding(22)
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 540, idealHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen2")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.string("mobile.mirror.title", fallback: "Pair Phone"))
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }
            Spacer()
            statusIndicator
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var statusSection: some View {
        switch coordinator.state {
        case .stopped, .denied, .unavailable, .failed:
            Button(action: coordinator.startPairing) {
                Label(
                    localizer.string("mobile.mirror.start", fallback: "Generate Pairing Code"),
                    systemImage: "qrcode"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .offering:
            pairingCode
        case .awaitingConfirmation:
            confirmation
        case .active:
            activeSummary
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        if coordinator.state == .offering || coordinator.state == .awaitingConfirmation {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text(localizer.string(
                    "mobile.mirror.security",
                    fallback: "One-use code - local network - 90 seconds"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(action: coordinator.revoke) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help(localizer.string("mobile.mirror.cancel", fallback: "Cancel pairing"))
            }
        }
    }

    private var pairingCode: some View {
        VStack(spacing: 14) {
            if let url = coordinator.pairingURL,
               let image = MobileMirrorQRCodeRenderer.image(for: url.absoluteString) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 236, height: 236)
                    .accessibilityLabel(localizer.string(
                        "mobile.mirror.qr.accessibility",
                        fallback: "One-use phone pairing code"
                    ))
            } else {
                ProgressView()
                    .frame(width: 236, height: 236)
            }
            Text(localizer.string("mobile.mirror.scan", fallback: "Scan with your phone"))
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.string(
                        "mobile.mirror.confirm.title",
                        fallback: "Confirm this phone"
                    ))
                    .font(.headline)
                    Text(coordinator.pendingPairing?.identity.remoteAddress ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(localizer.string(
                        "mobile.mirror.confirm.scope",
                        fallback: "Allows local projects, live agents, terminal control, and approvals until revoked."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button(action: coordinator.denyPendingPairing) {
                    Label(
                        localizer.string("common.deny", fallback: "Deny"),
                        systemImage: "xmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: coordinator.approvePendingPairing) {
                    Label(
                        localizer.string("common.allow", fallback: "Allow"),
                        systemImage: "checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.35)))
    }

    private var activeSummary: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.string("mobile.mirror.connected", fallback: "Phone connected"))
                        .font(.headline)
                    Text(coordinator.activePairing?.identity.remoteAddress ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 14) {
                    metric(value: coordinator.snapshot.projects.count, symbol: "folder")
                    metric(value: coordinator.snapshot.agents.count, symbol: "terminal")
                }
            }
            Button(role: .destructive, action: coordinator.revoke) {
                Label(
                    localizer.string("mobile.mirror.revoke", fallback: "Revoke Access"),
                    systemImage: "lock.slash"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3)))
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    localizer.string(
                        "mobile.mirror.projectRoot.label",
                        fallback: "Project Creation Folder"
                    ),
                    systemImage: "folder.badge.plus"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: coordinator.chooseProjectCreationRoot) {
                    Image(systemName: "folder")
                }
                .help(localizer.string("mobile.mirror.projectRoot.choose", fallback: "Choose folder"))
            }
            Text(coordinator.projectCreationRoot?.path ?? localizer.string(
                "mobile.mirror.projectRoot.none",
                fallback: "Not selected"
            ))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metric(value: Int, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text("\(value)")
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .active: return .green
        case .offering, .awaitingConfirmation: return .orange
        case .failed, .unavailable, .denied: return .red
        case .stopped: return .secondary
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .stopped:
            return localizer.string("mobile.mirror.status.stopped", fallback: "Not paired")
        case .offering:
            return localizer.string("mobile.mirror.status.offering", fallback: "Pairing code ready")
        case .awaitingConfirmation:
            return localizer.string(
                "mobile.mirror.status.confirmation",
                fallback: "Desktop confirmation required"
            )
        case .active:
            return localizer.string("mobile.mirror.status.active", fallback: "Connected locally")
        case .denied:
            return localizer.string("mobile.mirror.status.denied", fallback: "Pairing denied")
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}

enum MobileMirrorQRCodeRenderer {
    static func image(for value: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = floor(236 / max(output.extent.width, output.extent.height))
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: 236, height: 236))
    }
}
