import CoreGraphics
import Foundation
import ImageIO
import TeststripCore
import UniformTypeIdentifiers

enum BenchmarkImageFixtures {
    static func writeJPEG(to url: URL, index: Int) throws {
        let width = 1200
        let height = 800
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create benchmark bitmap context")
        }
        let red = CGFloat((index % 5) + 1) / 5.0
        let green = CGFloat((index % 7) + 1) / 7.0
        let blue = CGFloat((index % 11) + 1) / 11.0
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create benchmark jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write benchmark jpeg")
        }
    }
}
