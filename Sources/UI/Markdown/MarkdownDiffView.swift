// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownDiffView.swift - Displays git diff output for a markdown file.

import AppKit

// MARK: - Diff View

/// View that displays git diff hunks for the current markdown file.
///
/// Shows additions in green, deletions in red, and context lines in the
/// default text color. Each hunk is separated by its header.
@MainActor
final class MarkdownDiffView: NSView {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let emptyLabel = NSTextField(labelWithString: "No changes detected")

    /// Sets the diff hunks to display.
    var hunks: [GitDiffHunk] = [] {
        didSet { renderDiff() }
    }

    /// Sets blame lines to display. Clears diff hunks.
    var blameLines: [GitBlameLine] = [] {
        didSet { renderBlame() }
    }

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownDiffView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        scrollView.documentView = textView

        emptyLabel.font = .systemFont(ofSize: 13, weight: .regular)
        emptyLabel.textColor = CocxyColors.subtext0
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // MARK: - Rendering

    private func renderDiff() {
        if hunks.isEmpty {
            textView.string = ""
            emptyLabel.stringValue = "No changes detected"
            emptyLabel.isHidden = false
            return
        }

        emptyLabel.isHidden = true

        let result = NSMutableAttributedString()
        let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        for (hunkIndex, hunk) in hunks.enumerated() {
            if hunkIndex > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            // Hunk header
            result.append(NSAttributedString(string: hunk.header + "\n", attributes: [
                .font: codeFont,
                .foregroundColor: CocxyColors.blue,
                .backgroundColor: CocxyColors.surface0.withAlphaComponent(0.5)
            ]))

            // Diff lines
            for diffLine in hunk.lines {
                let prefix: String
                let fgColor: NSColor
                let bgColor: NSColor

                switch diffLine.type {
                case .addition:
                    prefix = "+ "
                    fgColor = CocxyColors.green
                    bgColor = CocxyColors.green.withAlphaComponent(0.08)
                case .deletion:
                    prefix = "- "
                    fgColor = CocxyColors.red
                    bgColor = CocxyColors.red.withAlphaComponent(0.08)
                case .context:
                    prefix = "  "
                    fgColor = CocxyColors.subtext0
                    bgColor = .clear
                }

                result.append(NSAttributedString(string: prefix + diffLine.text + "\n", attributes: [
                    .font: codeFont,
                    .foregroundColor: fgColor,
                    .backgroundColor: bgColor
                ]))
            }
        }

        textView.textStorage?.setAttributedString(result)
    }

    private func renderBlame() {
        if blameLines.isEmpty {
            textView.string = ""
            emptyLabel.stringValue = "No blame data (file not tracked or not in a git repository)"
            emptyLabel.isHidden = false
            return
        }

        emptyLabel.isHidden = true

        let result = NSMutableAttributedString()
        let codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let metaFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

        // Compute column widths for alignment
        let maxAuthorLen = min(16, blameLines.map(\.author.count).max() ?? 0)

        // Header
        let authorCount = Set(blameLines.map(\.author)).count
        let commitCount = Set(blameLines.map(\.commitHash)).count
        let summary = "\(blameLines.count) lines · \(authorCount) authors · \(commitCount) commits\n\n"
        result.append(NSAttributedString(string: summary, attributes: [
            .font: metaFont,
            .foregroundColor: CocxyColors.blue
        ]))

        for line in blameLines {
            let paddedAuthor = String(line.author.prefix(maxAuthorLen))
                .padding(toLength: maxAuthorLen, withPad: " ", startingAt: 0)

            // Blame metadata (hash, author, date)
            let meta = "\(line.commitHash)  \(paddedAuthor)  \(line.date)  "
            result.append(NSAttributedString(string: meta, attributes: [
                .font: metaFont,
                .foregroundColor: CocxyColors.subtext0
            ]))

            // Line content
            result.append(NSAttributedString(string: line.content + "\n", attributes: [
                .font: codeFont,
                .foregroundColor: CocxyColors.text
            ]))
        }

        textView.textStorage?.setAttributedString(result)
    }
}
