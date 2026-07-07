import XCTest
@testable import TeststripCore

/// VNClassifyImageRequest returns Apple's full ~1,300-label taxonomy with a
/// confidence for every label. Keeping everything with confidence > 0 yields
/// ~100+ noise labels per photo (and made autopilot propose hundreds of
/// keywords per frame). Apple's intended usage is the precision/recall filter,
/// which collapses the output to the handful of labels that actually describe
/// the image. This guards that only meaningful labels survive.
///
/// Corpus-gated: the real sample photos are downloaded, not committed, so the
/// test SKIPs when they are absent (mirrors verify_reverse_geocode_smoke).
final class AppleVisionKeywordThresholdTests: XCTestCase {
    private func sampleImageURL() -> URL? {
        // sample-data/photos/faces holds Vision-verified real portraits.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let facesDir = root.appendingPathComponent("sample-data/photos/faces")
        let contents = (try? FileManager.default.contentsOfDirectory(at: facesDir, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.pathExtension.lowercased() == "jpg" }
    }

    func testClassificationKeepsOnlyMeaningfulLabels() throws {
        guard let imageURL = sampleImageURL() else {
            throw XCTSkip("No downloaded sample photos (run script/download_sample_photos.sh --manifest sample-data/faces.tsv)")
        }
        let analysis = try AppleVisionAnalyzer().analyze(previewURL: imageURL)

        // A real photo describes itself with a few labels, not a hundred. The
        // pre-fix confidence>0 filter returned ~100+ here.
        XCTAssertGreaterThan(analysis.classificationLabels.count, 0, "a real photo should classify to at least one label")
        XCTAssertLessThanOrEqual(
            analysis.classificationLabels.count,
            20,
            "keyword classification returned \(analysis.classificationLabels.count) labels — the meaningful-label filter is not being applied"
        )
    }
}
