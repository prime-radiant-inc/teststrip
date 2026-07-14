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

    func testEncodingIsDeterministicAndOmitsEmptyProvenance() throws {
        var meta = AssetMetadata(rating: 4, keywords: ["beach", "people"])
        meta.aiUnconfirmedKeywords = ["people", "beach"]
        meta.aiUnconfirmedFields = [.rating, .flag]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(meta), as: UTF8.self)

        XCTAssertTrue(
            json.contains(#""aiUnconfirmedFields":["flag","rating"]"#),
            "expected sorted aiUnconfirmedFields, got: \(json)"
        )
        XCTAssertTrue(
            json.contains(#""aiUnconfirmedKeywords":["beach","people"]"#),
            "expected sorted aiUnconfirmedKeywords, got: \(json)"
        )

        let emptyProvenance = AssetMetadata(rating: 4, keywords: [])
        let emptyJSON = String(decoding: try encoder.encode(emptyProvenance), as: UTF8.self)
        XCTAssertEqual(emptyJSON, #"{"keywords":[],"rating":4}"#)
    }
}
