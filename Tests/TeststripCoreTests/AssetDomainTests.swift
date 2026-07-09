import XCTest
@testable import TeststripCore

final class AssetDomainTests: XCTestCase {
    func testAssetStoresExternalOriginalAndAvailability() {
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: URL(fileURLWithPath: "/Volumes/Archive/2024/frame.dng"),
            volumeIdentifier: "ArchiveVolume",
            fingerprint: FileFingerprint(size: 42, modificationDate: Date(timeIntervalSince1970: 10), contentHash: "abc"),
            availability: .offline,
            metadata: AssetMetadata(rating: 4, colorLabel: .green, flag: .pick, keywords: ["Patagonia"])
        )

        XCTAssertEqual(asset.id.rawValue, "asset-1")
        XCTAssertEqual(asset.availability, .offline)
        XCTAssertEqual(asset.metadata.rating, 4)
        XCTAssertTrue(asset.metadata.keywords.contains("Patagonia"))
    }

    func testMetadataRejectsInvalidRating() {
        XCTAssertThrowsError(try AssetMetadata.validated(rating: 6, colorLabel: nil, flag: nil, keywords: [])) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("rating must be between 0 and 5"))
        }
    }

    func testMetadataValidatedAcceptsBoundaryRatings() throws {
        XCTAssertEqual(try AssetMetadata.validated(rating: 0, colorLabel: nil, flag: nil, keywords: []).rating, 0)
        XCTAssertEqual(try AssetMetadata.validated(rating: 5, colorLabel: nil, flag: nil, keywords: []).rating, 5)
    }

    func testHasWrittenPortableMetadataReflectsUserWrites() {
        XCTAssertFalse(AssetMetadata().hasWrittenPortableMetadata)
        XCTAssertTrue(AssetMetadata(rating: 1).hasWrittenPortableMetadata)
        XCTAssertTrue(AssetMetadata(flag: .reject).hasWrittenPortableMetadata)
        XCTAssertTrue(AssetMetadata(keywords: ["beach"]).hasWrittenPortableMetadata)
        XCTAssertTrue(AssetMetadata(creator: "Jesse").hasWrittenPortableMetadata)
        // Empty strings are not writes.
        XCTAssertFalse(AssetMetadata(caption: "", creator: "").hasWrittenPortableMetadata)
    }

    func testMetadataDecodingRejectsInvalidRating() {
        let data = """
        {
            "rating": 9,
            "colorLabel": null,
            "flag": null,
            "keywords": [],
            "caption": null,
            "creator": null,
            "copyright": null
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(AssetMetadata.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("expected data corrupted decoding error, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "rating must be between 0 and 5")
        }
    }

    func testAssetIDNewProducesUUIDString() {
        let id = AssetID.new()

        XCTAssertFalse(id.rawValue.isEmpty)
        XCTAssertNotNil(UUID(uuidString: id.rawValue))
    }

    func testProviderProvenanceIdentifiesSignalSource() {
        let provenance = ProviderProvenance(provider: "AppleVision", model: "aesthetics", version: "1", settingsHash: "default")

        XCTAssertEqual(provenance.provider, "AppleVision")
        XCTAssertEqual(provenance.model, "aesthetics")
    }
}
