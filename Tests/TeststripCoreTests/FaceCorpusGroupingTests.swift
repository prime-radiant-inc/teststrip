import XCTest
import CoreGraphics
import ImageIO
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

    func testAstronautCorpusClustersByIdentity() throws {
        guard let model = ArcFaceCoreMLModel.bundled() else { throw XCTSkip("face model not downloaded") }
        guard let dir = Bundle.faceCorpusDirectory() else { throw XCTSkip("face corpus not downloaded") }
        let embedder = FaceRecognitionEmbedder(model: model)
        var faces: [FaceEmbedding] = []
        var personByFace: [String: String] = [:]   // faceID -> person, from filename prefix
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in files where url.pathExtension == "jpg" {
            let cg = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
            for (i, o) in try embedder.faceObservations(in: cg).enumerated() {
                let id = "\(url.lastPathComponent)#\(i)"
                faces.append(FaceEmbedding(faceID: FaceID(assetID: AssetID(rawValue: id), faceIndex: i), vector: o.featurePrintVector))
                personByFace[id] = url.lastPathComponent.contains("glenn") ? "glenn"
                    : url.lastPathComponent.contains("ride") ? "ride"
                    : url.lastPathComponent.contains("armstrong") ? "armstrong" : "aldrin"
            }
        }
        let clusters = FaceSuggestionBuilder().suggestions(unassignedFaces: faces, confirmedFacesByPerson: [:]).clusters
        // No cluster mixes two different people.
        for c in clusters {
            let people = Set(c.faceIDs.compactMap { personByFace[$0.assetID.rawValue] })
            XCTAssertEqual(people.count, 1, "cluster mixes people: \(people)")
        }
        // Glenn and Ride each form a multi-face cluster.
        let glennClustered = clusters.contains { c in c.faceIDs.allSatisfy { personByFace[$0.assetID.rawValue] == "glenn" } && c.faceIDs.count >= 2 }
        let rideClustered = clusters.contains { c in c.faceIDs.allSatisfy { personByFace[$0.assetID.rawValue] == "ride" } && c.faceIDs.count >= 2 }
        XCTAssertTrue(glennClustered, "Glenn's faces did not cluster")
        XCTAssertTrue(rideClustered, "Ride's faces did not cluster")
    }
}
