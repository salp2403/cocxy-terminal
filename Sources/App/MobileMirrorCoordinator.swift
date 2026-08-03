// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator.swift - App-scoped local mobile mirror ownership.

import AppKit
import Combine
import Foundation

enum MobileMirrorServiceState: Equatable {
    case stopped
    case starting
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

    @Published var state: MobileMirrorServiceState = .stopped
    @Published var pairingURL: URL?
    @Published var pendingPairing: MobileMirrorPendingPairing?
    @Published var activePairing: MobileMirrorActivePairing?
    @Published var projectCreationRoot: URL?
    @Published var snapshot: MobileMirrorSnapshot = .empty
    @Published private(set) var tunnelTargets: [MobileMirrorTunnelTarget] = []
    @Published var selectedTunnelTargetID: UUID?

    weak var appDelegate: AppDelegate?
    let projectRegistry: ProjectRegistry
    let projectResolver: CachedProjectResolver
    let titleStore: AuroraWorkspaceTitleStore
    let sessionRegistry: SessionRegistryImpl
    let approvalRegistry: MobileMirrorApprovalRegistry
    let auditLog: RelayAuditLog
    let authority: MobileMirrorPairingAuthority
    let routeRegistry = MobileMirrorRouteRegistry()
    let terminalPasteDeliveryCoordinator = TerminalPasteDeliveryCoordinator()
    let projectService: any MobileMirrorProjectCreating
    let tunnelController: MobileMirrorSSHTunnelController
    var projectRecordsSnapshot: [ProjectRecord]
    var sessionEntriesSnapshot: [SessionEntry]
    var gateway: MobileMirrorGateway?
    var router: MobileMirrorRequestRouter?
    var tunnelLease: MobileMirrorTunnelLease?
    var pairingChannelID: UUID?
    var ownedStreams: [SurfaceID: OwnedStream] = [:]
    var cancellables = Set<AnyCancellable>()
    var refreshTimer: Timer?
    var expiryTask: Task<Void, Never>?
    var pairingTask: Task<Void, Never>?
    var tunnelClosureTask: Task<Void, Never>?
    var transportGeneration: UInt64 = 0
    var announcedApprovalIDs: Set<String> = []
    var projectCreationRootHandle: ProjectDirectoryRoot?

    init(
        appDelegate: AppDelegate,
        projectRegistry: ProjectRegistry,
        projectResolver: CachedProjectResolver,
        titleStore: AuroraWorkspaceTitleStore,
        sessionRegistry: SessionRegistryImpl,
        approvalRegistry: MobileMirrorApprovalRegistry,
        auditLog: RelayAuditLog,
        tunnelController: MobileMirrorSSHTunnelController,
        authority: MobileMirrorPairingAuthority = MobileMirrorPairingAuthority(),
        projectService: any MobileMirrorProjectCreating = MobileMirrorProjectService()
    ) {
        self.appDelegate = appDelegate
        self.projectRegistry = projectRegistry
        self.projectResolver = projectResolver
        self.titleStore = titleStore
        self.sessionRegistry = sessionRegistry
        self.approvalRegistry = approvalRegistry
        self.auditLog = auditLog
        self.tunnelController = tunnelController
        self.authority = authority
        self.projectService = projectService
        projectRecordsSnapshot = projectRegistry.records
        sessionEntriesSnapshot = sessionRegistry.allSessions
        subscribeToAppState()
        subscribeToTunnelTargets()
    }

    func startPairing() {
        let priorPairing = pairingTask
        priorPairing?.cancel()
        pairingTask = nil
        stopTransport(revoke: true)
        guard let targetID = selectedTunnelTargetID,
              let target = tunnelTargets.first(where: { $0.id == targetID }) else {
            state = .unavailable(MobileMirrorTunnelError.noConnectedTarget.localizedDescription)
            return
        }
        transportGeneration &+= 1
        let generation = transportGeneration
        let pendingClosure = tunnelClosureTask
        state = .starting
        pairingTask = Task { [weak self] in
            await priorPairing?.value
            await pendingClosure?.value
            guard !Task.isCancelled else { return }
            await self?.openPairingTransport(
                target: target,
                generation: generation
            )
        }
    }

