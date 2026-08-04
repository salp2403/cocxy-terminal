// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Approvals.swift - Signed mobile approval decisions.

import Foundation

extension MobileMirrorCoordinator {
    func claimApproval(
        _ action: MobileMirrorAction
    ) throws -> MobileMirrorApprovalRegistry.ResolutionClaim {
        guard let approvalID = action.approvalID else {
            throw MobileMirrorError.invalidAction
        }
        let decision: MobileMirrorApprovalDecision
        switch action.kind {
        case .approvalApprove:
            decision = .approve(response: action.text)
        case .approvalReject:
            decision = .reject
        default:
            throw MobileMirrorError.invalidAction
        }
        guard let claim = approvalRegistry.claimResolution(
            id: approvalID,
            decision: decision
        ) else {
            throw MobileMirrorError.targetUnavailable
        }
        return claim
    }
}
