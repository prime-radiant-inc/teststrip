import CoreGraphics
import Foundation

/// Shared low-level pixel sampling and edge-detail focus scoring for
/// evaluation providers that measure sharpness on cached previews.
enum PreviewPixelMetrics {
    /// Draws `image` into a `width` x `height` RGBA8 buffer and returns the pixels.
    static func rgbaSamples(of image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw TeststripError.io("could not allocate image sample buffer")
            }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw TeststripError.io("could not create image metrics context")
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// Average neighbor luminance delta over the sampled pixels, clamped to 0...1.
    static func focusScore(in pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 1, height > 1 else { return 0 }
        var totalDelta = 0.0
        var comparisonCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let current = luminance(atX: x, y: y, in: pixels, width: width)
                if x + 1 < width {
                    totalDelta += abs(current - luminance(atX: x + 1, y: y, in: pixels, width: width))
                    comparisonCount += 1
                }
                if y + 1 < height {
                    totalDelta += abs(current - luminance(atX: x, y: y + 1, in: pixels, width: width))
                    comparisonCount += 1
                }
            }
        }
        guard comparisonCount > 0 else { return 0 }
        return min(max(totalDelta / Double(comparisonCount), 0.0), 1.0)
    }

    static func luminance(atX x: Int, y: Int, in pixels: [UInt8], width: Int) -> Double {
        let index = (y * width + x) * 4
        return luminance(
            red: Double(pixels[index]) / 255.0,
            green: Double(pixels[index + 1]) / 255.0,
            blue: Double(pixels[index + 2]) / 255.0
        )
    }

    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
