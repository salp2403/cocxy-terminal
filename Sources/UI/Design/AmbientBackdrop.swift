// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AmbientBackdrop.swift - Ambient aurora blobs for the redesigned chrome.
//
// The design reference renders three large radial blobs behind every
// glass surface so that the glass material has something to refract:
// without a vivid backdrop, glass looks identical to a flat blur.
// This view is the SwiftUI port of the `.ambient-canvas` / `.aurora-blob`
// CSS primitives in `Terminal Redesign.html`.
//
// Contract:
// - Read the active theme palette from the environment (the same key
//   consumed by `GlassSurface`).
// - Render three animated blobs whose positions and scales drift on a
//   deterministic timeline so the backdrop stays pleasant on idle.
// - Respect `accessibilityReduceMotion`: when enabled the blobs snap
//   to their canonical positions and the animation stops entirely.
// - Mix via `.screen` on dark themes and `.multiply` on the Paper
//   palette so the blobs additively brighten dark backgrounds while
//   subtly colouring light ones — this matches the CSS
//   `mix-blend-mode` branch in the reference.
//
// The view is fully decoupled from any existing chrome. Hosting it
// is as simple as placing it behind everything else:
//
//     ZStack {
//         Design.AmbientBackdrop()
//         // glass chrome on top
//     }
//     .designThemePalette(.aurora)
//
// `AmbientBackdrop` has no state of its own and never writes to the
// environment, so embedding it in a preview or a test harness has
// zero side effects on any other subsystem.

import SwiftUI

extension Design {

    /// Animated ambient backdrop used by the Aurora redesign. Renders
    /// three soft blobs that drift on a 28 second loop, mirroring the
    /// design-reference CSS keyframes exactly.
    struct AmbientBackdrop: View {

        /// Visual identity of a single blob. The design reference uses
        /// three blobs with distinct sizes, starting corners, hues and
        /// phase offsets — mapping them to a small struct keeps the
        /// `body` readable and lets tests diff the catalogue directly.
        struct BlobDescriptor: Equatable, Sendable {
            let diameter: CGFloat
            let colour: OKLCHColor
            /// Anchor point inside the parent's coordinate space
            /// (0 ... 1 in both axes).
            let anchor: UnitPoint
            /// Phase offset of the blob's animation loop, in seconds.
            let phaseOffset: Double

            init(
                diameter: CGFloat,
                colour: OKLCHColor,
                anchor: UnitPoint,
                phaseOffset: Double
            ) {
                self.diameter = diameter
                self.colour = colour
                self.anchor = anchor
                self.phaseOffset = phaseOffset
            }
        }

        @Environment(\.designThemePalette) private var palette
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// Total loop duration — matches the CSS reference.
        private let loopDuration: Double = 28.0

        /// Default catalogue of blobs (size, colour, anchor, phase).
        /// Exposed as a static so tests can assert the shipped values.
        static let defaultBlobs: [BlobDescriptor] = [
            BlobDescriptor(
                diameter: 560,
                colour: OKLCHColor(0.55, 0.15, 250),
                anchor: UnitPoint(x: -0.08, y: -0.08),
                phaseOffset: 0
            ),
            BlobDescriptor(
                diameter: 480,
                colour: OKLCHColor(0.55, 0.15, 180),
                anchor: UnitPoint(x: 1.06, y: 1.08),
                phaseOffset: -8
            ),
            BlobDescriptor(
                diameter: 380,
                colour: OKLCHColor(0.55, 0.15, 300),
                anchor: UnitPoint(x: 0.45, y: 0.40),
                phaseOffset: -16
            ),
        ]

        private let blobs: [BlobDescriptor]

        init(blobs: [BlobDescriptor] = defaultBlobs) {
            self.blobs = blobs
        }

