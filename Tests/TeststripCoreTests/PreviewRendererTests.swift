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
}
