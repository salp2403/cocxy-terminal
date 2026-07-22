// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+SocketCommandAuthorization.swift - Native approval for privileged CLI socket commands.

import AppKit

struct SocketPrivilegedCommandApprovalCopy: Equatable {
    let title: String
    let message: String
    let approveButton: String
    let cancelButton: String
    let previewAccessibilityLabel: String
}

@MainActor
final class SocketPrivilegedCommandAuthorizationCoordinator {
    typealias PresentationTargetProvider = @MainActor () -> SocketPrivilegedCommandPresentationTarget?
    typealias Completion = @MainActor (SocketPrivilegedCommandAuthorizationGrant?) -> Void

    var presenter: ((
        SocketPrivilegedCommandAuthorizationRequest,
        SocketPrivilegedCommandContext
    ) -> Bool)?

    private var activeRequestID: UUID?
    private var consumedRequestIDs: [UUID: Date] = [:]

    func requestAuthorization(
        _ request: SocketPrivilegedCommandAuthorizationRequest,
        targetProvider: @escaping PresentationTargetProvider,
        completion: @escaping Completion
    ) {
        let now = Date()
        consumedRequestIDs = consumedRequestIDs.filter { $0.value > now }
        guard request.isValid(at: now),
              activeRequestID == nil,
              consumedRequestIDs[request.id] == nil,
              let target = targetProvider() else {
            completion(nil)
            return
        }

        consumedRequestIDs[request.id] = request.expiresAt
        activeRequestID = request.id

        if let presenter {
            let approved = presenter(request, target.context)
            let currentTarget = targetProvider()
            activeRequestID = nil
            guard approved,
                  request.isValid(at: Date()),
                  currentTarget?.context == target.context else {
                completion(nil)
                return
            }
            completion(SocketPrivilegedCommandAuthorizationGrant(
                request: request,
                context: target.context
            ))
            return
        }

        guard let parentWindow = target.controller.window,
              parentWindow.attachedSheet == nil else {
            activeRequestID = nil
            completion(nil)
            return
        }

        let copy = MainWindowController.localizedPrivilegedSocketCommandApprovalCopy(
            request: request,
            context: target.context,
            localizer: target.controller.appLocalizer()
        )
        let alert = NSAlert()
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.alertStyle = .warning
        alert.icon = NSImage(
            systemSymbolName: "lock.shield.fill",
            accessibilityDescription: copy.title
        ) ?? AppIconGenerator.generatePlaceholderIcon()
        let approveButton = alert.addButton(withTitle: copy.approveButton)
        approveButton.keyEquivalent = ""
        let cancelButton = alert.addButton(withTitle: copy.cancelButton)
        cancelButton.keyEquivalent = "\u{1B}"
        alert.accessoryView = MainWindowController.privilegedSocketCommandPreview(
            MainWindowController.privilegedSocketCommandApprovalPreview(
                request: request,
                context: target.context
            ),
            accessibilityLabel: copy.previewAccessibilityLabel
        )

        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, self.activeRequestID == request.id else { return }
                self.activeRequestID = nil
                let currentTarget = targetProvider()
                guard response == .alertFirstButtonReturn,
                      request.isValid(at: Date()),
                      currentTarget?.context == target.context else {
                    completion(nil)
                    return
                }
                completion(SocketPrivilegedCommandAuthorizationGrant(
                    request: request,
                    context: target.context
                ))
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, request.expiresAt.timeIntervalSinceNow)) {
            MainActor.assumeIsolated { [weak self, weak parentWindow, weak alert] in
                guard let self,
                      self.activeRequestID == request.id,
                      let parentWindow,
                      let alert,
                      alert.window.sheetParent === parentWindow else {
                    return
                }
                parentWindow.endSheet(alert.window, returnCode: .abort)
            }
        }
    }
}

@MainActor
struct SocketPrivilegedCommandPresentationTarget {
    let context: SocketPrivilegedCommandContext
    let controller: MainWindowController
}

extension AppDelegate {
    @MainActor
    func socketBrowserViewModel(
        for context: SocketPrivilegedCommandContext?
    ) -> BrowserViewModel? {
        if let context {
            return privilegedSocketBrowserViewModel(for: context)
        }
        // browser-init-script-add has a separate exact native approval flow.
        return activeBrowserViewModelForCLI()
    }

