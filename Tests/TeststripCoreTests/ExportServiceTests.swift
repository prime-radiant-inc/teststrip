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

    func testExportResolvesFilenameCollisionsWithDeterministicSuffix() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-collisions")
        let firstFolder = directory.appendingPathComponent("a", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let firstSource = firstFolder.appendingPathComponent("photo.jpg")
        let secondSource = secondFolder.appendingPathComponent("photo.jpg")
        try TestDirectories.writeTestJPEG(to: firstSource, width: 100, height: 80)
        try TestDirectories.writeTestJPEG(to: secondSource, width: 100, height: 80)
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: destination.appendingPathComponent("photo.jpg"), width: 10, height: 10)

        let results = try ExportService().export(
            originalURLs: [firstSource, secondSource],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        )

        XCTAssertEqual(results, [
            ExportFileResult(sourceURL: firstSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo-2.jpg"))),
            ExportFileResult(sourceURL: secondSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo-3.jpg")))
        ])
        let preexistingDimensions = try PreviewRenderer().dimensions(of: destination.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(preexistingDimensions, PreviewDimensions(width: 10, height: 10))
    }

    func testExportSkipsMissingOriginalsAndReportsUndecodableOnesAsFailed() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-skip-fail")
        let goodSource = directory.appendingPathComponent("good.jpg")
        let missingSource = directory.appendingPathComponent("missing.jpg")
        let brokenSource = directory.appendingPathComponent("broken.jpg")
        try TestDirectories.writeTestJPEG(to: goodSource, width: 100, height: 80)
        try Data("not an image".utf8).write(to: brokenSource)
        let destination = directory.appendingPathComponent("out", isDirectory: true)

        let results = try ExportService().export(
            originalURLs: [goodSource, missingSource, brokenSource],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].outcome, .exported(destinationURL: destination.appendingPathComponent("good.jpg")))
        XCTAssertEqual(results[1].outcome, .skippedUnavailable)
        guard case .failed(let message) = results[2].outcome else {
            XCTFail("expected failed outcome, got \(results[2].outcome)")
            return
        }
        XCTAssertTrue(message.contains("broken.jpg"), "failure message should name the file: \(message)")
        let writtenNames = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(writtenNames, ["good.jpg"])
    }

    func testExportReportsProgressPerFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-progress")
        let sources = try (0..<3).map { index -> URL in
            let url = directory.appendingPathComponent("photo-\(index).jpg")
            try TestDirectories.writeTestJPEG(to: url, width: 50, height: 40)
            return url
        }
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        let recorded = ProgressRecorder()

        _ = try ExportService().export(
            originalURLs: sources,
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        ) { completedCount, totalCount in
            recorded.append(completed: completedCount, total: totalCount)
        }

        XCTAssertEqual(recorded.pairs.map(\.completed), [1, 2, 3])
        XCTAssertEqual(recorded.pairs.map(\.total), [3, 3, 3])
    }

    func testLowerQualityProducesSmallerFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-quality")
        let source = directory.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 800, height: 600)
        let highDestination = directory.appendingPathComponent("high", isDirectory: true)
        let lowDestination = directory.appendingPathComponent("low", isDirectory: true)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 1.0),
            destinationDirectory: highDestination
        )
        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.1),
            destinationDirectory: lowDestination
        )

        let highSize = try XCTUnwrap(FileManager.default.attributesOfItem(
            atPath: highDestination.appendingPathComponent("source.jpg").path
        )[.size] as? Int64)
        let lowSize = try XCTUnwrap(FileManager.default.attributesOfItem(
            atPath: lowDestination.appendingPathComponent("source.jpg").path
        )[.size] as? Int64)
        XCTAssertLessThan(lowSize, highSize)
    }

    func testExportLeavesOriginalsUntouchedAndWritesOnlyIntoDestination() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-non-destructive")
        let sourceFolder = directory.appendingPathComponent("originals", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 100, height: 80)
        let originalBytes = try Data(contentsOf: source)
        let destination = directory.appendingPathComponent("out", isDirectory: true)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        )

        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sourceFolder.path), ["source.jpg"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["source.jpg"])
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private(set) var pairs: [(completed: Int, total: Int)] = []
    private let lock = NSLock()

    func append(completed: Int, total: Int) {
        lock.lock()
        defer { lock.unlock() }
        pairs.append((completed, total))
    }
}
