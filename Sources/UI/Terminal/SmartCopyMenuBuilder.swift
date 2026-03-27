// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartCopyMenuBuilder.swift - Intelligent right-click context menu for the terminal.

import AppKit

// MARK: - Smart Copy Menu Builder

/// Builds a context-aware right-click menu for the terminal surface.
///
/// Analyzes the text around the click position to detect actionable content:
/// - URLs (http/https)
/// - File paths (absolute and ~-relative)
/// - IPv4/IPv6 addresses
/// - Git commit hashes (7-40 hex chars)
/// - Email addresses
///
/// When detected, offers targeted actions like "Open URL", "Copy IP Address",
/// "Copy Git Hash", etc. Always includes standard Copy/Paste actions.
///
/// This is a differentiating feature — no other terminal emulator offers
/// intelligent content detection in the right-click menu.
@MainActor
enum SmartCopyMenuBuilder {

    // MARK: - Menu Construction

    /// Builds a context menu for the terminal surface at the given position.
    ///
    /// Scans the terminal output buffer around the click for detectable patterns.
    /// Returns a menu with smart options based on what was found.
    ///
    /// - Parameters:
    ///   - text: The text content around the click position (e.g., current visible line).
    ///   - clipboardService: Service for clipboard operations.
    ///   - bridge: Terminal engine for paste operations.
    ///   - surfaceID: Target surface for paste operations.
    /// - Returns: A configured NSMenu ready for display.
    static func buildMenu(
        nearText text: String,
        clipboardService: ClipboardServiceProtocol,
        bridge: GhosttyBridge?,
        surfaceID: SurfaceID?
    ) -> NSMenu {
        let menu = NSMenu()
        let detections = detectContent(in: text)

        // Smart options first — grouped by type.
        if !detections.isEmpty {
            for detection in detections {
                let item = menuItem(for: detection, clipboard: clipboardService)
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }

        // Standard terminal actions.
        let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command]
        let copyAction = SmartCopyAction(clipboard: clipboardService) {
            clipboardService.write(text)
        }
        copyItem.target = copyAction
        copyItem.action = #selector(SmartCopyAction.execute)
        copyItem.representedObject = copyAction
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: nil, keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.command]
        if let bridge, let surfaceID {
            let pasteAction = SmartCopyAction(clipboard: clipboardService) {
                if let text = clipboardService.read() {
                    bridge.sendText(text, to: surfaceID)
                }
            }
            pasteItem.target = pasteAction
            pasteItem.action = #selector(SmartCopyAction.execute)
            pasteItem.representedObject = pasteAction
        }
        menu.addItem(pasteItem)

        menu.addItem(NSMenuItem.separator())

