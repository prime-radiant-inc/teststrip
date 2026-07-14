import XCTest
@testable import TeststripCore

final class MetadataTests: XCTestCase {
    func testDecodesLegacyBlobWithoutProvenanceFields() throws {
        let json = #"{"rating":3,"keywords":["beach"]}"#
        let meta = try JSONDecoder().decode(AssetMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(meta.keywords, ["beach"])
        XCTAssertTrue(meta.aiUnconfirmedKeywords.isEmpty)
        XCTAssertTrue(meta.aiUnconfirmedFields.isEmpty)
    }

    func testProvenanceRoundTrips() throws {
        var meta = AssetMetadata(rating: 0, keywords: ["beach", "people"])
        meta.aiUnconfirmedKeywords = ["people"]
        meta.aiUnconfirmedFields = [.flag]
        meta.flag = .reject
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(AssetMetadata.self, from: data)
        XCTAssertEqual(decoded, meta)
    }

    func testConfirmedProjectionDropsUnconfirmed() throws {
        var meta = AssetMetadata(rating: 4, keywords: ["beach", "people"], caption: "a caption")
        meta.aiUnconfirmedKeywords = ["people"]
        meta.aiUnconfirmedFields = [.caption, .rating]
        meta.flag = .pick // confirmed (not in aiUnconfirmedFields)
        let confirmed = meta.confirmedProjection
        XCTAssertEqual(confirmed.keywords, ["beach"])
        XCTAssertNil(confirmed.caption)
        XCTAssertEqual(confirmed.rating, 0)
        XCTAssertEqual(confirmed.flag, .pick)
        XCTAssertTrue(confirmed.aiUnconfirmedKeywords.isEmpty)
        XCTAssertTrue(confirmed.aiUnconfirmedFields.isEmpty)
    }

    func testHasWrittenPortableMetadataIgnoresUnconfirmed() throws {
        var meta = AssetMetadata(rating: 0, keywords: ["people"])
        meta.aiUnconfirmedKeywords = ["people"]
        XCTAssertFalse(meta.hasWrittenPortableMetadata)
        meta.aiUnconfirmedKeywords = []
        XCTAssertTrue(meta.hasWrittenPortableMetadata)
    }
}
