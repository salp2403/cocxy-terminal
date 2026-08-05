// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator.swift - App-scoped local mobile mirror ownership.

import AppKit
import Combine
import Foundation

typealias MobileMirrorProjectCreationConfirmation = @MainActor (
    String,
    MobileMirrorClientIdentity
) async -> Bool

@MainActor
final class MobileMirrorCoordinator: ObservableObject {
    @Published var state: MobileMirrorServiceState = .stopped
    @Published var pairingURL: URL?
    @Published var pendingPairing: MobileMirrorPendingPairing?
    @Published var activePairing: MobileMirrorActivePairing?
    @Published var projectCreationRoot: URL?
    @Published var snapshot: MobileMirrorSnapshot = .empty
    @Published private(set) var tunnelTargets: [MobileMirrorTunnelTarget] = []
    @Published var selectedTunnelTargetID: UUID?
    @Published var usesSSHTunnel = false

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
    let backgroundActionQueue = MobileMirrorBackgroundActionQueue()
    let staticAssetServer = MobileMirrorStaticAssetServer()
    let projectService: any MobileMirrorProjectCreating
    let projectCreationConfirmation: MobileMirrorProjectCreationConfirmation
    let relayManager: RelayManagerImpl
    let tunnelController: MobileMirrorSSHTunnelController
    var projectRecordsSnapshot: [ProjectRecord]
    var sessionEntriesSnapshot: [SessionEntry]
    var gateway: MobileMirrorGateway?
    var router: MobileMirrorRequestRouter?
    var tunnelLease: MobileMirrorTunnelLease?
    var localRelayLease: MobileMirrorLocalRelayLease?
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
    var projectCreationIsQueued = false

    init(
        appDelegate: AppDelegate,
        projectRegistry: ProjectRegistry,
        projectResolver: CachedProjectResolver,
        titleStore: AuroraWorkspaceTitleStore,
        sessionRegistry: SessionRegistryImpl,
        approvalRegistry: MobileMirrorApprovalRegistry,
        auditLog: RelayAuditLog,
        relayManager: RelayManagerImpl,
        tunnelController: MobileMirrorSSHTunnelController,
        authority: MobileMirrorPairingAuthority = MobileMirrorPairingAuthority(),
        projectService: any MobileMirrorProjectCreating = MobileMirrorProjectService(),
        projectCreationConfirmation: MobileMirrorProjectCreationConfirmation? = nil
    ) {
        self.appDelegate = appDelegate
        self.projectRegistry = projectRegistry
        self.projectResolver = projectResolver
        self.titleStore = titleStore
        self.sessionRegistry = sessionRegistry
        self.approvalRegistry = approvalRegistry
        self.auditLog = auditLog
        self.relayManager = relayManager
        self.tunnelController = tunnelController
        self.authority = authority
        self.projectService = projectService
        self.projectCreationConfirmation = projectCreationConfirmation ?? { [weak appDelegate] name, identity in
            await MobileMirrorProjectConfirmationPresenter.confirm(
                named: name,
                identity: identity,
                appDelegate: appDelegate
            )
        }
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
        let target: MobileMirrorTunnelTarget?
        if usesSSHTunnel {
            guard let targetID = selectedTunnelTargetID,
                  let selected = tunnelTargets.first(where: { $0.id == targetID }) else {
                state = .unavailable(
                    MobileMirrorTunnelError.noConnectedTarget.localizedDescription
                )
                return
            }
            target = selected
        } else {
            target = nil
        }
        transportGeneration &+= 1
        let generation = transportGeneration
        let pendingClosure = tunnelClosureTask
        state = .starting
        pairingTask = Task { [weak self] in
            await priorPairing?.value
            await pendingClosure?.value
            guard !Task.isCancelled, let self else { return }
            guard self.tunnelLease == nil,
                  self.tunnelController.unresolvedLease == nil else {
                self.state = .failed(
                    MobileMirrorTunnelError.closureUnconfirmed.localizedDescription
                )
                return
            }
            if let target {
                await self.openPairingTransport(target: target, generation: generation)
            } else {
                await self.openLocalPairingTransport(generation: generation)
            }
        }
    }

