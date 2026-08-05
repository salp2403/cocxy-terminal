// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Actions.swift - Signed mobile action dispatch.

import Foundation

extension MobileMirrorCoordinator {
    func handle(
        action: MobileMirrorAction,
        cookie: String,
        channelID: UUID,
        identity: MobileMirrorClientIdentity
    ) async throws -> MobileMirrorSnapshot {
        var rollbackQueuedAction: (@MainActor () -> Void)?
        do {
            guard let active = authority.activePairing(cookie: cookie),
                  active.channelID == channelID,
                  active.identity.fingerprint == identity.fingerprint else {
                throw MobileMirrorError.sessionExpired
            }
            refreshSnapshot()
            var publishesState = true
            var auditOutcome = MobileMirrorActionAudit.Outcome.accepted
            var startQueuedAction: (@MainActor () -> Void)?
            switch action.kind {
            case .selectSession:
                let selection = try terminalSelection(for: action, requiresRoute: false)
                guard authority.selectTerminal(
                    sessionID: selection.entry.sessionID.rawValue.uuidString,
                    surfaceID: selection.surfaceID.rawValue.uuidString,
                    cookie: cookie
                ) else {
                    throw MobileMirrorError.targetUnavailable
                }
            case .terminalControl:
                let selection = try terminalSelection(for: action)
                guard let route = selection.route else {
                    throw MobileMirrorError.targetUnavailable
                }
                if action.controlType == "viewport-scroll" {
                    guard let scrollDelta = action.scrollDelta else {
                        throw MobileMirrorError.invalidAction
                    }
                    try scrollTerminal(
                        selection.entry,
                        route: route,
                        deltaRows: scrollDelta
                    )
                } else {
                    guard let writer = makeTerminalWriter(channelID: active.channelID) else {
                        throw MobileMirrorError.targetUnavailable
                    }
                    if action.controlType == "paste" {
                        let prepared = try await writer.prepare(
                            action: action,
                            tabID: selection.entry.tabID,
                            surfaceID: route.surfaceID
                        )
                        auditOutcome = .queued
                        startQueuedAction = { [self] in
                            startBackgroundAction(
                                action,
                                channelID: channelID,
                                identity: identity,
                                notificationSessionID: selection.entry.sessionID.rawValue.uuidString
                            ) {
                                let result = try await prepared.execute()
                                return result == .partial ? .partial : .accepted
                            }
                        }
                    } else {
                        try await writer.write(
                            action: action,
                            to: selection.entry.tabID,
                            surfaceID: route.surfaceID
                        )
                    }
                }
                publishesState = false
            case .agentRespond:
                let selection = try terminalSelection(for: action)
                guard let route = selection.route else {
                    throw MobileMirrorError.targetUnavailable
                }
                let surfaceState = selection.controller.injectedPerSurfaceStore?
                    .state(for: route.surfaceID)
                guard (surfaceState?.agentState ?? selection.entry.agentState) == .waitingInput,
                      let text = action.text,
                      let writer = makeTerminalWriter(channelID: active.channelID) else {
                    throw MobileMirrorError.targetUnavailable
                }
                try await writer.respond(
                    text,
                    to: selection.entry.tabID,
                    surfaceID: route.surfaceID
                )
            case .approvalApprove, .approvalReject:
                let claim = try claimApproval(action)
                auditOutcome = .queued
                rollbackQueuedAction = { claim.cancel() }
                startQueuedAction = { [self] in
                    startBackgroundAction(
                        action,
                        channelID: channelID,
                        identity: identity,
                        notificationSessionID: claim.record.sessionID
                    ) {
                        guard await claim.execute() else {
                            throw MobileMirrorError.targetUnavailable
                        }
                        return .accepted
                    }
                }
            case .projectCreate:
                guard let name = action.name else { throw MobileMirrorError.invalidAction }
                guard !projectCreationIsQueued else {
                    throw MobileMirrorError.targetUnavailable
                }
                let projectCreation = try prepareProjectCreation(
                    named: name,
                    identity: identity,
                    cookie: cookie,
                    channelID: channelID
                )
                projectCreationIsQueued = true
                auditOutcome = .queued
                rollbackQueuedAction = { [weak self] in
                    self?.projectCreationIsQueued = false
                }
                startQueuedAction = { [self] in
                    startBackgroundAction(
                        action,
                        channelID: channelID,
                        identity: identity,
                        notificationSessionID: channelID.uuidString
                    ) { [self] in
                        defer { projectCreationIsQueued = false }
                        try await projectCreation()
                        return .accepted
                    }
                }
            }
            try auditLog.log(MobileMirrorActionAudit.event(
                action: action,
                channelID: channelID,
                identity: identity,
                outcome: auditOutcome
            ))
            if publishesState {
                refreshSnapshotAndPublish()
            }
            startQueuedAction?()
            rollbackQueuedAction = nil
        } catch {
            rollbackQueuedAction?()
            do {
                try auditLog.log(MobileMirrorActionAudit.event(
                    action: action,
                    channelID: channelID,
                    identity: identity,
                    accepted: false
                ))
            } catch let auditError {
                throw auditError
            }
            throw error
        }
        return snapshot
    }

    func recordRequestRejection(
        _ reason: MobileMirrorActionAudit.RejectionReason,
        channelID: UUID,
        identity: MobileMirrorClientIdentity
    ) throws {
        try auditLog.log(MobileMirrorActionAudit.rejectionEvent(
            reason: reason,
            channelID: channelID,
            identity: identity
        ))
    }

    private struct TerminalSelection {
        let entry: SessionEntry
        let surfaceID: SurfaceID
        let route: MobileMirrorTerminalRoute?
        let controller: MainWindowController
    }

    private func terminalSelection(
        for action: MobileMirrorAction,
        requiresRoute: Bool = true
    ) throws -> TerminalSelection {
        guard let rawSessionID = action.sessionID,
              let rawSurfaceID = action.surfaceID,
              let surfaceUUID = UUID(uuidString: rawSurfaceID),
              let entry = sessionEntriesSnapshot.first(where: {
                  $0.sessionID.rawValue.uuidString == rawSessionID
              }), sessionRegistry.session(for: entry.sessionID) == entry,
              let controller = appDelegate?.allWindowControllers.first(where: {
                  $0.windowID == entry.ownerWindowID
              }), controller.tabManager.tab(for: entry.tabID) != nil,
              controller.tabID(for: SurfaceID(rawValue: surfaceUUID)) == entry.tabID else {
            throw MobileMirrorError.targetUnavailable
        }
        let route = routeRegistry.route(
            sessionID: rawSessionID,
            surfaceID: rawSurfaceID
        )
        guard !requiresRoute || route?.surfaceID.rawValue == surfaceUUID else {
            throw MobileMirrorError.targetUnavailable
        }
        return TerminalSelection(
            entry: entry,
            surfaceID: SurfaceID(rawValue: surfaceUUID),
            route: route,
            controller: controller
        )
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
                      target.controller.tabID(for: target.surfaceID)
                        == TabID(rawValue: rawTabID) else {
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