        var body: some View {
            GeometryReader { proxy in
                SwiftUI.TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1.0 / 30.0, paused: reduceMotion)) { context in
                    ZStack {
                        palette.backgroundPrimary.resolvedColor()
                            .ignoresSafeArea()

                        ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                            let phase = phase(for: blob, at: context.date)
                            Circle()
                                .fill(blob.colour.resolvedColor())
                                .frame(
                                    width: blob.diameter * phase.scale,
                                    height: blob.diameter * phase.scale
                                )
                                .opacity(blobOpacity)
                                .blur(radius: 80)
                                .position(
                                    x: proxy.size.width * blob.anchor.x + phase.translation.width,
                                    y: proxy.size.height * blob.anchor.y + phase.translation.height
                                )
                                .blendMode(palette.prefersMultiplyBlend ? .multiply : .screen)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        // MARK: - Animation math

        /// Phase evaluation for a single blob at a given wall-clock
        /// time. The scale / translation values mirror the CSS
        /// keyframes (0%/100% rest, 33% translate (80, -60) scale 1.10,
        /// 66% translate (-60, 80) scale 0.95) so the blob trajectory
        /// is identical to the reference.
        func phase(for blob: BlobDescriptor, at date: Date) -> BlobPhase {
            guard !reduceMotion else {
                return BlobPhase(scale: 1.0, translation: .zero)
            }
            let seconds = date.timeIntervalSinceReferenceDate + blob.phaseOffset
            let normalized = seconds.truncatingRemainder(dividingBy: loopDuration) / loopDuration
            let positive = normalized < 0 ? normalized + 1 : normalized
            return Self.phase(at: positive)
        }

        /// Pure helper exercised by tests. Maps a normalized time in
        /// `[0, 1]` to the design-reference keyframe values via linear
        /// interpolation between 0, 1/3, 2/3, and 1.
        static func phase(at normalized: Double) -> BlobPhase {
            let clamped = max(0, min(1, normalized))
            // Rest keyframes (0% and 100%) — scale 1, translation zero.
            let rest = BlobPhase(scale: 1.0, translation: .zero)
            // Mid keyframes from the CSS reference.
            let thirds = BlobPhase(scale: 1.10, translation: CGSize(width: 80, height: -60))
            let twoThirds = BlobPhase(scale: 0.95, translation: CGSize(width: -60, height: 80))

            if clamped <= 1.0 / 3.0 {
                let t = clamped / (1.0 / 3.0)
                return BlobPhase.lerp(rest, thirds, amount: t)
            }
            if clamped <= 2.0 / 3.0 {
                let t = (clamped - 1.0 / 3.0) / (1.0 / 3.0)
                return BlobPhase.lerp(thirds, twoThirds, amount: t)
            }
            let t = (clamped - 2.0 / 3.0) / (1.0 / 3.0)
            return BlobPhase.lerp(twoThirds, rest, amount: t)
        }

        /// Opacity used by each blob — matches the design reference's
        /// 0.5 (dark) / 0.25 (paper/nocturne) split. Reading the raw
        /// value from the palette is intentional: consumers can swap
        /// palettes at runtime without this view caching a stale
        /// value.
        private var blobOpacity: Double {
            palette.prefersMultiplyBlend ? 0.25 : 0.50
        }
    }

    /// Value returned by `phase(at:)`. Kept as a separate struct so
    /// tests can assert on the interpolated values without having to
    /// reach into the view hierarchy.
    struct BlobPhase: Equatable, Sendable {
        let scale: CGFloat
        let translation: CGSize

        static func lerp(_ a: BlobPhase, _ b: BlobPhase, amount: Double) -> BlobPhase {
            let t = CGFloat(max(0, min(1, amount)))
            return BlobPhase(
                scale: a.scale + (b.scale - a.scale) * t,
                translation: CGSize(
                    width: a.translation.width + (b.translation.width - a.translation.width) * t,
                    height: a.translation.height + (b.translation.height - a.translation.height) * t
                )
            )
        }
    }
}

// MARK: - Palette helper

extension Design.ThemePalette {

    /// Whether this palette expects the ambient blobs to mix via
    /// `.multiply` rather than `.screen`. Aurora and Nocturne keep
    /// the additive `.screen` behaviour (blobs brighten the dark
    /// background); Paper inverts to `.multiply` so blobs tint
    /// gently rather than glowing through the light surface.
    var prefersMultiplyBlend: Bool {
        // The Paper palette is the only light surface shipped today.
        // Detection by the background lightness keeps future palettes
        // working without touching this view.
        backgroundPrimary.lightness > 0.8
    }
}