    @MainActor
    func withPrivilegedSocketCommandContext<T>(
        _ context: SocketPrivilegedCommandContext?,
        operation: () -> T
    ) -> T {
        let previous = activePrivilegedSocketCommandContext
        activePrivilegedSocketCommandContext = context
        defer { activePrivilegedSocketCommandContext = previous }
        return operation()
    }

    @MainActor
    func privilegedSocketController(
        for context: SocketPrivilegedCommandContext?
    ) -> MainWindowController? {
        guard let context else { return nil }
        guard let identifier = context.windowControllerIdentifier else {
            guard context.scope == .internalTrusted else { return nil }
            return focusedWindowController() ?? windowController
        }
        return allWindowControllers.first {
            ObjectIdentifier($0) == identifier
        }
    }

    @MainActor
    func privilegedSocketTerminalTarget(
        for context: SocketPrivilegedCommandContext?
    ) -> (controller: MainWindowController, surfaceID: SurfaceID)? {
        guard let context,
              context.scope == .terminalSurface,
              let rawTabID = context.tabID,
              let rawSurfaceID = context.surfaceID,
              let controller = privilegedSocketController(for: context) else {
            return nil
        }
        let tabID = TabID(rawValue: rawTabID)
        let surfaceID = SurfaceID(rawValue: rawSurfaceID)
        guard controller.tabManager.tab(for: tabID) != nil,
              controller.surfaceIDs(for: tabID).contains(surfaceID) else {
            return nil
        }
        return (controller, surfaceID)
    }

    @MainActor
    func privilegedSocketBrowserViewModel(
        for context: SocketPrivilegedCommandContext?
    ) -> BrowserViewModel? {
        guard let context else { return nil }
        if context.scope == .internalTrusted {
            return activeBrowserViewModelForCLI()
        }
        guard context.scope == .browserPage,
              let modelIdentifier = context.browserViewModelIdentifier,
              let expectedBrowserTabID = context.browserTabID,
              let controller = privilegedSocketController(for: context),
              context.tabID.flatMap({ controller.tabManager.tab(for: TabID(rawValue: $0)) }) != nil,
              let viewModel = controller.allBrowserViewModels().first(where: {
                  ObjectIdentifier($0) == modelIdentifier
              }),
              viewModel.activeTabID == expectedBrowserTabID,
              (viewModel.currentURL?.absoluteString ?? viewModel.urlString) == context.browserURL,
              viewModel.currentAutomationPageIdentity()?.webViewIdentifier
                == context.browserWebViewIdentifier,
              viewModel.currentAutomationPageIdentity()?.navigationGeneration
                == context.browserNavigationGeneration else {
            return nil
        }
        return viewModel
    }

    @MainActor
    func privilegedSocketBrowserViewModels(
        for context: SocketPrivilegedCommandContext?
    ) -> [BrowserViewModel] {
        guard let context else { return [] }
        switch context.scope {
        case .browserGlobal, .internalTrusted:
            return allWindowControllers.flatMap { $0.allBrowserViewModels() }
        case .browserPage:
            return privilegedSocketBrowserViewModel(for: context).map { [$0] } ?? []
        default:
            return []
        }
    }

    @MainActor
    func privilegedSocketBrowserNavigationViewModel(
        for context: SocketPrivilegedCommandContext?
    ) -> BrowserViewModel? {
        guard let context else { return nil }
        if context.scope == .internalTrusted {
            return browserViewModelForExternalNavigationCLI()
        }
        if context.scope == .browserPage {
            return privilegedSocketBrowserViewModel(for: context)
        }
        guard context.scope == .browserNavigation,
              let rawTabID = context.tabID,
              let controller = privilegedSocketController(for: context),
              (controller.visibleTabID ?? controller.tabManager.activeTabID)?.rawValue == rawTabID else {
            return nil
        }
        return controller.browserViewModelForExternalNavigation()
    }

