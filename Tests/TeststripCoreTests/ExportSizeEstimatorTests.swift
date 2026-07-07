import Foundation
import XCTest
import TeststripCore

final class ExportSizeEstimatorTests: XCTestCase {
    func testEstimateReturnsNilForEmptySampleURLs() {
        let estimate = ExportSizeEstimator().estimate(
            sampleURLs: [],
            settings: ExportPreset.web2048.settings,
            totalAssetCount: 10
        )
        XCTAssertNil(estimate)
    }

    func testEstimateReturnsNilForZeroTotalAssetCount() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "estimate-zero-total")
        let source = directory.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 400, height: 300)

        let estimate = ExportSizeEstimator().estimate(
            sampleURLs: [source],
            settings: ExportPreset.web2048.settings,
            totalAssetCount: 0
        )
        XCTAssertNil(estimate)
    }

    func testEstimateExtrapolatesEqualSampleSizesAcrossTotalCount() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "estimate-equal-samples")
        let settings = ExportSettings(jpegQuality: 0.8)
        let urls = try (0..<3).map { index -> URL in
            let url = directory.appendingPathComponent("photo-\(index).jpg")
            try TestDirectories.writeTestJPEG(to: url, width: 400, height: 300)
            return url
        }
        let perFileSize = try XCTUnwrap(ExportService().estimatedEncodedByteCount(for: urls[0], settings: settings))

        let estimate = try XCTUnwrap(ExportSizeEstimator().estimate(
            sampleURLs: urls,
            settings: settings,
            totalAssetCount: 240
        ))

        XCTAssertEqual(estimate.sampledCount, 3)
        XCTAssertEqual(estimate.totalAssetCount, 240)
        XCTAssertEqual(estimate.estimatedTotalBytes, perFileSize * 240)
    }

    func testEstimateSkipsUnreadableSourcesButAveragesOverSuccessfulSamples() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "estimate-skips-unreadable")
        let settings = ExportSettings(jpegQuality: 0.8)
        let goodURL = directory.appendingPathComponent("good.jpg")
        try TestDirectories.writeTestJPEG(to: goodURL, width: 400, height: 300)
        let missingURL = directory.appendingPathComponent("missing.jpg")
        let perFileSize = try XCTUnwrap(ExportService().estimatedEncodedByteCount(for: goodURL, settings: settings))

        let estimate = try XCTUnwrap(ExportSizeEstimator().estimate(
            sampleURLs: [goodURL, missingURL],
            settings: settings,
            totalAssetCount: 10,
            sampleCount: 2
        ))

        XCTAssertEqual(estimate.sampledCount, 1)
        XCTAssertEqual(estimate.estimatedTotalBytes, perFileSize * 10)
    }

    func testEstimateReturnsNilWhenAllSamplesFail() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "estimate-all-fail")
        let missingURL = directory.appendingPathComponent("missing.jpg")

        let estimate = ExportSizeEstimator().estimate(
            sampleURLs: [missingURL],
            settings: ExportPreset.web2048.settings,
            totalAssetCount: 10
        )
        XCTAssertNil(estimate)
    }

    func testRepresentativeSampleReturnsAllURLsWhenFewerThanSampleCount() {
        let urls = (0..<2).map { URL(fileURLWithPath: "/photos/\($0).jpg") }

        XCTAssertEqual(ExportSizeEstimator.representativeSample(from: urls, count: 3), urls)
    }

    func testRepresentativeSampleEvenlySpacesIndicesAcrossLargeLists() {
        let urls = (0..<10).map { URL(fileURLWithPath: "/photos/\($0).jpg") }

        let sample = ExportSizeEstimator.representativeSample(from: urls, count: 3)

        XCTAssertEqual(sample, [urls[0], urls[3], urls[6]])
    }
}
