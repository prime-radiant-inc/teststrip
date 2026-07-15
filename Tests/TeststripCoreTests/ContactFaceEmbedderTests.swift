import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import TeststripCore

// Covers the off-main-thread embed phase split out of `ContactFaceSeeder`
// (see AppModel.importFacesFromContacts, which runs this inside a
// Task.detached so the Contacts fetch + CoreML embedding never touch main).
final class ContactFaceEmbedderTests: XCTestCase {
    // A tiny valid JPEG so decoding succeeds; face detection is stubbed via the seam.
    private func jpeg() -> Data {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
        return data as Data
    }

    // static: called from inside @Sendable detectFaces closures below, which
    // can't capture `self` (XCTestCase is not Sendable).
    private static func face(_ quality: Double) -> AppleVisionFaceObservation {
        AppleVisionFaceObservation(boundingBox: FaceBoundingBox(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                                   captureQuality: quality, featurePrintVector: [0.5, 0.5])
    }

    func testEmbedsOneFaceWithHashAndEmbedding() throws {
        let embedder = ContactFaceEmbedder(detectFaces: { _ in [Self.face(0.9)] })
        let data = jpeg()
        let result = try embedder.embed(
            records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: data)],
            currentHashes: [:]
        )

        XCTAssertEqual(result.embedded.count, 1)
        let face = try XCTUnwrap(result.embedded.first)
        XCTAssertEqual(face.identifier, "C1")
        XCTAssertEqual(face.name, "Dan Shapiro")
        XCTAssertEqual(face.imageData, data)
        XCTAssertEqual(face.embedding, [0.5, 0.5])
        XCTAssertEqual(face.boundingBox, FaceBoundingBox(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        XCTAssertEqual(face.photoHash, ContactFaceEmbedder.hash(data))
        XCTAssertEqual(result.unchanged, 0)
        XCTAssertEqual(result.skippedNoFace, 0)
    }

    func testUnchangedHashIsSkipped() throws {
        let data = jpeg()
        let embedder = ContactFaceEmbedder(detectFaces: { _ in [Self.face(0.9)] })
        let hash = ContactFaceEmbedder.hash(data)

        let result = try embedder.embed(
            records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: data)],
            currentHashes: ["C1": hash]
        )

        XCTAssertEqual(result.embedded, [])
        XCTAssertEqual(result.unchanged, 1)
        XCTAssertEqual(result.skippedNoFace, 0)
    }

    func testNoFaceDetectedIsSkipped() throws {
        let embedder = ContactFaceEmbedder(detectFaces: { _ in [] })
        let result = try embedder.embed(
            records: [ContactRecord(identifier: "C1", name: "Dan", imageData: jpeg())],
            currentHashes: [:]
        )

        XCTAssertEqual(result.embedded, [])
        XCTAssertEqual(result.unchanged, 0)
        XCTAssertEqual(result.skippedNoFace, 1)
    }

    func testUndecodableImageIsSkippedAsNoFace() throws {
        let embedder = ContactFaceEmbedder(detectFaces: { _ in [Self.face(0.9)] })
        let result = try embedder.embed(
            records: [ContactRecord(identifier: "C1", name: "Dan", imageData: Data([0x00, 0x01, 0x02]))],
            currentHashes: [:]
        )

        XCTAssertEqual(result.embedded, [])
        XCTAssertEqual(result.skippedNoFace, 1)
    }

    func testPicksHighestQualityFaceWhenMultipleDetected() throws {
        let embedder = ContactFaceEmbedder(detectFaces: { _ in
            [
                AppleVisionFaceObservation(boundingBox: FaceBoundingBox(x: 0, y: 0, width: 0.1, height: 0.1),
                                           captureQuality: 0.2, featurePrintVector: [0.1]),
                AppleVisionFaceObservation(boundingBox: FaceBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
                                           captureQuality: 0.95, featurePrintVector: [0.9]),
            ]
        })
        let result = try embedder.embed(
            records: [ContactRecord(identifier: "C1", name: "Dan", imageData: jpeg())],
            currentHashes: [:]
        )

        XCTAssertEqual(result.embedded.first?.embedding, [0.9])
    }
}
