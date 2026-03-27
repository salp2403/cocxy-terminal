// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppIconGenerator.swift - Clean minimalist app icon for macOS Dock.

import AppKit

/// Generates the Cocxy Terminal app icon programmatically.
///
/// Design: Dark rounded square with a terminal prompt ">" in blue,
/// a lavender cursor block, and three connected neural dots
/// representing AI agent awareness. The background uses a subtle
/// gradient from crust to base for depth. No text — the Dock shows the name.
enum AppIconGenerator {

    static func generatePlaceholderIcon() -> NSImage {
        generateIcon(size: 512)
    }

    static func generateIcon(size: CGFloat) -> NSImage {
        let iconSize = NSSize(width: size, height: size)
        let image = NSImage(size: iconSize)
        image.lockFocus()

        let s = size
        let padding = s * 0.04
        let outerRect = NSRect(
            x: padding, y: padding,
            width: s - padding * 2, height: s - padding * 2
        )
        let corner = outerRect.width * 0.22

        // Outer rounded rect with subtle gradient (Crust → slightly lighter).
        let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: corner, yRadius: corner)
        let gradient = NSGradient(
            starting: CocxyColors.crust,
            ending: CocxyColors.mantle
        )
        gradient?.draw(in: outerPath, angle: 90)

        // Inner rounded rect (Base) with inset for border effect.
        let inner = s * 0.07
        let innerRect = NSRect(
            x: inner, y: inner,
            width: s - inner * 2, height: s - inner * 2
        )
        let innerCorner = corner * 0.85
        CocxyColors.base.setFill()
        NSBezierPath(roundedRect: innerRect, xRadius: innerCorner, yRadius: innerCorner).fill()

        // Subtle inner border for depth.
        CocxyColors.surface0.withAlphaComponent(0.3).setStroke()
        let borderPath = NSBezierPath(roundedRect: innerRect, xRadius: innerCorner, yRadius: innerCorner)
        borderPath.lineWidth = max(1, s * 0.004)
        borderPath.stroke()

        // Terminal prompt ">".
        let promptFont = NSFont.monospacedSystemFont(ofSize: s * 0.36, weight: .heavy)
        let promptAttrs: [NSAttributedString.Key: Any] = [
            .font: promptFont,
            .foregroundColor: CocxyColors.blue,
        ]
        let promptStr = ">" as NSString
        let promptSize = promptStr.size(withAttributes: promptAttrs)
        let promptX = s * 0.15
        let promptY = (s - promptSize.height) * 0.48
        promptStr.draw(at: NSPoint(x: promptX, y: promptY), withAttributes: promptAttrs)

        // Cursor block (lavender with subtle glow).
        let cursorX = promptX + promptSize.width + s * 0.03
        let cursorY = promptY + promptSize.height * 0.08
        let cursorW = s * 0.05
        let cursorH = promptSize.height * 0.75
        let cursorRect = NSRect(x: cursorX, y: cursorY, width: cursorW, height: cursorH)

        // Glow behind cursor.
        CocxyColors.lavender.withAlphaComponent(0.15).setFill()
        NSBezierPath(
            roundedRect: cursorRect.insetBy(dx: -s * 0.015, dy: -s * 0.015),
            xRadius: cursorW * 0.5, yRadius: cursorW * 0.5
        ).fill()

        CocxyColors.lavender.setFill()
        NSBezierPath(
            roundedRect: cursorRect,
            xRadius: cursorW * 0.3, yRadius: cursorW * 0.3
        ).fill()

        // AI neural dots — triangle pattern in lower-right for balance.
        let dotR = s * 0.04
        let dotsBaseX = s * 0.62
        let dotsBaseY = s * 0.18
        let dots: [(x: CGFloat, y: CGFloat, color: NSColor)] = [
            (dotsBaseX, dotsBaseY, CocxyColors.teal),
            (dotsBaseX + s * 0.16, dotsBaseY, CocxyColors.blue),
            (dotsBaseX + s * 0.08, dotsBaseY + s * 0.13, CocxyColors.green),
        ]

        // Connecting lines with gradient effect.
        CocxyColors.surface2.withAlphaComponent(0.5).setStroke()
        let linePath = NSBezierPath()
        linePath.lineWidth = max(1.5, s * 0.006)
        for i in 0..<dots.count {
            for j in (i + 1)..<dots.count {
                linePath.move(to: NSPoint(x: dots[i].x, y: dots[i].y))
                linePath.line(to: NSPoint(x: dots[j].x, y: dots[j].y))
            }
        }
        linePath.stroke()

        // Draw dots with glow effect.
        for dot in dots {
            let glowR = dotR * 2.0
            dot.color.withAlphaComponent(0.15).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: dot.x - glowR, y: dot.y - glowR,
                width: glowR * 2, height: glowR * 2
            )).fill()

            dot.color.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: dot.x - dotR, y: dot.y - dotR,
                width: dotR * 2, height: dotR * 2
            )).fill()

            // Bright center for depth.
            let highlightR = dotR * 0.4
            dot.color.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: dot.x - highlightR, y: dot.y + dotR * 0.2,
                width: highlightR * 2, height: highlightR * 2
            )).fill()
        }

        image.unlockFocus()
        return image
    }
}
