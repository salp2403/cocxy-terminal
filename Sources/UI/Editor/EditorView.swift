// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorView.swift - Native reusable text editor panel for local files.

import AppKit

@MainActor
final class EditorView: NSView, NSTextViewDelegate {
    enum SaveError: Error, Equatable {
        case missingFileURL
    }

    private struct EditorUndoSnapshot: Equatable {
        var text: String
        var selection: EditorSelection
    }

    private struct EditorUndoEntry: Equatable {
        var before: EditorUndoSnapshot
        var after: EditorUndoSnapshot
    }

    private(set) var fileURL: URL?
    private(set) var session: EditorSession

    private let toolbar = NSStackView()
    private let fileNameLabel = NSTextField(labelWithString: "Untitled")
    private let statusLabel = NSTextField(labelWithString: "Saved")
    private let lspAccessoryLabel = NSTextField(labelWithString: "")
    private let lspHoverButton = NSButton()
    private let lspCompletionButton = NSButton()
    private let lspDefinitionButton = NSButton()
    private let lspReferencesButton = NSButton()
    private let lspPrimaryActionButton = NSButton()
    private let openButton = NSButton()
    private let saveButton = NSButton()
    private let textView = EditorTextView()
    private let scrollView: EditorScrollView
    private let clipboardService: ClipboardServiceProtocol
    private let lspResultsMenu = NSMenu()
    private var isApplyingProgrammaticUpdate = false
    private var statusOverride: String?
    private var lspPresentation = EditorLSPPresentation()
    private var vimController = VimController()
    private var vimUndoStack: [EditorUndoEntry] = []
    private var vimRedoStack: [EditorUndoEntry] = []
    private var pendingVimUndoStart: EditorUndoSnapshot?
    private var pendingVimUndoChanged = false
    private var inlineCompletionEngine: CompletionEngine?
    private var inlineCompletionTask: Task<Void, Never>?
    private let inlineGhostText = InlineGhostText()
    private var activeInlineCompletion: InlineCompletion?
    private var inlineCompletionRequestID = 0

    private(set) var isSoftWrapEnabled = true
    private(set) var isLSPControlsEnabled = false
    private(set) var isVimModeEnabled = false
    var isInlineCompletionEnabled: Bool { inlineCompletionEngine != nil }
    var inlineCompletionText: String? { activeInlineCompletion?.text }
    var vimMode: VimMode { vimController.mode }
    var currentText: String { textView.string }
    var statusText: String { statusLabel.stringValue }
    var isDirty: Bool { session.document.isDirty }
    var vimCommandLineText: String? { vimController.commandLineText }
    var vimPromptText: String? { vimController.promptText }
    var lspHoverText: String? { lspPresentation.hoverText }
    var lspCompletionItems: [LSPCompletionItem] { lspPresentation.completionItems }
    var lspDefinitionLocations: [LSPLocation] { lspPresentation.definitionLocations }
    var lspReferenceLocations: [LSPLocation] { lspPresentation.referenceLocations }
    var lspAccessoryText: String? { lspAccessoryLabel.isHidden ? nil : lspAccessoryLabel.stringValue }
    var lspResultItemTitles: [String] { lspPresentation.resultItemTitles }
    var onFileLoaded: ((URL) -> Void)?
    var onQuitRequested: (() -> Void)?
    var onLSPHoverRequested: ((LSPPosition) -> Void)?
    var onLSPCompletionRequested: ((LSPPosition) -> Void)?
    var onLSPDefinitionRequested: ((LSPPosition) -> Void)?
    var onLSPReferencesRequested: ((LSPPosition) -> Void)?
    var syntaxDecorationProvider: ((EditorDocument) -> [EditorDecoration])? {
        didSet {
            refreshSyntaxDecorations()
        }
    }

    @discardableResult
    func focusTextView() -> Bool {
        window?.makeFirstResponder(textView) ?? false
    }

    init(
        fileURL: URL? = nil,
        text: String = "",
        clipboardService: ClipboardServiceProtocol = SystemClipboardService()
    ) {
        self.fileURL = fileURL
        self.session = EditorSession(document: EditorDocument(fileURL: fileURL, text: text))
        self.scrollView = EditorScrollView(textView: textView)
        self.clipboardService = clipboardService
        super.init(frame: .zero)

        setupUI()
        wireCallbacks()

        if let fileURL {
            loadFile(fileURL)
        } else {
            applyText(text, preserveSelection: false)
            updateHeader()
        }
    }

