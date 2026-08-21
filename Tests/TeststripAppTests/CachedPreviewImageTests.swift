import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import TeststripApp

final class CachedPreviewImageTests: XCTestCase {
    func testPreviewImageTransitionRetainsImageForDifferentLevelsOfSameAsset() {
        let micro = URL(fileURLWithPath: "/Previews/asset-1/micro.heic")
        let grid = URL(fileURLWithPath: "/Previews/asset-1/grid.heic")

        XCTAssertTrue(PreviewImageTransition.shouldRetainCurrentImage(loadedURL: micro, nextURL: grid))
    }

    func testPreviewImageTransitionClearsImageForDifferentAsset() {
        let current = URL(fileURLWithPath: "/Previews/asset-1/grid.heic")
        let next = URL(fileURLWithPath: "/Previews/asset-2/grid.heic")

        XCTAssertFalse(PreviewImageTransition.shouldRetainCurrentImage(loadedURL: current, nextURL: next))
    }

    func testPreviewImageTransitionClearsImageWhenNextURLIsMissing() {
        let current = URL(fileURLWithPath: "/Previews/asset-1/grid.heic")

        XCTAssertFalse(PreviewImageTransition.shouldRetainCurrentImage(loadedURL: current, nextURL: nil))
    }

    // MARK: - Downsampling

    private func makeHEICFile(size: Int, named: String) throws -> URL {
        let dir = try makeTemporaryDirectory(named: named)
        let url = dir.appendingPathComponent("source.heic")
        let nsImage = NSImage(size: NSSize(width: size, height: size))
        nsImage.lockFocus()
        NSGraphicsContext.current?.flushGraphics()
        guard let cgImage = NSGraphicsContext.current?.cgContext.makeImage() else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not create CGImage"])
        }
        nsImage.unlockFocus()
        let heicType = UTType("public.heic")!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, heicType.identifier as CFString, 1, nil) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not create HEIC"])
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    func testLoadImageWithMaxPixelDimensionDownsamples() async throws {
        let source = try makeHEICFile(size: 512, named: "preview-image-downsample")
        let image = await PreviewImageDataLoader.loadImage(from: source, maxPixelDimension: 160, rotation: 0)
        XCTAssertNotNil(image)
        XCTAssertLessThanOrEqual(max(image!.size.width, image!.size.height), 160)
    }

    func testLoadImageWithoutMaxPixelDimensionLoadsFullSize() async throws {
        let source = try makeHEICFile(size: 512, named: "preview-image-full")
        let image = await PreviewImageDataLoader.loadImage(from: source, maxPixelDimension: nil, rotation: 0)
        XCTAssertNotNil(image)
        // Full-size load returns at least the source dimensions (may be larger on retina)
        XCTAssertGreaterThan(max(image!.size.width, image!.size.height), 160)
    }
}
