// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownContentView.swift - Embeddable markdown viewer for workspace splits.

import AppKit

// MARK: - Markdown Content View

/// NSView that renders markdown content for embedding in split panes.
///
/// Displays a markdown file using an `NSTextView` with basic formatting.
/// Supports loading from a file URL and live-reload when the file changes.
///
/// ## Layout
///
/// ```
/// +----------------------------------+
/// | [file icon] filename.md      [R] |  <- 32pt header
/// +----------------------------------+
/// |                                  |
/// |     Rendered markdown text       |
/// |                                  |
/// +----------------------------------+
/// ```
///
/// - SeeAlso: `PanelType.markdown`
@MainActor
final class MarkdownContentView: NSView {

    // MARK: - Properties

    /// The file being displayed.
    private(set) var filePath: URL?

    /// The text view showing rendered content.
    private var textView: NSTextView?

    /// The scroll view wrapping the text view.
    private var scrollView: NSScrollView?

    /// The file name label in the header.
    private var fileNameLabel: NSTextField?

    /// File system monitor for live-reload.
    private var fileMonitor: DispatchSourceFileSystemObject?

    /// Height of the header bar.
    private static let headerHeight: CGFloat = 32

    // MARK: - Initialization

    init(filePath: URL? = nil) {
        self.filePath = filePath
        super.init(frame: .zero)
        setupUI()
        if let path = filePath {
            loadFile(path)
        } else {
            showEmptyState()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownContentView does not support NSCoding")
    }

    deinit {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    // MARK: - UI Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        // Header bar.
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = CocxyColors.mantle.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        // File icon.
        let iconView = NSImageView()
        if let image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Markdown") {
            iconView.image = image.withSymbolConfiguration(
                .init(pointSize: 12, weight: .medium)
            )
        }
        iconView.contentTintColor = CocxyColors.blue
        iconView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(iconView)

        // File name label.
        let label = NSTextField(labelWithString: "Untitled.md")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = CocxyColors.text
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        self.fileNameLabel = label

        // Reload button.
        let reloadButton = NSButton()
        reloadButton.bezelStyle = .accessoryBarAction
        reloadButton.isBordered = false
        if let image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
            reloadButton.image = image.withSymbolConfiguration(
                .init(pointSize: 12, weight: .medium)
            )
        }
        reloadButton.contentTintColor = CocxyColors.subtext0
        reloadButton.target = self
        reloadButton.action = #selector(reloadAction)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(reloadButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: reloadButton.leadingAnchor, constant: -8),

            reloadButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -4),
            reloadButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 24),
            reloadButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Scroll view + text view.
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sv)
        self.scrollView = sv

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.backgroundColor = CocxyColors.base
        tv.textColor = CocxyColors.text
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 16, height: 12)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        sv.documentView = tv
        self.textView = tv

        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: header.bottomAnchor),
            sv.leadingAnchor.constraint(equalTo: leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - File Loading

    /// Loads and renders a markdown file.
    ///
    /// - Parameter url: The file URL of the markdown document.
    func loadFile(_ url: URL) {
        self.filePath = url
        fileNameLabel?.stringValue = url.lastPathComponent

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            textView?.string = "Failed to load file: \(url.lastPathComponent)"
            return
        }

        renderMarkdown(content)
        watchFileChanges(url)
    }

    /// Renders raw markdown text with basic formatting.
    private func renderMarkdown(_ text: String) {
        let attributed = NSMutableAttributedString()
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let headingFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        let h2Font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let attrs: [NSAttributedString.Key: Any]
            if line.hasPrefix("# ") {
                attrs = [.font: headingFont, .foregroundColor: CocxyColors.blue,
                         .paragraphStyle: paragraphStyle]
            } else if line.hasPrefix("## ") {
                attrs = [.font: h2Font, .foregroundColor: CocxyColors.mauve,
                         .paragraphStyle: paragraphStyle]
            } else if line.hasPrefix("### ") {
                attrs = [.font: h2Font, .foregroundColor: CocxyColors.teal,
                         .paragraphStyle: paragraphStyle]
            } else if line.hasPrefix("```") || line.hasPrefix("    ") {
                attrs = [.font: codeFont, .foregroundColor: CocxyColors.green,
                         .backgroundColor: CocxyColors.surface0,
                         .paragraphStyle: paragraphStyle]
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                attrs = [.font: bodyFont, .foregroundColor: CocxyColors.text,
                         .paragraphStyle: paragraphStyle]
            } else {
                attrs = [.font: bodyFont, .foregroundColor: CocxyColors.text,
                         .paragraphStyle: paragraphStyle]
            }
            attributed.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }

        textView?.textStorage?.setAttributedString(attributed)
    }

    /// Shows a placeholder when no file is loaded.
    private func showEmptyState() {
        fileNameLabel?.stringValue = "No file"
        textView?.string = "Drop a .md file here or open one from the Command Palette."
    }

    // MARK: - File Watching

    private func watchFileChanges(_ url: URL) {
        fileMonitor?.cancel()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.loadFile(url)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.fileMonitor = source
    }

    // MARK: - Actions

    @objc private func reloadAction(_ sender: Any?) {
        guard let path = filePath else { return }
        loadFile(path)
    }
}
