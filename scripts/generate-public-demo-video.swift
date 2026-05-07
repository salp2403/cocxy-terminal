#!/usr/bin/env swift
// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Generates the public Cocxy demo video from local website screenshots.

import AppKit
import AVFoundation

struct Slide {
    let imagePath: String
    let title: String
    let subtitle: String
    let seconds: Double
}

let frameWidth = 1280
let frameHeight = 720
let framesPerSecond = 30
let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputURL = repositoryRoot.appendingPathComponent("web/public/videos/cocxy-demo.mp4")

let slides = [
    Slide(
        imagePath: "web/public/images/cocxy-preview.png",
        title: "Cocxy Terminal",
        subtitle: "Native macOS terminal with local agent awareness",
        seconds: 2.4
    ),
    Slide(
        imagePath: "web/public/images/getting-started-sidebar.png",
        title: "Aurora sidebar",
        subtitle: "Tabs, sessions, projects, and remotes stay visible",
        seconds: 2.4
    ),
    Slide(
        imagePath: "web/public/images/getting-started-splits.png",
        title: "Split workflows",
        subtitle: "Terminal, Markdown, review, and tools side by side",
        seconds: 2.4
    ),
    Slide(
        imagePath: "web/public/images/getting-started-dashboard.png",
        title: "Local activity context",
        subtitle: "Agent status, timeline, and workflow state without telemetry",
        seconds: 2.4
    ),
    Slide(
        imagePath: "web/public/images/getting-started-command-palette.png",
        title: "Command palette",
        subtitle: "Fast keyboard access to Cocxy actions",
        seconds: 2.4
    ),
    Slide(
        imagePath: "web/public/images/getting-started-preferences.png",
        title: "Explicit controls",
        subtitle: "Privacy, backups, remotes, and preferences stay local by default",
        seconds: 2.4
    ),
]

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try? FileManager.default.removeItem(at: outputURL)

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let outputSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: frameWidth,
    AVVideoHeightKey: frameHeight,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 1_100_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ],
]
let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
writerInput.expectsMediaDataInRealTime = false

let pixelBufferAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: frameWidth,
    kCVPixelBufferHeightKey as String: frameHeight,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: writerInput,
    sourcePixelBufferAttributes: pixelBufferAttributes
)

guard writer.canAdd(writerInput) else {
    throw NSError(domain: "CocxyDemoVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
}
writer.add(writerInput)
guard writer.startWriting() else {
    throw writer.error ?? NSError(domain: "CocxyDemoVideo", code: 2)
}
writer.startSession(atSourceTime: .zero)

let colorSpace = CGColorSpaceCreateDeviceRGB()
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 52, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.93, green: 0.95, blue: 1.0, alpha: 1.0),
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.73, green: 0.76, blue: 0.87, alpha: 1.0),
]
let captionAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.71, green: 0.75, blue: 1.0, alpha: 1.0),
]

func nsColor(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawText(_ text: String, in rect: CGRect, attributes: [NSAttributedString.Key: Any]) {
    NSAttributedString(string: text, attributes: attributes).draw(in: rect)
}

func loadImage(_ path: String) throws -> NSImage {
    let url = repositoryRoot.appendingPathComponent(path)
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "CocxyDemoVideo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing image: \(path)"])
    }
    return image
}

