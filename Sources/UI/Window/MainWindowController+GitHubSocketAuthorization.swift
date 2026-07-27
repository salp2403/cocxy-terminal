// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+GitHubSocketAuthorization.swift - Native approval for socket mutations.

import AppKit

struct GitHubSocketMutationApprovalCopy: Equatable {
    let title: String
    let message: String
    let approveButton: String
    let cancelButton: String
    let previewAccessibilityLabel: String
}

extension MainWindowController {
    @MainActor
    func authorizeGitHubSocketMutation(
        _ request: GitHubSocketMutationAuthorizationRequest
    ) -> GitHubSocketMutationAuthorizationGrant? {
        let now = Date()
        consumedGitHubSocketMutationAuthorizationIDs =
            consumedGitHubSocketMutationAuthorizationIDs.filter { $0.value > now }
        guard githubSocketMutationAuthorizationContextMatches(request, at: now),
              !isGitHubSocketMutationAuthorizationPresented,
              consumedGitHubSocketMutationAuthorizationIDs[request.id] == nil else {
            return nil
        }

        consumedGitHubSocketMutationAuthorizationIDs[request.id] = request.expiresAt
        isGitHubSocketMutationAuthorizationPresented = true
        defer { isGitHubSocketMutationAuthorizationPresented = false }

        if let githubSocketMutationAuthorizationPresenter {
            guard githubSocketMutationAuthorizationPresenter(request) else { return nil }
            let approvedAt = Date()
            guard githubSocketMutationAuthorizationContextMatches(request, at: approvedAt) else {
                return nil
            }
            return GitHubSocketMutationAuthorizationGrant(
                request: request,
                approvedAt: approvedAt
            )
        }

        let copy = Self.localizedGitHubSocketMutationApprovalCopy(
            request: request,
            localizer: appLocalizer()
        )
        let alert = NSAlert()
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.alertStyle = .warning
        alert.icon = NSImage(
            systemSymbolName: "checkmark.shield.fill",
            accessibilityDescription: copy.title
        ) ?? AppIconGenerator.generatePlaceholderIcon()
        let approveButton = alert.addButton(withTitle: copy.approveButton)
        approveButton.keyEquivalent = ""
        let cancelButton = alert.addButton(withTitle: copy.cancelButton)
        cancelButton.keyEquivalent = "\u{1B}"
        alert.accessoryView = Self.githubSocketMutationPreview(
            GitHubSocketMutationSecurity.approvalPreview(request),
            accessibilityLabel: copy.previewAccessibilityLabel
        )

        guard let parentWindow = window, parentWindow.attachedSheet == nil else { return nil }
        var response: NSApplication.ModalResponse?
        alert.beginSheetModal(for: parentWindow) { modalResponse in
            response = modalResponse
        }
        while response == nil, Date() < request.expiresAt {
            _ = RunLoop.current.run(mode: .default, before: request.expiresAt)
        }
        if response == nil, alert.window.sheetParent === parentWindow {
            parentWindow.endSheet(alert.window, returnCode: .abort)
            _ = RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }

        let approvedAt = Date()
        guard response == .alertFirstButtonReturn,
              githubSocketMutationAuthorizationContextMatches(request, at: approvedAt) else {
            return nil
        }
        return GitHubSocketMutationAuthorizationGrant(
            request: request,
            approvedAt: approvedAt
        )
    }

    static func localizedGitHubSocketMutationApprovalCopy(
        request: GitHubSocketMutationAuthorizationRequest,
        localizer: AppLocalizer
    ) -> GitHubSocketMutationApprovalCopy {
        let messageTemplate = localizer.string(
            "github.socketApproval.message",
            fallback: "Repository: %@\nPull request: #%d\nFingerprint: %@\n\nA local CLI request wants to perform the exact GitHub action shown below. Approve it only if you initiated this request."
        )
        return GitHubSocketMutationApprovalCopy(
            title: localizer.string(
                "github.socketApproval.title",
                fallback: "Approve GitHub Action?"
            ),
            message: String(
                format: messageTemplate,
                locale: localizer.locale,
                GitHubSocketMutationSecurity.escapedPreview(
                    request.context.repository.displayName
                ),
                request.intent.pullRequestNumber,
                String(request.authorizationDigest.prefix(12))
            ),
            approveButton: localizer.string(
                "github.socketApproval.approveOnce",
                fallback: "Approve Once"
            ),
            cancelButton: localizer.string(
                "github.socketApproval.cancel",
                fallback: "Cancel"
            ),
            previewAccessibilityLabel: localizer.string(
                "github.socketApproval.preview.accessibility",
                fallback: "Exact GitHub action for approval"
            )
        )
    }

    @MainActor
    private func githubSocketMutationAuthorizationContextMatches(
        _ request: GitHubSocketMutationAuthorizationRequest,
        at date: Date
    ) -> Bool {
        guard request.isValid(at: date),
              request.context.windowControllerIdentifier == ObjectIdentifier(self),
              let activeTabID = visibleTabID ?? tabManager.activeTabID,
              activeTabID == request.context.tabID,
              let tab = tabManager.tab(for: activeTabID) else {
            return false
        }
        let directory = (tab.worktreeRoot ?? tab.workingDirectory).standardizedFileURL.path
        return directory == request.context.workingDirectory
    }

    @MainActor
    private static func githubSocketMutationPreview(
        _ source: String,
        accessibilityLabel: String
    ) -> NSView {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 180)
        let scrollView = NSScrollView(frame: frame)
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: frame.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = source
        textView.setAccessibilityLabel(accessibilityLabel)
        scrollView.documentView = textView
        return scrollView
    }
}
