// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ComputerUseActor.swift - Permission-gated local computer actions.

import Foundation

actor ComputerUseActor: ComputerUseControlling {
    private let permissionChecker: any ComputerUsePermissionChecking
    private let mouseController: any ComputerUseMouseControlling
    private let keyboardController: any ComputerUseKeyboardControlling
    private let screenshotCapture: any ComputerUseScreenshotCapturing
    private let auditLog: ComputerUseAuditLog

    init(
        permissionChecker: any ComputerUsePermissionChecking,
        mouseController: any ComputerUseMouseControlling,
        keyboardController: any ComputerUseKeyboardControlling,
        screenshotCapture: any ComputerUseScreenshotCapturing,
        auditLog: ComputerUseAuditLog = ComputerUseAuditLog()
    ) {
        self.permissionChecker = permissionChecker
        self.mouseController = mouseController
        self.keyboardController = keyboardController
        self.screenshotCapture = screenshotCapture
        self.auditLog = auditLog
    }

    func perform(_ action: ComputerUseAction) async throws -> ComputerUseResult {
        try await perform(action, promptForPermission: false)
    }

    func perform(
        _ action: ComputerUseAction,
        promptForPermission: Bool
    ) async throws -> ComputerUseResult {
        switch action {
        case .mouse(let mouseAction):
            try await requireAccessibilityPermission(
                actionName: mouseAction.auditName,
                promptForPermission: promptForPermission,
                metadata: mouseAction.auditMetadata
            )
            do {
                try await mouseController.perform(mouseAction)
                let result = mouseAction.result
                try record(action: mouseAction.auditName, outcome: .success, metadata: mouseAction.auditMetadata)
                return result
            } catch {
                try record(action: mouseAction.auditName, outcome: .failure, metadata: mouseAction.auditMetadata)
                throw error
            }

        case .keyboard(let keyboardAction):
            try await requireAccessibilityPermission(
                actionName: keyboardAction.auditName,
                promptForPermission: promptForPermission,
                metadata: keyboardAction.auditMetadata
            )
            do {
                switch keyboardAction {
                case .typeText(let text):
                    try await keyboardController.typeText(text)
                }
                let result = keyboardAction.result
                try record(action: keyboardAction.auditName, outcome: .success, metadata: keyboardAction.auditMetadata)
                return result
            } catch {
                try record(action: keyboardAction.auditName, outcome: .failure, metadata: keyboardAction.auditMetadata)
                throw error
            }

        case .screenshot(let request):
            do {
                let screenshot = try await screenshotCapture.capture(request)
                try record(action: request.auditName, outcome: .success, metadata: [
                    "path": .string(screenshot.fileURL.path),
                    "width": .number(Double(screenshot.width)),
                    "height": .number(Double(screenshot.height)),
                ])
                return .screenshot(
                    fileURL: screenshot.fileURL,
                    width: screenshot.width,
                    height: screenshot.height
                )
            } catch {
                try record(action: request.auditName, outcome: .failure)
                throw error
            }
        }
    }

    private func requireAccessibilityPermission(
        actionName: String,
        promptForPermission: Bool,
        metadata: [String: ComputerUseAuditValue]
    ) async throws {
        let trusted = await permissionChecker.hasAccessibilityPermission(prompt: promptForPermission)
        guard trusted else {
            try record(action: actionName, outcome: .denied, metadata: metadata)
            throw ComputerUseError.accessibilityPermissionDenied
        }
    }

    private func record(
        action: String,
        outcome: ComputerUseAuditOutcome,
        metadata: [String: ComputerUseAuditValue] = [:]
    ) throws {
        try auditLog.record(action: action, outcome: outcome, metadata: metadata)
    }
}

private extension ComputerUseMouseAction {
    var auditName: String {
        switch self {
        case .move:
            return "mouse.move"
        case .click:
            return "mouse.click"
        }
    }

    var auditMetadata: [String: ComputerUseAuditValue] {
        switch self {
        case .move(let x, let y):
            return ["x": .number(x), "y": .number(y)]
        case .click(let x, let y, let button, let clickCount):
            return [
                "x": .number(x),
                "y": .number(y),
                "button": .string(button.rawValue),
                "clickCount": .number(Double(clickCount)),
            ]
        }
    }

    var result: ComputerUseResult {
        switch self {
        case .move(let x, let y):
            return .mouseMoved(x: x, y: y)
        case .click(let x, let y, let button, let clickCount):
            return .mouseClicked(x: x, y: y, button: button, clickCount: clickCount)
        }
    }
}

private extension ComputerUseKeyboardAction {
    var auditName: String {
        switch self {
        case .typeText:
            return "keyboard.type_text"
        }
    }

    var auditMetadata: [String: ComputerUseAuditValue] {
        switch self {
        case .typeText(let text):
            return ["characters": .number(Double(text.count))]
        }
    }

    var result: ComputerUseResult {
        switch self {
        case .typeText(let text):
            return .keyboardTyped(characters: text.count)
        }
    }
}

private extension ComputerUseScreenshotRequest {
    var auditName: String {
        switch self {
        case .mainDisplay:
            return "screenshot.main_display"
        }
    }
}