func drawImage(_ image: NSImage, in target: CGRect, progress: CGFloat) {
    let imageSize = image.size
    let imageAspect = imageSize.width / max(imageSize.height, 1)
    let targetAspect = target.width / max(target.height, 1)
    var drawRect = target

    if imageAspect > targetAspect {
        let height = target.height * (1.02 + progress * 0.025)
        let width = height * imageAspect
        drawRect = CGRect(
            x: target.midX - width / 2 - progress * 18,
            y: target.midY - height / 2,
            width: width,
            height: height
        )
    } else {
        let width = target.width * (1.02 + progress * 0.025)
        let height = width / imageAspect
        drawRect = CGRect(
            x: target.midX - width / 2,
            y: target.midY - height / 2 - progress * 14,
            width: width,
            height: height
        )
    }

    image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

func renderFrame(slide: Slide, image: NSImage, slideProgress: CGFloat, globalProgress: CGFloat) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
    guard let buffer = pixelBuffer else {
        throw NSError(domain: "CocxyDemoVideo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot create pixel buffer"])
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard
        let baseAddress = CVPixelBufferGetBaseAddress(buffer),
        let context = CGContext(
            data: baseAddress,
            width: frameWidth,
            height: frameHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
    else {
        throw NSError(domain: "CocxyDemoVideo", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot create drawing context"])
    }

    context.translateBy(x: 0, y: CGFloat(frameHeight))
    context.scaleBy(x: 1, y: -1)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    defer { NSGraphicsContext.restoreGraphicsState() }

    drawRoundedRect(CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight), radius: 0, color: nsColor(0x0a0a12))

    let glowA = NSGradient(colors: [
        nsColor(0x89b4fa, alpha: 0.20),
        nsColor(0x0a0a12, alpha: 0.0),
    ])
    glowA?.draw(in: NSBezierPath(ovalIn: CGRect(x: -180, y: -140, width: 760, height: 420)), angle: -30)
    let glowB = NSGradient(colors: [
        nsColor(0xcba6f7, alpha: 0.18),
        nsColor(0x0a0a12, alpha: 0.0),
    ])
    glowB?.draw(in: NSBezierPath(ovalIn: CGRect(x: 760, y: 420, width: 680, height: 360)), angle: 135)

    drawText("Cocxy Terminal", in: CGRect(x: 72, y: 54, width: 320, height: 30), attributes: captionAttributes)
    drawText(slide.title, in: CGRect(x: 72, y: 108, width: 640, height: 72), attributes: titleAttributes)
    drawText(slide.subtitle, in: CGRect(x: 76, y: 178, width: 760, height: 42), attributes: subtitleAttributes)

    let card = CGRect(x: 72, y: 250, width: 1136, height: 382)
    drawRoundedRect(card.offsetBy(dx: 0, dy: 10), radius: 22, color: nsColor(0x000000, alpha: 0.24))
    drawRoundedRect(card, radius: 22, color: nsColor(0x181825))
    drawRoundedRect(CGRect(x: card.minX, y: card.minY, width: card.width, height: 46), radius: 22, color: nsColor(0x313244))
    drawRoundedRect(CGRect(x: card.minX, y: card.minY + 30, width: card.width, height: 34), radius: 0, color: nsColor(0x313244))
    for (index, color) in [0xf38ba8, 0xf9e2af, 0xa6e3a1].enumerated() {
        drawRoundedRect(
            CGRect(x: card.minX + 22 + CGFloat(index) * 24, y: card.minY + 17, width: 12, height: 12),
            radius: 6,
            color: nsColor(UInt32(color))
        )
    }
    drawText("local workflow demo", in: CGRect(x: card.midX - 120, y: card.minY + 13, width: 240, height: 24), attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
        .foregroundColor: nsColor(0xa6adc8),
    ])

    let imageRect = CGRect(x: card.minX + 18, y: card.minY + 64, width: card.width - 36, height: card.height - 84)
    NSGraphicsContext.current?.cgContext.saveGState()
    NSBezierPath(roundedRect: imageRect, xRadius: 14, yRadius: 14).addClip()
    drawRoundedRect(imageRect, radius: 14, color: nsColor(0x11111b))
    drawImage(image, in: imageRect, progress: slideProgress)
    NSGraphicsContext.current?.cgContext.restoreGState()

    let progressWidth = CGFloat(frameWidth - 144) * globalProgress
    drawRoundedRect(CGRect(x: 72, y: 666, width: frameWidth - 144, height: 6), radius: 3, color: nsColor(0x313244))
    drawRoundedRect(CGRect(x: 72, y: 666, width: progressWidth, height: 6), radius: 3, color: nsColor(0x89b4fa))

    return buffer
}

let totalFrames = slides.reduce(0) { $0 + Int(($1.seconds * Double(framesPerSecond)).rounded()) }
let loadedImages = try slides.map { try loadImage($0.imagePath) }
var frameIndex = 0

for (slideIndex, slide) in slides.enumerated() {
    let image = loadedImages[slideIndex]
    let slideFrameCount = Int((slide.seconds * Double(framesPerSecond)).rounded())

    for localFrame in 0..<slideFrameCount {
        while !writerInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.01)
        }

        let slideProgress = CGFloat(localFrame) / CGFloat(max(slideFrameCount - 1, 1))
        let globalProgress = CGFloat(frameIndex + 1) / CGFloat(max(totalFrames, 1))
        let buffer = try renderFrame(
            slide: slide,
            image: image,
            slideProgress: slideProgress,
            globalProgress: globalProgress
        )
        let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(framesPerSecond))
        adaptor.append(buffer, withPresentationTime: time)
        frameIndex += 1
    }
}

writerInput.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting {
    semaphore.signal()
}
semaphore.wait()

if writer.status != .completed {
    throw writer.error ?? NSError(domain: "CocxyDemoVideo", code: 6, userInfo: [NSLocalizedDescriptionKey: "Video writer failed"])
}

print("Generated \(outputURL.path)")
