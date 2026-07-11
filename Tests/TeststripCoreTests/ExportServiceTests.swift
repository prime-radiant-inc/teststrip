import Foundation
import ImageIO
import UniformTypeIdentifiers
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
        XCTAssertEqual(ExportPreset.all, [
            .fullResolutionJPEG,
            .web2048,
            .instagramSquareCapped,
            .print300dpi,
            .email1MB
        ])
    }

    func testInstagramPresetCapsLongEdgeInsteadOfCroppingSquare() {
        // The design mock implies a square crop ("Instagram 1080²"), but
        // Teststrip never crops on export — that would silently discard
        // pixels the user didn't ask to lose. This preset instead caps the
        // long edge at 1080, which is honest about what actually happens.
        XCTAssertEqual(ExportPreset.instagramSquareCapped.name, "Instagram 1080²")
        XCTAssertEqual(ExportPreset.instagramSquareCapped.settings.longEdgeMaximumPixels, 1080)
        XCTAssertEqual(ExportPreset.instagramSquareCapped.settings.jpegQuality, 0.85)
        XCTAssertEqual(ExportPreset.instagramSquareCapped.settings.format, .jpeg)
        XCTAssertNil(ExportPreset.instagramSquareCapped.settings.targetFileSizeBytes)
    }

    func testPrintPresetIsFullResolutionAtHighQuality() {
        XCTAssertEqual(ExportPreset.print300dpi.name, "Print 300dpi")
        XCTAssertEqual(ExportPreset.print300dpi.settings.jpegQuality, 0.95)
        XCTAssertNil(ExportPreset.print300dpi.settings.longEdgeMaximumPixels)
        XCTAssertNil(ExportPreset.print300dpi.settings.targetFileSizeBytes)
    }

    func testEmailPresetTargetsAOneMegabyteByteBudget() {
        XCTAssertEqual(ExportPreset.email1MB.name, "Email 1MB")
        XCTAssertEqual(ExportPreset.email1MB.settings.targetFileSizeBytes, 1_000_000)
        XCTAssertEqual(ExportPreset.email1MB.settings.format, .jpeg)
    }

    func testPresetsRoundTripThroughJSONForPersistence() throws {
        let custom = ExportPreset(
            name: "Client delivery",
            settings: ExportSettings(
                jpegQuality: 0.92,
                longEdgeMaximumPixels: 3600,
                includeSourceMetadata: false,
                format: .png,
                targetFileSizeBytes: 2_500_000
            )
        )
        let data = try JSONEncoder().encode([custom, ExportPreset.email1MB])
        let decoded = try JSONDecoder().decode([ExportPreset].self, from: data)
        XCTAssertEqual(decoded, [custom, .email1MB])
    }

    func testSettingsClampJpegQualityToUnitRange() {
        XCTAssertEqual(ExportSettings(jpegQuality: 1.5).jpegQuality, 1.0)
        XCTAssertEqual(ExportSettings(jpegQuality: -0.2).jpegQuality, 0.0)
        XCTAssertEqual(ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 2048).longEdgeMaximumPixels, 2048)
    }

    func testSettingsDefaultToJpegFormatAndNoByteBudget() {
        let settings = ExportSettings(jpegQuality: 0.8)
        XCTAssertEqual(settings.format, .jpeg)
        XCTAssertNil(settings.targetFileSizeBytes)
    }

    func testExportWritesPngWhenFormatIsPng() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-png-format")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeTestJPEG(to: source, width: 400, height: 300)

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.9, format: .png),
            destinationDirectory: destination
        )

        let exportedURL = destination.appendingPathComponent("source.png")
        XCTAssertEqual(results, [ExportFileResult(sourceURL: source, outcome: .exported(destinationURL: exportedURL))])
        let dimensions = try PreviewRenderer().dimensions(of: exportedURL)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 400, height: 300))
        let readBackSource = try XCTUnwrap(CGImageSourceCreateWithURL(exportedURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(readBackSource) as String?, UTType.png.identifier)
    }

    func testExportResolvesPngFilenameCollisionsWithDeterministicSuffixAndExtension() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-png-collisions")
        let firstFolder = directory.appendingPathComponent("a", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let firstSource = firstFolder.appendingPathComponent("photo.jpg")
        let secondSource = secondFolder.appendingPathComponent("photo.jpg")
        try TestDirectories.writeTestJPEG(to: firstSource, width: 100, height: 80)
        try TestDirectories.writeTestJPEG(to: secondSource, width: 100, height: 80)
        let destination = directory.appendingPathComponent("out", isDirectory: true)

        let results = try ExportService().export(
            originalURLs: [firstSource, secondSource],
            settings: ExportSettings(jpegQuality: 0.9, format: .png),
            destinationDirectory: destination
        )

        XCTAssertEqual(results, [
            ExportFileResult(sourceURL: firstSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo.png"))),
            ExportFileResult(sourceURL: secondSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo-2.png")))
        ])
    }

    func testExportCarriesSourceMetadataForPngFormatToo() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-png-metadata")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try writeMetadataFixtureJPEG(to: source, width: 400, height: 300)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.9, format: .png),
            destinationDirectory: destination
        )

        let properties = try imageProperties(of: destination.appendingPathComponent("source.png"))
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal] as? String, "2020:01:02 03:04:05")
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
    }

    func testExportStepsDownJpegQualityToFitByteBudget() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-byte-budget")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeNoisyTestJPEG(to: source, width: 400, height: 300)
        let budget = 50_000

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.9, targetFileSizeBytes: budget),
            destinationDirectory: destination
        )

        let exportedURL = destination.appendingPathComponent("source.jpg")
        XCTAssertEqual(results, [ExportFileResult(sourceURL: source, outcome: .exported(destinationURL: exportedURL))])
        let exportedSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: exportedURL.path)[.size] as? Int64)
        XCTAssertLessThanOrEqual(exportedSize, Int64(budget))

        // Confirm stepping actually kicked in: an unconstrained export at the
        // same starting quality is comfortably larger than the budget.
        let unconstrainedDestination = directory.appendingPathComponent("unconstrained", isDirectory: true)
        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.9),
            destinationDirectory: unconstrainedDestination
        )
        let unconstrainedSize = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: unconstrainedDestination.appendingPathComponent("source.jpg").path)[.size] as? Int64
        )
        XCTAssertGreaterThan(unconstrainedSize, Int64(budget))
    }

    func testExportSkipsSteppingWhenInitialQualityAlreadyFitsBudget() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-byte-budget-already-fits")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeNoisyTestJPEG(to: source, width: 400, height: 300)

        let stepped = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.1, targetFileSizeBytes: 1_000_000),
            destinationDirectory: destination
        )
        let unconstrainedDestination = directory.appendingPathComponent("unconstrained", isDirectory: true)
        let unconstrained = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.1),
            destinationDirectory: unconstrainedDestination
        )

        guard case .exported(let steppedURL) = stepped[0].outcome, case .exported(let unconstrainedURL) = unconstrained[0].outcome else {
            XCTFail("expected both exports to succeed")
            return
        }
        // A budget that already fits at the requested quality should produce
        // byte-identical output to a plain export at that quality.
        XCTAssertEqual(try Data(contentsOf: steppedURL), try Data(contentsOf: unconstrainedURL))
    }

    func testExportBestEffortWhenByteBudgetIsUnreachable() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-byte-budget-unreachable")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeNoisyTestJPEG(to: source, width: 400, height: 300)

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.9, targetFileSizeBytes: 1),
            destinationDirectory: destination
        )

        let exportedURL = destination.appendingPathComponent("source.jpg")
        guard case .exported = try XCTUnwrap(results.first?.outcome) else {
            XCTFail("expected best-effort export to still succeed even though the budget is unreachable")
            return
        }
        let floorDestination = directory.appendingPathComponent("floor", isDirectory: true)
        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.0),
            destinationDirectory: floorDestination
        )
        // Best effort should land on the same bytes as the lowest quality the
        // encoder can produce — the export never fails just because the
        // budget can't be hit.
        XCTAssertEqual(try Data(contentsOf: exportedURL), try Data(contentsOf: floorDestination.appendingPathComponent("source.jpg")))
    }

    func testExportPngIgnoresByteBudget() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-png-ignores-budget")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeNoisyTestJPEG(to: source, width: 400, height: 300)

        let budgeted = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.9, format: .png, targetFileSizeBytes: 1),
            destinationDirectory: destination
        )
        let unconstrainedDestination = directory.appendingPathComponent("unconstrained", isDirectory: true)
        let unconstrained = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.9, format: .png),
            destinationDirectory: unconstrainedDestination
        )

        guard case .exported(let budgetedURL) = budgeted[0].outcome, case .exported(let unconstrainedURL) = unconstrained[0].outcome else {
            XCTFail("expected both PNG exports to succeed")
            return
        }
        XCTAssertEqual(try Data(contentsOf: budgetedURL), try Data(contentsOf: unconstrainedURL))
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

    // Jesse's ruling (2026-07-11): before writing, the export flow detects
    // filename collisions in the destination and asks once — Replace All /
    // Keep Both / Cancel. Keep Both is the existing suffixing; Replace All
    // overwrites the colliding files in place.
    func testCollidingFilenamesReportsOnlyPlannedOutputsAlreadyOnDisk() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-collision-detect")
        let collidingSource = directory.appendingPathComponent("photo.jpg")
        let freshSource = directory.appendingPathComponent("fresh.jpg")
        try TestDirectories.writeTestJPEG(to: collidingSource, width: 100, height: 80)
        try TestDirectories.writeTestJPEG(to: freshSource, width: 100, height: 80)
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // Extension comes from the export format, so a RAW original collides
        // with an existing photo.jpg output too.
        try TestDirectories.writeTestJPEG(to: destination.appendingPathComponent("photo.jpg"), width: 10, height: 10)

        let collisions = ExportService().collidingFilenames(
            originalURLs: [collidingSource, freshSource],
            format: .jpeg,
            destinationDirectory: destination
        )

        XCTAssertEqual(collisions, ["photo.jpg"])
    }

    func testCollidingFilenamesIsEmptyForFreshDestination() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-collision-none")
        let source = directory.appendingPathComponent("photo.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 100, height: 80)
        let destination = directory.appendingPathComponent("out", isDirectory: true)

        XCTAssertEqual(
            ExportService().collidingFilenames(
                originalURLs: [source],
                format: .jpeg,
                destinationDirectory: destination
            ),
            []
        )
    }

    func testExportReplaceAllOverwritesCollidingFileInsteadOfSuffixing() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-replace-all")
        let source = directory.appendingPathComponent("photo.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 100, height: 80)
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: destination.appendingPathComponent("photo.jpg"), width: 10, height: 10)

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination,
            collisionResolution: .replaceAll
        )

        XCTAssertEqual(results, [
            ExportFileResult(sourceURL: source, outcome: .exported(destinationURL: destination.appendingPathComponent("photo.jpg")))
        ])
        // The pre-existing 10x10 file was replaced by the real export.
        let dimensions = try PreviewRenderer().dimensions(of: destination.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(dimensions, PreviewDimensions(width: 100, height: 80))
        let writtenNames = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(writtenNames, ["photo.jpg"])
    }

    func testExportReplaceAllStillSuffixesWithinBatchDuplicates() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-replace-all-batch")
        let firstFolder = directory.appendingPathComponent("a", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let firstSource = firstFolder.appendingPathComponent("photo.jpg")
        let secondSource = secondFolder.appendingPathComponent("photo.jpg")
        try TestDirectories.writeTestJPEG(to: firstSource, width: 100, height: 80)
        try TestDirectories.writeTestJPEG(to: secondSource, width: 100, height: 80)
        let destination = directory.appendingPathComponent("out", isDirectory: true)

        let results = try ExportService().export(
            originalURLs: [firstSource, secondSource],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination,
            collisionResolution: .replaceAll
        )

        // Replace All applies to files already on disk before the batch, not
        // to two same-named frames inside the batch — the second must never
        // clobber the first.
        XCTAssertEqual(results, [
            ExportFileResult(sourceURL: firstSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo.jpg"))),
            ExportFileResult(sourceURL: secondSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo-2.jpg")))
        ])
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

    func testExportCarriesSourceMetadataWithUprightOrientationByDefault() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-carry-metadata")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try writeMetadataFixtureJPEG(to: source, width: 400, height: 300)

        XCTAssertTrue(ExportSettings(jpegQuality: 0.9).includeSourceMetadata)
        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 200),
            destinationDirectory: destination
        )

        let properties = try imageProperties(of: destination.appendingPathComponent("source.jpg"))
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal] as? String, "2020:01:02 03:04:05")
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let latitude = try XCTUnwrap(gps?[kCGImagePropertyGPSLatitude] as? Double)
        XCTAssertEqual(latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(gps?[kCGImagePropertyGPSLatitudeRef] as? String, "N")
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        // Orientation 6 is baked into the pixels: the 400x300 source renders as
        // 300x400 upright, then the 200px long-edge cap applies.
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 150)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 200)
    }

    func testExportWithoutSourceMetadataDropsExifAndGps() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-strip-metadata")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try writeMetadataFixtureJPEG(to: source, width: 400, height: 300)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 200, includeSourceMetadata: false),
            destinationDirectory: destination
        )

        let properties = try imageProperties(of: destination.appendingPathComponent("source.jpg"))
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    // Priya (persona-6): exported JPEGs carried none of the catalog's
    // keywords/caption/creator/copyright despite "Include EXIF/IPTC
    // metadata" being checked — the deliverable was stripped of the work.
    // Catalog-authored metadata must be embedded as IPTC/TIFF in the export.
    func testExportEmbedsCatalogMetadataWhenMetadataIncluded() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-catalog-metadata")
        let source = directory.appendingPathComponent("ride-sts7.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try writeMetadataFixtureJPEG(to: source, width: 400, height: 300)
        let metadata = AssetMetadata(
            rating: 4,
            keywords: ["STS-7", "astronaut"],
            caption: "Sally Ride, official NASA portrait, 1984",
            creator: "NASA Photo Office",
            copyright: "Public Domain"
        )

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.8, includeSourceMetadata: true),
            destinationDirectory: destination,
            catalogMetadataBySourceURL: [source: metadata]
        )
        XCTAssertEqual(results.first?.outcome, .exported(destinationURL: destination.appendingPathComponent("ride-sts7.jpg")))

        let properties = try imageProperties(of: destination.appendingPathComponent("ride-sts7.jpg"))
        let iptc = try XCTUnwrap(properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any], "export carries an IPTC block")
        XCTAssertEqual(iptc[kCGImagePropertyIPTCKeywords] as? [String], ["STS-7", "astronaut"])
        XCTAssertEqual(iptc[kCGImagePropertyIPTCCaptionAbstract] as? String, "Sally Ride, official NASA portrait, 1984")
        XCTAssertEqual(iptc[kCGImagePropertyIPTCByline] as? [String], ["NASA Photo Office"])
        XCTAssertEqual(iptc[kCGImagePropertyIPTCCopyrightNotice] as? String, "Public Domain")
        XCTAssertEqual((iptc[kCGImagePropertyIPTCStarRating] as? NSNumber)?.intValue, 4)
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        XCTAssertEqual(tiff[kCGImagePropertyTIFFArtist] as? String, "NASA Photo Office")
        XCTAssertEqual(tiff[kCGImagePropertyTIFFCopyright] as? String, "Public Domain")
        XCTAssertEqual(tiff[kCGImagePropertyTIFFImageDescription] as? String, "Sally Ride, official NASA portrait, 1984")
        // Source EXIF still carried through alongside the catalog fields.
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal] as? String, "2020:01:02 03:04:05")
    }

    func testExportOmitsCatalogMetadataWhenMetadataToggleIsOff() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-catalog-metadata-off")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try writeMetadataFixtureJPEG(to: source, width: 400, height: 300)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.8, includeSourceMetadata: false),
            destinationDirectory: destination,
            catalogMetadataBySourceURL: [source: AssetMetadata(rating: 5, keywords: ["secret"], creator: "Someone")]
        )

        let properties = try imageProperties(of: destination.appendingPathComponent("source.jpg"))
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        XCTAssertNil(iptc?[kCGImagePropertyIPTCKeywords])
        XCTAssertNil(iptc?[kCGImagePropertyIPTCByline])
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary].flatMap { ($0 as? [CFString: Any])?[kCGImagePropertyTIFFArtist] })
    }

    func testExportEmbedsCatalogMetadataIntoPngExports() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-catalog-metadata-png")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try writeMetadataFixtureJPEG(to: source, width: 400, height: 300)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.8, includeSourceMetadata: true, format: .png),
            destinationDirectory: destination,
            catalogMetadataBySourceURL: [source: AssetMetadata(keywords: ["Mercury Program"], copyright: "Public Domain")]
        )

        let properties = try imageProperties(of: destination.appendingPathComponent("source.png"))
        let iptc = try XCTUnwrap(properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any])
        XCTAssertEqual(iptc[kCGImagePropertyIPTCKeywords] as? [String], ["Mercury Program"])
        XCTAssertEqual(iptc[kCGImagePropertyIPTCCopyrightNotice] as? String, "Public Domain")
    }

    private func writeMetadataFixtureJPEG(to url: URL, width: Int, height: Int) throws {
        try TestDirectories.writeTestJPEG(to: url, width: width, height: height)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not rewrite metadata fixture \(url.lastPathComponent)")
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05"
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.7749,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4194,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write metadata fixture \(url.lastPathComponent)")
        }
    }

    private func imageProperties(of url: URL) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TeststripError.io("could not read image properties of \(url.lastPathComponent)")
        }
        return properties
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
