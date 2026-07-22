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
        case noUpdatesWithFailures(Int)
        case updateCheckFailed(Int)
        case updatesFound(Int)
        case updatesFoundWithFailures(updates: Int, failures: Int)
    }

    @Published var sourceURLText: String = ""
    @Published var sourceDisplayName: String = ""
    @Published var installURLText: String = ""
    @Published var statusMessage: String?
    @Published private(set) var sources: [PluginSource] = []
    @Published private(set) var bundledPlugins: [PluginManifest] = []
    @Published private(set) var plugins: [PluginState] = []
    @Published private(set) var availableUpdates: [PluginUpdateCandidate] = []
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var isInstallingPlugin = false
    @Published private(set) var pendingCapabilityRequest: PluginCapabilityApprovalRequest?

    private var signatureStatusesByPluginID: [String: PluginSignatureStatus] = [:]
    private let sourceStore: PluginSourceStore
    private let installer: PluginInstaller
    private let pluginManager: PluginManager
    private let bundledCatalog: BundledPluginCatalog
    private let updater: PluginUpdater
    private let grantStore: PluginCapabilityGrantStore
    private var localizer: AppLocalizer
    private var statusState: StatusState?

    init(
        sourceStore: PluginSourceStore = PluginSourceStore(),
        installer: PluginInstaller = PluginInstaller(),
        pluginManager: PluginManager? = nil,
        bundledCatalog: BundledPluginCatalog = BundledPluginCatalog(),
        updater: PluginUpdater = PluginUpdater(),
        grantStore: PluginCapabilityGrantStore = PluginCapabilityGrantStore(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.sourceStore = sourceStore
        self.installer = installer
        self.pluginManager = pluginManager ?? PluginManager(pluginsDirectory: installer.pluginsDirectory.path)
        self.bundledCatalog = bundledCatalog
        self.updater = updater
        self.grantStore = grantStore
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
        completeInstallation(receipt)
    }

    func installPluginInBackground(replaceExisting: Bool) async throws {
        guard !isInstallingPlugin else { return }
        let url = try makeURL(from: installURLText)
        let installer = self.installer
        isInstallingPlugin = true
        defer { isInstallingPlugin = false }

        let task = Task.detached(priority: .userInitiated) {
            try installer.install(from: url, replaceExisting: replaceExisting)
        }
        let receipt = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        completeInstallation(receipt)
    }

    private func completeInstallation(_ receipt: PluginInstallReceipt) {
        installURLText = ""
        refresh()
        signatureStatusesByPluginID[receipt.pluginID] = receipt.signatureStatus
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
        signatureStatusesByPluginID[receipt.pluginID] = receipt.signatureStatus
        setStatus(.installed(receipt.pluginID))
    }

    func uninstallPlugin(id: String) throws {
        try installer.uninstall(id: id)
        signatureStatusesByPluginID[id] = nil
        refresh()
        setStatus(.uninstalled(id))
    }

    func setPlugin(_ id: String, enabled: Bool) throws {
        if enabled {
            guard let plugin = pluginManager.plugin(id: id) else {
                throw PluginManagerError.pluginNotFound(id)
            }
            let missing = missingCapabilities(for: plugin.manifest)
            guard missing.isEmpty else {
                pendingCapabilityRequest = PluginCapabilityApprovalRequest(
                    pluginID: id,
                    pluginName: plugin.manifest.name,
                    capabilities: missing.sorted { $0.rawValue < $1.rawValue },
                    reason: Self.localizedCapabilityRequestReason(localizer: localizer)
                )
                return
            }
            try pluginManager.enablePlugin(id: id)
        } else {
            try pluginManager.disablePlugin(id: id)
        }
        refresh()
        setStatus(enabled ? .enabled(id) : .disabled(id))
    }

    func approvePendingCapabilityRequest() throws {
        guard let request = pendingCapabilityRequest else { return }
        for capability in request.capabilities {
            try grantStore.grant(
                capability,
                for: request.pluginID,
                reason: request.reason
            )
        }
        pendingCapabilityRequest = nil
        try pluginManager.enablePlugin(id: request.pluginID)
        refresh()
        setStatus(.enabled(request.pluginID))
    }

    func dismissPendingCapabilityRequest() {
        pendingCapabilityRequest = nil
    }

    func checkForPluginUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        let result = await updater.checkAvailableUpdates(
            for: pluginManager.plugins.map(\.manifest)
        )
        guard !result.wasCancelled else { return }

        availableUpdates = result.updates
        if result.failedSourceCount == 0 {
            setStatus(result.updates.isEmpty ? .noUpdates : .updatesFound(result.updates.count))
        } else if result.checkedSourceCount == 0 {
            setStatus(.updateCheckFailed(result.failedSourceCount))
        } else if result.updates.isEmpty {
            setStatus(.noUpdatesWithFailures(result.failedSourceCount))
        } else {
            setStatus(.updatesFoundWithFailures(
                updates: result.updates.count,
                failures: result.failedSourceCount
            ))
        }
    }

    func signatureStatus(for pluginID: String) -> PluginSignatureStatus? {
        signatureStatusesByPluginID[pluginID]
    }

    func displaySignatureStatus(for plugin: PluginState) -> PluginSignatureStatus {
        signatureStatusesByPluginID[plugin.id] ?? .inferred(from: plugin.manifest)
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
        case .noUpdatesWithFailures(let count):
            return String(
                format: localizer.string(
                    "plugins.status.updateCheckPartial.noUpdates",
                    fallback: "No updates found. Sources not checked: %d."
                ),
                count
            )
        case .updateCheckFailed(let count):
            return String(
                format: localizer.string(
                    count == 1
                        ? "plugins.status.updateCheckFailed.one"
                        : "plugins.status.updateCheckFailed.many",
                    fallback: count == 1
                        ? "Could not check plugin updates. 1 source failed."
                        : "Could not check plugin updates. %d sources failed."
                ),
                count
            )
        case .updatesFound(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "plugins.status.updatesFound.one" : "plugins.status.updatesFound.many",
                    fallback: count == 1 ? "%d update found." : "%d updates found."
                ),
                count
            )
        case .updatesFoundWithFailures(let updates, let failures):
            return String(
                format: localizer.string(
                    "plugins.status.updateCheckPartial.updates",
                    fallback: "Updates found: %d. Sources not checked: %d."
                ),
                updates,
                failures
            )
        }
    }

    private func missingCapabilities(for manifest: PluginManifest) -> [PluginCapability] {
        return manifest.capabilities.filter { capability in
            !grantStore.isGrantedWithoutThrowing(capability, for: manifest.id)
        }
    }

    private static func localizedCapabilityRequestReason(localizer: AppLocalizer) -> String {
        localizer.string(
            "plugins.capabilityRequest.reason",
            fallback: "Approved while enabling the plugin."
        )
    }
}

