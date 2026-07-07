import CoreGraphics
import Foundation
import ImageIO

public struct LocalImageMetricsEvaluationProvider: EvaluationProvider {
    public static let providerName = "local-image-metrics"

    /// Version 2: focus-family scores (focus, motionBlur, and the focus
    /// term inside aesthetics) are on the calibrated 0-1 scale rather than
    /// the raw ~0.04-0.15 luminance-delta scale of version 1. Catalog reads
    /// key on this to keep superseded raw-scale rows invisible.
    public static let provenanceVersion = "2"

    public let name = Self.providerName

    public init() {}

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let metrics = try Self.previewMetrics(of: previewURL)
        let exposure = PreviewPixelMetrics.luminance(red: metrics.averageColor.red, green: metrics.averageColor.green, blue: metrics.averageColor.blue)
        let provenance = ProviderProvenance(provider: name, model: "preview-color-focus-metrics", version: Self.provenanceVersion, settingsHash: "default")
        return [
            EvaluationSignal(
                assetID: assetID,
                kind: .exposure,
                value: .score(exposure),
                confidence: 1.0,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .colorPalette,
                value: .vector([metrics.averageColor.red, metrics.averageColor.green, metrics.averageColor.blue]),
                confidence: 1.0,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .focus,
                value: .score(metrics.focusScore),
                confidence: 1.0,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .motionBlur,
                value: .score(Self.motionBlurScore(focusScore: metrics.focusScore)),
                confidence: 0.7,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .framing,
                value: .score(metrics.framingScore),
                confidence: 0.6,
                provenance: provenance
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .aesthetics,
                value: .score(Self.aestheticScore(
                    focusScore: metrics.focusScore,
                    exposure: exposure,
                    color: metrics.averageColor,
                    framingScore: metrics.framingScore
                )),
                confidence: 0.55,
                provenance: provenance
            )
        ]
    }

    private static func previewMetrics(of url: URL) throws -> PreviewImageMetrics {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TeststripError.unsupportedFormat("ImageIO could not read \(url.lastPathComponent)")
        }

        let sampleWidth = 16
        let sampleHeight = 16
        let pixels = try PreviewPixelMetrics.rgbaSamples(of: image, width: sampleWidth, height: sampleHeight)

        return PreviewImageMetrics(
            averageColor: averageColor(in: pixels, width: sampleWidth, height: sampleHeight),
            focusScore: PreviewPixelMetrics.focusScore(in: pixels, width: sampleWidth, height: sampleHeight),
            framingScore: framingScore(in: pixels, width: sampleWidth, height: sampleHeight)
        )
    }

    private static func averageColor(in pixels: [UInt8], width: Int, height: Int) -> RGBColor {
        let pixelCount = Double(width * height)
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Double(pixels[index]) / 255.0
            green += Double(pixels[index + 1]) / 255.0
            blue += Double(pixels[index + 2]) / 255.0
        }
        return RGBColor(red: red / pixelCount, green: green / pixelCount, blue: blue / pixelCount)
    }

    private static func motionBlurScore(focusScore: Double) -> Double {
        min(max(1.0 - focusScore, 0.0), 1.0)
    }

    private static func aestheticScore(
        focusScore: Double,
        exposure: Double,
        color: RGBColor,
        framingScore: Double
    ) -> Double {
        let balancedExposure = 1.0 - min(abs(exposure - 0.5) * 2.0, 1.0)
        let colorContrast = max(color.red, color.green, color.blue) - min(color.red, color.green, color.blue)
        let score = focusScore * 0.35
            + balancedExposure * 0.25
            + colorContrast * 0.20
            + framingScore * 0.20
        return min(max(score, 0.0), 1.0)
    }

    private static func framingScore(in pixels: [UInt8], width: Int, height: Int) -> Double {
        let average = averageLuminance(in: pixels, width: width, height: height)
        var weightedX = 0.0
        var weightedY = 0.0
        var totalWeight = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let luminance = PreviewPixelMetrics.luminance(atX: x, y: y, in: pixels, width: width)
                let weight = abs(luminance - average)
                weightedX += (Double(x) + 0.5) / Double(width) * weight
                weightedY += (Double(y) + 0.5) / Double(height) * weight
                totalWeight += weight
            }
        }

        guard totalWeight > 0.0001 else { return 0.5 }

        let centerX = weightedX / totalWeight
        let centerY = weightedY / totalWeight
        let thirds = [1.0 / 3.0, 2.0 / 3.0]
        let nearestDistance = thirds.flatMap { targetX in
            thirds.map { targetY in
                hypot(centerX - targetX, centerY - targetY)
            }
        }.min() ?? 0.5

        return min(max(1.0 - nearestDistance / 0.5, 0.0), 1.0)
    }

    private static func averageLuminance(in pixels: [UInt8], width: Int, height: Int) -> Double {
        let pixelCount = Double(width * height)
        guard pixelCount > 0 else { return 0 }
        var total = 0.0
        for y in 0..<height {
            for x in 0..<width {
                total += PreviewPixelMetrics.luminance(atX: x, y: y, in: pixels, width: width)
            }
        }
        return total / pixelCount
    }
}

private struct PreviewImageMetrics {
    var averageColor: RGBColor
    var focusScore: Double
    var framingScore: Double
}

private struct RGBColor {
    var red: Double
    var green: Double
    var blue: Double
}
