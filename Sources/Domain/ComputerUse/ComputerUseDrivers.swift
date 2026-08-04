// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ComputerUseDrivers.swift - Native macOS implementations for Computer Use.

import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct AccessibilityComputerUsePermissionChecker: ComputerUsePermissionChecking {
    func hasAccessibilityPermission(prompt: Bool) async -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

struct CoreGraphicsComputerUseMouseController: ComputerUseMouseControlling {
    func perform(_ action: ComputerUseMouseAction) async throws {
        switch action {
        case .move(let x, let y):
            try postMouseEvent(type: .mouseMoved, at: CGPoint(x: x, y: y), button: .left)
        case .click(let x, let y, let button, let clickCount):
            let point = CGPoint(x: x, y: y)
            let cgButton = button.cgMouseButton
            try postMouseEvent(type: button.downEventType, at: point, button: cgButton, clickCount: clickCount)
            try postMouseEvent(type: button.upEventType, at: point, button: cgButton, clickCount: clickCount)
        }
    }

    private func postMouseEvent(
        type: CGEventType,
        at point: CGPoint,
        button: CGMouseButton,
        clickCount: Int = 1
    ) throws {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            throw ComputerUseError.mouseEventCreationFailed
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(max(1, clickCount)))
        event.post(tap: .cghidEventTap)
    }
}

struct CoreGraphicsComputerUseKeyboardController: ComputerUseKeyboardControlling {
    func typeText(_ text: String) async throws {
        for scalar in text.unicodeScalars {
            try postUnicodeScalar(scalar)
        }
    }

    private func postUnicodeScalar(_ scalar: UnicodeScalar) throws {
        let units = Array(String(scalar).utf16)
        guard !units.isEmpty else { return }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            throw ComputerUseError.keyboardEventCreationFailed
        }

        try units.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw ComputerUseError.keyboardEventCreationFailed
            }
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: baseAddress)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

struct ScreenCaptureKitComputerUseScreenshotCapture: ComputerUseScreenshotCapturing {
    let directory: URL

    init(directory: URL = ScreenCaptureKitComputerUseScreenshotCapture.defaultDirectory()) {
        self.directory = directory
    }

    func capture(_ request: ComputerUseScreenshotRequest) async throws -> ComputerUseScreenshot {
        switch request {
        case .mainDisplay:
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
            } catch {
                throw ComputerUseError.screenshotCaptureFailed
            }

            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                throw ComputerUseError.screenshotCaptureFailed
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            let pixelSize = Self.pixelDimensions(for: display.displayID)
            configuration.width = pixelSize.width
            configuration.height = pixelSize.height
            configuration.showsCursor = true

            let image: CGImage
            do {
                image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } catch {
                throw ComputerUseError.screenshotCaptureFailed
            }
            return try write(image)
        }
    }

    static func pixelDimensions(
        for displayID: CGDirectDisplayID
    ) -> (width: Int, height: Int) {
        (
            width: max(1, CGDisplayPixelsWide(displayID)),
            height: max(1, CGDisplayPixelsHigh(displayID))
        )
    }

    func write(_ image: CGImage) throws -> ComputerUseScreenshot {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("screenshot-\(Self.fileTimestamp())-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ComputerUseError.screenshotWriteFailed(fileURL.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ComputerUseError.screenshotWriteFailed(fileURL.path)
        }
        return ComputerUseScreenshot(
            fileURL: fileURL,
            width: image.width,
            height: image.height
        )
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agent/computer-use-screenshots", isDirectory: true)
    }

    private static func fileTimestamp() -> String {
        ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }
}

extension ComputerUseActor {
    static func liveDefault() -> ComputerUseActor {
        ComputerUseActor(
            permissionChecker: AccessibilityComputerUsePermissionChecker(),
            mouseController: CoreGraphicsComputerUseMouseController(),
            keyboardController: CoreGraphicsComputerUseKeyboardController(),
            screenshotCapture: ScreenCaptureKitComputerUseScreenshotCapture()
        )
    }
}

private extension ComputerUseMouseButton {
    var cgMouseButton: CGMouseButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .center
        }
    }

    var downEventType: CGEventType {
        switch self {
        case .left:
            return .leftMouseDown
        case .right:
            return .rightMouseDown
        case .middle:
            return .otherMouseDown
        }
    }

    var upEventType: CGEventType {
        switch self {
        case .left:
            return .leftMouseUp
        case .right:
            return .rightMouseUp
        case .middle:
            return .otherMouseUp
        }
    }
}
