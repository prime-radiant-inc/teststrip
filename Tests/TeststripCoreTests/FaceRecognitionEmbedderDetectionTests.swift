import XCTest
import CoreGraphics
import ImageIO
@testable import TeststripCore

/// Regression: the embedder must detect faces as well as the dedicated
/// rectangle detector does. A hard EVA/helmet shot that VNDetectFaceRectangles
/// finds was being missed because the embedder ran VNDetectFaceLandmarksRequest
/// standalone (weaker built-in detector); it must seed landmarks with rectangle
/// results. Corpus-gated.
final class FaceRecognitionEmbedderDetectionTests: XCTestCase {
    private func corpusImage(_ name: String) throws -> CGImage {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("sample-data/photos/faces/\(name)")
        guard FileManager.default.fileExists(atPath: url.path),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw XCTSkip("corpus image \(name) not downloaded")
        }
        return cg
    }

    private struct UnitModel: FaceEmbeddingModel {
        let provenance = ProviderProvenance(provider: "face-recognition", model: "unit", version: "1", settingsHash: "default")
        func embedding(for alignedFace: CGImage) throws -> [Double] {
            var v = [Double](repeating: 0, count: 512); v[0] = 1; return v
        }
    }

    func testEmbedsHardEVAFaceThatRectangleDetectorFinds() throws {
        let image = try corpusImage("commons-armstrong-eva-training.jpg")
        let embedder = FaceRecognitionEmbedder(model: UnitModel())
        let observations = try embedder.faceObservations(in: image)
        XCTAssertGreaterThanOrEqual(
            observations.count, 1,
            "embedder found no face in a shot the rectangle detector detects — landmarks request is not seeded with rectangle results"
        )
    }

    func testEveryCorpusPortraitEmbedsAtLeastOneFace() throws {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("sample-data/photos/faces")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              !files.filter({ $0.pathExtension == "jpg" }).isEmpty else {
            throw XCTSkip("corpus not downloaded")
        }
        let embedder = FaceRecognitionEmbedder(model: UnitModel())
        var missed: [String] = []
        for url in files.filter({ $0.pathExtension == "jpg" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            if (try embedder.faceObservations(in: cg)).isEmpty { missed.append(url.lastPathComponent) }
        }
        XCTAssertEqual(missed, [], "these portraits embedded no face: \(missed)")
    }
}
