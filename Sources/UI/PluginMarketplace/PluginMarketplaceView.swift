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
    private enum StatusState: Equatable {
        case failedLoadSources
        case failedLoadBundledPlugins
        case sourceAdded
        case installed(String)
        case uninstalled(String)
        case enabled(String)
        case disabled(String)
        case noUpdates
        case updatesFound(Int)
    }

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
    private var localizer: AppLocalizer
    private var statusState: StatusState?

    init(
        sourceStore: PluginSourceStore = PluginSourceStore(),
        installer: PluginInstaller = PluginInstaller(),
        pluginManager: PluginManager? = nil,
        bundledCatalog: BundledPluginCatalog = BundledPluginCatalog(),
        updater: PluginUpdater = PluginUpdater(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.sourceStore = sourceStore
        self.installer = installer
        self.pluginManager = pluginManager ?? PluginManager(pluginsDirectory: installer.pluginsDirectory.path)
        self.bundledCatalog = bundledCatalog
        self.updater = updater
        self.localizer = localizer
        refresh()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        if let statusState {
            statusMessage = Self.localizedStatusText(statusState, localizer: localizer)
        }
    }

    func refresh() {
        do {
            sources = try sourceStore.load()
        } catch {
            sources = []
            setStatus(.failedLoadSources)
        }
        do {
            bundledPlugins = try bundledCatalog.loadManifests()
        } catch {
            bundledPlugins = []
            setStatus(.failedLoadBundledPlugins)
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
        setStatus(.sourceAdded)
    }

    func installPlugin(replaceExisting: Bool) throws {
        let url = try makeURL(from: installURLText)
        let receipt = try installer.install(from: url, replaceExisting: replaceExisting)
        installURLText = ""
        refresh()
        setStatus(.installed(receipt.pluginID))
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
        setStatus(.installed(receipt.pluginID))
    }

    func uninstallPlugin(id: String) throws {
        try installer.uninstall(id: id)
        refresh()
        setStatus(.uninstalled(id))
    }

    func setPlugin(_ id: String, enabled: Bool) throws {
        if enabled {
            try pluginManager.enablePlugin(id: id)
        } else {
            try pluginManager.disablePlugin(id: id)
        }
        refresh()
        setStatus(enabled ? .enabled(id) : .disabled(id))
    }

    func checkForPluginUpdates() {
        availableUpdates = updater.availableUpdates(for: pluginManager.plugins.map(\.manifest))
        setStatus(availableUpdates.isEmpty ? .noUpdates : .updatesFound(availableUpdates.count))
    }

    func localizedErrorDescription(_ error: Error) -> String {
        if let viewModelError = error as? PluginMarketplaceViewModelError {
            switch viewModelError {
            case .missingURL:
                return localizer.string(
                    "plugins.error.missingURL",
                    fallback: "Enter a plugin URL or local path."
                )
            }
        }
        return error.localizedDescription
    }

    private func makeURL(from rawValue: String) throws -> URL {
        guard let url = PluginSourceURLResolver.resolve(rawValue) else {
            throw PluginMarketplaceViewModelError.missingURL
        }
        return url
    }

    private func setStatus(_ state: StatusState) {
        statusState = state
        statusMessage = Self.localizedStatusText(state, localizer: localizer)
    }

    private static func localizedStatusText(_ state: StatusState, localizer: AppLocalizer) -> String {
        switch state {
        case .failedLoadSources:
            return localizer.string("plugins.status.failedLoadSources", fallback: "Failed to load sources.")
        case .failedLoadBundledPlugins:
            return localizer.string("plugins.status.failedLoadBundledPlugins", fallback: "Failed to load bundled plugins.")
        case .sourceAdded:
            return localizer.string("plugins.status.sourceAdded", fallback: "Plugin source added.")
        case .installed(let pluginID):
            return String(format: localizer.string("plugins.status.installed", fallback: "Installed %@."), pluginID)
        case .uninstalled(let pluginID):
            return String(format: localizer.string("plugins.status.uninstalled", fallback: "Uninstalled %@."), pluginID)
        case .enabled(let pluginID):
            return String(format: localizer.string("plugins.status.enabled", fallback: "Enabled %@."), pluginID)
        case .disabled(let pluginID):
            return String(format: localizer.string("plugins.status.disabled", fallback: "Disabled %@."), pluginID)
        case .noUpdates:
            return localizer.string("plugins.status.noUpdates", fallback: "No updates found.")
        case .updatesFound(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "plugins.status.updatesFound.one" : "plugins.status.updatesFound.many",
                    fallback: count == 1 ? "%d update found." : "%d updates found."
                ),
                count
            )
        }
    }
}

