// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ComputerUseSwiftTestingTests.swift - Local Computer Use domain contracts.

import CoreGraphics
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ComputerUseActor")
struct ComputerUseSwiftTestingTests {

    @Test("mouse and keyboard actions require Accessibility permission and write a denied audit event")
    func mouseAndKeyboardRequireAccessibilityPermission() async throws {
        let logURL = temporaryLogURL()
        let permission = RecordingComputerUsePermissionChecker(isTrusted: false)
        let mouse = RecordingMouseController()
        let keyboard = RecordingKeyboardController()
        let screenshot = RecordingScreenshotCapture()
        let actor = ComputerUseActor(
            permissionChecker: permission,
            mouseController: mouse,
            keyboardController: keyboard,
            screenshotCapture: screenshot,
            auditLog: ComputerUseAuditLog(fileURL: logURL)
        )

        await #expect(throws: ComputerUseError.accessibilityPermissionDenied) {
            _ = try await actor.perform(.mouse(.move(x: 10, y: 20)))
        }
        await #expect(throws: ComputerUseError.accessibilityPermissionDenied) {
            _ = try await actor.perform(.keyboard(.typeText("secret-token")))
        }

        #expect(await permission.promptFlags == [false, false])
        #expect(await mouse.actions.isEmpty)
        #expect(await keyboard.typedTexts.isEmpty)
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("\"outcome\":\"denied\""))
        #expect(!log.contains("secret-token"))
    }

    @Test("mouse and keyboard actions can request the macOS Accessibility permission prompt")
    func mouseAndKeyboardCanRequestAccessibilityPermissionPrompt() async throws {
        let permission = RecordingComputerUsePermissionChecker(isTrusted: false)
        let actor = ComputerUseActor(
            permissionChecker: permission,
            mouseController: RecordingMouseController(),
            keyboardController: RecordingKeyboardController(),
            screenshotCapture: RecordingScreenshotCapture(),
            auditLog: ComputerUseAuditLog(fileURL: temporaryLogURL())
        )

        await #expect(throws: ComputerUseError.accessibilityPermissionDenied) {
            _ = try await actor.perform(.mouse(.click(x: 10, y: 20, button: .left, clickCount: 1)), promptForPermission: true)
        }

        #expect(await permission.promptFlags == [true])
    }

    @Test("approved keyboard actions type text but audit only records character count")
    func approvedKeyboardActionsAuditOnlyCharacterCount() async throws {
        let logURL = temporaryLogURL()
        let permission = RecordingComputerUsePermissionChecker(isTrusted: true)
        let keyboard = RecordingKeyboardController()
        let actor = ComputerUseActor(
            permissionChecker: permission,
            mouseController: RecordingMouseController(),
            keyboardController: keyboard,
            screenshotCapture: RecordingScreenshotCapture(),
            auditLog: ComputerUseAuditLog(fileURL: logURL)
        )

        let result = try await actor.perform(.keyboard(.typeText("secret-token")))

        #expect(result == .keyboardTyped(characters: 12))
        #expect(await keyboard.typedTexts == ["secret-token"])
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("\"action\":\"keyboard.type_text\""))
        #expect(log.contains("\"characters\":12"))
        #expect(!log.contains("secret-token"))
    }

    @Test("approved mouse actions execute and write coordinate-only audit events")
    func approvedMouseActionsExecuteAndAuditCoordinates() async throws {
        let logURL = temporaryLogURL()
        let permission = RecordingComputerUsePermissionChecker(isTrusted: true)
        let mouse = RecordingMouseController()
        let actor = ComputerUseActor(
            permissionChecker: permission,
            mouseController: mouse,
            keyboardController: RecordingKeyboardController(),
            screenshotCapture: RecordingScreenshotCapture(),
            auditLog: ComputerUseAuditLog(fileURL: logURL)
        )

        let move = try await actor.perform(.mouse(.move(x: 10, y: 20)))
        let click = try await actor.perform(.mouse(.click(
            x: 30,
            y: 40,
            button: .right,
            clickCount: 2
        )))

        #expect(move == .mouseMoved(x: 10, y: 20))
        #expect(click == .mouseClicked(x: 30, y: 40, button: .right, clickCount: 2))
        #expect(await permission.promptFlags == [false, false])
        #expect(await mouse.actions == [
            .move(x: 10, y: 20),
            .click(x: 30, y: 40, button: .right, clickCount: 2),
        ])

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("\"action\":\"mouse.move\""))
        #expect(log.contains("\"action\":\"mouse.click\""))
        #expect(log.contains("\"outcome\":\"success\""))
        #expect(log.contains("\"button\":\"right\""))
        #expect(log.contains("\"clickCount\":2"))
    }

    @Test("mouse driver failures are audited before propagating")
    func mouseDriverFailuresAreAudited() async throws {
        let logURL = temporaryLogURL()
        let actor = ComputerUseActor(
            permissionChecker: RecordingComputerUsePermissionChecker(isTrusted: true),
            mouseController: FailingMouseController(error: ComputerUseError.mouseEventCreationFailed),
            keyboardController: RecordingKeyboardController(),
            screenshotCapture: RecordingScreenshotCapture(),
            auditLog: ComputerUseAuditLog(fileURL: logURL)
        )

        await #expect(throws: ComputerUseError.mouseEventCreationFailed) {
            _ = try await actor.perform(.mouse(.move(x: 15, y: 25)))
        }

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("\"action\":\"mouse.move\""))
        #expect(log.contains("\"outcome\":\"failure\""))
        #expect(log.contains("\"x\":15"))
        #expect(log.contains("\"y\":25"))
    }

    @Test("screenshot capture does not require Accessibility permission and returns local metadata")
    func screenshotCaptureDoesNotRequireAccessibilityPermission() async throws {
        let logURL = temporaryLogURL()
        let permission = RecordingComputerUsePermissionChecker(isTrusted: false)
        let screenshotURL = URL(fileURLWithPath: "/tmp/cocxy-computer-use-test.png")
        let actor = ComputerUseActor(
            permissionChecker: permission,
            mouseController: RecordingMouseController(),
            keyboardController: RecordingKeyboardController(),
            screenshotCapture: RecordingScreenshotCapture(result: ComputerUseScreenshot(
                fileURL: screenshotURL,
                width: 120,
                height: 80,
                scaleFactor: 2
            )),
            auditLog: ComputerUseAuditLog(fileURL: logURL)
        )

        let result = try await actor.perform(.screenshot(.mainDisplay))

        #expect(result == .screenshot(
            fileURL: screenshotURL,
            width: 120,
            height: 80,
            scaleFactor: 2
        ))
        #expect(await permission.promptFlags.isEmpty)
        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("\"action\":\"screenshot.main_display\""))
        #expect(log.contains("\"outcome\":\"success\""))
    }

    @Test("ScreenCaptureKit screenshots persist as local PNG files")
    func screenCaptureKitScreenshotsPersistAsPNG() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-screen-capture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 6,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 24,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let capture = ScreenCaptureKitComputerUseScreenshotCapture(
            directory: directory,
            displayGeometryProvider: { _ in
                ScreenCaptureKitComputerUseScreenshotCapture.DisplayGeometrySample(
                    modePixelWidth: 6,
                    modePixelHeight: 4,
                    fallbackPixelWidth: 3,
                    fallbackPixelHeight: 2,
                    pointWidth: 3
                )
            }
        )
        let plan = capture.capturePlan(for: 42)

        let screenshot = try capture.write(image, plan: plan)

        #expect(screenshot.width == 6)
        #expect(screenshot.height == 4)
        #expect(screenshot.scaleFactor == 2)
        #expect(screenshot.fileURL.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: screenshot.fileURL.path))
        #expect(try Data(contentsOf: screenshot.fileURL).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("capture plan prefers injected physical display mode dimensions")
    func capturePlanPrefersInjectedPhysicalDisplayModeDimensions() {
        let capture = ScreenCaptureKitComputerUseScreenshotCapture(
            directory: FileManager.default.temporaryDirectory,
            displayGeometryProvider: { _ in
                ScreenCaptureKitComputerUseScreenshotCapture.DisplayGeometrySample(
                    modePixelWidth: 3_456,
                    modePixelHeight: 2_234,
                    fallbackPixelWidth: 1_728,
                    fallbackPixelHeight: 1_117,
                    pointWidth: 1_728
                )
            }
        )

        let plan = capture.capturePlan(for: 42)

        #expect(plan.pixelWidth == 3_456)
        #expect(plan.pixelHeight == 2_234)
        #expect(plan.pointWidth == 1_728)
    }

    @Test("capture plan falls back from missing or invalid display mode dimensions")
    func capturePlanFallsBackFromInvalidDisplayModeDimensions() {
        let capture = ScreenCaptureKitComputerUseScreenshotCapture(
            directory: FileManager.default.temporaryDirectory,
            displayGeometryProvider: { _ in
                ScreenCaptureKitComputerUseScreenshotCapture.DisplayGeometrySample(
                    modePixelWidth: nil,
                    modePixelHeight: 0,
                    fallbackPixelWidth: 1_920,
                    fallbackPixelHeight: 1_080,
                    pointWidth: 1_280
                )
            }
        )

        let plan = capture.capturePlan(for: 42)

        #expect(plan.pixelWidth == 1_920)
        #expect(plan.pixelHeight == 1_080)
        #expect(plan.pointWidth == 1_280)
    }

    @Test("physical display dimensions reject invalid mode values")
    func physicalDisplayDimensionsRejectInvalidModeValues() {
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.physicalPixelDimension(
            preferred: 3_456,
            fallback: 1_728
        ) == 3_456)
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.physicalPixelDimension(
            preferred: 0,
            fallback: 1_920
        ) == 1_920)
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.physicalPixelDimension(
            preferred: nil,
            fallback: 0
        ) == 1)
    }

    @Test("screenshot scale uses fixed physical-width oracles")
    func screenshotScaleUsesFixedPhysicalWidthOracles() {
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.scale(
            pixelWidth: 3_456,
            pointWidth: 1_728
        ) == 2)
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.scale(
            pixelWidth: 1_920,
            pointWidth: 1_280
        ) == 1.5)
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.scale(
            pixelWidth: 1_024,
            pointWidth: 2_048
        ) == 1)
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.scale(
            pixelWidth: 0,
            pointWidth: 1_728
        ) == 1)
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.scale(
            pixelWidth: 3_456,
            pointWidth: 0
        ) == 1)
        #expect(ScreenCaptureKitComputerUseScreenshotCapture.scale(
            pixelWidth: 3_456,
            pointWidth: .leastNonzeroMagnitude
        ) == 1)
    }

    private func temporaryLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-computer-use-\(UUID().uuidString).jsonl")
    }
}

