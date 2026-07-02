import Foundation
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
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

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
}
