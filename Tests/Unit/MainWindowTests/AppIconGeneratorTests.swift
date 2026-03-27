// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppIconGeneratorTests.swift - Tests for the placeholder app icon generator.

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - App Icon Generator Tests

/// Tests for `AppIconGenerator` covering:
///
/// - Generated icon is not nil.
/// - Icon has the expected size (256x256).
/// - Icon contains valid image representations.
/// - Applying the icon to NSApp succeeds.
@MainActor
final class AppIconGeneratorTests: XCTestCase {

    // MARK: - Generation

    func testGeneratePlaceholderIconReturnsNonNilImage() {
        let icon = AppIconGenerator.generatePlaceholderIcon()
        XCTAssertNotNil(icon, "Generated icon must not be nil")
    }

    func testGeneratePlaceholderIconHasExpectedSize() {
        let icon = AppIconGenerator.generatePlaceholderIcon()
        XCTAssertEqual(icon.size.width, 512, accuracy: 0.1,
                       "Icon width must be 512 points")
        XCTAssertEqual(icon.size.height, 512, accuracy: 0.1,
                       "Icon height must be 512 points")
    }

    func testGeneratePlaceholderIconHasImageRepresentations() {
        let icon = AppIconGenerator.generatePlaceholderIcon()
        XCTAssertFalse(icon.representations.isEmpty,
                       "Icon must have at least one image representation")
    }

    func testGeneratePlaceholderIconIsSquare() {
        let icon = AppIconGenerator.generatePlaceholderIcon()
        XCTAssertEqual(icon.size.width, icon.size.height, accuracy: 0.1,
                       "Icon must be square")
    }

    // MARK: - Application

    func testApplyIconToAppDoesNotCrash() {
        let icon = AppIconGenerator.generatePlaceholderIcon()

        // NSApp may not be available in test context (no running application).
        guard NSApp != nil else { return }

        // Should not throw or crash.
        NSApp.applicationIconImage = icon

        // Verify it was applied.
        XCTAssertNotNil(NSApp.applicationIconImage,
                        "App icon should be set after applying")
    }
}
