import XCTest
import ImageIO
@testable import TeststripCore

final class PreIngestThumbnailRendererTests: XCTestCase {
    func testRenderCreatesThumbnailInCache() throws {
        let sourceURL = try writeTestJPEG()
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let renderer = PreIngestThumbnailRenderer()

        XCTAssertFalse(cache.thumbnailExists(for: sourceURL))
        try renderer.render(sourceURL: sourceURL, cache: cache)
        XCTAssertTrue(cache.thumbnailExists(for: sourceURL))
        cache.cleanup()
    }

    func testRenderSkipsWhenThumbnailExists() throws {
        let sourceURL = try writeTestJPEG()
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let renderer = PreIngestThumbnailRenderer()

        try renderer.render(sourceURL: sourceURL, cache: cache)
        let firstSize = try FileManager.default.attributesOfItem(
            atPath: cache.thumbnailURL(for: sourceURL).path
        )[.size] as? Int ?? 0

        // Render again — should skip (thumbnail already exists)
        try renderer.render(sourceURL: sourceURL, cache: cache)
        let secondSize = try FileManager.default.attributesOfItem(
            atPath: cache.thumbnailURL(for: sourceURL).path
        )[.size] as? Int ?? 0

        XCTAssertEqual(firstSize, secondSize)
        cache.cleanup()
    }

    func testRenderBatchConcurrent() throws {
        let urls = try (0..<8).map { _ in try writeTestJPEG() }
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let renderer = PreIngestThumbnailRenderer()

        try renderer.renderBatch(urls, cache: cache, concurrency: 4)

        for url in urls {
            XCTAssertTrue(cache.thumbnailExists(for: url), "missing thumbnail for \(url.path)")
        }
        cache.cleanup()
    }

    func testRenderBoundsThumbnailToMicroPixelDimension() throws {
        let sourceURL = try writeTestJPEG(width: 1200, height: 800)
        let cache = PreIngestThumbnailCache(directoryURL: makeTempDir())
        let renderer = PreIngestThumbnailRenderer()

        try renderer.render(sourceURL: sourceURL, cache: cache)

        let thumbnailURL = cache.thumbnailURL(for: sourceURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(thumbnailURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(
            max(width, height),
            PreviewLevel.micro.maxPixelDimension!,
            "pre-ingest thumbnails must render at .micro's 160px bound"
        )
        cache.cleanup()
    }

    private func writeTestJPEG(width: Int = 4, height: Int = 4) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jpg")
        let cgImage = createTestCGImage(width: width, height: height)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    private func createTestCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("renderer-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
