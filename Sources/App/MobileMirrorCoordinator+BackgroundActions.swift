// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+BackgroundActions.swift - Audited request-independent work.

import Foundation

extension MobileMirrorCoordinator {
    func startBackgroundAction(
        _ action: MobileMirrorAction,
        channelID: UUID,
        identity: MobileMirrorClientIdentity,
        notificationSessionID: String,
        operation: @escaping @MainActor () async throws -> MobileMirrorActionAudit.Outcome
    ) {
        backgroundActionQueue.enqueue { [self] in
            let outcome: MobileMirrorActionAudit.Outcome
            do {
                outcome = try await operation()
            } catch {
                Self.logger.error(
                    "Mobile action was rejected: \(String(describing: error), privacy: .private)"
                )
                outcome = .rejected
            }

            do {
                try auditLog.log(MobileMirrorActionAudit.event(
                    action: action,
                    channelID: channelID,
                    identity: identity,
                    outcome: outcome
                ))
            } catch {
                stopTransport(revoke: true)
                state = .failed(.auditUnavailable)
                return
            }

            refreshSnapshotAndPublish()
            publishBackgroundActionNotification(
                action,
                outcome: outcome,
                sessionID: notificationSessionID
            )
        }
    }

    private func publishBackgroundActionNotification(
        _ action: MobileMirrorAction,
        outcome: MobileMirrorActionAudit.Outcome,
        sessionID: String
    ) {
        let localizer = appDelegate?.appLocalizer()
            ?? AppLocalizer(languagePreference: .system)
        let titleKey: String
        let titleFallback: String
        switch action.kind {
        case .approvalApprove, .approvalReject:
            titleKey = "mobile.web.approval.title"
            titleFallback = "Approval"
        case .projectCreate:
            titleKey = "mobile.web.project.new"
            titleFallback = "New project"
        default:
            titleKey = "mobile.web.terminal.input"
            titleFallback = "Terminal input"
        }
        let messageKey: String
        let messageFallback: String
        switch outcome {
        case .accepted:
            messageKey = "mobile.web.action.completed"
            messageFallback = "Action completed"
        case .partial:
            messageKey = "mobile.web.action.partial"
            messageFallback = "Action was only partially completed"
        case .rejected:
            messageKey = "mobile.web.action.failed"
            messageFallback = "Action could not be completed"
        case .queued:
            return
        }
        publishNotification(
            kind: "action-\(outcome.rawValue)",
            title: localizer.string(titleKey, fallback: titleFallback),
            message: localizer.string(messageKey, fallback: messageFallback),
            sessionID: sessionID
        )
    }
}
