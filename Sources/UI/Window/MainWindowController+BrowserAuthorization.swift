// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+BrowserAuthorization.swift - Native approval for persistent browser scripts.

import AppKit

struct BrowserInitScriptApprovalCopy: Equatable {
    let title: String
    let message: String
    let approveButton: String
    let cancelButton: String
    let sourceAccessibilityLabel: String
}

extension MainWindowController {
    func allBrowserViewModels() -> [BrowserViewModel] {
        var models: [BrowserViewModel] = []
        var seen: Set<ObjectIdentifier> = []
        func append(_ model: BrowserViewModel?) {
            guard let model, seen.insert(ObjectIdentifier(model)).inserted else { return }
            models.append(model)
        }

        append(browserViewModel)
        append(browserHostingView?.rootView.viewModel)
        for panelView in panelContentViews.values {
            append(browserViewModel(containedIn: panelView))
        }
        for savedPanels in savedTabPanelContentViews.values {
            for panelView in savedPanels.values {
                append(browserViewModel(containedIn: panelView))
            }
        }
        return models
    }

    func revokeBrowserAuthorizations(in panelViews: [NSView]) {
        for panelView in panelViews {
            guard let viewModel = browserViewModel(containedIn: panelView) else { continue }
            viewModel.revokeDOMGrabAuthorization()
            viewModel.revokeAllInitScripts()
        }
    }

    @MainActor
    func authorizeBrowserInitScript(_ request: BrowserInitScriptAuthorizationRequest) -> Bool {
        guard allBrowserViewModels().contains(where: {
            ObjectIdentifier($0) == request.context.viewModelIdentifier
        }) else {
            return false
        }
        guard !isBrowserInitScriptAuthorizationPresented else { return false }
        isBrowserInitScriptAuthorizationPresented = true
        defer { isBrowserInitScriptAuthorizationPresented = false }

        guard request.expiresAt.timeIntervalSinceNow > 0 else { return false }
        if let browserInitScriptAuthorizationPresenter {
            return browserInitScriptAuthorizationPresenter(request)
        }

        let localizer = appLocalizer()
        let profileDisplayTitle = request.context.browserProfileID.flatMap { profileID in
            browserProfileManager?.profiles.first(where: { $0.id == profileID })?.name
        }
        let copy = Self.localizedBrowserInitScriptApprovalCopy(
            request: request,
            profileDisplayTitle: profileDisplayTitle,
            localizer: localizer
        )
        let alert = NSAlert()
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: copy.title)
            ?? AppIconGenerator.generatePlaceholderIcon()
        Self.configureBrowserInitScriptApprovalButtons(alert, copy: copy)
        alert.accessoryView = Self.browserInitScriptSourcePreview(
            BrowserInitScriptSecurity.approvalPreview(request.script),
            accessibilityLabel: copy.sourceAccessibilityLabel
        )
        guard let parentWindow = window, parentWindow.attachedSheet == nil else { return false }

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
        return response == .alertFirstButtonReturn && Date() < request.expiresAt
    }

    static func localizedBrowserInitScriptApprovalCopy(
        request: BrowserInitScriptAuthorizationRequest,
        profileDisplayTitle: String? = nil,
        localizer: AppLocalizer
    ) -> BrowserInitScriptApprovalCopy {
        let sourceLabel: String
        switch request.source {
        case .localCLI:
            sourceLabel = localizer.string(
                "browser.initScriptApproval.source.localCLI",
                fallback: "Local process (CLI socket)"
            )
        case .agentMode:
            sourceLabel = localizer.string(
                "browser.initScriptApproval.source.agentMode",
                fallback: "Agent Mode"
            )
        }
        let profileLabel: String
        if let profileDisplayTitle {
            profileLabel = profileDisplayTitle
        } else if let profileID = request.context.browserProfileID {
            let profileTemplate = localizer.string(
                "browser.initScriptApproval.profile.unknown",
                fallback: "Profile %@"
            )
            profileLabel = String(format: profileTemplate, locale: localizer.locale, profileID.uuidString)
        } else {
            profileLabel = localizer.string(
                "browser.initScriptApproval.profile.default",
                fallback: "Default"
            )
        }
        let remoteLabel = request.remoteDisplayTitle
            ?? request.context.remoteRouteAuthority?.fallbackDisplayTitle
            ?? localizer.string(
                "browser.initScriptApproval.remote.local",
                fallback: "Local"
            )
        let messageTemplate = localizer.string(
            "browser.initScriptApproval.message",
            fallback: "Requested by: %@\nTab: %@\nBrowser profile: %@\nOrigin: %@\nRemote route: %@\n\nFor the next 10 minutes, this JavaScript will be injected into the main frame at document start on future loads, limited to this tab, profile, origin, and remote route. Expiration or revocation prevents future injections; it cannot undo changes or activity from code that already ran. It can read and change the signed-in page with your authority. Review the exact source below; invisible controls are shown as Unicode escapes."
        )
        return BrowserInitScriptApprovalCopy(
            title: localizer.string(
                "browser.initScriptApproval.title",
                fallback: "Allow Browser Init Script?"
            ),
            message: String(
                format: messageTemplate,
                locale: localizer.locale,
                sourceLabel,
                BrowserInitScriptSecurity.approvalMetadataPreview(request.tabDisplayTitle),
                BrowserInitScriptSecurity.approvalMetadataPreview(profileLabel),
                request.context.origin.serialized,
                BrowserInitScriptSecurity.approvalMetadataPreview(remoteLabel)
            ),
            approveButton: localizer.string(
                "browser.initScriptApproval.approve",
                fallback: "Allow Future Loads"
            ),
            cancelButton: localizer.string("common.cancel", fallback: "Cancel"),
            sourceAccessibilityLabel: localizer.string(
                "browser.initScriptApproval.source.accessibility",
                fallback: "JavaScript source for approval"
            )
        )
    }

    @MainActor
    static func configureBrowserInitScriptApprovalButtons(
        _ alert: NSAlert,
        copy: BrowserInitScriptApprovalCopy
    ) {
        let approveButton = alert.addButton(withTitle: copy.approveButton)
        approveButton.keyEquivalent = ""
        let cancelButton = alert.addButton(withTitle: copy.cancelButton)
        cancelButton.keyEquivalent = "\u{1B}"
    }

    @MainActor
    private static func browserInitScriptSourcePreview(
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
