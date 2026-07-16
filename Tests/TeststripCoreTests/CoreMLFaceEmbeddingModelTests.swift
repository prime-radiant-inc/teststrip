import XCTest
import CoreGraphics
@testable import TeststripCore

final class CoreMLFaceEmbeddingModelTests: XCTestCase {
    private func model() throws -> CoreMLFaceEmbeddingModel {
        guard let m = CoreMLFaceEmbeddingModel.auraFace() else {
            throw XCTSkip("Compiled face model missing (run script/download_face_model.sh, or script/compile_face_models.sh if the .mlpackage is already downloaded)")
        }
        return m
    }

    func testInitRejectsUncompiledPackage() throws {
        let package = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("sample-data/models/auraface-v1.mlpackage")
        guard FileManager.default.fileExists(atPath: package.path) else {
            throw XCTSkip("Face model package not downloaded (run script/download_face_model.sh)")
        }
        // Runtime loading must never compile: MLModel.compileModel writes a fresh
        // ~125 MB .mlmodelc into the process temp dir per call and nothing cleans
        // it up. Compilation belongs to script/compile_face_models.sh; an
        // uncompiled .mlpackage is rejected here.
        XCTAssertNil(CoreMLFaceEmbeddingModel(
            modelURL: package,
            provenance: ProviderProvenance(provider: "face-recognition", model: "auraface-v1", version: "1", settingsHash: "default")
        ))
    }

    func testCandidateURLsPointAtPrecompiledModels() {
        let urls = CoreMLFaceEmbeddingModel.candidateURLs(baseName: "auraface-v1")
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            XCTAssertEqual(url.pathExtension, "mlmodelc", "runtime candidate must be precompiled: \(url.path)")
        }
        XCTAssertTrue(urls.contains { $0.path.hasSuffix("sample-data/models/auraface-v1.mlmodelc") })
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
        XCTAssertEqual(m.provenance, ProviderProvenance(provider: "face-recognition", model: "auraface-v1", version: "1", settingsHash: "default"))
    }
}