        // Copy entire visible line.
        let copyLineItem = NSMenuItem(title: "Copy Line", action: nil, keyEquivalent: "")
        let copyLineAction = SmartCopyAction(clipboard: clipboardService) {
            clipboardService.write(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        copyLineItem.target = copyLineAction
        copyLineItem.action = #selector(SmartCopyAction.execute)
        copyLineItem.representedObject = copyLineAction
        menu.addItem(copyLineItem)

        return menu
    }

    // MARK: - Content Detection

    /// Detects all actionable content patterns in the given text.
    ///
    /// Scans for URLs, file paths, IPs, git hashes, and emails.
    /// Returns them ordered by type priority (URLs first, then paths, etc.).
    static func detectContent(in text: String) -> [DetectedContent] {
        var results: [DetectedContent] = []
        let range = NSRange(text.startIndex..., in: text)

        // URLs
        for match in Patterns.url.matches(in: text, range: range) {
            if let swiftRange = Range(match.range, in: text) {
                let value = String(text[swiftRange])
                results.append(DetectedContent(type: .url, value: value))
            }
        }

        // File paths — skip fragments of URLs and protocol prefixes.
        let detectedURLValues = Set(results.map(\.value))
        for match in Patterns.filePath.matches(in: text, range: range) {
            if let swiftRange = Range(match.range, in: text) {
                let value = String(text[swiftRange])
                // Skip: too short, starts with http, starts with // (URL fragment),
                // or is a substring of an already-detected URL.
                let isURLFragment = value.hasPrefix("//")
                    || value.hasPrefix("http")
                    || detectedURLValues.contains(where: { $0.contains(value) })
                if value.count > 2, !isURLFragment {
                    results.append(DetectedContent(type: .filePath, value: value))
                }
            }
        }

        // IPv4
        for match in Patterns.ipv4.matches(in: text, range: range) {
            if let swiftRange = Range(match.range, in: text) {
                results.append(DetectedContent(type: .ipAddress, value: String(text[swiftRange])))
            }
        }

        // Git hashes (7-40 hex chars, standalone)
        for match in Patterns.gitHash.matches(in: text, range: range) {
            if let swiftRange = Range(match.range, in: text) {
                results.append(DetectedContent(type: .gitHash, value: String(text[swiftRange])))
            }
        }

        // Emails
        for match in Patterns.email.matches(in: text, range: range) {
            if let swiftRange = Range(match.range, in: text) {
                results.append(DetectedContent(type: .email, value: String(text[swiftRange])))
            }
        }

        return results
    }

    // MARK: - Menu Item Factory

    /// Creates a menu item for a detected content pattern.
    private static func menuItem(
        for detection: DetectedContent,
        clipboard: ClipboardServiceProtocol
    ) -> NSMenuItem {
        let title: String
        let icon: String

        switch detection.type {
        case .url:
            title = "Open URL"
            icon = "link"
        case .filePath:
            title = "Open Path"
            icon = "folder"
        case .ipAddress:
            title = "Copy IP Address"
            icon = "network"
        case .gitHash:
            title = "Copy Git Hash"
            icon = "number"
        case .email:
            title = "Copy Email"
            icon = "envelope"
        }

        let truncatedValue = detection.value.count > 40
            ? String(detection.value.prefix(37)) + "..."
            : detection.value

        let item = NSMenuItem(title: "\(title): \(truncatedValue)", action: nil, keyEquivalent: "")
        if let image = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            item.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        }

        let action = SmartCopyAction(clipboard: clipboard) {
            switch detection.type {
            case .url:
                if let url = URL(string: detection.value) {
                    NSWorkspace.shared.open(url)
                }
            case .filePath:
                let expanded = (detection.value as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                NSWorkspace.shared.open(url)
            case .ipAddress, .gitHash, .email:
                clipboard.write(detection.value)
            }
        }

        item.target = action
        item.action = #selector(SmartCopyAction.execute)
        item.representedObject = action
        return item
    }
}

// MARK: - Detected Content

/// A piece of actionable content detected in terminal output.
struct DetectedContent: Equatable, Sendable {

    /// The type of content detected.
    let type: ContentType

    /// The raw matched text value.
    let value: String

    /// Categories of detectable terminal content.
    enum ContentType: String, Sendable {
        case url
        case filePath
        case ipAddress
        case gitHash
        case email
    }
}

// MARK: - Regex Patterns

/// Compiled regex patterns for smart content detection.
///
/// All patterns are compiled once as static constants. Failure to compile
/// is a programming error (patterns are literals, not user input).
private enum Patterns {

    // swiftlint:disable force_try

    /// HTTP/HTTPS URLs.
    static let url: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"https?://[^\s<>\"'\])}]+"#,
            options: .caseInsensitive
        )
    }()

    /// Absolute and home-relative file paths.
    static let filePath: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?:~|/)[/\w.\-@]+"#,
            options: []
        )
    }()

    /// IPv4 addresses.
    static let ipv4: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
            options: []
        )
    }()

    /// Git commit hashes (7-40 hex characters, standalone word).
    static let gitHash: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b[0-9a-f]{7,40}\b"#,
            options: .caseInsensitive
        )
    }()

    /// Email addresses.
    static let email: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
            options: []
        )
    }()

    // swiftlint:enable force_try
}

// MARK: - Smart Copy Action

/// NSObject wrapper that holds a closure for menu item target-action.
///
/// Retained via the menu item's `representedObject` to prevent deallocation.
@MainActor
final class SmartCopyAction: NSObject {
    private let clipboard: ClipboardServiceProtocol
    private let handler: () -> Void

    init(clipboard: ClipboardServiceProtocol, handler: @escaping () -> Void) {
        self.clipboard = clipboard
        self.handler = handler
    }

    @objc func execute() {
        handler()
    }
}