struct PluginCapabilityApprovalRequest: Equatable, Identifiable {
    let pluginID: String
    let pluginName: String
    let capabilities: [PluginCapability]
    let reason: String

    var id: String { pluginID }
}

struct PluginMarketplaceView: View {
    static let initialScrollAnchorID = "plugin-marketplace-top"

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
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pluginSection(localized("plugins.sources", fallback: "Sources")) {
                        TextField(
                            localized("plugins.urlOrPath", fallback: "URL or local path"),
                            text: $viewModel.sourceURLText
                        )
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
                    .id(Self.initialScrollAnchorID)
                    .disabled(viewModel.isInstallingPlugin)

                    pluginSection(localized("plugins.install.section", fallback: "Install")) {
                        PluginInstallSheet(
                            urlText: $viewModel.installURLText,
                            replaceExisting: $replaceExisting,
                            localizer: localizer,
                            isInstalling: viewModel.isInstallingPlugin
                        ) {
                            Task {
                                await perform {
                                    try await viewModel.installPluginInBackground(
                                        replaceExisting: replaceExisting
                                    )
                                }
                            }
                        }
                    }

                    pluginSection(localized("plugins.bundled.section", fallback: "Built-in")) {
                        if viewModel.bundledPlugins.isEmpty {
                            emptyText(localized("plugins.empty.bundled", fallback: "No bundled plugins available."))
                        } else {
                            ForEach(viewModel.bundledPlugins) { plugin in
                                PluginCardView(
                                    title: Self.localizedPluginName(plugin, using: localizer),
                                    subtitle: plugin.id,
                                    detail: Self.localizedPluginDescription(plugin, using: localizer),
                                    capabilities: plugin.capabilities,
                                    localizer: localizer,
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
                    .disabled(viewModel.isInstallingPlugin)

                    pluginSection(localized("plugins.installed.section", fallback: "Installed")) {
                        if viewModel.plugins.isEmpty {
                            emptyText(localized("plugins.empty.installed", fallback: "No plugins installed."))
                        } else {
                            ForEach(viewModel.plugins) { plugin in
                                PluginCardView(
                                    title: Self.localizedPluginName(plugin.manifest, using: localizer),
                                    subtitle: plugin.id,
                                    detail: Self.localizedPluginDescription(plugin.manifest, using: localizer),
                                    capabilities: plugin.manifest.capabilities,
                                    signatureStatus: viewModel.displaySignatureStatus(for: plugin),
                                    localizer: localizer,
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
                    .disabled(viewModel.isInstallingPlugin)

                    pluginSection(localized("plugins.updates.section", fallback: "Updates")) {
                        PluginUpdatePicker(
                            updates: viewModel.availableUpdates,
                            isRefreshing: viewModel.isCheckingForUpdates,
                            localizer: localizer,
                            onRefresh: {
                                Task {
                                    await viewModel.checkForPluginUpdates()
                                }
                            }
                        )
                    }
                    .disabled(viewModel.isInstallingPlugin)

                    if let status = viewModel.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .glassPanelBackground()
            .onAppear {
                viewModel.updateLocalizer(localizer)
                resetInitialScrollPosition(scrollProxy)
            }
            .onChange(of: localizer.resolvedLanguage) {
                viewModel.updateLocalizer(localizer)
            }
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
        .sheet(
            item: Binding(
                get: { viewModel.pendingCapabilityRequest },
                set: { newValue in
                    if newValue == nil {
                        viewModel.dismissPendingCapabilityRequest()
                    }
                }
            )
        ) { request in
            CapabilityRequestDialogView(
                request: request,
                localizer: localizer,
                onApprove: {
                    perform { try viewModel.approvePendingCapabilityRequest() }
                },
                onCancel: {
                    viewModel.dismissPendingCapabilityRequest()
                }
            )
        }
    }

    private func pluginSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func resetInitialScrollPosition(_ scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            scrollProxy.scrollTo(Self.initialScrollAnchorID, anchor: .top)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            viewModel.statusMessage = viewModel.localizedErrorDescription(error)
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
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
