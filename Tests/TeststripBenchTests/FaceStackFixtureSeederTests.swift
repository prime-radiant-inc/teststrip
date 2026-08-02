import XCTest
import TeststripCore
@testable import TeststripBench

final class FaceStackFixtureSeederTests: XCTestCase {
    func testSeedFaceStackFixturesCommandParsesBothDirectories() throws {
        let command = BenchmarkCommand.parse([
            "TeststripBench", "seed-face-stack-fixtures", "/tmp/out", "/tmp/faces"
        ])

        XCTAssertEqual(
            command,
            .seedFaceStackFixtures(
                directory: URL(fileURLWithPath: "/tmp/out"),
                sourcePhotoDirectory: URL(fileURLWithPath: "/tmp/faces")
            )
        )
    }

    func testSeededStackFramesShareACaptureWindowAndTheRestDoNot() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else { throw Self.corpusSkip }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        XCTAssertEqual(result.stackFilenames.count, 4)
        XCTAssertGreaterThan(result.singleCount, 0)

        let provider = ImageIODecodeProvider()
        let stackCaptures = try result.stackFilenames.map { filename -> Date in
            try XCTUnwrap(provider.metadata(for: directory.appendingPathComponent(filename)).capturedAt)
        }
        // Chained adjacent gaps inside AssetStackBuilder's 2s window.
        for (earlier, later) in zip(stackCaptures, stackCaptures.dropFirst()) {
            XCTAssertLessThanOrEqual(later.timeIntervalSince(earlier), AssetStackBuilder.defaultMaximumCaptureGap)
            XCTAssertGreaterThan(later.timeIntervalSince(earlier), 0)
        }

        let singleFiles = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .filter { !result.stackFilenames.contains($0.lastPathComponent) }
        for single in singleFiles {
            let capturedAt = try XCTUnwrap(provider.metadata(for: single).capturedAt)
            let gapToStack = abs(capturedAt.timeIntervalSince(try XCTUnwrap(stackCaptures.last)))
            XCTAssertGreaterThan(gapToStack, AssetStackBuilder.defaultMaximumCaptureGap)
        }
    }

    // Regression coverage for the fixture guarantee ("2026-dated, hours
    // apart"): every seeded frame's decoded DateTimeOriginal must equal the
    // exact stamp the seeder intended, for stack frames and singletons
    // alike. `copyJPEG` previously re-encoded via
    // `CGImageDestinationAddImageFromSource`, which does not reliably
    // override `DateTimeOriginal`/`DateTimeDigitized` already present in a
    // source JPEG's Exif block — three corpus files (two Sally Ride STS-7
    // shots carrying only a 2008 DateTimeDigitized, and the Armstrong
    // Gemini 8 shot carrying a 1966 DateTimeOriginal plus a 2013
    // DateTimeDigitized) came out with the wrong date instead of the
    // intended 2026 stamp.
    func testEverySeededFrameDecodesItsIntendedCaptureDateExactly() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else { throw Self.corpusSkip }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        XCTAssertFalse(result.capturedAtByFilename.isEmpty)
        let provider = ImageIODecodeProvider()
        for (filename, expected) in result.capturedAtByFilename.sorted(by: { $0.key < $1.key }) {
            let actual = try provider.metadata(for: directory.appendingPathComponent(filename)).capturedAt
            XCTAssertEqual(actual, expected, "\(filename) decoded the wrong capture date")
        }
    }

    func testTheStackCarriesDetectableFacesAndOneDeliberatelyFacelessFrame() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else { throw Self.corpusSkip }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        let analyzer = CoreImageFaceExpressionAnalyzer()
        for filename in FaceStackFixtureSeeder.stackFaceFilenames {
            let faces = try analyzer.detectFaces(previewURL: directory.appendingPathComponent(filename))
            XCTAssertFalse(faces.isEmpty, "\(filename) must carry a detectable face for the rail-dot card")
        }
        // The falsification leg: a frame in the same stack with no faces at
        // all, which must never get a rail dot.
        let facelessURL = directory.appendingPathComponent(FaceStackFixtureSeeder.stackNoFaceFilename)
        XCTAssertEqual(try analyzer.detectFaces(previewURL: facelessURL), [])
        XCTAssertTrue(result.stackFilenames.contains(FaceStackFixtureSeeder.stackNoFaceFilename))
    }

    // The prominence-cap rule needs a live subject: one frame with a large
    // subject face and one genuinely small background face, so the card can
    // prove that a ruined bystander caps the frame at yellow rather than red.
    func testTheCompositeFrameCarriesASubjectAndABelowFloorBackgroundFace() throws {
        guard let sourceDirectory = Self.facesCorpusDirectory() else { throw Self.corpusSkip }
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try FaceStackFixtureSeeder(
            directory: directory,
            sourcePhotoDirectory: sourceDirectory
        ).run()

        let compositeURL = directory.appendingPathComponent(FaceStackFixtureSeeder.stackCompositeFilename)
        let faces = try CoreImageFaceExpressionAnalyzer().detectFaces(previewURL: compositeURL)

        XCTAssertEqual(faces.count, 2, "composite must present exactly one subject and one background face")
        let areas = faces
            .map { Double($0.normalizedBounds.width * $0.normalizedBounds.height) }
            .sorted()
        XCTAssertLessThan(areas[0], FaceReportGrading.prominenceFloor, "background face must sit below the prominence floor")
        XCTAssertGreaterThan(areas[1], FaceReportGrading.prominenceFloor, "subject face must sit above the prominence floor")
        XCTAssertEqual(result.backgroundFaceProminence, areas[0], accuracy: 0.0001)
    }

    private static var corpusSkip: XCTSkip {
        XCTSkip("No downloaded sample photos (run script/download_sample_photos.sh --manifest sample-data/faces.tsv --destination sample-data/photos/faces)")
    }

    private static func facesCorpusDirectory() -> URL? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("sample-data/photos/faces")
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.contains { $0.pathExtension.lowercased() == "jpg" } ? directory : nil
    }

    private static func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-face-stack-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
