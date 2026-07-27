// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TabConfig.swift - UI affordances for reusable tab configs.

import AppKit

struct TabConfigStartupApprovalCopy: Equatable {
    let title: String
    let message: String
    let approveButton: String
    let skipButton: String
    let previewAccessibilityLabel: String
}

extension MainWindowController {

    @MainActor
    func authorizeTabConfigStartup(_ request: TabConfigStartupAuthorizationRequest) -> Bool {
        guard tabConfigAuthorizationContextMatches(request),
              consumedTabConfigStartupAuthorizationIDs.insert(request.id).inserted,
              !isTabConfigStartupAuthorizationPresented else {
            return false
        }
        isTabConfigStartupAuthorizationPresented = true
        defer { isTabConfigStartupAuthorizationPresented = false }

        if let tabConfigStartupAuthorizationPresenter {
            return tabConfigStartupAuthorizationPresenter(request)
                && tabConfigAuthorizationContextMatches(request)
        }

        let copy = Self.localizedTabConfigStartupApprovalCopy(
            request: request,
            localizer: appLocalizer()
        )
        let alert = NSAlert()
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: copy.title)
            ?? AppIconGenerator.generatePlaceholderIcon()
        let approveButton = alert.addButton(withTitle: copy.approveButton)
        approveButton.keyEquivalent = ""
        let skipButton = alert.addButton(withTitle: copy.skipButton)
        skipButton.keyEquivalent = "\u{1B}"
        alert.accessoryView = Self.tabConfigStartupPreview(
            TabConfigStartupSecurity.approvalPreview(request),
            accessibilityLabel: copy.previewAccessibilityLabel
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
        return response == .alertFirstButtonReturn
            && tabConfigAuthorizationContextMatches(request)
    }

    static func localizedTabConfigStartupApprovalCopy(
        request: TabConfigStartupAuthorizationRequest,
        localizer: AppLocalizer
    ) -> TabConfigStartupApprovalCopy {
        let messageTemplate = localizer.string(
            "tabConfig.startupApproval.message",
            fallback: "Config: %@\nWorking directory: %@\nFingerprint: %@\n\nThe exact input below will be sent once to the new terminal and can execute commands with your user account. Review it before continuing."
        )
        return TabConfigStartupApprovalCopy(
            title: localizer.string(
                "tabConfig.startupApproval.title",
                fallback: "Run Tab Config Startup Input?"
            ),
            message: String(
                format: messageTemplate,
                locale: localizer.locale,
                TabConfigStartupSecurity.approvalMetadataPreview(request.configName),
                TabConfigStartupSecurity.approvalMetadataPreview(request.workingDirectory),
                String(request.sourceDigest.prefix(12))
            ),
            approveButton: localizer.string(
                "tabConfig.startupApproval.runOnce",
                fallback: "Run Once"
            ),
            skipButton: localizer.string(
                "tabConfig.startupApproval.skip",
                fallback: "Open Without Running"
            ),
            previewAccessibilityLabel: localizer.string(
                "tabConfig.startupApproval.preview.accessibility",
                fallback: "Exact terminal input for approval"
            )
        )
    }

    @objc func saveCurrentTabConfigAction(_ sender: Any?) {
        promptAndSaveCurrentTabConfig()
    }

    @objc func openTabConfigAction(_ sender: Any?) {
        promptAndOpenTabConfig()
    }

    func promptAndSaveCurrentTabConfig() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let activeTitle = tabManager.activeTab?.displayTitle ?? "tab"
        let field = NSTextField(string: TabConfigStore.suggestedName(from: activeTitle))
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        let copy = Self.localizedSaveTabConfigCopy(localizer: appLocalizer())
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.accessoryView = field
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appDelegate.saveFocusedTabConfigForCLI(
            name: name,
            command: nil,
            theme: nil,
            environment: [:]
        ) != nil else {
            showTabConfigError(Self.localizedTabConfigSaveFailureMessage(localizer: appLocalizer()))
            return
        }
    }

    func promptAndOpenTabConfig() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let names = appDelegate.listTabConfigsForCLI() ?? []
        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        field.completes = true
        field.addItems(withObjectValues: names)
        field.stringValue = names.first ?? ""

        let alert = NSAlert()
        let copy = Self.localizedOpenTabConfigCopy(localizer: appLocalizer())
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.accessoryView = field
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appDelegate.openTabConfigFromUserInterface(named: name) != nil else {
            showTabConfigError(Self.localizedTabConfigOpenFailureMessage(localizer: appLocalizer()))
            return
        }
    }

    private func showTabConfigError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: appLocalizer().string("common.ok", fallback: "OK"))
        alert.runModal()
    }

    @MainActor
    private func tabConfigAuthorizationContextMatches(
        _ request: TabConfigStartupAuthorizationRequest
    ) -> Bool {
        guard request.launchOrigin == .userInterface,
              Date() < request.expiresAt,
              let tab = tabManager.tab(for: request.destinationTabID) else {
            return false
        }
        return tab.workingDirectory.standardizedFileURL.path == request.workingDirectory
    }

    @MainActor
    private static func tabConfigStartupPreview(
        _ source: String,
        accessibilityLabel: String
    ) -> NSView {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 150)
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
