import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TeststripCore

final class PreviewRendererTests: XCTestCase {
    func testRendererCreatesBoundedGridPreview() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render")
        let source = directory.appendingPathComponent("source.jpg")
        let output = directory.appendingPathComponent("grid.jpg")
        try writeTestJPEG(to: source, width: 1200, height: 800)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

        let dimensions = try renderer.dimensions(of: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
    }

    private func writeTestJPEG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create test bitmap context")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create test jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write test jpeg")
        }
    }
}