private actor RecordingComputerUsePermissionChecker: ComputerUsePermissionChecking {
    let isTrusted: Bool
    private(set) var promptFlags: [Bool] = []

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func hasAccessibilityPermission(prompt: Bool) async -> Bool {
        promptFlags.append(prompt)
        return isTrusted
    }
}

private actor RecordingMouseController: ComputerUseMouseControlling {
    private(set) var actions: [ComputerUseMouseAction] = []

    func perform(_ action: ComputerUseMouseAction) async throws {
        actions.append(action)
    }
}

private struct FailingMouseController: ComputerUseMouseControlling {
    let error: Error

    func perform(_ action: ComputerUseMouseAction) async throws {
        _ = action
        throw error
    }
}

private actor RecordingKeyboardController: ComputerUseKeyboardControlling {
    private(set) var typedTexts: [String] = []

    func typeText(_ text: String) async throws {
        typedTexts.append(text)
    }
}

private actor RecordingScreenshotCapture: ComputerUseScreenshotCapturing {
    let result: ComputerUseScreenshot

    init(result: ComputerUseScreenshot = ComputerUseScreenshot(
        fileURL: URL(fileURLWithPath: "/tmp/cocxy-computer-use-default.png"),
        width: 1,
        height: 1,
        scaleFactor: 1
    )) {
        self.result = result
    }

    func capture(_ request: ComputerUseScreenshotRequest) async throws -> ComputerUseScreenshot {
        result
    }
}