    @MainActor
    func privilegedSocketTabOutputLines(
        for context: SocketPrivilegedCommandContext?
    ) -> [String] {
        guard let context else { return [] }
        if context.scope == .internalTrusted {
            return (focusedWindowController() ?? windowController)?.terminalOutputBuffer.lines ?? []
        }
        guard
              context.scope == .terminalTab,
              let rawTabID = context.tabID,
              let controller = privilegedSocketController(for: context) else {
            return []
        }
        let tabID = TabID(rawValue: rawTabID)
        guard controller.tabManager.tab(for: tabID) != nil else { return [] }
        return controller.tabOutputBuffers[tabID]?.lines ?? []
    }

    @MainActor
    func privilegedSocketCommandPresentationTarget(
        for request: SocketPrivilegedCommandAuthorizationRequest
    ) -> SocketPrivilegedCommandPresentationTarget? {
        guard request.isValid(at: Date()),
              let focusedController = focusedWindowController() ?? windowController else {
            return nil
        }

        switch request.category {
        case .terminalInput, .terminalRead, .terminalSharing:
            if request.command == .timelineShow || request.command == .timelineExport {
                if let rawTabID = request.params["tabId"] {
                    return terminalTabPresentationTarget(
                        tabID: rawTabID,
                        fallbackController: focusedController,
                        displayPrefix: "Terminal timeline"
                    )
                }
                return SocketPrivilegedCommandPresentationTarget(
                    context: SocketPrivilegedCommandContext(
                        scope: .terminalTab,
                        windowControllerIdentifier: ObjectIdentifier(focusedController),
                        tabID: nil,
                        workingDirectory: "All terminal timelines",
                        surfaceID: nil,
                        browserViewModelIdentifier: nil,
                        browserTabID: nil,
                        browserURL: nil,
                        targetDisplayName: "All terminal timelines"
                    ),
                    controller: focusedController
                )
            }
            if let rawTabID = request.params["tabId"] {
                guard request.command == .timelineShow
                    || request.command == .timelineExport
                    || request.command == .search else {
                    return nil
                }
                return terminalTabPresentationTarget(
                    tabID: rawTabID,
                    fallbackController: focusedController,
                    displayPrefix: "Terminal tab"
                )
            }
            guard let (tabID, tab) = activeTab(in: focusedController) else { return nil }
            let workingDirectory = canonicalWorkingDirectory(for: tab)
            if request.command == .capturePane || request.command == .search {
                return SocketPrivilegedCommandPresentationTarget(
                    context: SocketPrivilegedCommandContext(
                        scope: .terminalTab,
                        windowControllerIdentifier: ObjectIdentifier(focusedController),
                        tabID: tabID.rawValue,
                        workingDirectory: workingDirectory,
                        surfaceID: nil,
                        browserViewModelIdentifier: nil,
                        browserTabID: nil,
                        browserURL: nil,
                        targetDisplayName: "Terminal tab \(tab.displayTitle)"
                    ),
                    controller: focusedController
                )
            }
            guard let surfaceID = focusedController.focusedSplitSurfaceView?.terminalViewModel?.surfaceID
                ?? focusedController.activeTerminalSurfaceView?.terminalViewModel?.surfaceID,
                  focusedController.surfaceIDs(for: tabID).contains(surfaceID) else {
                return nil
            }
            return SocketPrivilegedCommandPresentationTarget(
                context: SocketPrivilegedCommandContext(
                    scope: .terminalSurface,
                    windowControllerIdentifier: ObjectIdentifier(focusedController),
                    tabID: tabID.rawValue,
                    workingDirectory: workingDirectory,
                    surfaceID: surfaceID.rawValue,
                    browserViewModelIdentifier: nil,
                    browserTabID: nil,
                    browserURL: nil,
                    targetDisplayName: "Terminal surface \(surfaceID.rawValue.uuidString)"
                ),
                controller: focusedController
            )

        case .browserControl, .browserRead:
            if request.command == .browserImportPreview
                || request.command == .browserImportRun {
                return browserImportPresentationTarget(
                    for: request,
                    controller: focusedController
                )
            }
            if request.command == .browserInitScriptRemove
                || request.command == .browserInitScriptsList {
                return globalPresentationTarget(
                    controller: focusedController,
                    scope: .browserGlobal,
                    displayName: "Browser profiles and scripts"
                )
            }

            guard let (tabID, tab) = activeTab(in: focusedController) else { return nil }
            let workingDirectory = canonicalWorkingDirectory(for: tab)
            if let viewModel = focusedController.activeBrowserViewModel(),
               let browserTabID = viewModel.activeTabID {
                let localResourcePaths = canonicalSocketResourcePaths(for: request)
                let automationPage = viewModel.currentAutomationPageIdentity()
                return SocketPrivilegedCommandPresentationTarget(
                    context: SocketPrivilegedCommandContext(
                        scope: .browserPage,
                        windowControllerIdentifier: ObjectIdentifier(focusedController),
                        tabID: tabID.rawValue,
                        workingDirectory: workingDirectory,
                        localResourcePaths: localResourcePaths,
                        surfaceID: nil,
                        browserViewModelIdentifier: ObjectIdentifier(viewModel),
                        browserTabID: browserTabID,
                        browserURL: automationPage?.url
                            ?? viewModel.currentURL?.absoluteString
                            ?? viewModel.urlString,
                        browserWebViewIdentifier: automationPage?.webViewIdentifier,
                        browserNavigationGeneration: automationPage?.navigationGeneration,
                        targetDisplayName: viewModel.currentURL?.absoluteString
                            ?? viewModel.urlString
                    ),
                    controller: focusedController
                )
            }
            guard request.command == .browserNavigate else { return nil }
            return SocketPrivilegedCommandPresentationTarget(
                context: SocketPrivilegedCommandContext(
                    scope: .browserNavigation,
                    windowControllerIdentifier: ObjectIdentifier(focusedController),
                    tabID: tabID.rawValue,
                    workingDirectory: workingDirectory,
                    surfaceID: nil,
                    browserViewModelIdentifier: nil,
                    browserTabID: nil,
                    browserURL: nil,
                    targetDisplayName: "Browser in terminal tab \(tab.displayTitle)"
                ),
                controller: focusedController
            )

        case .providerCredentialUse:
            guard let (tabID, tab) = activeTab(in: focusedController) else { return nil }
            let workingDirectory = canonicalWorkingDirectory(for: tab)
            let settings = configService?.current.gitAssistant ?? .defaults
            guard settings.enabled,
                  let authorityDetails = GitAssistantSocketAuthority.details(
                    request: request,
                    provider: settings.defaultProvider,
                    workingDirectory: URL(fileURLWithPath: workingDirectory)
                  ) else {
                return nil
            }
            return SocketPrivilegedCommandPresentationTarget(
                context: SocketPrivilegedCommandContext(
                    scope: .repository,
                    windowControllerIdentifier: ObjectIdentifier(focusedController),
                    tabID: tabID.rawValue,
                    workingDirectory: workingDirectory,
                    authorityDetails: authorityDetails,
                    surfaceID: nil,
                    browserViewModelIdentifier: nil,
                    browserTabID: nil,
                    browserURL: nil,
                    targetDisplayName: "\(workingDirectory) via \(settings.defaultProvider.rawValue)"
                ),
                controller: focusedController
            )

        case .localExecution:
            if request.command == .agentTeamLaunch {
                guard let (tabID, tab) = activeTab(in: focusedController) else { return nil }
                let workingDirectory = canonicalWorkingDirectory(for: tab)
                return SocketPrivilegedCommandPresentationTarget(
                    context: SocketPrivilegedCommandContext(
                        scope: .localExecution,
                        windowControllerIdentifier: ObjectIdentifier(focusedController),
                        tabID: tabID.rawValue,
                        workingDirectory: workingDirectory,
                        surfaceID: nil,
                        browserViewModelIdentifier: nil,
                        browserTabID: nil,
                        browserURL: nil,
                        targetDisplayName: "Agent team in \(tab.displayTitle)"
                    ),
                    controller: focusedController
                )
            }
            let inputPath = request.params["input"] ?? request.params["output"]
            let localResourcePaths = ["input", "output", "cwd"].reduce(
                into: [String: String]()
            ) { paths, key in
                if let canonicalPath = canonicalCLIPath(request.params[key])?.path {
                    paths[key] = canonicalPath
                }
            }
            var localResourceDigests: [String: String] = [:]
            if request.command == .workflowRun {
                guard let inputPath = localResourcePaths["input"],
                      let digest = SocketPrivilegedCommandSecurity.boundedFileDigest(
                        at: URL(fileURLWithPath: inputPath)
                      ) else {
                    return nil
                }
                localResourceDigests["input"] = digest
            }
            let workingDirectory = localResourcePaths["cwd"]
                ?? localResourcePaths["input"].map {
                    URL(fileURLWithPath: $0).deletingLastPathComponent().path
                }
                ?? localResourcePaths["output"].map {
                    URL(fileURLWithPath: $0).deletingLastPathComponent().path
                }
                ?? activeTab(in: focusedController).map {
                    canonicalWorkingDirectory(for: $0.tab)
                }
                ?? FileManager.default.homeDirectoryForCurrentUser.path
            return globalPresentationTarget(
                controller: focusedController,
                scope: .localExecution,
                workingDirectory: workingDirectory,
                localResourcePaths: localResourcePaths,
                localResourceDigests: localResourceDigests,
                displayName: inputPath ?? request.command.rawValue
            )

        case .computeControl:
            let identifier = request.params["cell-id"]
                ?? request.params["name"]
                ?? request.params["profile"]
                ?? request.params["provider"]
                ?? "Compute cells"
            return globalPresentationTarget(
                controller: focusedController,
                scope: .computeCell,
                localResourcePaths: canonicalSocketResourcePaths(for: request),
                displayName: identifier
            )

        case .remoteConnection:
            guard let (tabID, tab) = activeTab(in: focusedController) else { return nil }
            return SocketPrivilegedCommandPresentationTarget(
                context: SocketPrivilegedCommandContext(
                    scope: .remoteConnection,
                    windowControllerIdentifier: ObjectIdentifier(focusedController),
                    tabID: tabID.rawValue,
                    workingDirectory: canonicalWorkingDirectory(for: tab),
                    localResourcePaths: canonicalSocketResourcePaths(for: request),
                    surfaceID: nil,
                    browserViewModelIdentifier: nil,
                    browserTabID: nil,
                    browserURL: nil,
                    targetDisplayName: request.params["destination"] ?? "SSH connection"
                ),
                controller: focusedController
            )
        }
    }

