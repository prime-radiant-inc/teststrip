#!/usr/bin/env swift
//
// render_app_icon.swift
//
// Draws the Teststrip app icon with CoreGraphics and writes it out as a PNG.
// This exists because the machines building Teststrip only have stock macOS
// tools available (no rsvg-convert, no Inkscape, no pyobjc for Python). The
// design mirrors config/macos/AppIcon.svg, which is the human-readable source
// of truth for the artwork; this script is the renderer we can actually run.
//
// Usage: swift script/render_app_icon.swift <output.png> [size-in-pixels]
//
// `size-in-pixels` defaults to 1024. script/generate_app_icon.sh calls this
// once per size an .iconset needs (16 through 1024) rather than downsampling
// a single master, because the five stepped frames collapse into mud if a
// 1024px render is shrunk 64x down to 16px. Below 64px this switches to a
// simplified, higher-contrast rendition of the same motif -- fewer, bolder
// frames with no rounding or soft shadows -- following the normal HIG
// practice of simplifying icon detail at small sizes.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Argument parsing

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: swift render_app_icon.swift <output.png> [size-in-pixels]\n".data(using: .utf8)!)
    exit(2)
}
let outputPath = arguments[1]
let canvasSize: CGFloat = arguments.count >= 3 ? CGFloat(Int(arguments[2]) ?? 1024) : 1024
let isCompact = canvasSize <= 64

// MARK: - Color helpers

func rgb(_ r: Int, _ g: Int, _ b: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: alpha)
}

// MARK: - Context setup

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(canvasSize),
    height: Int(canvasSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("failed to create CGContext\n".data(using: .utf8)!)
    exit(1)
}
ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// MARK: - Squircle background (Big Sur-era macOS icon grid: ~80.5% of the
// canvas, corner radius ~22.5% of that square's side)

let squircleSide = canvasSize * 0.805
let squircleOrigin = (canvasSize - squircleSide) / 2
let squircleRect = CGRect(x: squircleOrigin, y: squircleOrigin, width: squircleSide, height: squircleSide)
let squircleRadius = squircleSide * 0.225
let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: squircleRadius, cornerHeight: squircleRadius, transform: nil)

ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

// Near-black vertical gradient, background of a darkroom.
let bgColors = [rgb(23, 22, 26), rgb(11, 11, 13)] as CFArray
let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: canvasSize / 2, y: squircleRect.maxY),
    end: CGPoint(x: canvasSize / 2, y: squircleRect.minY),
    options: []
)

if !isCompact {
    // Faint safelight-amber glow, as if the strip is lit from behind. Skipped
    // at small sizes, where it just muddies the background instead of reading.
    let glowColors = [rgb(232, 162, 60, 0.16), rgb(232, 162, 60, 0)] as CFArray
    let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1])!
    ctx.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: canvasSize / 2, y: canvasSize * 0.56),
        startRadius: 0,
        endCenter: CGPoint(x: canvasSize / 2, y: canvasSize * 0.56),
        endRadius: squircleSide * 0.62,
        options: []
    )
}

ctx.restoreGState()

// Subtle rim so the squircle reads as a distinct surface.
ctx.addPath(squirclePath)
ctx.setStrokeColor(rgb(255, 255, 255, 0.07))
ctx.setLineWidth(canvasSize * 0.0015)
ctx.strokePath()

// MARK: - Test strip: stepped exposures, darkest to the safelight amber
//
// A real darkroom test strip is a single sheet of paper with several bands
// exposed for progressively longer times. We draw that as a vertical stack
// of frames stepping from near-black to #e8a23c. At full size that is five
// frames with soft rounding and a contact shadow; at icon-tray sizes it
// drops to three bold, square-edged bands so the "stepped strip" impression
// survives at 16x16.

let stepColorsFull: [CGColor] = [
    rgb(54, 49, 45),    // darkest exposure, still a shade lifted off the background
    rgb(96, 68, 40),
    rgb(148, 98, 42),
    rgb(192, 128, 48),
    rgb(232, 162, 60),  // full safelight amber, the "keeper" exposure
]
let stepColorsCompact: [CGColor] = [
    rgb(70, 63, 57),
    rgb(150, 100, 44),
    rgb(232, 162, 60),
]
let stepColors = isCompact ? stepColorsCompact : stepColorsFull
let frameCount = stepColors.count

let stripWidth = squircleSide * (isCompact ? 0.50 : 0.40)
let stripHeight = squircleSide * (isCompact ? 0.82 : 0.745)
let stripX = (canvasSize - stripWidth) / 2
let stripY = (canvasSize - stripHeight) / 2
let stripRect = CGRect(x: stripX, y: stripY, width: stripWidth, height: stripHeight)

if !isCompact {
    // Soft contact shadow beneath the strip so it lifts off the background.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -canvasSize * 0.012), blur: canvasSize * 0.03, color: rgb(0, 0, 0, 0.55))
    ctx.setFillColor(rgb(0, 0, 0, 0.001))
    ctx.fill(stripRect.insetBy(dx: -1, dy: -1))
    ctx.restoreGState()
}

let gapFraction: CGFloat = isCompact ? 0.10 : 0.045
let gap = stripHeight * gapFraction
let totalGap = gap * CGFloat(frameCount - 1)
let frameHeight = (stripHeight - totalGap) / CGFloat(frameCount)

// The brightest, correctly-exposed frame reads as the "pick": it steps
// wider than the rest, echoing the app's culling/selection concept.
let pickWidthMultiplier: CGFloat = isCompact ? 1.26 : 1.18

for index in 0..<frameCount {
    // index 0 = top (darkest) frame, so walk top-down.
    let frameTop = stripRect.maxY - CGFloat(index) * (frameHeight + gap)
    let frameRect0 = CGRect(x: stripX, y: frameTop - frameHeight, width: stripWidth, height: frameHeight)

    let isPick = index == frameCount - 1
    let frameRect: CGRect
    if isPick {
        let widened = stripWidth * pickWidthMultiplier
        let widenedX = canvasSize / 2 - widened / 2
        frameRect = CGRect(x: widenedX, y: frameRect0.minY, width: widened, height: frameHeight)
    } else {
        frameRect = frameRect0
    }

    let cornerRadius = isCompact ? 0 : frameRect.height * 0.16
    let framePath = CGPath(roundedRect: frameRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    if isPick && !isCompact {
        // A quiet amber glow behind the pick frame, echoing the background glow.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: canvasSize * 0.028, color: rgb(232, 162, 60, 0.55))
        ctx.addPath(framePath)
        ctx.setFillColor(stepColors[index])
        ctx.fillPath()
        ctx.restoreGState()
    } else {
        ctx.addPath(framePath)
        ctx.setFillColor(stepColors[index])
        ctx.fillPath()
    }

    if !isCompact {
        // A faint rim keeps each frame legible against the near-black
        // background, especially the darkest one.
        ctx.addPath(framePath)
        ctx.setStrokeColor(rgb(255, 255, 255, 0.08))
        ctx.setLineWidth(canvasSize * 0.0012)
        ctx.strokePath()
    }
}

// MARK: - Export

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write("failed to render image\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: image)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write("failed to write \(outputPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outputPath) (\(Int(canvasSize))x\(Int(canvasSize)))")