struct PluginMarketplaceView: View {
    @StateObject private var viewModel: PluginMarketplaceViewModel
    @State private var replaceExisting = false
    @State private var pendingUninstallID: String?
    var localizer: AppLocalizer

    init(
        pluginManager: PluginManager? = nil,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        _viewModel = StateObject(
            wrappedValue: PluginMarketplaceViewModel(
                pluginManager: pluginManager,
                localizer: localizer
            )
        )
        self.localizer = localizer
    }

    init(
        viewModel: PluginMarketplaceViewModel,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.localizer = localizer
        viewModel.updateLocalizer(localizer)
    }

    var body: some View {
        Form {
            Section(localized("plugins.sources", fallback: "Sources")) {
                TextField(localized("plugins.urlOrPath", fallback: "URL or local path"), text: $viewModel.sourceURLText)
                    .textFieldStyle(.roundedBorder)
                TextField(localized("plugins.name", fallback: "Name"), text: $viewModel.sourceDisplayName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button {
                        perform { try viewModel.addSource() }
                    } label: {
                        Label(localized("plugins.add", fallback: "Add"), systemImage: "plus")
                    }
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label(localized("plugins.refresh", fallback: "Refresh"), systemImage: "arrow.clockwise")
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

            Section(localized("plugins.install.section", fallback: "Install")) {
                PluginInstallSheet(
                    urlText: $viewModel.installURLText,
                    replaceExisting: $replaceExisting,
                    localizer: localizer
                ) {
                    perform { try viewModel.installPlugin(replaceExisting: replaceExisting) }
                }
            }

            Section(localized("plugins.bundled.section", fallback: "Built-in")) {
                if viewModel.bundledPlugins.isEmpty {
                    Text(localized("plugins.empty.bundled", fallback: "No bundled plugins available."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.bundledPlugins) { plugin in
                        PluginCardView(
                            title: Self.localizedPluginName(plugin, using: localizer),
                            subtitle: plugin.id,
                            detail: Self.localizedPluginDescription(plugin, using: localizer),
                            capabilities: plugin.capabilities,
                            primaryAction: PluginCardAction(
                                title: localized("plugins.install", fallback: "Install"),
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

            Section(localized("plugins.installed.section", fallback: "Installed")) {
                if viewModel.plugins.isEmpty {
                    Text(localized("plugins.empty.installed", fallback: "No plugins installed."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.plugins) { plugin in
                        PluginCardView(
                            title: Self.localizedPluginName(plugin.manifest, using: localizer),
                            subtitle: plugin.id,
                            detail: Self.localizedPluginDescription(plugin.manifest, using: localizer),
                            capabilities: plugin.manifest.capabilities,
                            primaryAction: PluginCardAction(
                                title: plugin.isEnabled
                                    ? localized("plugins.disable", fallback: "Disable")
                                    : localized("plugins.enable", fallback: "Enable"),
                                systemImage: plugin.isEnabled ? "pause.circle" : "play.circle",
                                perform: {
                                    perform {
                                        try viewModel.setPlugin(plugin.id, enabled: !plugin.isEnabled)
                                    }
                                }
                            ),
                            secondaryAction: PluginCardAction(
                                title: localized("plugins.uninstall", fallback: "Uninstall"),
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

            Section(localized("plugins.updates.section", fallback: "Updates")) {
                PluginUpdatePicker(
                    updates: viewModel.availableUpdates,
                    localizer: localizer,
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
        .glassPanelBackground()
        .onAppear {
            viewModel.updateLocalizer(localizer)
        }
        .onChange(of: localizer.resolvedLanguage) {
            viewModel.updateLocalizer(localizer)
        }
        .confirmationDialog(
            localized("plugins.uninstall.title", fallback: "Uninstall Plugin"),
            isPresented: Binding(
                get: { pendingUninstallID != nil },
                set: { if !$0 { pendingUninstallID = nil } }
            )
        ) {
            Button(localized("plugins.uninstall", fallback: "Uninstall"), role: .destructive) {
                if let id = pendingUninstallID {
                    perform { try viewModel.uninstallPlugin(id: id) }
                }
                pendingUninstallID = nil
            }
            Button(localized("common.cancel", fallback: "Cancel"), role: .cancel) {
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
            viewModel.statusMessage = viewModel.localizedErrorDescription(error)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    static func localizedPluginName(_ plugin: PluginManifest, using localizer: AppLocalizer) -> String {
        localizer.string("plugins.builtin.\(plugin.id).name", fallback: plugin.name)
    }

    static func localizedPluginDescription(_ plugin: PluginManifest, using localizer: AppLocalizer) -> String {
        localizer.string("plugins.builtin.\(plugin.id).description", fallback: plugin.description)
    }
}