    @MainActor
    private func terminalTabPresentationTarget(
        tabID rawTabID: String,
        fallbackController: MainWindowController,
        displayPrefix: String
    ) -> SocketPrivilegedCommandPresentationTarget? {
        guard let uuid = UUID(uuidString: rawTabID) else { return nil }
        let tabID = TabID(rawValue: uuid)
        guard let controller = controllerContainingTab(tabID),
              let tab = controller.tabManager.tab(for: tabID) else {
            return nil
        }
        return SocketPrivilegedCommandPresentationTarget(
            context: SocketPrivilegedCommandContext(
                scope: .terminalTab,
                windowControllerIdentifier: ObjectIdentifier(controller),
                tabID: uuid,
                workingDirectory: canonicalWorkingDirectory(for: tab),
                surfaceID: nil,
                browserViewModelIdentifier: nil,
                browserTabID: nil,
                browserURL: nil,
                targetDisplayName: "\(displayPrefix) \(tab.displayTitle)"
            ),
            controller: controller
        )
    }

    @MainActor
    private func globalPresentationTarget(
        controller: MainWindowController,
        scope: SocketPrivilegedCommandContext.Scope,
        workingDirectory: String? = nil,
        localResourcePaths: [String: String] = [:],
        localResourceDigests: [String: String] = [:],
        browserProfileID: UUID? = nil,
        displayName: String
    ) -> SocketPrivilegedCommandPresentationTarget {
        SocketPrivilegedCommandPresentationTarget(
            context: SocketPrivilegedCommandContext(
                scope: scope,
                windowControllerIdentifier: ObjectIdentifier(controller),
                tabID: nil,
                workingDirectory: workingDirectory ?? "Cocxy application",
                localResourcePaths: localResourcePaths,
                localResourceDigests: localResourceDigests,
                surfaceID: nil,
                browserViewModelIdentifier: nil,
                browserTabID: nil,
                browserURL: nil,
                browserProfileID: browserProfileID,
                targetDisplayName: displayName
            ),
            controller: controller
        )
    }

