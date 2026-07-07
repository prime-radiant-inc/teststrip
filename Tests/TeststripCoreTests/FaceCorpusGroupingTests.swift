import XCTest
@testable import TeststripCore

/// End-to-end guard on the real astronaut corpus: Apple Vision face detection +
/// feature-print embedding + FaceSuggestionBuilder must produce grouping
/// suggestions for repeated individuals. Skipped when the corpus has not been
/// downloaded (see script/build_and_run.sh --faces).
final class FaceCorpusGroupingTests: XCTestCase {
    func testRealCorpusProducesGroupingSuggestions() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sample-data/photos/faces")
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            throw XCTSkip("face corpus not downloaded")
        }
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(files.isEmpty, "face corpus is empty")

        let provider = AppleVisionEvaluationProvider()
        var embeddings: [FaceEmbedding] = []
        for file in files {
            let outcome = try provider.evaluateWithFaces(
                assetID: AssetID(rawValue: file.lastPathComponent),
                previewURL: file
            )
            for observation in outcome.faceObservations {
                embeddings.append(FaceEmbedding(
                    faceID: FaceID(assetID: observation.assetID, faceIndex: observation.faceIndex),
                    vector: observation.embedding
                ))
            }
        }

        let suggestions = FaceSuggestionBuilder().suggestions(
            unassignedFaces: embeddings,
            confirmedFacesByPerson: [:]
        )

        XCTAssertFalse(
            suggestions.clusters.isEmpty,
            "repeated individuals in the corpus must yield at least one grouping suggestion"
        )
    }
}
