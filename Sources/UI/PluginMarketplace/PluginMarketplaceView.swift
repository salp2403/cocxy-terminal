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
    @Published private(set) var bundledPlugins: [PluginManifest] = []
    @Published private(set) var plugins: [PluginState] = []
    @Published private(set) var availableUpdates: [PluginUpdateCandidate] = []

    private let sourceStore: PluginSourceStore
    private let installer: PluginInstaller
    private let pluginManager: PluginManager
    private let bundledCatalog: BundledPluginCatalog
    private let updater: PluginUpdater

    init(
        sourceStore: PluginSourceStore = PluginSourceStore(),
        installer: PluginInstaller = PluginInstaller(),
        pluginManager: PluginManager? = nil,
        bundledCatalog: BundledPluginCatalog = BundledPluginCatalog(),
        updater: PluginUpdater = PluginUpdater()
    ) {
        self.sourceStore = sourceStore
        self.installer = installer
        self.pluginManager = pluginManager ?? PluginManager(pluginsDirectory: installer.pluginsDirectory.path)
        self.bundledCatalog = bundledCatalog
        self.updater = updater
        refresh()
    }

    func refresh() {
        do {
            sources = try sourceStore.load()
        } catch {
            sources = []
            statusMessage = "Failed to load sources."
        }
        do {
            bundledPlugins = try bundledCatalog.loadManifests()
        } catch {
            bundledPlugins = []
            statusMessage = "Failed to load bundled plugins."
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

    func installBundledPlugin(id: String, replaceExisting: Bool) throws {
        guard let manifest = bundledPlugins.first(where: { $0.id == id }) else {
            throw PluginInstallerError.pluginNotInstalled(id)
        }
        let receipt = try installer.install(
            from: URL(fileURLWithPath: manifest.directoryPath, isDirectory: true),
            replaceExisting: replaceExisting
        )
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

    func checkForPluginUpdates() {
        availableUpdates = updater.availableUpdates(for: pluginManager.plugins.map(\.manifest))
        statusMessage = availableUpdates.isEmpty
            ? "No updates found."
            : "\(availableUpdates.count) update\(availableUpdates.count == 1 ? "" : "s") found."
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
                PluginInstallSheet(
                    urlText: $viewModel.installURLText,
                    replaceExisting: $replaceExisting
                ) {
                    perform { try viewModel.installPlugin(replaceExisting: replaceExisting) }
                }
            }

            Section("Built-in") {
                if viewModel.bundledPlugins.isEmpty {
                    Text("No bundled plugins available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.bundledPlugins) { plugin in
                        PluginCardView(
                            title: plugin.name,
                            subtitle: plugin.id,
                            detail: plugin.description,
                            capabilities: plugin.capabilities,
                            primaryAction: PluginCardAction(
                                title: "Install",
                                systemImage: "square.and.arrow.down",
                                perform: {
                                    perform {
                                        try viewModel.installBundledPlugin(
                                            id: plugin.id,
                                            replaceExisting: replaceExisting
                                        )
                                    }
                                }
                            )
                        )
                    }
                }
            }

            Section("Installed") {
                if viewModel.plugins.isEmpty {
                    Text("No plugins installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.plugins) { plugin in
                        PluginCardView(
                            title: plugin.manifest.name,
                            subtitle: plugin.id,
                            detail: plugin.manifest.description,
                            capabilities: plugin.manifest.capabilities,
                            primaryAction: PluginCardAction(
                                title: plugin.isEnabled ? "Disable" : "Enable",
                                systemImage: plugin.isEnabled ? "pause.circle" : "play.circle",
                                perform: {
                                    perform {
                                        try viewModel.setPlugin(plugin.id, enabled: !plugin.isEnabled)
                                    }
                                }
                            ),
                            secondaryAction: PluginCardAction(
                                title: "Uninstall",
                                systemImage: "trash",
                                role: .destructive,
                                perform: {
                                    pendingUninstallID = plugin.id
                                }
                            )
                        )
                    }
                }
            }

            Section("Updates") {
                PluginUpdatePicker(
                    updates: viewModel.availableUpdates,
                    onRefresh: {
                        viewModel.checkForPluginUpdates()
                    }
                )
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
