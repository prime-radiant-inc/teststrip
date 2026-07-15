import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import TeststripCore

final class ContactFaceSeederTests: XCTestCase {
    private func repo() throws -> (CatalogRepository, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try CatalogDatabase.open(at: dir.appendingPathComponent("c.sqlite")); try db.migrate()
        return (CatalogRepository(database: db), dir)
    }

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

    func testSeedsLatentContactWhenNoNameMatch() throws {
        let (r, dir) = try repo()
        let seeder = ContactFaceSeeder(
            detectFaces: { _ in [Self.face(0.9)] },
            repository: r, photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        let summary = try seeder.seed(records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: jpeg())])

        XCTAssertEqual(summary.seeded, 1)
        XCTAssertEqual(try r.contactReferenceEmbeddingsByPerson(), ["contact:C1": [[0.5, 0.5]]])
        XCTAssertEqual(try r.contactReferenceNamesByPerson()["contact:C1"], "Dan Shapiro")
    }

    func testSeedAttachesToExistingPersonByName() throws {
        let (r, dir) = try repo()
        try r.upsertPerson(id: "p1", name: "Dan Shapiro")
        let seeder = ContactFaceSeeder(detectFaces: { _ in [Self.face(0.9)] }, repository: r,
                                       photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        _ = try seeder.seed(records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: jpeg())])
        XCTAssertEqual(try r.contactReferenceEmbeddingsByPerson().keys.sorted(), ["p1"]) // attached, not latent
    }

    func testSkipsContactWithNoDetectableFace() throws {
        let (r, dir) = try repo()
        let seeder = ContactFaceSeeder(detectFaces: { _ in [] }, repository: r,
                                       photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        let summary = try seeder.seed(records: [ContactRecord(identifier: "C1", name: "Dan", imageData: jpeg())])
        XCTAssertEqual(summary.skippedNoFace, 1)
        XCTAssertTrue(try r.contactReferenceEmbeddingsByPerson().isEmpty)
    }

    func testUnchangedPhotoIsSkippedOnReseed() throws {
        let (r, dir) = try repo()
        let seeder = ContactFaceSeeder(detectFaces: { _ in [Self.face(0.9)] }, repository: r,
                                       photoCache: ContactPhotoCache(root: dir.appendingPathComponent("photos")))
        let record = ContactRecord(identifier: "C1", name: "Dan", imageData: jpeg())
        _ = try seeder.seed(records: [record])
        let second = try seeder.seed(records: [record])
        XCTAssertEqual(second.unchanged, 1)
        XCTAssertEqual(second.seeded, 0)
    }
}
