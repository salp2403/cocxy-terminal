// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Projection.swift - Snapshot and stream projection.

import Foundation

extension MobileMirrorCoordinator {
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
            let projectID = projectResolver.resolveProject(for: entry.workingDirectory).groupingID
            if projectsByID[projectID.storageKey] == nil {
                projectsByID[projectID.storageKey] = projectSnapshot(
                    id: projectID,
                    isPinned: false,
                    accent: nil
                )
            }
            let sessionID = entry.sessionID.rawValue.uuidString
            let terminalAvailable = routeRegistry.contains(sessionID: sessionID)
            agents.append(MobileMirrorAgentSnapshot(
                sessionID: sessionID,
                projectID: projectID.storageKey,
                title: entry.title,
                name: entry.detectedAgentName,
                state: entry.agentState.rawValue,
                stateLabel: Self.stateLabel(entry.agentState),
                canRespond: entry.agentState == .waitingInput && terminalAvailable,
                terminalAvailable: terminalAvailable
            ))
        }

        let approvals = approvalSnapshots()
        let projects = projectsByID.values.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let selected = authority.selectedSessionID().flatMap { id in
            agents.contains(where: { $0.sessionID == id }) ? id : nil
        }
        snapshot = MobileMirrorSnapshot(
            selectedSessionID: selected,
            projectCreationEnabled: projectCreationRootHandle != nil,
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
        let desiredIDs = Set(sessionEntriesSnapshot.map { $0.sessionID.rawValue.uuidString })
        for (sessionID, stream) in Array(ownedStreams) where !desiredIDs.contains(sessionID) {
            stopOwnedStream(stream)
            ownedStreams.removeValue(forKey: sessionID)
        }

        var routes: [MobileMirrorTerminalRoute] = []
        for entry in sessionEntriesSnapshot.sorted(by: Self.sortSessions) {
            let sessionID = entry.sessionID.rawValue.uuidString
            guard let controller = appDelegate.allWindowControllers.first(where: {
                $0.windowID == entry.ownerWindowID
            }), controller.tabManager.tab(for: entry.tabID) != nil,
                  let surfaceID = preferredSurfaceID(for: entry.tabID, controller: controller),
                  let bridge = controller.cocxyCoreBridge(forSurface: surfaceID) else {
                if let stream = ownedStreams.removeValue(forKey: sessionID) {
                    stopOwnedStream(stream)
                }
                continue
            }

            if let stream = ownedStreams[sessionID] {
                let status = stream.bridge.webTerminalStatus(for: stream.surfaceID)
                if stream.bridge === bridge, stream.surfaceID == surfaceID,
                   status?.running == true, status?.port == stream.port,
                   status?.allowsInput == false {
                    routes.append(MobileMirrorTerminalRoute(
                        sessionID: sessionID,
                        surfaceID: surfaceID,
                        port: stream.port,
                        bearerToken: stream.token
                    ))
                    continue
                }
                stopOwnedStream(stream)
                ownedStreams.removeValue(forKey: sessionID)
            }

            guard bridge.webTerminalStatus(for: surfaceID) == nil else { continue }
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
                continue
            }
            let stream = OwnedStream(
                bridge: bridge,
                surfaceID: surfaceID,
                port: status.port,
                token: token
            )
            ownedStreams[sessionID] = stream
            routes.append(MobileMirrorTerminalRoute(
                sessionID: sessionID,
                surfaceID: surfaceID,
                port: status.port,
                bearerToken: token
            ))
        }
        routeRegistry.replace(routes: routes, preferredSessionID: snapshot.selectedSessionID)
    }

    func preferredSurfaceID(
        for tabID: TabID,
        controller: MainWindowController
    ) -> SurfaceID? {
        let available = controller.surfaceIDs(for: tabID)
        if let primary = controller.tabSurfaceMap[tabID], available.contains(primary) {
            return primary
        }
        return available.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.first
    }

    func stopOwnedStream(_ stream: OwnedStream) {
        guard stream.bridge.webTerminalStatus(for: stream.surfaceID)?.port == stream.port else {
            return
        }
        stream.bridge.stopWebTerminal(for: stream.surfaceID)
    }

    func publishAgentNotification(_ entry: SessionEntry) {
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
            message: Self.stateLabel(entry.agentState),
            sessionID: entry.sessionID.rawValue.uuidString
        )
    }

    func publishApprovalNotification(_ record: MobileMirrorApprovalRecord) {
        publishNotification(
            kind: "approval",
            title: record.title,
            message: "Approval requested",
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
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
        guard activePairing == nil, state == .offering || state == .awaitingConfirmation else { return }
        auditLog.log(.channelClosed(channelID: id))
        stopTransport(revoke: true, logRevocation: false)
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

    func stopTransport(revoke: Bool, logRevocation: Bool = true) {
        transportGeneration &+= 1
        pairingTask?.cancel()
        pairingTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        let channelID = activePairing?.channelID
            ?? pendingPairing?.channelID
            ?? pairingChannelID
        if revoke {
            _ = authority.revoke()
        }
        if logRevocation, let channelID {
            auditLog.log(.channelClosed(channelID: channelID))
        }
        gateway?.stop()
        gateway = nil
        router = nil
        if let lease = tunnelLease {
            let priorClosure = tunnelClosureTask
            tunnelClosureTask = Task { [tunnelController] in
                await priorClosure?.value
                try? await tunnelController.close(lease)
            }
        }
        tunnelLease = nil
        for stream in ownedStreams.values { stopOwnedStream(stream) }
        ownedStreams.removeAll()
        routeRegistry.replace(routes: [], preferredSessionID: nil)
        pairingURL = nil
        pendingPairing = nil
        activePairing = nil
        pairingChannelID = nil
        announcedApprovalIDs.removeAll()
        snapshot = .empty
    }

    static func stateLabel(_ state: AgentState) -> String {
        switch state {
        case .idle: return "Idle"
        case .launched: return "Starting"
        case .working: return "Working"
        case .waitingInput: return "Waiting for input"
        case .finished: return "Finished"
        case .error: return "Error"
        }
    }

    static func sortSessions(_ lhs: SessionEntry, _ rhs: SessionEntry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.sessionID.rawValue.uuidString < rhs.sessionID.rawValue.uuidString
    }
}
