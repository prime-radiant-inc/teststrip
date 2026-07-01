import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import TeststripCore

final class PreviewRendererTests: XCTestCase {
    func testPreviewDimensionsCanBeConstructedByPublicClients() {
        let dimensions = PreviewDimensions(width: 10, height: 20)

        XCTAssertEqual(dimensions, PreviewDimensions(width: 10, height: 20))
        XCTAssertEqual(dimensions.width, 10)
        XCTAssertEqual(dimensions.height, 20)
    }

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

    func testRendererWrapsDestinationDirectoryCreationFailureAsIO() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-directory-error")
        let source = directory.appendingPathComponent("source.jpg")
        let blockedParent = directory.appendingPathComponent("blocked-parent")
        let output = blockedParent.appendingPathComponent("grid.jpg")
        try writeTestJPEG(to: source, width: 1200, height: 800)
        try Data("not a directory".utf8).write(to: blockedParent)

        let renderer = PreviewRenderer()

        XCTAssertThrowsError(try renderer.render(sourceURL: source, level: .grid, destinationURL: output)) { error in
            guard case .io = error as? TeststripError else {
                XCTFail("expected TeststripError.io, got \(error)")
                return
            }
        }
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
