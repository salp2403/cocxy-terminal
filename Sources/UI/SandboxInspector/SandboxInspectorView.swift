// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SandboxInspectorView.swift - User-facing sandbox grants and audit log inspector.

import SwiftUI

struct SandboxInspectorGrantRow: Identifiable, Equatable {
    let pluginID: String
    let capability: PluginCapability
    let reason: String?
    let grantedAt: Date

    var id: String {
        "\(pluginID):\(capability.rawValue)"
    }
}

@MainActor
final class SandboxInspectorViewModel: ObservableObject {
    @Published private(set) var grants: [SandboxInspectorGrantRow] = []
    @Published private(set) var auditEntries: [SandboxAuditEntry] = []
    @Published var statusMessage: String?

    private let grantStore: PluginCapabilityGrantStore
    private let auditLog: SandboxAuditLog
    private var localizer: AppLocalizer

    init(
        grantStore: PluginCapabilityGrantStore = PluginCapabilityGrantStore(),
        auditLog: SandboxAuditLog = SandboxAuditLog(fileURL: .defaultSandboxAuditLog),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.grantStore = grantStore
        self.auditLog = auditLog
        self.localizer = localizer
        refresh()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
    }

    func refresh() {
        do {
            grants = try grantStore.allGrants().map {
                SandboxInspectorGrantRow(
                    pluginID: $0.pluginID,
                    capability: $0.capability,
                    reason: $0.reason,
                    grantedAt: $0.grantedAt
                )
            }
        } catch {
            grants = []
            statusMessage = String(
                format: localized("sandboxInspector.status.loadGrantsFailed", fallback: "Failed to load grants: %@"),
                error.localizedDescription
            )
        }

        do {
            auditEntries = Array(try auditLog.entries().suffix(100))
        } catch {
            auditEntries = []
            statusMessage = String(
                format: localized("sandboxInspector.status.loadAuditFailed", fallback: "Failed to load audit log: %@"),
                error.localizedDescription
            )
        }
    }

    func revoke(_ row: SandboxInspectorGrantRow) {
        do {
            try grantStore.revoke(row.capability, for: row.pluginID)
            refresh()
            statusMessage = String(
                format: localized("sandboxInspector.status.revoked", fallback: "Revoked %@ from %@."),
                row.capability.rawValue,
                row.pluginID
            )
        } catch {
            statusMessage = String(
                format: localized("sandboxInspector.status.revokeFailed", fallback: "Failed to revoke grant: %@"),
                error.localizedDescription
            )
        }
    }

    func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    func localizedCapability(_ capability: PluginCapability) -> String {
        localizer.string(
            "sandboxInspector.capability.\(capability.rawValue)",
            fallback: capability.rawValue
        )
    }
}

struct SandboxInspectorView: View {
    @StateObject private var viewModel: SandboxInspectorViewModel
    private let localizer: AppLocalizer

    init(
        grantStore: PluginCapabilityGrantStore = PluginCapabilityGrantStore(),
        auditLog: SandboxAuditLog = SandboxAuditLog(fileURL: .defaultSandboxAuditLog),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        _viewModel = StateObject(wrappedValue: SandboxInspectorViewModel(
            grantStore: grantStore,
            auditLog: auditLog,
            localizer: localizer
        ))
        self.localizer = localizer
    }

    var body: some View {
        Form {
            grantsSection
            auditSection
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            viewModel.updateLocalizer(localizer)
            viewModel.refresh()
        }
    }

    private var grantsSection: some View {
        Section(viewModel.localized("sandboxInspector.grants.section", fallback: "Capability Grants")) {
            if viewModel.grants.isEmpty {
                Text(viewModel.localized("sandboxInspector.grants.empty", fallback: "No active grants."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.grants) { grant in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(grant.pluginID)
                                .font(.headline)
                            Text(viewModel.localizedCapability(grant.capability))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let reason = grant.reason, !reason.isEmpty {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.revoke(grant)
                        } label: {
                            Label(
                                viewModel.localized("sandboxInspector.revoke", fallback: "Revoke"),
                                systemImage: "xmark.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var auditSection: some View {
        Section(viewModel.localized("sandboxInspector.audit.section", fallback: "Audit Log")) {
            SandboxAuditLogView(entries: viewModel.auditEntries, localizer: localizer)
        }
    }
}

struct SandboxAuditLogView: View {
    let entries: [SandboxAuditEntry]
    let localizer: AppLocalizer

    var body: some View {
        if entries.isEmpty {
            Text(localizer.string("sandboxInspector.audit.empty", fallback: "No sandbox audit entries yet."))
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.subjectID)
                            .font(.headline)
                        Spacer()
                        Text(entry.decision.rawValue)
                            .font(.caption)
                            .foregroundStyle(entry.decision == .granted ? .green : .red)
                    }
                    Text("\(entry.subjectKind.rawValue) | \(entry.capability.rawValue) | \(entry.operation)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private extension URL {
    static var defaultSandboxAuditLog: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Cocxy", isDirectory: true)
            .appendingPathComponent("sandbox-audit.log")
        ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Cocxy", isDirectory: true)
            .appendingPathComponent("sandbox-audit.log")
    }
}