    private func openPairingTransport(
        target: MobileMirrorTunnelTarget,
        generation: UInt64
    ) async {
        let publicAddress = "127.0.0.1"
        let staticAssetEndpoint: MobileMirrorStaticAssetEndpoint
        do {
            staticAssetEndpoint = try staticAssetServer.start()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        let router = makePairingRouter(
            publicAddress: publicAddress,
            transport: .sshTunnel,
            staticAssetEndpoint: staticAssetEndpoint
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
            tunnelLease = lease
            guard !Task.isCancelled, generation == transportGeneration else {
                gateway.stop()
                staticAssetServer.stop()
                await closeUnpublishedTunnelLease(lease)
                return
            }
            router.updatePublicPort(lease.remotePort)
            let offer = authority.makeOffer()
            guard let url = MobileMirrorPairingURL.sshTunnel(
                address: publicAddress,
                port: lease.remotePort,
                token: offer.token,
                pairingSecret: offer.pairingSecret
            ) else {
                gateway.stop()
                await closeUnpublishedTunnelLease(lease)
                throw MobileMirrorError.unavailable
            }
            do {
                try publishPairingOffer(
                    router: router,
                    gateway: gateway,
                    url: url,
                    offer: offer
                )
            } catch {
                gateway.stop()
                _ = authority.revoke()
                await closeUnpublishedTunnelLease(lease)
                throw error
            }
        } catch {
            gateway.stop()
            staticAssetServer.stop()
            guard generation == transportGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }

    private func openLocalPairingTransport(generation: UInt64) async {
        guard let publicAddress = relayManager.privateMobileMirrorAddress() else {
            state = .unavailable(MobileMirrorLocalRelayError.noPrivateNetwork.localizedDescription(
                using: mobileMirrorLocalizer
            ))
            return
        }
        let staticAssetEndpoint: MobileMirrorStaticAssetEndpoint
        do {
            staticAssetEndpoint = try staticAssetServer.start()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        let preambleSecret = MobileMirrorPairingAuthority.base64URL(
            RelayToken.generate().secret
        )
        let router = makePairingRouter(
            publicAddress: publicAddress,
            transport: .localTLS,
            staticAssetEndpoint: staticAssetEndpoint
        )
        let gateway = MobileMirrorGateway(
            trustedRelaySecret: preambleSecret
        ) { [weak router] request, identity in
            guard let router else {
                return .response(.error("Mobile mirror is unavailable.", status: 503))
            }
            return await router.route(request: request, identity: identity)
        }
        var openedLease: MobileMirrorLocalRelayLease?
        do {
            let gatewayPort = try gateway.start()
            let lease = try await relayManager.openMobileMirrorRelay(
                gatewayPort: gatewayPort,
                preambleSecret: preambleSecret,
                bindAddress: publicAddress
            )
            openedLease = lease
            localRelayLease = lease
            guard !Task.isCancelled, generation == transportGeneration else {
                gateway.stop()
                staticAssetServer.stop()
                relayManager.closeMobileMirrorRelay(leaseID: lease.id)
                localRelayLease = nil
                return
            }
            router.updatePublicPort(lease.port)
            let offer = authority.makeOffer()
            guard let url = MobileMirrorPairingURL.local(
                address: lease.address,
                port: lease.port,
                token: offer.token,
                pairingSecret: offer.pairingSecret
            ) else {
                throw MobileMirrorError.unavailable
            }
            try publishPairingOffer(
                router: router,
                gateway: gateway,
                url: url,
                offer: offer
            )
        } catch {
            gateway.stop()
            staticAssetServer.stop()
            if let openedLease {
                relayManager.closeMobileMirrorRelay(leaseID: openedLease.id)
                if localRelayLease == openedLease { localRelayLease = nil }
            }
            _ = authority.revoke()
            guard generation == transportGeneration else { return }
            state = .failed(localizedLocalRelayError(error))
        }
    }

    private var mobileMirrorLocalizer: AppLocalizer {
        appDelegate?.appLocalizer() ?? AppLocalizer(languagePreference: .system)
    }

    private func localizedLocalRelayError(_ error: any Error) -> String {
        guard let relayError = error as? MobileMirrorLocalRelayError else {
            return error.localizedDescription
        }
        return relayError.localizedDescription(using: mobileMirrorLocalizer)
    }

    private func makePairingRouter(
        publicAddress: String,
        transport: MobileMirrorRouterTransport,
        staticAssetEndpoint: MobileMirrorStaticAssetEndpoint
    ) -> MobileMirrorRequestRouter {
        let localizer = appDelegate?.appLocalizer()
            ?? AppLocalizer(languagePreference: .system)
        return MobileMirrorRequestRouter(
            publicAddress: publicAddress,
            transport: transport,
            authority: authority,
            routeRegistry: routeRegistry,
            localization: MobileMirrorWebLocalization(localizer: localizer),
            staticAssetEndpoint: staticAssetEndpoint,
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
            rejectionAuditor: { [weak self] reason, channelID, identity in
                guard let self else { throw MobileMirrorError.unavailable }
                try await self.recordRequestRejection(
                    reason,
                    channelID: channelID,
                    identity: identity
                )
            },
            pendingPairingHandler: { [weak self] pending in
                await self?.receivePendingPairing(pending)
            }
        )
    }

    private func publishPairingOffer(
        router: MobileMirrorRequestRouter,
        gateway: MobileMirrorGateway,
        url: URL,
        offer: MobileMirrorPairingOffer
    ) throws {
        try auditLog.log(.channelOpened(channelID: offer.id, name: "Mobile mirror"))
        self.router = router
        self.gateway = gateway
        pairingURL = url
        pendingPairing = nil
        activePairing = nil
        pairingChannelID = offer.id
        state = .offering
        scheduleOfferExpiry(offer)
    }

    private func closeUnpublishedTunnelLease(_ lease: MobileMirrorTunnelLease) async {
        do {
            try await tunnelController.close(lease)
            if tunnelLease == lease { tunnelLease = nil }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func approvePendingPairing() {
        guard let pendingPairing else { return }
        do {
            guard let active = try authority.decide(pendingID: pendingPairing.id, approve: true) else {
                throw MobileMirrorError.pairingDenied
            }
            try auditLog.log(.connectionAccepted(
                channelID: active.channelID,
                remoteHost: active.identity.remoteAddress
            ))
            self.pendingPairing = nil
            activePairing = active
            state = .active
            refreshSnapshotAndPublish()
            receiveApprovalRecords(approvalRegistry.currentRecords())
            startRefreshTimer()
            scheduleSessionExpiry(active)
        } catch {
            _ = authority.revoke()
            stopTransport(revoke: false)
            state = .failed(error.localizedDescription)
        }
    }

    func denyPendingPairing() {
        guard let pendingPairing else { return }
        do {
            _ = try authority.decide(pendingID: pendingPairing.id, approve: false)
            try auditLog.log(.connectionRejected(
                channelID: pendingPairing.channelID,
                remoteHost: pendingPairing.identity.remoteAddress,
                reason: "Desktop confirmation denied"
            ))
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
            stopTransport(revoke: true)
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
        guard let controller = appDelegate?.focusedWindowController() else { return }
        controller.showRemoteWorkspacePanel()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

}
