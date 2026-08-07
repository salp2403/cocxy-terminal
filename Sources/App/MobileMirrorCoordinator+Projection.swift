// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Projection.swift - Snapshot and stream projection.

import Foundation

extension MobileMirrorCoordinator {
    func updateLocalization(_ localizer: AppLocalizer) {
        configuredLocalizer = localizer
        router?.updateLocalization(MobileMirrorWebLocalization(localizer: localizer))
        refreshSnapshotAndPublish()
    }

    func refreshSnapshotAndPublish() {
        guard activePairing != nil else { return }
        refreshSnapshot()
        gateway?.eventHub.publish(event: "state", data: "{}")
    }

    func refreshSnapshot() {
        guard activePairing != nil else {
            snapshot = .empty
            return
        }
        synchronizeTerminalStreams()
        let localizer = mobileMirrorLocalizer
        var projectsByID: [String: MobileMirrorProjectSnapshot] = [:]
        for record in projectRecordsSnapshot {
            projectsByID[record.id.storageKey] = projectSnapshot(
                id: record.id,
                isPinned: record.isPinned,
                accent: record.accent
            )
        }

        var agents: [MobileMirrorAgentSnapshot] = []
        for entry in sessionEntriesSnapshot.sorted(by: Self.sortSessions) {
            let sessionID = entry.sessionID.rawValue.uuidString
            guard let controller = appDelegate?.allWindowControllers.first(where: {
                $0.windowID == entry.ownerWindowID
            }), controller.tabManager.tab(for: entry.tabID) != nil else { continue }
            let surfaces = orderedSurfaceIDs(for: entry.tabID, controller: controller)
            for (index, surfaceID) in surfaces.enumerated()
                where controller.tabID(for: surfaceID) == entry.tabID {
                let directory = controller.workingDirectory(for: surfaceID) ?? entry.workingDirectory
                let projectID = projectResolver.resolveProject(for: directory).groupingID
                if projectsByID[projectID.storageKey] == nil {
                    projectsByID[projectID.storageKey] = projectSnapshot(
                        id: projectID,
                        isPinned: false,
                        accent: nil
                    )
                }
                let surfaceIDString = surfaceID.rawValue.uuidString
                let state = controller.injectedPerSurfaceStore?.state(for: surfaceID)
                let agentState = state?.agentState ?? (surfaces.count == 1 ? entry.agentState : .idle)
                let agentName = state?.detectedAgent?.displayName
                    ?? (surfaces.count == 1 ? entry.detectedAgentName : nil)
                let terminalAvailable = routeRegistry.contains(
                    sessionID: sessionID,
                    surfaceID: surfaceIDString
                )
                agents.append(MobileMirrorAgentSnapshot(
                    sessionID: sessionID,
                    surfaceID: surfaceIDString,
                    projectID: projectID.storageKey,
                    title: surfaces.count > 1 ? "\(entry.title) \(index + 1)" : entry.title,
                    name: agentName,
                    state: agentState.rawValue,
                    stateLabel: Self.stateLabel(agentState, using: localizer),
                    canRespond: agentState == .waitingInput && terminalAvailable,
                    terminalAvailable: terminalAvailable
                ))
            }
        }

        let approvals = approvalSnapshots()
        let projects = projectsByID.values.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let selected = authority.selectedTerminal().flatMap { selection in
            agents.contains(where: {
                $0.sessionID == selection.sessionID && $0.surfaceID == selection.surfaceID
            }) ? selection : nil
        }
        snapshot = MobileMirrorSnapshot(
            selectedSessionID: selected?.sessionID,
            selectedSurfaceID: selected?.surfaceID,
            projectCreationEnabled: projectCreationRootHandle != nil && !projectCreationIsQueued,
            projects: projects,
            agents: agents,
            approvals: approvals
        )
    }

    func projectSnapshot(
        id: ProjectID,
        isPinned: Bool,
        accent: String?
    ) -> MobileMirrorProjectSnapshot {
        let url = URL(fileURLWithPath: id.rawValue, isDirectory: true)
        return MobileMirrorProjectSnapshot(
            id: id.storageKey,
            name: titleStore.title(for: id.rawValue)
                ?? ProjectDescriptor.automaticName(for: url),
            isPinned: isPinned,
            accent: accent
        )
    }

    func approvalSnapshots() -> [MobileMirrorApprovalSnapshot] {
        approvalRegistry.currentRecords().map { record in
            MobileMirrorApprovalSnapshot(
                id: record.id,
                sessionID: record.sessionID,
                title: record.title,
                body: record.body,
                requiresResponse: record.requiresResponse
            )
        }
    }

