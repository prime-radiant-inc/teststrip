import Foundation
import XCTest
import TeststripCore

final class ExportServiceTests: XCTestCase {
    func testPresetsMatchApprovedSpecValues() {
        XCTAssertEqual(ExportPreset.fullResolutionJPEG.name, "Full-res JPEG")
        XCTAssertEqual(ExportPreset.fullResolutionJPEG.settings.jpegQuality, 0.9)
        XCTAssertNil(ExportPreset.fullResolutionJPEG.settings.longEdgeMaximumPixels)
        XCTAssertEqual(ExportPreset.web2048.name, "Web 2048px")
        XCTAssertEqual(ExportPreset.web2048.settings.jpegQuality, 0.8)
        XCTAssertEqual(ExportPreset.web2048.settings.longEdgeMaximumPixels, 2048)
        XCTAssertEqual(ExportPreset.all, [.fullResolutionJPEG, .web2048])
    }

    func testSettingsClampJpegQualityToUnitRange() {
        XCTAssertEqual(ExportSettings(jpegQuality: 1.5).jpegQuality, 1.0)
        XCTAssertEqual(ExportSettings(jpegQuality: -0.2).jpegQuality, 0.0)
        XCTAssertEqual(ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 2048).longEdgeMaximumPixels, 2048)
    }

    func testExportWritesJpegBoundedByLongEdgeCap() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-resize")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 600),
            destinationDirectory: destination
        )

        let exportedURL = destination.appendingPathComponent("source.jpg")
        XCTAssertEqual(results, [ExportFileResult(sourceURL: source, outcome: .exported(destinationURL: exportedURL))])
        let dimensions = try PreviewRenderer().dimensions(of: exportedURL)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 600, height: 400))
    }

    func testExportWithoutCapKeepsFullResolutionAndReplacesExtension() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-full-res")
        let source = directory.appendingPathComponent("source.png")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportPreset.fullResolutionJPEG.settings,
            destinationDirectory: destination
        )

        let exportedURL = destination.appendingPathComponent("source.jpg")
        XCTAssertEqual(results, [ExportFileResult(sourceURL: source, outcome: .exported(destinationURL: exportedURL))])
        let dimensions = try PreviewRenderer().dimensions(of: exportedURL)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 1200, height: 800))
    }

    func testExportWrapsDestinationDirectoryCreationFailureAsIO() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-destination-error")
        let source = directory.appendingPathComponent("source.jpg")
        let blockedParent = directory.appendingPathComponent("blocked-parent")
        try TestDirectories.writeTestJPEG(to: source, width: 100, height: 100)
        try Data("not a directory".utf8).write(to: blockedParent)

        XCTAssertThrowsError(try ExportService().export(
            originalURLs: [source],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: blockedParent.appendingPathComponent("nested", isDirectory: true)
        )) { error in
            guard case .io = error as? TeststripError else {
                XCTFail("expected TeststripError.io, got \(error)")
                return
            }
        }
    }
}
