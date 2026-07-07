import XCTest
import CoreGraphics
import ImageIO
@testable import TeststripCore

private struct StubModel: FaceEmbeddingModel {
    let provenance = ProviderProvenance(provider: "face-recognition", model: "stub", version: "1", settingsHash: "default")
    func embedding(for alignedFace: CGImage) throws -> [Double] {
        var v = [Double](repeating: 0, count: 512); v[0] = 1; return v   // unit vector
    }
}

final class FaceRecognitionEmbedderTests: XCTestCase {
    func testProducesOneNormalizedObservationPerDetectedFace() throws {
        guard let url = Bundle.faceCorpusImageURL() else { throw XCTSkip("face corpus not downloaded") }
        let cg = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let embedder = FaceRecognitionEmbedder(model: StubModel())
        let observations = try embedder.faceObservations(in: cg)
        XCTAssertGreaterThanOrEqual(observations.count, 1)
        for o in observations { XCTAssertEqual(o.featurePrintVector.count, 512) }
    }
}
