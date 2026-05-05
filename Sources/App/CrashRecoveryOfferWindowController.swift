// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CrashRecoveryOfferWindowController.swift - Local crash recovery prompt window.

import AppKit

typealias CrashRecoveryOfferPresenter = @MainActor (
    _ copy: AppAlertCopy,
    _ parentWindow: NSWindow,
    _ completion: @escaping (NSApplication.ModalResponse) -> Void
) -> Void

@MainActor
final class CrashRecoveryOfferWindowController: NSWindowController, NSWindowDelegate {
    private enum Layout {
        static let panelSize = NSSize(width: 500, height: 196)
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 22
        static let buttonWidth: CGFloat = 118
    }

    private weak var parentWindow: NSWindow?
    private var completion: ((NSApplication.ModalResponse) -> Void)?
    private var didComplete = false
    private var isRunningModalSession = false

    private let messageLabel = NSTextField(labelWithString: "")
    private let informativeLabel = NSTextField(wrappingLabelWithString: "")
    private let restoreButton = NSButton(title: "", target: nil, action: nil)
    private let keepCurrentButton = NSButton(title: "", target: nil, action: nil)

    init(copy: AppAlertCopy, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completion = completion

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Layout.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = copy.messageText
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.backgroundColor = CocxyColors.base
        panel.contentMinSize = Layout.panelSize
        panel.collectionBehavior = [.fullScreenAuxiliary]

        super.init(window: panel)

        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = makeContentView(copy: copy)
        panel.setAccessibilityTitle(copy.messageText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CrashRecoveryOfferWindowController does not support NSCoding")
    }

    func show(over parentWindow: NSWindow, runModally: Bool = false) {
        self.parentWindow = parentWindow
        guard let window else { return }

        let parentFrame = parentWindow.frame
        let origin = NSPoint(
            x: parentFrame.midX - Layout.panelSize.width / 2,
            y: parentFrame.midY - Layout.panelSize.height / 2
        )
        window.setFrameOrigin(origin)
        parentWindow.addChildWindow(window, ordered: .above)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if runModally {
            isRunningModalSession = true
            NSApp.runModal(for: window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        complete(.alertSecondButtonReturn)
    }

    @objc private func restoreButtonPressed(_ sender: Any?) {
        complete(.alertFirstButtonReturn)
    }

    @objc private func keepCurrentButtonPressed(_ sender: Any?) {
        complete(.alertSecondButtonReturn)
    }

    private func complete(_ response: NSApplication.ModalResponse) {
        guard !didComplete else { return }
        didComplete = true

        let callback = completion
        completion = nil

        if isRunningModalSession {
            isRunningModalSession = false
            NSApp.stopModal(withCode: response)
        }

        callback?(response)

        if let window {
            parentWindow?.removeChildWindow(window)
            window.orderOut(nil)
        }
    }

    private func makeContentView(copy: AppAlertCopy) -> NSView {
        let contentView = NSView(frame: NSRect(origin: .zero, size: Layout.panelSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = CocxyColors.base.cgColor

        messageLabel.stringValue = copy.messageText
        messageLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        messageLabel.textColor = CocxyColors.text
        messageLabel.lineBreakMode = .byWordWrapping

        informativeLabel.stringValue = copy.informativeText
        informativeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        informativeLabel.textColor = CocxyColors.subtext0
        informativeLabel.maximumNumberOfLines = 3

        restoreButton.title = copy.primaryButton
        restoreButton.bezelStyle = .rounded
        restoreButton.keyEquivalent = "\r"
        restoreButton.target = self
        restoreButton.action = #selector(restoreButtonPressed(_:))

        keepCurrentButton.title = copy.secondaryButton
        keepCurrentButton.bezelStyle = .rounded
        keepCurrentButton.keyEquivalent = "\u{1b}"
        keepCurrentButton.target = self
        keepCurrentButton.action = #selector(keepCurrentButtonPressed(_:))

        let iconView = NSImageView(image: AppIconGenerator.generatePlaceholderIcon())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [messageLabel, informativeLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [iconView, textStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .top
        headerStack.spacing = 16
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [keepCurrentButton, restoreButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 10
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(headerStack)
        contentView.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalPadding),
            headerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalPadding),
            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalPadding),

            restoreButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.buttonWidth),
            keepCurrentButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.buttonWidth),
            buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalPadding),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalPadding),
        ])

        return contentView
    }
}
