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
        let output = directory.appendingPathComponent("grid.heic")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

        let dimensions = try renderer.dimensions(of: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
    }

    func testRendererPreservesSourceAspectRatioWhenBoundingGridPreview() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-aspect")
        let source = directory.appendingPathComponent("source.jpg")
        let output = directory.appendingPathComponent("grid.heic")
        try TestDirectories.writeTestJPEG(to: source, width: 800, height: 1200)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

        let dimensions = try renderer.dimensions(of: output)
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
        XCTAssertEqual(
            Double(dimensions.width) / Double(dimensions.height),
            800.0 / 1200.0,
            accuracy: 0.01
        )
    }

    func testRendererCreatesFullResolutionOriginalPreview() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-original")
        let source = directory.appendingPathComponent("source.jpg")
        let output = directory.appendingPathComponent("full.heic")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .original, destinationURL: output)

        let dimensions = try renderer.dimensions(of: output)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 1200, height: 800))
    }

    func testRendererWrapsDestinationDirectoryCreationFailureAsIO() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-directory-error")
        let source = directory.appendingPathComponent("source.jpg")
        let blockedParent = directory.appendingPathComponent("blocked-parent")
        let output = blockedParent.appendingPathComponent("grid.heic")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)
        try Data("not a directory".utf8).write(to: blockedParent)

        let renderer = PreviewRenderer()

        XCTAssertThrowsError(try renderer.render(sourceURL: source, level: .grid, destinationURL: output)) { error in
            guard case .io = error as? TeststripError else {
                XCTFail("expected TeststripError.io, got \(error)")
                return
            }
        }
    }

    func testRendererOutputsHEICFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-heic")
        let source = directory.appendingPathComponent("source.jpg")
        let output = directory.appendingPathComponent("grid.heic")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let sourceRef = CGImageSourceCreateWithURL(output as CFURL, nil)
        XCTAssertNotNil(sourceRef)
        let typeID = CGImageSourceGetType(sourceRef!) as String?
        XCTAssertEqual(typeID, "public.heic")
    }

    func testGridPreviewHasCorrectMaxDimension() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-heic-grid-dim")
        let source = directory.appendingPathComponent("source.jpg")
        let output = directory.appendingPathComponent("grid.heic")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

        let dimensions = try renderer.dimensions(of: output)
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
    }

    func testOriginalPreviewIsFullResolution() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-heic-original")
        let source = directory.appendingPathComponent("source.jpg")
        let output = directory.appendingPathComponent("full.heic")
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .original, destinationURL: output)

        let dimensions = try renderer.dimensions(of: output)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 1200, height: 800))
    }

    func testRenderLevelsGeneratesMultiplePhysicalFilesFromOneSource() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-batch")
        let source = directory.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 3200, height: 2400)
        let previewDir = directory.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

        let renderer = PreviewRenderer()
        let assetID = AssetID(rawValue: "asset-1")
        let cache = PreviewCache(root: previewDir)

        try renderer.renderLevels(
            fromLocalSource: source,
            levels: [.grid, .large, .original],
            destinationProvider: { level in
                cache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            }
        )

        let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
        let fullURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .original))

        XCTAssertTrue(FileManager.default.fileExists(atPath: gridURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: largeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullURL.path))
    }

    func testRenderLevelsDeduplicatesLevelsMappingToSamePhysicalFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-batch-dedup")
        let source = directory.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 3200, height: 2400)
        let previewDir = directory.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

        let renderer = PreviewRenderer()
        let assetID = AssetID(rawValue: "asset-1")
        let cache = PreviewCache(root: previewDir)

        try renderer.renderLevels(
            fromLocalSource: source,
            levels: [.micro, .grid, .medium, .large],
            destinationProvider: { level in
                cache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            }
        )

        let gridURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        let microURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .micro))
        let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
        let mediumURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .medium))

        XCTAssertEqual(gridURL, microURL)
        XCTAssertEqual(largeURL, mediumURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: gridURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: largeURL.path))
    }

    func testRenderLevelsMediumAloneProducesLargeResolution() throws {
        // Rendering .medium alone must still write large.heic at .large's
        // 3200px resolution, not .medium's 1600px, so .large is not starved.
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render-medium-alone")
        let source = directory.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 4000, height: 3000)
        let previewDir = directory.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

        let renderer = PreviewRenderer()
        let assetID = AssetID(rawValue: "asset-1")
        let cache = PreviewCache(root: previewDir)

        try renderer.renderLevels(
            fromLocalSource: source,
            levels: [.medium],
            destinationProvider: { level in
                cache.url(for: PreviewCacheKey(assetID: assetID, level: level))
            }
        )

        let largeURL = cache.url(for: PreviewCacheKey(assetID: assetID, level: .large))
        let dims = try renderer.dimensions(of: largeURL)
        // .large's maxPixelDimension is 3200; the file must be at that resolution,
        // not .medium's 1600.
        XCTAssertGreaterThan(
            max(dims.width, dims.height),
            PreviewLevel.medium.maxPixelDimension!,
            "large.heic must be rendered at .large's 3200px, not .medium's 1600px"
        )
        XCTAssertLessThanOrEqual(
            max(dims.width, dims.height),
            PreviewLevel.large.maxPixelDimension!,
            "large.heic must not exceed .large's 3200px bound"
        )
    }
}