    func synchronizeTerminalStreams() {
        guard let appDelegate else { return }
        var candidates: [(SessionEntry, MainWindowController, SurfaceID)] = []
        for entry in sessionEntriesSnapshot.sorted(by: Self.sortSessions) {
            guard let controller = appDelegate.allWindowControllers.first(where: {
                $0.windowID == entry.ownerWindowID
            }), controller.tabManager.tab(for: entry.tabID) != nil else { continue }
            for surfaceID in orderedSurfaceIDs(for: entry.tabID, controller: controller)
                where controller.tabID(for: surfaceID) == entry.tabID {
                candidates.append((entry, controller, surfaceID))
            }
        }
        let preferredSurfaceID = authority.selectedTerminal()
            .flatMap { UUID(uuidString: $0.surfaceID) }
            .map(SurfaceID.init(rawValue:))
        let desired = preferredSurfaceID.flatMap { preferred in
            candidates.first { $0.2 == preferred }
        } ?? candidates.first
        let desiredSurfaceIDs: Set<SurfaceID> = Set(desired.map { [$0.2] } ?? [])
        for (surfaceID, stream) in Array(ownedStreams)
            where !desiredSurfaceIDs.contains(surfaceID) {
            stopOwnedStream(stream)
            ownedStreams.removeValue(forKey: surfaceID)
        }

        guard let (entry, controller, surfaceID) = desired,
              let bridge = controller.cocxyCoreBridge(forSurface: surfaceID) else {
            routeRegistry.replace(routes: [], preferredSurfaceID: nil)
            return
        }
        let sessionID = entry.sessionID.rawValue.uuidString
        if let stream = ownedStreams[surfaceID] {
            let status = stream.bridge.webTerminalStatus(for: stream.surfaceID)
            if stream.bridge === bridge,
               status?.running == true, status?.port == stream.port,
               status?.allowsInput == false {
                routeRegistry.replace(
                    routes: [MobileMirrorTerminalRoute(
                        sessionID: sessionID,
                        surfaceID: surfaceID,
                        port: stream.port,
                        bearerToken: stream.token
                    )],
                    preferredSurfaceID: surfaceID.rawValue.uuidString
                )
                return
            }
            stopOwnedStream(stream)
            ownedStreams.removeValue(forKey: surfaceID)
        }

        guard bridge.webTerminalStatus(for: surfaceID) == nil else {
            routeRegistry.replace(routes: [], preferredSurfaceID: nil)
            return
        }
        let token = MobileMirrorPairingAuthority.base64URL(RelayToken.generate().secret)
        guard let status = bridge.startWebTerminal(
            for: surfaceID,
            configuration: WebTerminalConfiguration(
                bindAddress: WebTerminalConfiguration.defaultBindAddress,
                port: 0,
                authToken: token,
                maxConnections: 2,
                maxFrameRate: 30,
                allowsInput: false
            )
        ), status.running, !status.allowsInput else {
            routeRegistry.replace(routes: [], preferredSurfaceID: nil)
            return
        }
        let stream = OwnedStream(
            bridge: bridge,
            surfaceID: surfaceID,
            port: status.port,
            token: token
        )
        ownedStreams[surfaceID] = stream
        routeRegistry.replace(
            routes: [MobileMirrorTerminalRoute(
                sessionID: sessionID,
                surfaceID: surfaceID,
                port: status.port,
                bearerToken: token
            )],
            preferredSurfaceID: surfaceID.rawValue.uuidString
        )
    }

    func orderedSurfaceIDs(
        for tabID: TabID,
        controller: MainWindowController
    ) -> [SurfaceID] {
        var surfaces = controller.surfaceIDs(for: tabID).sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        guard let primary = controller.tabSurfaceMap[tabID],
              let primaryIndex = surfaces.firstIndex(of: primary) else {
            return surfaces
        }
        surfaces.remove(at: primaryIndex)
        surfaces.insert(primary, at: 0)
        return surfaces
    }

    func stopOwnedStream(_ stream: OwnedStream) {
        guard stream.bridge.webTerminalStatus(for: stream.surfaceID)?.port == stream.port else {
            return
        }
        stream.bridge.stopWebTerminal(for: stream.surfaceID)
    }

    func publishAgentNotification(_ entry: SessionEntry) {
        let localizer = appDelegate?.appLocalizer()
            ?? AppLocalizer(languagePreference: .system)
        let kind: String
        switch entry.agentState {
        case .waitingInput: kind = "agent-waiting"
        case .finished: kind = "agent-finished"
        case .error: kind = "agent-error"
        default: return
        }
        publishNotification(
            kind: kind,
            title: entry.detectedAgentName ?? entry.title,
            message: Self.stateLabel(entry.agentState, using: localizer),
            sessionID: entry.sessionID.rawValue.uuidString
        )
    }

