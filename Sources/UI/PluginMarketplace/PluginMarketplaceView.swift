// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginMarketplaceView.swift - Local decentralized plugin management UI.

import SwiftUI

enum PluginMarketplaceViewModelError: Error, LocalizedError, Equatable {
    case missingURL

    var errorDescription: String? {
        switch self {
        case .missingURL: return "Enter a plugin URL or local path."
        }
    }
}

@MainActor
final class PluginMarketplaceViewModel: ObservableObject {
    @Published var sourceURLText: String = ""
    @Published var sourceDisplayName: String = ""
    @Published var installURLText: String = ""
    @Published var statusMessage: String?
    @Published private(set) var sources: [PluginSource] = []
    @Published private(set) var plugins: [PluginState] = []

    private let sourceStore: PluginSourceStore
    private let installer: PluginInstaller
    private let pluginManager: PluginManager

    init(
        sourceStore: PluginSourceStore = PluginSourceStore(),
        installer: PluginInstaller = PluginInstaller(),
        pluginManager: PluginManager? = nil
    ) {
        self.sourceStore = sourceStore
        self.installer = installer
        self.pluginManager = pluginManager ?? PluginManager(pluginsDirectory: installer.pluginsDirectory.path)
        refresh()
    }

    func refresh() {
        do {
            sources = try sourceStore.load()
        } catch {
            sources = []
            statusMessage = "Failed to load sources."
        }
        pluginManager.scanPlugins()
        plugins = pluginManager.plugins
    }

    func addSource() throws {
        let url = try makeURL(from: sourceURLText)
        let displayName = sourceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        try sourceStore.add(
            PluginSource(
                url: url,
                displayName: displayName.isEmpty ? nil : displayName
            )
        )
        sourceURLText = ""
        sourceDisplayName = ""
        refresh()
        statusMessage = "Plugin source added."
    }

    func installPlugin(replaceExisting: Bool) throws {
        let url = try makeURL(from: installURLText)
        let receipt = try installer.install(from: url, replaceExisting: replaceExisting)
        installURLText = ""
        refresh()
        statusMessage = "Installed \(receipt.pluginID)."
    }

    func uninstallPlugin(id: String) throws {
        try installer.uninstall(id: id)
        refresh()
        statusMessage = "Uninstalled \(id)."
    }

    func setPlugin(_ id: String, enabled: Bool) throws {
        if enabled {
            try pluginManager.enablePlugin(id: id)
        } else {
            try pluginManager.disablePlugin(id: id)
        }
        refresh()
        statusMessage = enabled ? "Enabled \(id)." : "Disabled \(id)."
    }

    private func makeURL(from rawValue: String) throws -> URL {
        guard let url = PluginSourceURLResolver.resolve(rawValue) else {
            throw PluginMarketplaceViewModelError.missingURL
        }
        return url
    }
}

struct PluginMarketplaceView: View {
    @StateObject private var viewModel: PluginMarketplaceViewModel
    @State private var replaceExisting = false
    @State private var pendingUninstallID: String?

    init(pluginManager: PluginManager? = nil) {
        _viewModel = StateObject(
            wrappedValue: PluginMarketplaceViewModel(pluginManager: pluginManager)
        )
    }

    init(viewModel: PluginMarketplaceViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Sources") {
                TextField("URL or local path", text: $viewModel.sourceURLText)
                    .textFieldStyle(.roundedBorder)
                TextField("Name", text: $viewModel.sourceDisplayName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button {
                        perform { try viewModel.addSource() }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                }
                ForEach(viewModel.sources) { source in
                    HStack {
                        Text(source.displayName ?? source.url.absoluteString)
                        Spacer()
                        Text(source.url.absoluteString)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Install") {
                TextField("URL or local path", text: $viewModel.installURLText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Replace existing", isOn: $replaceExisting)
                Button {
                    perform { try viewModel.installPlugin(replaceExisting: replaceExisting) }
                } label: {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
            }

            Section("Installed") {
                if viewModel.plugins.isEmpty {
                    Text("No plugins installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.plugins) { plugin in
                        PluginMarketplaceRow(
                            plugin: plugin,
                            onToggle: { enabled in
                                perform { try viewModel.setPlugin(plugin.id, enabled: enabled) }
                            },
                            onUninstall: {
                                pendingUninstallID = plugin.id
                            }
                        )
                    }
                }
            }

            if let status = viewModel.statusMessage {
                Section {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .confirmationDialog(
            "Uninstall Plugin",
            isPresented: Binding(
                get: { pendingUninstallID != nil },
                set: { if !$0 { pendingUninstallID = nil } }
            )
        ) {
            Button("Uninstall", role: .destructive) {
                if let id = pendingUninstallID {
                    perform { try viewModel.uninstallPlugin(id: id) }
                }
                pendingUninstallID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUninstallID = nil
            }
        } message: {
            if let pendingUninstallID {
                Text(pendingUninstallID)
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            viewModel.statusMessage = error.localizedDescription
        }
    }
}

private struct PluginMarketplaceRow: View {
    let plugin: PluginState
    let onToggle: (Bool) -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.manifest.name)
                    .font(.headline)
                Text(plugin.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onToggle(!plugin.isEnabled)
            } label: {
                Label(
                    plugin.isEnabled ? "Disable" : "Enable",
                    systemImage: plugin.isEnabled ? "pause.circle" : "play.circle"
                )
            }
            Button(role: .destructive) {
                onUninstall()
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
        }
    }
}