    @MainActor
    private func browserImportPresentationTarget(
        for request: SocketPrivilegedCommandAuthorizationRequest,
        controller: MainWindowController
    ) -> SocketPrivilegedCommandPresentationTarget? {
        guard let rawSource = request.params["source"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              let source = BrowserImportSource(rawValue: rawSource),
              let profileManager = browserProfileManager else {
            return nil
        }

        let profileID: UUID
        if let rawProfileID = request.params["profile"] {
            guard let parsedProfileID = UUID(uuidString: rawProfileID) else { return nil }
            profileID = parsedProfileID
        } else {
            profileID = profileManager.activeProfileID
        }
        guard let profile = profileManager.profiles.first(where: { $0.id == profileID }),
              !profile.isRemoteBacked else {
            return nil
        }

        var canonicalExplicitPaths: [String: String] = [:]
        for key in ["history", "cookies", "bookmarks"] {
            guard let rawPath = request.params[key] else { continue }
            guard let canonicalPath = canonicalCLIPath(rawPath)?.path else { return nil }
            canonicalExplicitPaths[key] = canonicalPath
        }
        let isEnabled: (String) -> Bool = { key in
            request.params[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() != "false"
        }
        let importHistory = isEnabled("import-history")
        let importCookies = isEnabled("import-cookies")
        let importBookmarks = isEnabled("import-bookmarks")
        guard importHistory || importCookies || importBookmarks else { return nil }

        let locations = BrowserImportLocationPathBinding.requestedLocations(
            source: source,
            profileName: request.params["source-profile"],
            discoverProfiles: false,
            importHistory: importHistory,
            importCookies: importCookies,
            importBookmarks: importBookmarks,
            historyPath: canonicalExplicitPaths["history"],
            cookiesPath: canonicalExplicitPaths["cookies"],
            bookmarksPath: canonicalExplicitPaths["bookmarks"]
        )
        guard !locations.isEmpty,
              let resourcePaths = BrowserImportLocationPathBinding.canonicalResourcePaths(
            for: locations,
            importHistory: importHistory,
            importCookies: importCookies,
            importBookmarks: importBookmarks,
            canonicalize: { [self] url in canonicalCLIPath(url.path) }
        ) else {
            return nil
        }

        let locationLabel = locations.count == 1 ? "location" : "locations"
        return globalPresentationTarget(
            controller: controller,
            scope: .browserGlobal,
            localResourcePaths: resourcePaths,
            browserProfileID: profileID,
            displayName: "Import \(source.displayName) into \(profile.name) (\(locations.count) \(locationLabel))"
        )
    }

    @MainActor
    private func activeTab(
        in controller: MainWindowController
    ) -> (id: TabID, tab: Tab)? {
        guard let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let tab = controller.tabManager.tab(for: tabID) else {
            return nil
        }
        return (tabID, tab)
    }

    private func canonicalWorkingDirectory(for tab: Tab) -> String {
        (tab.worktreeRoot ?? tab.workingDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
    }

    private func canonicalCLIPath(_ rawPath: String?) -> URL? {
        guard let rawPath,
              !rawPath.isEmpty,
              rawPath.utf8.count <= 4_096,
              !rawPath.contains("\0") else {
            return nil
        }
        let expanded = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private func canonicalSocketResourcePaths(
        for request: SocketPrivilegedCommandAuthorizationRequest
    ) -> [String: String] {
        if request.command == .cellCreate {
            return CellCLICommandService.createLocalResourcePathValues(in: request.params)
                .reduce(into: [String: String]()) { paths, entry in
                    if let canonicalPath = canonicalCLIPath(entry.value)?.path {
                        paths[entry.key] = canonicalPath
                    }
                }
        }
        var keys: [String]
        switch request.command {
        case .browserStateSave, .browserStateLoad, .browserUpload:
            keys = ["path"]
        case .browserScreenshot:
            keys = ["output"]
        case .ssh:
            keys = ["identity"]
        default:
            keys = []
        }
        if request.params["screenshotDir"] != nil {
            keys.append("screenshotDir")
        }
        return keys.reduce(into: [String: String]()) { paths, key in
            if let canonicalPath = canonicalCLIPath(request.params[key])?.path {
                paths[key] = canonicalPath
            }
        }
    }
}

extension MainWindowController {
    static func privilegedSocketCommandApprovalPreview(
        request: SocketPrivilegedCommandAuthorizationRequest,
        context: SocketPrivilegedCommandContext
    ) -> String {
        var lines = [
            SocketPrivilegedCommandSecurity.approvalPreview(request),
            "",
            "Resolved authority:",
            "scope: \(SocketPrivilegedCommandSecurity.escapedPreview(context.scope.rawValue))",
            "target: \(SocketPrivilegedCommandSecurity.escapedPreview(context.targetDisplayName))",
            "directory: \(SocketPrivilegedCommandSecurity.escapedPreview(context.workingDirectory))",
        ]
        if let profileID = context.browserProfileID {
            lines.append("browser-profile: \(profileID.uuidString)")
        }
        for key in context.localResourcePaths.keys.sorted() {
            let value = context.localResourcePaths[key] ?? ""
            lines.append(
                "\(SocketPrivilegedCommandSecurity.escapedPreview(key)): "
                    + SocketPrivilegedCommandSecurity.escapedPreview(value)
            )
        }
        for key in context.localResourceDigests.keys.sorted() {
            let value = context.localResourceDigests[key] ?? ""
            lines.append(
                "\(SocketPrivilegedCommandSecurity.escapedPreview(key))-sha256: "
                    + SocketPrivilegedCommandSecurity.escapedPreview(value)
            )
        }
        for key in context.authorityDetails.keys.sorted() {
            let value = context.authorityDetails[key] ?? ""
            lines.append(
                "authority.\(SocketPrivilegedCommandSecurity.escapedPreview(key)): "
                    + SocketPrivilegedCommandSecurity.escapedPreview(value)
            )
        }
        return lines.joined(separator: "\n")
    }

    static func localizedPrivilegedSocketCommandApprovalCopy(
        request: SocketPrivilegedCommandAuthorizationRequest,
        context: SocketPrivilegedCommandContext,
        localizer: AppLocalizer
    ) -> SocketPrivilegedCommandApprovalCopy {
        let messageTemplate = localizer.string(
            "socket.privilegedApproval.message",
            fallback: "Command: %@\nTarget: %@\nDirectory: %@\nFingerprint: %@\n\nA local CLI request wants to use the exact Cocxy authority shown below. Approve it only if you initiated this request. Approval is valid for this action once."
        )
        return SocketPrivilegedCommandApprovalCopy(
            title: localizer.string(
                "socket.privilegedApproval.title",
                fallback: "Approve Local CLI Action?"
            ),
            message: String(
                format: messageTemplate,
                locale: localizer.locale,
                SocketPrivilegedCommandSecurity.escapedPreview(request.command.rawValue),
                SocketPrivilegedCommandSecurity.escapedPreview(context.targetDisplayName),
                SocketPrivilegedCommandSecurity.escapedPreview(context.workingDirectory),
                String(request.authorizationDigest.prefix(12))
            ),
            approveButton: localizer.string(
                "socket.privilegedApproval.approveOnce",
                fallback: "Approve Once"
            ),
            cancelButton: localizer.string(
                "socket.privilegedApproval.cancel",
                fallback: "Cancel"
            ),
            previewAccessibilityLabel: localizer.string(
                "socket.privilegedApproval.preview.accessibility",
                fallback: "Exact local CLI action for approval"
            )
        )
    }

    @MainActor
    static func privilegedSocketCommandPreview(
        _ source: String,
        accessibilityLabel: String
    ) -> NSView {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 220)
        let scrollView = NSScrollView(frame: frame)
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: frame.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = source
        textView.setAccessibilityLabel(accessibilityLabel)
        scrollView.documentView = textView
        return scrollView
    }
}
