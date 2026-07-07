import XCTest
import CoreGraphics
@testable import TeststripCore

final class ArcFaceCoreMLModelTests: XCTestCase {
    private func model() throws -> ArcFaceCoreMLModel {
        guard let m = ArcFaceCoreMLModel.bundled() else {
            throw XCTSkip("Face model not downloaded (run script/download_face_model.sh)")
        }
        return m
    }

    func testEmbeddingIs512DimAndL2Normalized() throws {
        let m = try model()
        // A solid gray 112x112 image is a valid input; we assert shape+norm, not identity.
        let ctx = CGContext(data: nil, width: 112, height: 112, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 112, height: 112))
        let img = ctx.makeImage()!
        let v = try m.embedding(for: img)
        XCTAssertEqual(v.count, 512)
        let norm = v.map { $0 * $0 }.reduce(0, +).squareRoot()
        XCTAssertEqual(norm, 1.0, accuracy: 1e-3)
    }

    func testProvenanceIsFaceRecognition() throws {
        let m = try model()
        XCTAssertEqual(m.provenance, ProviderProvenance(provider: "face-recognition", model: "arcface-w600k-r50", version: "1", settingsHash: "default"))
    }
}