    private func openPairingTransport(
        target: MobileMirrorTunnelTarget,
        generation: UInt64
    ) async {
        let publicAddress = "127.0.0.1"
        let router = MobileMirrorRequestRouter(
            publicAddress: publicAddress,
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
        let gateway = MobileMirrorGateway(
            clientIdentityLabel: "SSH \(target.destination)"
        ) { [weak router] request, identity in
            guard let router else {
                return .response(.error("Mobile mirror is unavailable.", status: 503))
            }
            return await router.route(request: request, identity: identity)
        }

        do {
            let localPort = try gateway.start()
            let lease = try await tunnelController.open(
                profileID: target.id,
                localPort: localPort
            )
            guard !Task.isCancelled, generation == transportGeneration else {
                gateway.stop()
                try? await tunnelController.close(lease)
                return
            }
            router.updatePublicPort(lease.remotePort)
            let offer = authority.makeOffer()
            guard let url = URL(
                string: "http://\(publicAddress):\(lease.remotePort)/pair?token=\(offer.token)"
            ) else {
                gateway.stop()
                try? await tunnelController.close(lease)
                throw MobileMirrorError.unavailable
            }
            self.router = router
            self.gateway = gateway
            tunnelLease = lease
            pairingURL = url
            pendingPairing = nil
            activePairing = nil
            pairingChannelID = offer.id
            state = .offering
            auditLog.log(.channelOpened(channelID: offer.id, name: "Mobile mirror"))
            scheduleOfferExpiry(offer)
        } catch {
            gateway.stop()
            guard generation == transportGeneration else { return }
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
            receiveApprovalRecords(approvalRegistry.currentRecords())
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
        pairingTask?.cancel()
        pairingTask = nil
        stopTransport(revoke: true)
        state = .stopped
    }

    func shutdown() {
        pairingTask?.cancel()
        pairingTask = nil
        stopTransport(revoke: true)
        state = .stopped
    }

    func openRemoteWorkspaceSetup() {
        appDelegate?.focusedWindowController()?.showRemoteWorkspacePanel()
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
        approvalRegistry.$records
            .dropFirst()
            .sink { [weak self] records in self?.receiveApprovalRecords(records) }
            .store(in: &cancellables)
    }

    private func subscribeToTunnelTargets() {
        tunnelController.$targets
            .sink { [weak self] targets in
                guard let self else { return }
                tunnelTargets = targets
                if selectedTunnelTargetID.map({ id in targets.contains(where: { $0.id == id }) })
                    != true {
                    selectedTunnelTargetID = targets.first?.id
                }
                if let lease = tunnelLease,
                   !targets.contains(where: { $0.id == lease.profileID }) {
                    stopTransport(revoke: true)
                    state = .unavailable(
                        MobileMirrorTunnelError.noConnectedTarget.localizedDescription
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func receiveSessionUpdate(_ event: SessionChangeEvent) {
        if let updated = sessionRegistry.session(for: event.sessionID) {
            sessionEntriesSnapshot.removeAll { $0.sessionID == event.sessionID }
            sessionEntriesSnapshot.append(updated)
        }
        if case .agentStateChanged(let old, let new) = event.change,
           old != new, new == .waitingInput || new == .finished || new == .error,
           let entry = sessionRegistry.session(for: event.sessionID) {
            publishAgentNotification(entry)
        }
        refreshSnapshotAndPublish()
    }

    private func receiveApprovalRecords(_ records: [MobileMirrorApprovalRecord]) {
        guard activePairing != nil else {
            announcedApprovalIDs.removeAll()
            return
        }
        let currentIDs = Set(records.map(\.id))
        let newRecords = records.filter { !announcedApprovalIDs.contains($0.id) }
        announcedApprovalIDs = currentIDs
        for record in newRecords {
            publishApprovalNotification(record)
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
        let selected = authority.selectedTerminal(cookie: cookie)
        let selectionIsAvailable = selected.map { selection in
            snapshot.agents.contains {
                $0.sessionID == selection.sessionID
                    && $0.surfaceID == selection.surfaceID
                    && $0.terminalAvailable
            }
        } == true
        if !selectionIsAvailable {
            let fallback = snapshot.agents.first(where: \.terminalAvailable)
            _ = authority.selectTerminal(
                sessionID: fallback?.sessionID,
                surfaceID: fallback?.surfaceID,
                cookie: cookie
            )
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
        do {
            guard let active = authority.activePairing(cookie: cookie),
                  active.channelID == channelID,
                  active.identity.fingerprint == identity.fingerprint else {
                throw MobileMirrorError.sessionExpired
            }
            refreshSnapshot()
            var publishesState = true
            switch action.kind {
            case .selectSession:
                let selection = try terminalSelection(for: action)
                guard authority.selectTerminal(
                    sessionID: selection.entry.sessionID.rawValue.uuidString,
                    surfaceID: selection.route.surfaceID.rawValue.uuidString,
                    cookie: cookie
                ) else {
                    throw MobileMirrorError.targetUnavailable
                }
            case .terminalControl:
                let selection = try terminalSelection(for: action)
                if action.controlType == "viewport-scroll" {
                    guard let scrollDelta = action.scrollDelta else {
                        throw MobileMirrorError.invalidAction
                    }
                    try scrollTerminal(
                        selection.entry,
                        route: selection.route,
                        deltaRows: scrollDelta
                    )
                } else {
                    guard let writer = makeTerminalWriter(channelID: active.channelID) else {
                        throw MobileMirrorError.targetUnavailable
                    }
                    try await writer.write(
                        action: action,
                        to: selection.entry.tabID,
                        surfaceID: selection.route.surfaceID
                    )
                }
                publishesState = false
            case .agentRespond:
                let selection = try terminalSelection(for: action)
                let surfaceState = selection.controller.injectedPerSurfaceStore?
                    .state(for: selection.route.surfaceID)
                guard (surfaceState?.agentState ?? selection.entry.agentState) == .waitingInput,
                      let text = action.text,
                      let writer = makeTerminalWriter(channelID: active.channelID) else {
                    throw MobileMirrorError.targetUnavailable
                }
                try await writer.respond(
                    text,
                    to: selection.entry.tabID,
                    surfaceID: selection.route.surfaceID
                )
            case .approvalApprove, .approvalReject:
                try await handleApproval(action)
            case .projectCreate:
                guard let name = action.name else { throw MobileMirrorError.invalidAction }
                try await createProject(named: name, identity: identity)
            }
            if publishesState {
                refreshSnapshotAndPublish()
            }
            auditLog.log(MobileMirrorActionAudit.event(
                action: action,
                channelID: channelID,
                identity: identity,
                accepted: true
            ))
            return snapshot
        } catch {
            auditLog.log(MobileMirrorActionAudit.event(
                action: action,
                channelID: channelID,
                identity: identity,
                accepted: false
            ))
            throw error
        }
    }

    private struct TerminalSelection {
        let entry: SessionEntry
        let route: MobileMirrorTerminalRoute
        let controller: MainWindowController
    }

    private func terminalSelection(for action: MobileMirrorAction) throws -> TerminalSelection {
        guard let rawSessionID = action.sessionID,
              let rawSurfaceID = action.surfaceID,
              let surfaceUUID = UUID(uuidString: rawSurfaceID),
              let entry = sessionEntriesSnapshot.first(where: {
                  $0.sessionID.rawValue.uuidString == rawSessionID
              }), sessionRegistry.session(for: entry.sessionID) == entry,
              let controller = appDelegate?.allWindowControllers.first(where: {
                  $0.windowID == entry.ownerWindowID
              }), controller.tabManager.tab(for: entry.tabID) != nil,
              controller.tabID(for: SurfaceID(rawValue: surfaceUUID)) == entry.tabID,
              let route = routeRegistry.route(
                  sessionID: rawSessionID,
                  surfaceID: rawSurfaceID
              ), route.surfaceID.rawValue == surfaceUUID else {
            throw MobileMirrorError.targetUnavailable
        }
        return TerminalSelection(entry: entry, route: route, controller: controller)
    }

    private func scrollTerminal(
        _ entry: SessionEntry,
        route: MobileMirrorTerminalRoute,
        deltaRows: Int
    ) throws {
        guard let controller = appDelegate?.allWindowControllers.first(where: {
            $0.windowID == entry.ownerWindowID
        }), controller.tabManager.tab(for: entry.tabID) != nil,
              controller.surfaceIDs(for: entry.tabID).contains(route.surfaceID),
              let bridge = controller.cocxyCoreBridge(forSurface: route.surfaceID) else {
            throw MobileMirrorError.targetUnavailable
        }
        bridge.scrollViewport(surfaceID: route.surfaceID, deltaRows: deltaRows)
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
                guard let rawTabID = context.tabID,
                      let rawSurfaceID = context.surfaceID,
                      let target = appDelegate?.privilegedSocketTerminalTarget(for: context),
                      target.surfaceID.rawValue == rawSurfaceID,
                      target.controller.tabID(for: target.surfaceID) == TabID(rawValue: rawTabID) else {
                    return nil
                }
                let engine = target.controller.terminalEngine(for: target.surfaceID)
                let surfaceID = target.surfaceID
                return MobileMirrorTerminalTarget(
                    sendText: { engine.sendText($0, to: surfaceID) },
                    sendKeyEvent: { event in
                        if let bridge = engine as? CocxyCoreBridge {
                            return bridge.sendKeyEventConfirmingDelivery(
                                event,
                                to: surfaceID
                            )
                        }
                        return engine.sendKeyEvent(event, to: surfaceID)
                    },
                    pasteConfiguration: {
                        let agentPaced = target.controller.surfaceLooksLikeActiveAgent(surfaceID)
                        guard let bridge = engine as? CocxyCoreBridge,
                              let diagnostics = bridge.modeDiagnostics(for: surfaceID) else {
                            return TerminalPasteDeliveryConfiguration(
                                usesBracketedPaste: false,
                                agentPaced: true
                            )
                        }
                        return TerminalPasteDeliveryConfiguration(
                            usesBracketedPaste: diagnostics.bracketedPasteMode,
                            agentPaced: agentPaced
                                || diagnostics.altScreen
                                || diagnostics.mouseTrackingMode > 0
                        )
                    },
                    isAvailable: {
                        target.controller.tabID(for: surfaceID) == TabID(rawValue: rawTabID)
                            && ((engine as? CocxyCoreBridge)?.surfaceState(for: surfaceID) != nil
                                || !(engine is CocxyCoreBridge))
                    }
                )
            },
            pasteDeliveryCoordinator: terminalPasteDeliveryCoordinator
        )
    }

}