    override func layout() {
        super.layout()
        applySoftWrapConfiguration()
        inlineGhostText.layout()
    }

    deinit {
        inlineCompletionTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorView does not support NSCoding")
    }

    func loadFile(_ url: URL) {
        fileURL = url
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            session = EditorSession(document: EditorDocument(fileURL: url, text: text))
            statusOverride = nil
            resetVimUndoState()
            clearLSPPresentation()
            dismissInlineCompletion()
            applyText(text, preserveSelection: false)
            refreshSyntaxDecorations()
            onFileLoaded?(url)
        } catch {
            session = EditorSession(document: EditorDocument(fileURL: url, text: ""))
            statusOverride = "Load failed"
            resetVimUndoState()
            clearLSPPresentation()
            dismissInlineCompletion()
            applyText("", preserveSelection: false)
            refreshSyntaxDecorations()
        }
        updateHeader()
    }

    func replaceText(_ text: String) {
        dismissInlineCompletion()
        applyText(text, preserveSelection: true)
        syncSessionFromTextView()
        resetVimUndoState()
    }

    func setSelection(_ selection: EditorSelection) {
        dismissInlineCompletion()
        let maximumLength = (textView.string as NSString).length
        let clamped = selection.clamped(to: maximumLength)
        session.setSelection(clamped)
        let nsRanges = clamped.normalizedRanges(maximumLength: maximumLength).map {
            NSValue(range: NSRange(location: $0.location, length: $0.length))
        }
        isApplyingProgrammaticUpdate = true
        textView.selectedRanges = nsRanges
        isApplyingProgrammaticUpdate = false
    }

    func insertTextAtSelections(_ text: String) {
        dismissInlineCompletion()
        let change = session.replaceSelection(with: text)
        statusOverride = nil
        applyText(change.afterText, preserveSelection: false)
        setSelection(change.selectionAfter)
        refreshSyntaxDecorations()
        updateHeader()
    }

    @discardableResult
    func handleTextInsertion(_ text: String) -> Bool {
        guard shouldUseDomainEditing else { return false }
        insertTextAtSelections(text)
        return true
    }

    @discardableResult
    func handleDeleteBackward() -> Bool {
        guard shouldUseDomainEditing else { return false }
        let change = session.deleteBackward()
        statusOverride = nil
        applyText(change.afterText, preserveSelection: false)
        setSelection(change.selectionAfter)
        refreshSyntaxDecorations()
        updateHeader()
        return true
    }

    @discardableResult
    func handleAdditiveCursor(atUTF16Offset offset: Int) -> Bool {
        let maximumLength = (textView.string as NSString).length
        let clampedOffset = min(max(0, offset), maximumLength)
        let requestedRange = EditorTextRange(location: clampedOffset, length: 0)
        let ranges = session.selection.normalizedRanges(maximumLength: maximumLength) + [requestedRange]
        let normalizedRanges = EditorSelection(ranges: ranges)
            .normalizedRanges(maximumLength: maximumLength)
        let primaryIndex = normalizedRanges.firstIndex { $0.contains(clampedOffset) }
            ?? max(0, normalizedRanges.count - 1)

        setSelection(EditorSelection(ranges: normalizedRanges, primaryIndex: primaryIndex))
        return true
    }

    func setSoftWrapEnabled(_ enabled: Bool) {
        isSoftWrapEnabled = enabled
        applySoftWrapConfiguration()
    }

    func setVimModeEnabled(_ enabled: Bool) {
        isVimModeEnabled = enabled
    }

    func setInlineCompletionEngine(_ engine: CompletionEngine?) {
        cancelInlineCompletionTask()
        inlineCompletionEngine = engine
        dismissInlineCompletion()
    }

    @discardableResult
    func requestInlineCompletion(idleDuration: TimeInterval? = nil, insertedText: String? = nil) -> Bool {
        guard let engine = inlineCompletionEngine,
              let languageID = currentCompletionLanguageID()
        else {
            return false
        }

        let requestID = nextInlineCompletionRequestID()
        let input = CompletionTriggerInput(
            document: session.document,
            selection: session.selection,
            languageID: languageID,
            idleDuration: idleDuration ?? engine.config.idleDelaySeconds,
            insertedText: insertedText
        )

        inlineCompletionTask?.cancel()
        inlineCompletionTask = Task { [weak self] in
            do {
                let suggestion = try await engine.suggestion(for: input)
                await MainActor.run {
                    self?.applyInlineCompletionResult(suggestion, requestID: requestID)
                }
            } catch {
                await MainActor.run {
                    self?.applyInlineCompletionResult(nil, requestID: requestID)
                }
            }
        }
        return true
    }

    @discardableResult
    func showInlineCompletion(_ completion: InlineCompletion) -> Bool {
        let clampedRange = completion.replacementRange.clamped(to: session.document.buffer.utf16Length)
        guard !completion.text.isEmpty,
              session.selection.ranges.count == 1,
              session.selection.primaryRange.isCaret,
              session.selection.primaryRange.location == clampedRange.location
        else {
            dismissInlineCompletion()
            return false
        }

        let normalized = InlineCompletion(
            text: completion.text,
            replacementRange: clampedRange,
            source: completion.source
        )
        activeInlineCompletion = normalized
        inlineGhostText.show(
            text: normalized.text,
            atUTF16Location: normalized.replacementRange.location,
            in: textView
        )
        return true
    }

    @discardableResult
    func dismissInlineCompletion() -> Bool {
        cancelInlineCompletionTask()
        let hadCompletion = activeInlineCompletion != nil
        activeInlineCompletion = nil
        inlineGhostText.hide()
        return hadCompletion
    }

    @discardableResult
    func acceptInlineCompletion() -> Bool {
        guard let completion = activeInlineCompletion,
              let replacement = CompletionAcceptHandler().replacement(
                for: completion,
                document: session.document
              )
        else {
            return false
        }

        dismissInlineCompletion()
        let change = session.apply(replacement)
        statusOverride = nil
        applyText(change.afterText, preserveSelection: false)
        setSelection(change.selectionAfter)
        refreshSyntaxDecorations()
        updateHeader()
        return true
    }

    @discardableResult
    func handleVimInput(_ input: VimInput) -> Bool {
        guard isVimModeEnabled else { return false }
        let beforeMode = vimController.mode
        let beforeSnapshot = currentEditorUndoSnapshot()
        let result = vimController.handle(
            input,
            session: &session,
            systemRegisters: makeVimSystemRegisterAccess()
        )
        guard result.handled else { return false }
        let afterMode = vimController.mode
        let textChanged = beforeSnapshot.text != session.document.buffer.text

        if let editCommand = result.editCommand {
            let restoredText = performVimEditCommand(editCommand)
            applySessionToTextView()
            if restoredText {
                statusOverride = nil
                clearSearchDecorations()
                refreshSyntaxDecorations()
            }
            updateHeader()
            return true
        }

        if let fileCommand = result.fileCommand {
            _ = performVimFileCommand(fileCommand)
            return true
        }

        updateVimUndoTracking(
            beforeSnapshot: beforeSnapshot,
            beforeMode: beforeMode,
            afterMode: afterMode,
            textChanged: textChanged
        )

        applySessionToTextView()
        if textChanged {
            statusOverride = nil
            clearSearchDecorations()
            refreshSyntaxDecorations()
        }
        updateHeader()
        if let searchHighlightQuery = result.searchHighlightQuery {
            replaceSearchDecorations(for: searchHighlightQuery)
        }
        if let exCommand = result.exCommand {
            executeVimExCommand(exCommand)
        }
        return true
    }

    private func currentEditorUndoSnapshot() -> EditorUndoSnapshot {
        EditorUndoSnapshot(
            text: session.document.buffer.text,
            selection: session.selection
        )
    }

    private func resetVimUndoState() {
        vimUndoStack.removeAll()
        vimRedoStack.removeAll()
        pendingVimUndoStart = nil
        pendingVimUndoChanged = false
    }

    private func updateVimUndoTracking(
        beforeSnapshot: EditorUndoSnapshot,
        beforeMode: VimMode,
        afterMode: VimMode,
        textChanged: Bool
    ) {
        if pendingVimUndoStart == nil,
           shouldGroupVimUndo(beforeMode: beforeMode, afterMode: afterMode, textChanged: textChanged) {
            pendingVimUndoStart = beforeSnapshot
        }

        if textChanged {
            if pendingVimUndoStart != nil {
                pendingVimUndoChanged = true
            } else {
                pushVimUndoEntry(before: beforeSnapshot, after: currentEditorUndoSnapshot())
            }
        }

        if shouldFinishGroupedVimUndo(beforeMode: beforeMode, afterMode: afterMode) {
            finishPendingVimUndo()
        }
    }

    private func shouldGroupVimUndo(beforeMode: VimMode, afterMode: VimMode, textChanged: Bool) -> Bool {
        isGroupedVimUndoMode(afterMode) && (beforeMode != afterMode || textChanged)
    }

    private func shouldFinishGroupedVimUndo(beforeMode: VimMode, afterMode: VimMode) -> Bool {
        isGroupedVimUndoMode(beforeMode) && !isGroupedVimUndoMode(afterMode)
    }

    private func isGroupedVimUndoMode(_ mode: VimMode) -> Bool {
        mode == .insert || mode == .replace
    }

    private func finishPendingVimUndo() {
        guard let before = pendingVimUndoStart else { return }
        defer {
            pendingVimUndoStart = nil
            pendingVimUndoChanged = false
        }

        let after = currentEditorUndoSnapshot()
        guard pendingVimUndoChanged, before.text != after.text else { return }
        pushVimUndoEntry(before: before, after: after)
    }

    private func pushVimUndoEntry(before: EditorUndoSnapshot, after: EditorUndoSnapshot) {
        guard before.text != after.text else { return }
        vimUndoStack.append(EditorUndoEntry(before: before, after: after))
        vimRedoStack.removeAll()
    }

    @discardableResult
    private func performVimEditCommand(_ command: VimEditCommand) -> Bool {
        finishPendingVimUndo()
        switch command {
        case .undo:
            guard let entry = vimUndoStack.popLast() else { return false }
            vimRedoStack.append(entry)
            restoreEditorUndoSnapshot(entry.before)
            return true
        case .redo:
            guard let entry = vimRedoStack.popLast() else { return false }
            vimUndoStack.append(entry)
            restoreEditorUndoSnapshot(entry.after)
            return true
        }
    }

    private func restoreEditorUndoSnapshot(_ snapshot: EditorUndoSnapshot) {
        session.replaceAllText(with: snapshot.text)
        session.setSelection(snapshot.selection.clamped(to: session.document.buffer.utf16Length))
    }

    @discardableResult
    private func performVimFileCommand(_ command: VimFileCommand) -> Bool {
        finishPendingVimUndo()
        switch command {
        case let .openFileAtMark(url, offset, lineWise):
            guard FileManager.default.fileExists(atPath: url.path) else {
                statusOverride = "Mark file missing"
                updateHeader()
                return false
            }

            loadFile(url)
            let buffer = session.document.buffer
            let safeOffset = min(max(0, offset), buffer.utf16Length)
            let targetOffset = lineWise
                ? firstNonblankOffset(containing: safeOffset, in: buffer)
                : safeOffset
            setSelection(.caret(at: targetOffset))
            textView.scrollRangeToVisible(NSRange(location: targetOffset, length: 0))
            return true
        }
    }

    private func firstNonblankOffset(containing offset: Int, in buffer: EditorBuffer) -> Int {
        let nsText = buffer.text as NSString
        guard nsText.length > 0 else { return 0 }

        let safeOffset = min(max(0, offset), nsText.length)
        let lineRange = buffer.lineRange(containing: safeOffset)
        let lineStart = min(max(0, lineRange.location), nsText.length)
        let lineEnd = min(nsText.length, lineRange.location + lineRange.length)

        var index = lineStart
        while index < lineEnd {
            let character = nsText.character(at: index)
            if character == 10 || character == 13 {
                break
            }
            if !isVimWhitespace(character) {
                return index
            }
            index += 1
        }
        return lineStart
    }

    private func isVimWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 10 || character == 13 || character == 32
    }

    private func makeVimSystemRegisterAccess() -> VimSystemRegisterAccess {
        VimSystemRegisterAccess(
            read: { [clipboardService] _ in
                MainActor.assumeIsolated {
                    clipboardService.read()
                }
            },
            write: { [clipboardService] text, _ in
                MainActor.assumeIsolated {
                    clipboardService.write(text)
                }
            }
        )
    }

    func replaceDecorations(kind: EditorDecorationKind, with decorations: [EditorDecoration]) {
        session.replaceDecorations(kind: kind, with: decorations)
        applyDecorations()
    }

    func lspDocumentSnapshot(languageID: String) -> LSPDocumentSnapshot? {
        guard let fileURL else { return nil }
        return LSPDocumentSnapshot(
            uri: fileURL.absoluteString,
            languageID: languageID,
            version: session.document.version,
            text: currentText
        )
    }

    func applyLSPClientEvent(_ event: LSPClientEvent) {
        switch event {
        case let .diagnostics(uri, diagnostics):
            guard uri == fileURL?.absoluteString else { return }
            replaceDecorations(
                kind: .diagnostic,
                with: LSPEditorBridge.decorations(
                    from: diagnostics,
                    in: session.document.buffer,
                    uri: uri
                )
            )
        case .hover, .completion, .definition, .references:
            lspPresentation.apply(event)
            renderLSPPresentation()
        }
    }

    func setLSPControlsEnabled(_ enabled: Bool) {
        isLSPControlsEnabled = enabled
        renderLSPControls()
    }

    @discardableResult
    func requestLSPHoverAtSelection() -> Bool {
        requestLSPPosition(onLSPHoverRequested)
    }

    @discardableResult
    func requestLSPCompletionAtSelection() -> Bool {
        requestLSPPosition(onLSPCompletionRequested)
    }

    @discardableResult
    func requestLSPDefinitionAtSelection() -> Bool {
        requestLSPPosition(onLSPDefinitionRequested)
    }

    @discardableResult
    func requestLSPReferencesAtSelection() -> Bool {
        requestLSPPosition(onLSPReferencesRequested)
    }

    @discardableResult
    func acceptLSPCompletion(at index: Int) -> Bool {
        guard lspPresentation.completionItems.indices.contains(index) else { return false }
        let item = lspPresentation.completionItems[index]
        let insertion = item.insertText.flatMap { $0.isEmpty ? nil : $0 } ?? item.label
        insertTextAtSelections(insertion)
        lspPresentation.completionItems = []
        renderLSPPresentation()
        return true
    }

    @discardableResult
    func goToLSPDefinition(at index: Int) -> Bool {
        guard lspPresentation.definitionLocations.indices.contains(index) else { return false }
        return jumpToLSPLocation(lspPresentation.definitionLocations[index])
    }

    @discardableResult
    func goToLSPReference(at index: Int) -> Bool {
        guard lspPresentation.referenceLocations.indices.contains(index) else { return false }
        return jumpToLSPLocation(lspPresentation.referenceLocations[index])
    }

    func saveNow() throws {
        guard let fileURL else { throw SaveError.missingFileURL }
        try currentText.write(to: fileURL, atomically: true, encoding: .utf8)
        session.markSaved()
        statusOverride = nil
        updateHeader()
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticUpdate else { return }
        dismissInlineCompletion()
        syncSessionFromTextView()
        scheduleInlineCompletion(insertedText: nil)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticUpdate else { return }
        dismissInlineCompletion()
        session.setSelection(EditorSelectionLayer.selection(from: textView))
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        configureIconButton(openButton, symbolName: "folder", tooltip: "Open File", action: #selector(openButtonPressed))
        configureIconButton(saveButton, symbolName: "square.and.arrow.down", tooltip: "Save", action: #selector(saveButtonPressed))
        configureIconButton(lspHoverButton, symbolName: "info.circle", tooltip: "Show Hover", action: #selector(lspHoverButtonPressed))
        configureIconButton(lspCompletionButton, symbolName: "wand.and.stars", tooltip: "Show Completions", action: #selector(lspCompletionButtonPressed))
        configureIconButton(lspDefinitionButton, symbolName: "arrowshape.turn.up.right", tooltip: "Go to Definition", action: #selector(lspDefinitionButtonPressed))
        configureIconButton(lspReferencesButton, symbolName: "number", tooltip: "Find References", action: #selector(lspReferencesButtonPressed))

        fileNameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        fileNameLabel.textColor = CocxyColors.text
        fileNameLabel.lineBreakMode = .byTruncatingMiddle

        lspAccessoryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        lspAccessoryLabel.textColor = CocxyColors.overlay1
        lspAccessoryLabel.lineBreakMode = .byTruncatingMiddle
        lspAccessoryLabel.isHidden = true
        lspAccessoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = CocxyColors.overlay1
        statusLabel.alignment = .right

        configureIconButton(
            lspPrimaryActionButton,
            symbolName: "arrow.right.circle",
            tooltip: "Apply Suggestion",
            action: #selector(lspPrimaryActionPressed)
        )
        lspPrimaryActionButton.isHidden = true

        toolbar.addArrangedSubview(openButton)
        toolbar.addArrangedSubview(saveButton)
        toolbar.addArrangedSubview(fileNameLabel)
        toolbar.addArrangedSubview(lspHoverButton)
        toolbar.addArrangedSubview(lspCompletionButton)
        toolbar.addArrangedSubview(lspDefinitionButton)
        toolbar.addArrangedSubview(lspReferencesButton)
        toolbar.addArrangedSubview(lspAccessoryLabel)
        toolbar.addArrangedSubview(lspPrimaryActionButton)
        toolbar.addArrangedSubview(statusLabel)

        fileNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lspAccessoryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        textView.applyDefaultConfiguration()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        renderLSPControls()
        applySoftWrapConfiguration()
    }

    private func wireCallbacks() {
        textView.delegate = self
        textView.saveHandler = { [weak self] in
            try? self?.saveNow()
        }
        textView.keyDownHandler = { [weak self] input in
            self?.handleVimInput(input) ?? false
        }
        textView.insertTextHandler = { [weak self] text in
            self?.handleTextInsertion(text) ?? false
        }
        textView.deleteBackwardHandler = { [weak self] in
            self?.handleDeleteBackward() ?? false
        }
        textView.additiveCursorHandler = { [weak self] offset in
            self?.handleAdditiveCursor(atUTF16Offset: offset) ?? false
        }
        textView.inlineCompletionKeyHandler = { [weak self] command in
            self?.handleInlineCompletionCommand(command) ?? false
        }
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, tooltip: String, action: Selector) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            button.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        }
        button.contentTintColor = CocxyColors.overlay1
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func applyText(_ text: String, preserveSelection: Bool) {
        let selectedRange = textView.selectedRange()
        isApplyingProgrammaticUpdate = true
        textView.string = text
        if preserveSelection {
            let maxLength = (text as NSString).length
            textView.setSelectedRange(NSRange(
                location: min(selectedRange.location, maxLength),
                length: min(selectedRange.length, max(0, maxLength - min(selectedRange.location, maxLength)))
            ))
        } else {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
        isApplyingProgrammaticUpdate = false
        applyDecorations()
    }

    private func applySessionToTextView() {
        isApplyingProgrammaticUpdate = true
        if textView.string != session.document.buffer.text {
            textView.string = session.document.buffer.text
        }
        let maximumLength = (textView.string as NSString).length
        textView.selectedRanges = session.selection
            .clamped(to: maximumLength)
            .normalizedRanges(maximumLength: maximumLength)
            .map { NSValue(range: NSRange(location: $0.location, length: $0.length)) }
        isApplyingProgrammaticUpdate = false
        applyDecorations()
    }

    private func clearLSPPresentation() {
        lspPresentation.clearDocumentScopedState()
        renderLSPPresentation()
    }

    private func renderLSPPresentation() {
        let text = lspPresentation.accessoryText
        lspAccessoryLabel.stringValue = text ?? ""
        lspAccessoryLabel.isHidden = text == nil
        lspPrimaryActionButton.isHidden = !hasLSPPrimaryAction
        rebuildLSPResultsMenu()
        renderLSPControls()
    }

    private func renderLSPControls() {
        let controls = [lspHoverButton, lspCompletionButton, lspDefinitionButton, lspReferencesButton]
        controls.forEach { $0.isHidden = !isLSPControlsEnabled }
        lspPrimaryActionButton.isEnabled = isLSPControlsEnabled && hasLSPPrimaryAction
    }

    private func rebuildLSPResultsMenu() {
        lspResultsMenu.removeAllItems()
        for (index, title) in lspPresentation.resultItemTitles.enumerated() {
            let item = NSMenuItem(
                title: title,
                action: #selector(lspResultMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            lspResultsMenu.addItem(item)
        }
    }

    private var hasLSPPrimaryAction: Bool {
        !lspPresentation.completionItems.isEmpty
            || !lspPresentation.definitionLocations.isEmpty
            || !lspPresentation.referenceLocations.isEmpty
    }

    @objc private func lspPrimaryActionPressed() {
        if lspResultsMenu.items.count > 1 {
            lspResultsMenu.popUp(
                positioning: lspResultsMenu.items.first,
                at: NSPoint(x: 0, y: lspPrimaryActionButton.bounds.height),
                in: lspPrimaryActionButton
            )
            return
        }
        performLSPResultAction(at: 0)
    }

    @objc private func lspResultMenuItemSelected(_ sender: NSMenuItem) {
        performLSPResultAction(at: sender.tag)
    }

    private func performLSPResultAction(at index: Int) {
        if !lspPresentation.completionItems.isEmpty {
            _ = acceptLSPCompletion(at: index)
        } else if !lspPresentation.definitionLocations.isEmpty {
            _ = goToLSPDefinition(at: index)
        } else if !lspPresentation.referenceLocations.isEmpty {
            _ = goToLSPReference(at: index)
        }
    }

    @objc private func lspHoverButtonPressed() {
        _ = requestLSPHoverAtSelection()
    }

    @objc private func lspCompletionButtonPressed() {
        _ = requestLSPCompletionAtSelection()
    }

    @objc private func lspDefinitionButtonPressed() {
        _ = requestLSPDefinitionAtSelection()
    }

    @objc private func lspReferencesButtonPressed() {
        _ = requestLSPReferencesAtSelection()
    }

    private func requestLSPPosition(_ handler: ((LSPPosition) -> Void)?) -> Bool {
        guard isLSPControlsEnabled,
              let handler,
              let position = currentLSPPosition() else {
            return false
        }
        handler(position)
        return true
    }

    private func currentLSPPosition() -> LSPPosition? {
        let buffer = session.document.buffer
        let range = session.selection.primaryRange.clamped(to: buffer.utf16Length)
        let lineColumn = buffer.lineAndColumn(for: range.location)
        return LSPPosition(line: lineColumn.line, character: lineColumn.column)
    }

    private func jumpToLSPLocation(_ location: LSPLocation) -> Bool {
        guard let url = URL(string: location.uri), url.isFileURL else {
            return false
        }

        if fileURL?.absoluteString != location.uri {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return false
            }
            loadFile(url)
        }

        let buffer = session.document.buffer
        let startOffset = buffer.offset(
            line: location.range.start.line,
            column: location.range.start.character
        )
        let endOffset = buffer.offset(
            line: location.range.end.line,
            column: location.range.end.character
        )
        let selection = EditorTextRange(
            location: min(startOffset, endOffset),
            length: abs(endOffset - startOffset)
        )
        setSelection(EditorSelection(ranges: [selection]))
        textView.scrollRangeToVisible(NSRange(location: selection.location, length: selection.length))
        return true
    }

    private func syncSessionFromTextView() {
        statusOverride = nil
        session.setSelection(EditorSelectionLayer.selection(from: textView))
        session.replaceAllText(with: textView.string)
        updateHeader()
        refreshSyntaxDecorations()
    }

    private func handleInlineCompletionCommand(_ command: EditorTextKeyCommand) -> Bool {
        switch command {
        case .tab:
            return acceptInlineCompletion()
        case .escape:
            return dismissInlineCompletion()
        }
    }

    private func scheduleInlineCompletion(insertedText: String?) {
        guard let engine = inlineCompletionEngine else { return }
        cancelInlineCompletionTask()
        let delay = max(0, engine.config.idleDelaySeconds)
        inlineCompletionTask = Task { [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                _ = self?.requestInlineCompletion(
                    idleDuration: delay,
                    insertedText: insertedText
                )
            }
        }
    }

    private func applyInlineCompletionResult(_ completion: InlineCompletion?, requestID: Int) {
        guard requestID == inlineCompletionRequestID else { return }
        guard let completion else {
            dismissInlineCompletion()
            return
        }
        _ = showInlineCompletion(completion)
    }

    private func nextInlineCompletionRequestID() -> Int {
        inlineCompletionRequestID += 1
        return inlineCompletionRequestID
    }

    private func cancelInlineCompletionTask() {
        inlineCompletionRequestID += 1
        inlineCompletionTask?.cancel()
        inlineCompletionTask = nil
    }

    private func currentCompletionLanguageID() -> String? {
        guard let fileURL else { return nil }
        if let server = LSPLanguageRegistry.defaults.server(forFileURL: fileURL) {
            return server.languageID
        }

        switch fileURL.pathExtension.lowercased() {
        case "c", "h":
            return "c"
        case "cc", "cpp", "cxx", "hpp", "hxx":
            return "cpp"
        case "go":
            return "go"
        case "js", "jsx", "mjs", "cjs":
            return "javascript"
        case "py":
            return "python"
        case "rs":
            return "rust"
        case "swift":
            return "swift"
        case "ts", "tsx":
            return "typescript"
        case "zig":
            return "zig"
        default:
            return nil
        }
    }

    private func refreshSyntaxDecorations() {
        let decorations = syntaxDecorationProvider?(session.document) ?? []
        session.replaceDecorations(kind: .syntaxToken, with: decorations)
        applyDecorations()
    }

    private func applyDecorations() {
        guard let textStorage = textView.textStorage else { return }
        let length = (textView.string as NSString).length
        EditorDecorationLayer.apply(session.decorations, to: textStorage, textLength: length)
    }

    private func applySoftWrapConfiguration() {
        scrollView.hasHorizontalScroller = !isSoftWrapEnabled
        textView.isHorizontallyResizable = !isSoftWrapEnabled
        textView.textContainer?.widthTracksTextView = isSoftWrapEnabled
        if isSoftWrapEnabled {
            let width = max(0, scrollView.contentSize.width)
            textView.textContainer?.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private var shouldUseDomainEditing: Bool {
        let length = (textView.string as NSString).length
        return session.selection.normalizedRanges(maximumLength: length).count > 1
    }

    private func updateHeader() {
        fileNameLabel.stringValue = fileURL?.lastPathComponent ?? "Untitled"
        if let vimPromptText {
            statusLabel.stringValue = vimPromptText
        } else {
            statusLabel.stringValue = statusOverride ?? (isDirty ? "Edited" : "Saved")
        }
        saveButton.isEnabled = fileURL != nil && isDirty
    }

    private func executeVimExCommand(_ command: VimExCommand) {
        switch command {
        case .write:
            do {
                try saveNow()
                statusOverride = "Written"
            } catch {
                statusOverride = "Write failed"
            }
            updateHeader()
        case .quit:
            if isDirty {
                statusOverride = "No write since last change"
                updateHeader()
            } else {
                onQuitRequested?()
            }
        case .writeQuit:
            do {
                try saveNow()
                statusOverride = "Written"
                updateHeader()
                onQuitRequested?()
            } catch {
                statusOverride = "Write failed"
                updateHeader()
            }
        case .clearSearchHighlights:
            clearSearchDecorations()
        case .setSoftWrap(let enabled):
            setSoftWrapEnabled(enabled)
        case .toggleSoftWrap:
            setSoftWrapEnabled(!isSoftWrapEnabled)
        case .reportSoftWrap:
            statusOverride = isSoftWrapEnabled ? "wrap" : "nowrap"
            updateHeader()
        }
    }

    private func replaceSearchDecorations(for query: String) {
        guard !query.isEmpty else {
            clearSearchDecorations()
            return
        }

        let text = textView.string as NSString
        var searchRange = NSRange(location: 0, length: text.length)
        var decorations: [EditorDecoration] = []

        while searchRange.length > 0 {
            let match = text.range(of: query, options: [], range: searchRange)
            guard match.location != NSNotFound, match.length > 0 else { break }
            decorations.append(EditorDecoration(
                id: "vim.search.\(decorations.count)",
                range: EditorTextRange(location: match.location, length: match.length),
                kind: .searchResult
            ))

            let nextLocation = match.location + match.length
            searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
        }

        session.replaceDecorations(kind: .searchResult, with: decorations)
        applyDecorations()
    }

    private func clearSearchDecorations() {
        session.replaceDecorations(kind: .searchResult, with: [])
        applyDecorations()
    }

    @objc private func saveButtonPressed() {
        try? saveNow()
    }

    @objc private func openButtonPressed() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = fileURL?.deletingLastPathComponent()

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadFile(url)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}
