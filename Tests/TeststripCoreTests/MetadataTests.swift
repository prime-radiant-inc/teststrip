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

    func testMergingConfirmedSidecarPreservesCatalogAILabels() throws {
        // Catalog holds a confirmed keyword plus an AI-proposed, unconfirmed
        // one; the sidecar (confirmed labels only, per confirmedProjection)
        // has just the confirmed keyword. Importing/freshening from the
        // sidecar must not wipe the still-unconfirmed catalog proposal.
        var catalogMetadata = AssetMetadata(keywords: ["beach", "people"])
        catalogMetadata.aiUnconfirmedKeywords = ["people"]
        let sidecarMetadata = AssetMetadata(keywords: ["beach"])

        let merged = catalogMetadata.mergingConfirmedSidecar(sidecarMetadata)

        XCTAssertEqual(Set(merged.keywords), ["beach", "people"])
        XCTAssertEqual(merged.aiUnconfirmedKeywords, ["people"])
    }

    func testMergingConfirmedSidecarRestoresUnconfirmedCaptionFlagAndRating() throws {
        var catalogMetadata = AssetMetadata(rating: 4, flag: .pick, caption: "AI caption")
        catalogMetadata.aiUnconfirmedFields = [.caption, .flag, .rating]
        let sidecarMetadata = AssetMetadata(rating: 0, keywords: ["confirmed"])

        let merged = catalogMetadata.mergingConfirmedSidecar(sidecarMetadata)

        XCTAssertEqual(merged.keywords, ["confirmed"])
        XCTAssertEqual(merged.rating, 4)
        XCTAssertEqual(merged.flag, .pick)
        XCTAssertEqual(merged.caption, "AI caption")
        XCTAssertEqual(merged.aiUnconfirmedFields, [.caption, .flag, .rating])
    }

    func testMergePrefersConfirmedSidecarValueOverUnconfirmedAI() throws {
        // A field/keyword the sidecar already carries is confirmed — even
        // when the catalog still marks it AI-unconfirmed, an external tool's
        // (or human's) sidecar value wins and the field graduates to
        // confirmed rather than being clobbered by the stale AI value.
        var catalogMetadata = AssetMetadata(rating: 2, flag: .pick, keywords: ["people"], caption: "ai guess")
        catalogMetadata.aiUnconfirmedFields = [.caption, .flag, .rating]
        catalogMetadata.aiUnconfirmedKeywords = ["people"]
        let sidecarMetadata = AssetMetadata(rating: 5, flag: .reject, keywords: ["people"], caption: "human caption")

        let merged = catalogMetadata.mergingConfirmedSidecar(sidecarMetadata)

        XCTAssertEqual(merged.caption, "human caption")
        XCTAssertFalse(merged.aiUnconfirmedFields.contains(.caption))
        XCTAssertEqual(merged.flag, .reject)
        XCTAssertFalse(merged.aiUnconfirmedFields.contains(.flag))
        XCTAssertEqual(merged.rating, 5)
        XCTAssertFalse(merged.aiUnconfirmedFields.contains(.rating))
        XCTAssertTrue(merged.keywords.contains("people"))
        XCTAssertFalse(merged.aiUnconfirmedKeywords.contains("people"))

        // Original preserve-case: the sidecar has no caption at all, so the
        // catalog's unconfirmed AI value is restored and stays unconfirmed.
        var catalogOnlyMetadata = AssetMetadata(caption: "ai guess")
        catalogOnlyMetadata.aiUnconfirmedFields = [.caption]
        let emptySidecarMetadata = AssetMetadata()

        let preserved = catalogOnlyMetadata.mergingConfirmedSidecar(emptySidecarMetadata)

        XCTAssertEqual(preserved.caption, "ai guess")
        XCTAssertTrue(preserved.aiUnconfirmedFields.contains(.caption))
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
