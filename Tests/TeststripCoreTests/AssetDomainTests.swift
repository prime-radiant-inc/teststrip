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

    func testProviderProvenanceIdentifiesSignalSource() {
        let provenance = ProviderProvenance(provider: "AppleVision", model: "aesthetics", version: "1", settingsHash: "default")

        XCTAssertEqual(provenance.provider, "AppleVision")
        XCTAssertEqual(provenance.model, "aesthetics")
    }
}
