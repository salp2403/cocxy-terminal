// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ComputerUseAction.swift - Local computer control contracts.

import Foundation

enum ComputerUseMouseButton: String, Sendable, Equatable {
    case left
    case right
    case middle
}

enum ComputerUseMouseAction: Sendable, Equatable {
    case move(x: Double, y: Double)
    case click(x: Double, y: Double, button: ComputerUseMouseButton, clickCount: Int)
}

enum ComputerUseKeyboardAction: Sendable, Equatable {
    case typeText(String)
}

enum ComputerUseScreenshotRequest: Sendable, Equatable {
    case mainDisplay
}

struct ComputerUseScreenshot: Sendable, Equatable {
    let fileURL: URL
    let width: Int
    let height: Int
}

enum ComputerUseAction: Sendable, Equatable {
    case mouse(ComputerUseMouseAction)
    case keyboard(ComputerUseKeyboardAction)
    case screenshot(ComputerUseScreenshotRequest)
}

enum ComputerUseResult: Sendable, Equatable {
    case mouseMoved(x: Double, y: Double)
    case mouseClicked(x: Double, y: Double, button: ComputerUseMouseButton, clickCount: Int)
    case keyboardTyped(characters: Int)
    case screenshot(fileURL: URL, width: Int, height: Int)
}

enum ComputerUseError: Error, Sendable, Equatable {
    case accessibilityPermissionDenied
    case mouseEventCreationFailed
    case keyboardEventCreationFailed
    case screenshotCaptureFailed
    case screenshotWriteFailed(String)
}

extension ComputerUseError: LocalizedError {
    var code: String {
        switch self {
        case .accessibilityPermissionDenied:
            return "computer_use_accessibility_denied"
        case .mouseEventCreationFailed:
            return "computer_use_mouse_event_failed"
        case .keyboardEventCreationFailed:
            return "computer_use_keyboard_event_failed"
        case .screenshotCaptureFailed:
            return "computer_use_screenshot_failed"
        case .screenshotWriteFailed:
            return "computer_use_screenshot_write_failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required before Cocxy can control the mouse or keyboard."
        case .mouseEventCreationFailed:
            return "Cocxy could not create the requested mouse event."
        case .keyboardEventCreationFailed:
            return "Cocxy could not create the requested keyboard event."
        case .screenshotCaptureFailed:
            return "Cocxy could not capture the display screenshot."
        case .screenshotWriteFailed(let path):
            return "Cocxy could not write the screenshot to \(path)."
        }
    }
}

protocol ComputerUseControlling: Sendable {
    func perform(_ action: ComputerUseAction, promptForPermission: Bool) async throws -> ComputerUseResult
}

extension ComputerUseControlling {
    func perform(_ action: ComputerUseAction) async throws -> ComputerUseResult {
        try await perform(action, promptForPermission: false)
    }
}

protocol ComputerUsePermissionChecking: Sendable {
    func hasAccessibilityPermission(prompt: Bool) async -> Bool
}

protocol ComputerUseMouseControlling: Sendable {
    func perform(_ action: ComputerUseMouseAction) async throws
}

protocol ComputerUseKeyboardControlling: Sendable {
    func typeText(_ text: String) async throws
}

protocol ComputerUseScreenshotCapturing: Sendable {
    func capture(_ request: ComputerUseScreenshotRequest) async throws -> ComputerUseScreenshot
}
