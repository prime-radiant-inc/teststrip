import CoreGraphics
import Foundation
import ImageIO

public struct LocalImageMetricsEvaluationProvider: EvaluationProvider {
    public let name = "local-image-metrics"

    public init() {}

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let color = try Self.averageColor(of: previewURL)
        let exposure = Self.luminance(red: color.red, green: color.green, blue: color.blue)
        let provenance = ProviderProvenance(provider: name, model: "average-preview-metrics", version: "1", settingsHash: "default")
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
                value: .vector([color.red, color.green, color.blue]),
                confidence: 1.0,
                provenance: provenance
            )
        ]
    }

    private static func averageColor(of url: URL) throws -> RGBColor {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TeststripError.unsupportedFormat("ImageIO could not read \(url.lastPathComponent)")
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw TeststripError.io("could not allocate image sample buffer")
            }
            guard let context = CGContext(
                data: baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw TeststripError.io("could not create image metrics context")
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        return RGBColor(
            red: Double(pixel[0]) / 255.0,
            green: Double(pixel[1]) / 255.0,
            blue: Double(pixel[2]) / 255.0
        )
    }

    private static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

private struct RGBColor {
    var red: Double
    var green: Double
    var blue: Double
}
