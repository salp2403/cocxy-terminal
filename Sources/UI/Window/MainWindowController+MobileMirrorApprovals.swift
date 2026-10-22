// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+MobileMirrorApprovals.swift - Agent tool approval projection.

import Combine
import Foundation

extension MainWindowController {
    func bindMobileMirrorApprovals(to viewModel: AgentPanelViewModel) {
        guard mobileMirrorApprovalCancellable == nil,
              let registry = mobileMirrorApprovalRegistry else {
            return
        }
        let sourceID = "agent-tool:\(windowID.rawValue.uuidString)"
        mobileMirrorApprovalCancellable = viewModel.$pendingApproval
            .sink { [weak self, weak viewModel, weak registry] request in
                Task { @MainActor [weak self, weak viewModel, weak registry] in
                    guard let self, let viewModel, let registry else { return }
                    guard let request, viewModel.pendingApproval == request else {
                        registry.remove(sourceID: sourceID)
                        return
                    }
                    registerMobileMirrorApproval(
                        request,
                        from: viewModel,
                        sourceID: sourceID,
                        registry: registry
                    )
                }
            }
    }

    private func registerMobileMirrorApproval(
        _ request: AgentToolApprovalRequest,
        from viewModel: AgentPanelViewModel,
        sourceID: String,
        registry: MobileMirrorApprovalRegistry
    ) {
        guard let tabID = visibleTabID ?? tabManager.activeTabID,
              let sessionID = tabSessionMap[tabID],
              let entry = sessionRegistry?.session(for: sessionID),
              entry.ownerWindowID == windowID,
              entry.tabID == tabID else {
            registry.remove(sourceID: sourceID)
            return
        }
        let approvalID = MobileMirrorPairingAuthority.digest(Data("""
        agent-tool
        \(sessionID.rawValue.uuidString)
        \(request.id)
        \(request.preview.kind.rawValue)
        \(request.preview.title)
        \(request.preview.body)
        """.utf8))
        let record = MobileMirrorApprovalRecord(
            id: approvalID,
            kind: .agentTool,
            sessionID: sessionID.rawValue.uuidString,
            title: request.preview.title,
            body: request.preview.body,
            requiresResponse: request.preview.kind == .userInput,
            expiresAt: nil
        )
        registry.register(
            sourceID: sourceID,
            record: record,
            isCurrent: { [weak self, weak viewModel] in
                guard let self, let viewModel,
                      viewModel.pendingApproval == request,
                      tabSessionMap[tabID] == sessionID,
                      let current = sessionRegistry?.session(for: sessionID) else {
                    return false
                }
                return current.ownerWindowID == windowID && current.tabID == tabID
            },
            resolve: { [weak viewModel] decision in
                guard let viewModel, viewModel.pendingApproval == request else { return false }
                switch decision {
                case .reject:
                    viewModel.rejectPendingTool()
                    return viewModel.pendingApproval?.id != request.id
                case .approve(let response):
                    if request.preview.kind == .userInput {
                        guard let response,
                              !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              response.utf8.count <= 8_192 else {
                            return false
                        }
                        viewModel.pendingApprovalResponseDraft = response
                    }
                    guard viewModel.canApprovePendingTool else { return false }
                    await viewModel.approvePendingTool()
                    return viewModel.pendingApproval?.id != request.id
                }
            }
        )
    }
}