    func publishApprovalNotification(_ record: MobileMirrorApprovalRecord) {
        let localizer = appDelegate?.appLocalizer()
            ?? AppLocalizer(languagePreference: .system)
        publishNotification(
            kind: "approval",
            title: record.title,
            message: localizer.string(
                "mobile.web.notification.approvalRequested",
                fallback: "Approval requested"
            ),
            sessionID: record.sessionID
        )
    }

    func publishNotification(
        kind: String,
        title: String,
        message: String,
        sessionID: String
    ) {
        guard activePairing != nil,
              let data = try? JSONSerialization.data(withJSONObject: [
                  "kind": kind,
                  "title": title,
                  "message": message,
                  "sessionID": sessionID,
              ]), let json = String(data: data, encoding: .utf8) else {
            return
        }
        gateway?.eventHub.publish(event: "notification", data: json)
    }

    func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSnapshotAndPublish() }
        }
    }

    func scheduleOfferExpiry(_ offer: MobileMirrorPairingOffer) {
        expiryTask?.cancel()
        let delay = max(0, offer.expiresAt.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expireOffer(id: offer.id)
        }
    }

    func scheduleSessionExpiry(_ active: MobileMirrorActivePairing) {
        expiryTask?.cancel()
        let delay = max(0, active.expiresAt.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expireSession(channelID: active.channelID)
        }
    }

    func expireOffer(id: UUID) {
        guard pairingChannelID == id,
              activePairing == nil,
              state == .offering || state == .awaitingConfirmation else { return }
        stopTransport(revoke: true)
        state = .stopped
    }

    func expireSession(channelID: UUID) {
        guard activePairing?.channelID == channelID else { return }
        stopTransport(revoke: true)
        state = .stopped
    }

    func finishDeniedPairing() {
        guard state == .denied else { return }
        stopTransport(revoke: true)
        state = .stopped
    }

    func stopTransport(revoke: Bool) {
        transportGeneration &+= 1
        pairingTask?.cancel()
        pairingTask = nil
        backgroundActionQueue.cancelAll()
        expiryTask?.cancel()
        expiryTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        let channelID = activePairing?.channelID
            ?? pendingPairing?.channelID
            ?? pairingChannelID
        if revoke {
            if activePairing != nil {
                gateway?.eventHub.publishAndWait(event: "revoked", data: "{}")
            }
            _ = authority.revoke()
        }
        if let lease = localRelayLease {
            relayManager.closeMobileMirrorRelay(leaseID: lease.id)
            localRelayLease = nil
        }
        gateway?.stop()
        gateway = nil
        staticAssetServer.stop()
        router = nil
        if let lease = tunnelLease {
            if tunnelClosureTask == nil {
                tunnelClosureTask = Task { [weak self, tunnelController] in
                    do {
                        try await tunnelController.close(lease)
                        guard let self else { return }
                        if self.tunnelLease == lease {
                            self.tunnelLease = nil
                        }
                        if let channelID {
                            try self.auditLog.log(.channelClosed(channelID: channelID))
                        }
                    } catch {
                        self?.state = .failed(error.localizedDescription)
                    }
                    self?.tunnelClosureTask = nil
                }
            }
        } else if let channelID {
            do {
                try auditLog.log(.channelClosed(channelID: channelID))
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
        for stream in ownedStreams.values { stopOwnedStream(stream) }
        ownedStreams.removeAll()
        routeRegistry.replace(routes: [], preferredSurfaceID: nil)
        terminalPasteDeliveryCoordinator.cancelAll()
        pairingURL = nil
        pendingPairing = nil
        activePairing = nil
        pairingChannelID = nil
        announcedApprovalIDs.removeAll()
        snapshot = .empty
    }

    static func stateLabel(_ state: AgentState, using localizer: AppLocalizer) -> String {
        switch state {
        case .idle:
            return localizer.string("agentDashboard.state.idle", fallback: "Idle")
        case .launched:
            return localizer.string("agentDashboard.state.launching", fallback: "Launching")
        case .working:
            return localizer.string("agentDashboard.state.working", fallback: "Working")
        case .waitingInput:
            return localizer.string(
                "agentDashboard.state.waitingForInput",
                fallback: "Waiting for input"
            )
        case .finished:
            return localizer.string("agentDashboard.state.finished", fallback: "Finished")
        case .error:
            return localizer.string("agentDashboard.state.error", fallback: "Error")
        }
    }

    static func sortSessions(_ lhs: SessionEntry, _ rhs: SessionEntry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.sessionID.rawValue.uuidString < rhs.sessionID.rawValue.uuidString
    }
}
