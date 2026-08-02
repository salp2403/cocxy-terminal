// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator.swift - App-scoped local mobile mirror ownership.

import AppKit
import Combine
import Foundation

enum MobileMirrorServiceState: Equatable {
    case stopped
    case offering
    case awaitingConfirmation
    case active
    case denied
    case unavailable(String)
    case failed(String)
}

@MainActor
final class MobileMirrorCoordinator: ObservableObject {
    struct OwnedStream {
        let bridge: CocxyCoreBridge
        let surfaceID: SurfaceID
        let port: UInt16
        let token: String
    }

    struct ApprovalTarget {
        let sessionID: SessionID
        let requestID: String
        let viewModel: AgentPanelViewModel
    }

    @Published var state: MobileMirrorServiceState = .stopped
    @Published var pairingURL: URL?
    @Published var pendingPairing: MobileMirrorPendingPairing?
    @Published var activePairing: MobileMirrorActivePairing?
    @Published var projectCreationRoot: URL?
    @Published var snapshot: MobileMirrorSnapshot = .empty

    weak var appDelegate: AppDelegate?
    let projectRegistry: ProjectRegistry
    let projectResolver: CachedProjectResolver
    let titleStore: AuroraWorkspaceTitleStore
    let sessionRegistry: SessionRegistryImpl
    let auditLog: RelayAuditLog
    let authority: MobileMirrorPairingAuthority
    let routeRegistry = MobileMirrorRouteRegistry()
    let projectService: any MobileMirrorProjectCreating
    let addressProvider: @Sendable () -> [String]
    var projectRecordsSnapshot: [ProjectRecord]
    var sessionEntriesSnapshot: [SessionEntry]
    var gateway: MobileMirrorGateway?
    var router: MobileMirrorRequestRouter?
    var pairingChannelID: UUID?
    var ownedStreams: [String: OwnedStream] = [:]
    var approvalTargets: [String: ApprovalTarget] = [:]
    var cancellables = Set<AnyCancellable>()
    var refreshTimer: Timer?
    var expiryTask: Task<Void, Never>?

    init(
        appDelegate: AppDelegate,
        projectRegistry: ProjectRegistry,
        projectResolver: CachedProjectResolver,
        titleStore: AuroraWorkspaceTitleStore,
        sessionRegistry: SessionRegistryImpl,
        auditLog: RelayAuditLog,
        authority: MobileMirrorPairingAuthority = MobileMirrorPairingAuthority(),
        projectService: any MobileMirrorProjectCreating = MobileMirrorProjectService(),
        addressProvider: @escaping @Sendable () -> [String] = {
            MobileMirrorGateway.privateIPv4Addresses()
        }
    ) {
        self.appDelegate = appDelegate
        self.projectRegistry = projectRegistry
        self.projectResolver = projectResolver
        self.titleStore = titleStore
        self.sessionRegistry = sessionRegistry
        self.auditLog = auditLog
        self.authority = authority
        self.projectService = projectService
        self.addressProvider = addressProvider
        projectRecordsSnapshot = projectRegistry.records
        sessionEntriesSnapshot = sessionRegistry.allSessions
        subscribeToAppState()
    }

    func startPairing() {
        stopTransport(revoke: true)
        guard let bindAddress = addressProvider().first else {
            state = .unavailable(MobileMirrorError.noPrivateNetwork.localizedDescription)
            return
        }

        let router = MobileMirrorRequestRouter(
            bindAddress: bindAddress,
            authority: authority,
            routeRegistry: routeRegistry,
            snapshotProvider: { [weak self] cookie in
                guard let self else { throw MobileMirrorError.unavailable }
                return try await self.snapshot(for: cookie)
            },
            actionHandler: { [weak self] action, cookie, channelID, identity in
                guard let self else { throw MobileMirrorError.unavailable }
                return try await self.handle(
                    action: action,
                    cookie: cookie,
                    channelID: channelID,
                    identity: identity
                )
            },
            pendingPairingHandler: { [weak self] pending in
                await self?.receivePendingPairing(pending)
            }
        )
        let gateway = MobileMirrorGateway(bindAddress: bindAddress) { [weak router] request, identity in
            guard let router else {
                return .response(.error("Mobile mirror is unavailable.", status: 503))
            }
            return await router.route(request: request, identity: identity)
        }

        do {
            let port = try gateway.start()
            router.updateGatewayPort(port)
            let offer = authority.makeOffer()
            guard let url = URL(string: "http://\(bindAddress):\(port)/pair?token=\(offer.token)") else {
                gateway.stop()
                throw MobileMirrorError.unavailable
            }
            self.router = router
            self.gateway = gateway
            pairingURL = url
            pendingPairing = nil
            activePairing = nil
            pairingChannelID = offer.id
            state = .offering
            auditLog.log(.channelOpened(channelID: offer.id, name: "Mobile mirror"))
            scheduleOfferExpiry(offer)
        } catch {
            gateway.stop()
            state = .failed(error.localizedDescription)
        }
    }

