// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownContentView+Actions.swift - Export, Git, and Drag & Drop actions.

import AppKit

// MARK: - Git Blame & Diff

extension MarkdownContentView {

    func toggleBlame() {
        guard let fileURL = filePath else { return }

        if isBlameVisible {
            isBlameVisible = false
            gitRequestGeneration &+= 1
            applyMode()
            return
        }

        gitRequestGeneration &+= 1
        let generation = gitRequestGeneration

        MarkdownGitService.blame(fileURL: fileURL) { blameLines in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.gitRequestGeneration == generation else { return }

                self.diffView.blameLines = blameLines
                self.isBlameVisible = true
                self.isDiffVisible = false

                self.contentContainer.subviews.forEach { $0.removeFromSuperview() }
                self.embed(self.diffView, in: self.contentContainer)
            }
        }
    }

    func toggleDiff() {
        guard let fileURL = filePath else { return }

        if isDiffVisible {
            isDiffVisible = false
            gitRequestGeneration &+= 1
            applyMode()
            return
        }

        gitRequestGeneration &+= 1
        let generation = gitRequestGeneration

        MarkdownGitService.diff(fileURL: fileURL) { hunks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.gitRequestGeneration == generation else { return }

                self.diffView.hunks = hunks
                self.isDiffVisible = true
                self.isBlameVisible = false

                self.contentContainer.subviews.forEach { $0.removeFromSuperview() }
                self.embed(self.diffView, in: self.contentContainer)
            }
        }
    }
}

// MARK: - Export

extension MarkdownContentView {

    func exportPDF() {
        // If the template is reloading (e.g., after a directory change),
        // defer the export until it finishes loading.
        guard previewView.isReady else {
            previewView.whenReady { [weak self] in self?.exportPDF() }
            return
        }
        guard let printOp = previewView.createPrintOperation() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultExportName(extension: "pdf")
        panel.beginSheetModal(for: window ?? NSApp.mainWindow ?? NSWindow()) { response in
            guard response == .OK, let url = panel.url else { return }
            printOp.printInfo.dictionary()[NSPrintInfo.AttributeKey("NSPrintSaveJob")] = url.path
            printOp.showsPrintPanel = false
            printOp.showsProgressPanel = true
            printOp.run()
        }
    }

    func exportHTML() {
        let baseDir = filePath?.deletingLastPathComponent()

        previewView.captureRenderedHTML { [weak self] html in
            guard let self, let rawHTML = html else { return }

            // Inline local images as base64 data URIs for a truly standalone export.
            let standalone: String
            if let baseDir {
                standalone = MarkdownImageInliner.inlineLocalImages(in: rawHTML, baseDirectory: baseDir)
            } else {
                standalone = rawHTML
            }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = self.defaultExportName(extension: "html")
            panel.beginSheetModal(for: self.window ?? NSApp.mainWindow ?? NSWindow()) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try standalone.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    NSLog("Export HTML failed: %@", String(describing: error))
                }
            }
        }
    }

    func exportSlides() {
        var html = MarkdownSlideExporter.export(
            document: document,
            mermaidJS: previewView.loadResourceFile(named: "mermaid.min", ext: "js"),
            katexJS: previewView.loadResourceFile(named: "katex.min", ext: "js"),
            katexCSS: previewView.loadResourceFile(named: "katex.min", ext: "css"),
            autoRenderJS: previewView.loadResourceFile(named: "katex-auto-render.min", ext: "js")
        )

        // Inline local images for a truly standalone presentation file.
        if let baseDir = filePath?.deletingLastPathComponent() {
            html = MarkdownImageInliner.inlineLocalImages(in: html, baseDirectory: baseDir)
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = defaultExportName(extension: "slides.html")
        panel.beginSheetModal(for: window ?? NSApp.mainWindow ?? NSWindow()) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Export Slides failed: %@", String(describing: error))
            }
        }
    }

    func defaultExportName(extension ext: String) -> String {
        let baseName = filePath?.deletingPathExtension().lastPathComponent ?? "document"
        return "\(baseName).\(ext)"
    }
}

// MARK: - Drag & Drop

extension MarkdownContentView {

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let urls = fileURLsFromPasteboard(sender.draggingPasteboard) else {
            return []
        }
        let hasAcceptable = urls.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "md" || ext == "markdown" || Self.imageExtensions.contains(ext)
        }
        return hasAcceptable ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = fileURLsFromPasteboard(sender.draggingPasteboard) else {
            return false
        }

        var handled = false
        for url in urls {
            let ext = url.pathExtension.lowercased()

            if ext == "md" || ext == "markdown" {
                loadFile(url)
                handled = true
            } else if Self.imageExtensions.contains(ext) {
                insertImageReference(for: url)
                handled = true
            }
        }
        return handled
    }

    func fileURLsFromPasteboard(_ pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]
    }

    func insertImageReference(for imageURL: URL) {
        let imageName = imageURL.deletingPathExtension().lastPathComponent
        let imagePath: String

        if let docDir = filePath?.deletingLastPathComponent() {
            // Ensure trailing slash so /docs doesn't match /docs-old
            let docPath = docDir.standardizedFileURL.path.hasSuffix("/")
                ? docDir.standardizedFileURL.path
                : docDir.standardizedFileURL.path + "/"
            let imgPath = imageURL.standardizedFileURL.path

            if imgPath.hasPrefix(docPath) {
                // Image is inside the document's directory tree
                imagePath = String(imgPath.dropFirst(docPath.count))
            } else {
                imagePath = imageURL.path
            }
        } else {
            imagePath = imageURL.path
        }

        let markdown = "![\(imageName)](\(imagePath))"

        let source = sourceView.currentSource
        let insertionRange = sourceView.selectedSourceRange

        let nsSource = source as NSString
        let safeLoc = min(insertionRange.location, nsSource.length)
        let before = nsSource.substring(to: safeLoc)
        let after = nsSource.substring(from: safeLoc)

        let prefix = before.isEmpty || before.hasSuffix("\n") ? "" : "\n"
        let suffix = after.isEmpty || after.hasPrefix("\n") ? "" : "\n"

        let insertion = prefix + markdown + suffix
        let newSource = before + insertion + after
        sourceView.replaceEntireSource(with: newSource)

        if mode == .preview {
            mode = .source
        }
    }
}
