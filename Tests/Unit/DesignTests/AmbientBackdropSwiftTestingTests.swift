// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AmbientBackdropSwiftTestingTests.swift - Pure math coverage for the
// aurora blob backdrop used by the Aurora redesign.
//
// The view itself is a SwiftUI `View`; the math that drives it lives
// in two pure helpers (`Design.AmbientBackdrop.phase(at:)` and the
// `BlobPhase.lerp` interpolator) plus a handful of static catalogues.
// These tests pin the math to the design reference's CSS keyframes
// and the blob catalogue to the documented shipping values so the
// backdrop never drifts from the prototype as the redesign evolves.

import CoreGraphics
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Aurora ambient backdrop math")
struct AmbientBackdropSwiftTestingTests {

    // MARK: - Keyframe anchors

    @Test("phase(at: 0) returns the rest keyframe")
    func phaseAtZeroIsRest() {
        let phase = Design.AmbientBackdrop.phase(at: 0.0)
        #expect(phase.scale == 1.0)
        #expect(phase.translation == .zero)
    }

    @Test("phase(at: 1/3) matches the first CSS keyframe (scale 1.10, translate 80/-60)")
    func phaseAtThirdMatchesReference() {
        let phase = Design.AmbientBackdrop.phase(at: 1.0 / 3.0)
        #expect(abs(phase.scale - 1.10) < 0.0001)
        #expect(abs(phase.translation.width - 80) < 0.0001)
        #expect(abs(phase.translation.height + 60) < 0.0001)
    }

    @Test("phase(at: 2/3) matches the second CSS keyframe (scale 0.95, translate -60/80)")
    func phaseAtTwoThirdsMatchesReference() {
        let phase = Design.AmbientBackdrop.phase(at: 2.0 / 3.0)
        #expect(abs(phase.scale - 0.95) < 0.0001)
        #expect(abs(phase.translation.width + 60) < 0.0001)
        #expect(abs(phase.translation.height - 80) < 0.0001)
    }

    @Test("phase(at: 1) loops back to the rest keyframe")
    func phaseAtOneReturnsRest() {
        let phase = Design.AmbientBackdrop.phase(at: 1.0)
        #expect(abs(phase.scale - 1.0) < 0.0001)
        #expect(abs(phase.translation.width) < 0.0001)
        #expect(abs(phase.translation.height) < 0.0001)
    }

    // MARK: - Clamping

    @Test("phase(at:) clamps out-of-range inputs to the valid window")
    func phaseClampsOutOfRange() {
        let below = Design.AmbientBackdrop.phase(at: -0.25)
        let above = Design.AmbientBackdrop.phase(at: 1.5)
        #expect(below.scale == 1.0)
        #expect(below.translation == .zero)
        #expect(above.scale == 1.0)
        #expect(above.translation == .zero)
    }

    // MARK: - Interpolation helper

    @Test("BlobPhase.lerp stays linear between anchors")
    func blobPhaseLerpIsLinear() {
        let a = Design.BlobPhase(scale: 1.0, translation: .zero)
        let b = Design.BlobPhase(scale: 1.10, translation: CGSize(width: 80, height: -60))
        let mid = Design.BlobPhase.lerp(a, b, amount: 0.5)
        #expect(abs(mid.scale - 1.05) < 0.0001)
        #expect(abs(mid.translation.width - 40) < 0.0001)
        #expect(abs(mid.translation.height + 30) < 0.0001)
    }

    @Test("BlobPhase.lerp clamps the amount to the unit range")
    func blobPhaseLerpClampsAmount() {
        let a = Design.BlobPhase(scale: 1.0, translation: .zero)
        let b = Design.BlobPhase(scale: 1.10, translation: CGSize(width: 80, height: -60))
        let below = Design.BlobPhase.lerp(a, b, amount: -1.0)
        let above = Design.BlobPhase.lerp(a, b, amount: 2.0)
        #expect(below == a)
        #expect(above == b)
    }

    // MARK: - Default blob catalogue

    @Test("Default blob catalogue matches the CSS reference (sizes + phases)")
    func defaultBlobsMatchReference() {
        let blobs = Design.AmbientBackdrop.defaultBlobs
        #expect(blobs.count == 3)

        #expect(blobs[0].diameter == 560)
        #expect(blobs[0].phaseOffset == 0)
        #expect(blobs[0].colour.hue == 250)

        #expect(blobs[1].diameter == 480)
        #expect(blobs[1].phaseOffset == -8)
        #expect(blobs[1].colour.hue == 180)

        #expect(blobs[2].diameter == 380)
        #expect(blobs[2].phaseOffset == -16)
        #expect(blobs[2].colour.hue == 300)
    }

    @Test("Every default blob uses the same lightness and chroma to stay visually balanced")
    func defaultBlobsShareLightnessAndChroma() {
        for blob in Design.AmbientBackdrop.defaultBlobs {
            #expect(blob.colour.lightness == 0.55)
            #expect(blob.colour.chroma == 0.15)
        }
    }

    // MARK: - Blend-mode preference

    @Test("Aurora and Nocturne palettes use the additive blend; Paper uses multiply")
    func blendModePreferenceMatchesReference() {
        #expect(Design.ThemePalette.aurora.prefersMultiplyBlend == false)
        #expect(Design.ThemePalette.nocturne.prefersMultiplyBlend == false)
        #expect(Design.ThemePalette.paper.prefersMultiplyBlend == true)
    }
}