    func approvePendingPairing() {
        guard let pendingPairing else { return }
        do {
            guard let active = try authority.decide(pendingID: pendingPairing.id, approve: true) else {
                throw MobileMirrorError.pairingDenied
            }
            self.pendingPairing = nil
            activePairing = active
            state = .active
            auditLog.log(.connectionAccepted(
                channelID: active.channelID,
                remoteHost: active.identity.remoteAddress
            ))
            refreshSnapshotAndPublish()
            startRefreshTimer()
            scheduleSessionExpiry(active)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func denyPendingPairing() {
        guard let pendingPairing else { return }
        do {
            _ = try authority.decide(pendingID: pendingPairing.id, approve: false)
            auditLog.log(.connectionRejected(
                channelID: pendingPairing.channelID,
                remoteHost: pendingPairing.identity.remoteAddress,
                reason: "Desktop confirmation denied"
            ))
            auditLog.log(.channelClosed(channelID: pendingPairing.channelID))
            pairingChannelID = nil
            self.pendingPairing = nil
            pairingURL = nil
            state = .denied
            expiryTask?.cancel()
            expiryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishDeniedPairing()
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func revoke() {
        stopTransport(revoke: true)
        state = .stopped
    }

    func shutdown() {
        stopTransport(revoke: true)
        state = .stopped
    }

    func chooseProjectCreationRoot() {
        let panel = NSOpenPanel()
        let localizer = appDelegate?.appLocalizer()
            ?? AppLocalizer(languagePreference: .system)
        panel.title = localizer.string(
            "mobile.mirror.projectRoot.title",
            fallback: "Choose Project Creation Folder"
        )
        panel.prompt = localizer.string("common.choose", fallback: "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                let standardized = url.standardizedFileURL
                guard standardized.resolvingSymlinksInPath().standardizedFileURL == standardized else {
                    NSSound.beep()
                    return
                }
                self?.projectCreationRoot = standardized
                self?.refreshSnapshotAndPublish()
            }
        }
    }

    private func subscribeToAppState() {
        projectRegistry.$records
            .sink { [weak self] records in
                self?.projectRecordsSnapshot = records
                self?.refreshSnapshotAndPublish()
            }
            .store(in: &cancellables)
        titleStore.$revision
            .dropFirst()
            .sink { [weak self] _ in self?.refreshSnapshotAndPublish() }
            .store(in: &cancellables)
        sessionRegistry.sessionAdded
            .sink { [weak self] entry in
                guard let self else { return }
                sessionEntriesSnapshot.removeAll { $0.sessionID == entry.sessionID }
                sessionEntriesSnapshot.append(entry)
                refreshSnapshotAndPublish()
            }
            .store(in: &cancellables)
        sessionRegistry.sessionRemoved
            .sink { [weak self] event in
                self?.sessionEntriesSnapshot.removeAll { $0.sessionID == event.sessionID }
                self?.refreshSnapshotAndPublish()
            }
            .store(in: &cancellables)
        sessionRegistry.sessionUpdated
            .sink { [weak self] event in self?.receiveSessionUpdate(event) }
            .store(in: &cancellables)
    }

    private func receiveSessionUpdate(_ event: SessionChangeEvent) {
        if let updated = sessionRegistry.session(for: event.sessionID) {
            sessionEntriesSnapshot.removeAll { $0.sessionID == event.sessionID }
            sessionEntriesSnapshot.append(updated)
        }
        if case .agentStateChanged(let old, let new) = event.change,
           old != new, new == .waitingInput || new == .finished,
           let entry = sessionRegistry.session(for: event.sessionID) {
            publishAgentState(entry)
        }
        refreshSnapshotAndPublish()
    }

    private func receivePendingPairing(_ pending: MobileMirrorPendingPairing) {
        guard state == .offering else { return }
        pendingPairing = pending
        state = .awaitingConfirmation
    }

    private func snapshot(for cookie: String) throws -> MobileMirrorSnapshot {
        _ = try authority.credentials(cookie: cookie)
        refreshSnapshot()
        let availableIDs = Set(snapshot.agents.map(\.sessionID))
        let selected = authority.selectedSessionID(cookie: cookie)
        if selected == nil || !availableIDs.contains(selected ?? "") {
            let fallback = snapshot.agents.first(where: \.terminalAvailable)?.sessionID
                ?? snapshot.agents.first?.sessionID
            _ = authority.selectSession(fallback, cookie: cookie)
            refreshSnapshot()
        }
        return snapshot
    }

    private func handle(
        action: MobileMirrorAction,
        cookie: String,
        channelID: UUID,
        identity: MobileMirrorClientIdentity
    ) async throws -> MobileMirrorSnapshot {
        guard let active = authority.activePairing(cookie: cookie),
              active.channelID == channelID,
              active.identity.fingerprint == identity.fingerprint else {
            throw MobileMirrorError.sessionExpired
        }
        refreshSnapshot()
        var publishesState = true
        switch action.kind {
        case .selectSession:
            guard let sessionID = action.sessionID,
                  sessionEntriesSnapshot.contains(where: {
                      $0.sessionID.rawValue.uuidString == sessionID
                  }), authority.selectSession(sessionID, cookie: cookie) else {
                throw MobileMirrorError.targetUnavailable
            }
        case .terminalControl:
            let entry = try terminalEntry(for: action.sessionID)
            guard routeRegistry.contains(sessionID: entry.sessionID.rawValue.uuidString) else {
                throw MobileMirrorError.targetUnavailable
            }
            if action.controlType == "viewport-scroll" {
                guard let scrollDelta = action.scrollDelta else {
                    throw MobileMirrorError.invalidAction
                }
                try scrollTerminal(entry, deltaRows: scrollDelta)
            } else {
                guard let writer = makeTerminalWriter(channelID: active.channelID) else {
                    throw MobileMirrorError.targetUnavailable
                }
                try await writer.write(action: action, to: entry.tabID)
            }
            publishesState = false
        case .agentRespond:
            let entry = try terminalEntry(for: action.sessionID)
            guard entry.agentState == .waitingInput,
                  routeRegistry.contains(sessionID: entry.sessionID.rawValue.uuidString),
                  let text = action.text,
                  let writer = makeTerminalWriter(channelID: active.channelID) else {
                throw MobileMirrorError.targetUnavailable
            }
            try await writer.respond(text, to: entry.tabID)
        case .approvalApprove, .approvalReject:
            try await handleApproval(action)
        case .projectCreate:
            guard let name = action.name else { throw MobileMirrorError.invalidAction }
            try await createProject(named: name, identity: identity)
        }
        if publishesState {
            refreshSnapshotAndPublish()
        }
        return snapshot
    }

    private func terminalEntry(for rawSessionID: String?) throws -> SessionEntry {
        guard let rawSessionID,
              let entry = sessionEntriesSnapshot.first(where: {
                  $0.sessionID.rawValue.uuidString == rawSessionID
              }), sessionRegistry.session(for: entry.sessionID) == entry else {
            throw MobileMirrorError.targetUnavailable
        }
        return entry
    }

    private func scrollTerminal(_ entry: SessionEntry, deltaRows: Int) throws {
        guard let controller = appDelegate?.allWindowControllers.first(where: {
            $0.windowID == entry.ownerWindowID
        }), controller.tabManager.tab(for: entry.tabID) != nil,
              let surfaceID = preferredSurfaceID(for: entry.tabID, controller: controller),
              let bridge = controller.cocxyCoreBridge(forSurface: surfaceID) else {
            throw MobileMirrorError.targetUnavailable
        }
        bridge.scrollViewport(surfaceID: surfaceID, deltaRows: deltaRows)
    }

    private func makeTerminalWriter(channelID: UUID) -> MobileMirrorTerminalWriter? {
        guard let appDelegate else { return nil }
        return MobileMirrorTerminalWriter(
            grantProvider: { [weak self, weak appDelegate] request in
                guard let self, let appDelegate,
                      let initial = appDelegate.privilegedSocketCommandPresentationTarget(
                          for: request
                      ), let current = appDelegate.privilegedSocketCommandPresentationTarget(
                          for: request
                      ), current.context == initial.context,
                      let rawTabID = initial.context.tabID else {
                    return nil
                }
                return MobileMirrorPrivilegedAuthorization.grant(
                    for: request,
                    channelID: channelID,
                    activePairing: self.authority.activePairing(),
                    tabID: TabID(rawValue: rawTabID),
                    context: current.context
                )
            },
            targetProvider: { [weak appDelegate] context in
                guard let target = appDelegate?.privilegedSocketTerminalTarget(for: context) else {
                    return nil
                }
                let engine = target.controller.terminalEngine(for: target.surfaceID)
                let surfaceID = target.surfaceID
                return MobileMirrorTerminalTarget(
                    sendText: { engine.sendText($0, to: surfaceID) },
                    sendKeyEvent: { engine.sendKeyEvent($0, to: surfaceID) }
                )
            }
        )
    }

    private func handleApproval(_ action: MobileMirrorAction) async throws {
        guard let approvalID = action.approvalID,
              let target = approvalTargets[approvalID],
              let request = target.viewModel.pendingApproval,
              request.id == target.requestID,
              approvalID == approvalDigest(sessionID: target.sessionID, request: request),
              approvalTargetIsCurrent(target) else {
            throw MobileMirrorError.targetUnavailable
        }
        if action.kind == .approvalReject {
            target.viewModel.rejectPendingTool()
            return
        }
        if request.preview.kind == .userInput {
            guard let text = action.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MobileMirrorError.invalidAction
            }
            target.viewModel.pendingApprovalResponseDraft = text
        }
        guard target.viewModel.canApprovePendingTool else {
            throw MobileMirrorError.targetUnavailable
        }
        await target.viewModel.approvePendingTool()
    }

    private func approvalTargetIsCurrent(_ target: ApprovalTarget) -> Bool {
        guard let entry = sessionRegistry.session(for: target.sessionID),
              let controller = appDelegate?.allWindowControllers.first(where: {
                  $0.windowID == entry.ownerWindowID
              }), (controller.visibleTabID ?? controller.tabManager.activeTabID) == entry.tabID,
              controller.agentPanelViewModel === target.viewModel else {
            return false
        }
        return true
    }

    private func createProject(
        named name: String,
        identity: MobileMirrorClientIdentity
    ) async throws {
        guard let root = projectCreationRoot else {
            throw MobileMirrorError.projectCreationUnavailable
        }
        guard await confirmProjectCreation(named: name, identity: identity) else {
            throw MobileMirrorError.authorizationDenied
        }
        let destination = try await projectService.createProject(named: name, in: root)
        projectResolver.invalidate(directory: destination)
        let descriptor = projectResolver.resolveProject(for: destination)
        try projectRegistry.recordOpen(descriptor, incrementOpenCount: false)
        _ = try appDelegate?.activateProject(descriptor.groupingID)
        appDelegate?.windowEventBus?.broadcast(.custom(name: "project.changed", payload: [:]))
    }

    private func confirmProjectCreation(
        named name: String,
        identity: MobileMirrorClientIdentity
    ) async -> Bool {
        guard let appDelegate,
              let window = appDelegate.mobileMirrorWindowController?.window,
              window.attachedSheet == nil else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        let localizer = appDelegate.appLocalizer()
        let alert = NSAlert()
        alert.messageText = localizer.string(
            "mobile.mirror.projectConfirm.title",
            fallback: "Create Project from Phone?"
        )
        alert.informativeText = String(
            format: localizer.string(
                "mobile.mirror.projectConfirm.message",
                fallback: "Create %@ for the paired device at %@?"
            ),
            name,
            identity.remoteAddress
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizer.string("common.create", fallback: "Create"))
        alert.addButton(withTitle: localizer.string("common.cancel", fallback: "Cancel"))
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }

}
