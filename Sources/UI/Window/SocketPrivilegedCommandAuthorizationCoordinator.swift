// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketPrivilegedCommandAuthorizationCoordinator.swift - Native and mobile approval rendezvous.

import AppKit
import CocxyShared
import Foundation

@MainActor
final class SocketPrivilegedCommandAuthorizationCoordinator {
    typealias PresentationTargetProvider = @MainActor () -> SocketPrivilegedCommandPresentationTarget?
    typealias Completion = @MainActor (SocketPrivilegedCommandAuthorizationGrant?) -> Void

    private struct ActiveResolution {
        let request: SocketPrivilegedCommandAuthorizationRequest
        let target: SocketPrivilegedCommandPresentationTarget
        let targetProvider: PresentationTargetProvider
        let completion: Completion
        let parentWindow: NSWindow
        let alert: NSAlert
        var registrySourceID: String?
    }

    var presenter: ((
        SocketPrivilegedCommandAuthorizationRequest,
        SocketPrivilegedCommandContext
    ) -> Bool)?

    private let approvalRegistry: MobileMirrorApprovalRegistry?
    private var activeRequestID: UUID?
    private var activeResolution: ActiveResolution?
    private var consumedRequestIDs: [UUID: Date] = [:]

    init(approvalRegistry: MobileMirrorApprovalRegistry? = nil) {
        self.approvalRegistry = approvalRegistry
    }

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
            activeRequestID = nil
            completion(approved ? validatedGrant(
                request: request,
                target: target,
                targetProvider: targetProvider
            ) : nil)
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
        let alert = makeAlert(request: request, target: target, copy: copy)
        activeResolution = ActiveResolution(
            request: request,
            target: target,
            targetProvider: targetProvider,
            completion: completion,
            parentWindow: parentWindow,
            alert: alert,
            registrySourceID: nil
        )
        if let sourceID = registerOrchestrationLease(
            request: request,
            target: target,
            copy: copy
        ) {
            activeResolution?.registrySourceID = sourceID
        }

        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            MainActor.assumeIsolated {
                _ = self?.resolveActiveRequest(
                    id: request.id,
                    approved: response == .alertFirstButtonReturn,
                    closeSheet: false
                )
            }
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, request.expiresAt.timeIntervalSinceNow)
        ) { [weak self] in
            MainActor.assumeIsolated {
                _ = self?.resolveActiveRequest(
                    id: request.id,
                    approved: false,
                    closeSheet: true
                )
            }
        }
    }

    private func makeAlert(
        request: SocketPrivilegedCommandAuthorizationRequest,
        target: SocketPrivilegedCommandPresentationTarget,
        copy: SocketPrivilegedCommandApprovalCopy
    ) -> NSAlert {
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
        return alert
    }

    private func registerOrchestrationLease(
        request: SocketPrivilegedCommandAuthorizationRequest,
        target: SocketPrivilegedCommandPresentationTarget,
        copy: SocketPrivilegedCommandApprovalCopy
    ) -> String? {
        guard request.command == .taskRun,
              let approvalRegistry,
              let rawTabID = target.context.tabID,
              let sessionID = target.controller.tabSessionMap[TabID(rawValue: rawTabID)] else {
            return nil
        }
        let sourceID = "orchestration-lease:\(request.id.uuidString)"
        let approvalID = MobileMirrorPairingAuthority.digest(Data("""
        orchestration-lease
        \(sessionID.rawValue.uuidString)
        \(request.id.uuidString)
        \(request.authorizationDigest)
        \(target.context.workingDirectory)
        """.utf8))
        let preview = MainWindowController.privilegedSocketCommandApprovalPreview(
            request: request,
            context: target.context
        )
        let record = MobileMirrorApprovalRecord(
            id: approvalID,
            kind: .orchestrationLease,
            sessionID: sessionID.rawValue.uuidString,
            title: copy.title,
            body: "\(copy.message)\n\n\(preview)",
            requiresResponse: false,
            expiresAt: request.expiresAt
        )
        let registered = approvalRegistry.register(
            sourceID: sourceID,
            record: record,
            isCurrent: { [weak self] in
                self?.activeRequestID == request.id
                    && target.controller.tabSessionMap[TabID(rawValue: rawTabID)] == sessionID
                    && request.isValid(at: Date())
            },
            resolve: { [weak self] decision in
                guard let self else { return false }
                return resolveActiveRequest(
                    id: request.id,
                    approved: decision.isApproval,
                    closeSheet: true
                )
            }
        )
        return registered ? sourceID : nil
    }

    private func resolveActiveRequest(
        id: UUID,
        approved: Bool,
        closeSheet: Bool
    ) -> Bool {
        guard activeRequestID == id,
              let resolution = activeResolution,
              resolution.request.id == id else {
            return false
        }
        activeRequestID = nil
        activeResolution = nil
        if let sourceID = resolution.registrySourceID {
            approvalRegistry?.remove(sourceID: sourceID)
        }
        if closeSheet,
           resolution.alert.window.sheetParent === resolution.parentWindow {
            resolution.parentWindow.endSheet(resolution.alert.window, returnCode: .abort)
        }
        guard approved else {
            resolution.completion(nil)
            return true
        }
        let grant = validatedGrant(
            request: resolution.request,
            target: resolution.target,
            targetProvider: resolution.targetProvider
        )
        resolution.completion(grant)
        return grant != nil
    }

    private func validatedGrant(
        request: SocketPrivilegedCommandAuthorizationRequest,
        target: SocketPrivilegedCommandPresentationTarget,
        targetProvider: PresentationTargetProvider
    ) -> SocketPrivilegedCommandAuthorizationGrant? {
        guard request.isValid(at: Date()),
              let currentTarget = targetProvider(),
              currentTarget.context == target.context,
              let approvedContext = currentTarget.contextAfterApproval(),
              approvedContext.replacingLocalResourceDigests(
                target.context.localResourceDigests
              ) == target.context,
              targetProvider()?.context == target.context,
              request.isValid(at: Date()) else {
            return nil
        }
        return SocketPrivilegedCommandAuthorizationGrant(
            request: request,
            context: approvedContext
        )
    }
}

private extension MobileMirrorApprovalDecision {
    var isApproval: Bool {
        if case .approve = self { return true }
        return false
    }
}
