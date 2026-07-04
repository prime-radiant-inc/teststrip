import XCTest
import CoreGraphics
import TeststripCore
@testable import TeststripApp

final class InspectorViewTests: XCTestCase {
    func testSelectedPreviewLayoutPinsSize() {
        XCTAssertEqual(InspectorPreviewLayout.size, CGSize(width: 258, height: 186))
    }

    func testAssetIdentitySplitsFilenameExtensionAndStatus() {
        let asset = makeAsset(
            id: "identity",
            originalURL: URL(fileURLWithPath: "/Photos/Patagonia/frame-001.CR2"),
            availability: .offline,
            metadata: AssetMetadata(rating: 4)
        )

        let identity = InspectorAssetIdentity(asset: asset)

        XCTAssertEqual(identity.fullFilename, "frame-001.CR2")
        XCTAssertEqual(identity.displayName, "frame-001")
        XCTAssertEqual(identity.extensionBadge, "CR2")
        XCTAssertEqual(identity.availabilityText, "Availability: offline")
        XCTAssertEqual(identity.ratingText, "Rating: 4")
        XCTAssertNil(identity.capturedText)
    }

    func testAssetIdentityUsesCapturedDateWhenTechnicalMetadataExists() {
        let asset = makeAsset(
            id: "captured",
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: Date(timeIntervalSince1970: 1_704_067_200),
                provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
            )
        )

        let identity = InspectorAssetIdentity(asset: asset)

        XCTAssertNotNil(identity.capturedText)
    }

    func testTechnicalRowsUseCompactCatalogMetadata() {
        let metadata = AssetTechnicalMetadata(
            pixelWidth: 8256,
            pixelHeight: 5504,
            cameraMake: "Fujifilm",
            cameraModel: "GFX 100S",
            lensModel: "GF45-100mmF4",
            isoSpeed: 800,
            capturedAt: nil,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        XCTAssertEqual(
            InspectorTechnicalRows(metadata: metadata).rows,
            [
                InspectorMetadataRow(title: "Dimensions", value: "8256 x 5504"),
                InspectorMetadataRow(title: "Camera", value: "Fujifilm GFX 100S"),
                InspectorMetadataRow(title: "Lens", value: "GF45-100mmF4"),
                InspectorMetadataRow(title: "ISO", value: "800")
            ]
        )
    }

    func testMetadataDraftFormatsPortableMetadataFromAsset() {
        let asset = makeAsset(
            id: "draft-asset",
            metadata: AssetMetadata(
                keywords: ["Patagonia", "keeper"],
                caption: "Fitz Roy sunrise",
                creator: "Jesse",
                copyright: "Copyright Jesse"
            )
        )

        let draft = InspectorMetadataDraft(asset: asset)

        XCTAssertEqual(draft.assetID, asset.id)
        XCTAssertEqual(draft.keywords, "Patagonia, keeper")
        XCTAssertEqual(draft.caption, "Fitz Roy sunrise")
        XCTAssertEqual(draft.creator, "Jesse")
        XCTAssertEqual(draft.copyright, "Copyright Jesse")
    }

    func testMetadataDraftResetsOnlyWhenSelectionChanges() {
        let first = makeAsset(
            id: "first",
            metadata: AssetMetadata(keywords: ["first"], caption: "First caption")
        )
        let second = makeAsset(
            id: "second",
            metadata: AssetMetadata(keywords: ["second"], caption: "Second caption")
        )
        var draft = InspectorMetadataDraft(asset: first)
        draft.caption = "Unsaved typing"

        draft.sync(to: first)
        XCTAssertEqual(draft.caption, "Unsaved typing")

        draft.sync(to: second)
        XCTAssertEqual(draft.assetID, second.id)
        XCTAssertEqual(draft.keywords, "second")
        XCTAssertEqual(draft.caption, "Second caption")
    }

    func testMetadataDraftRefreshesSameSelectionWhenSourceMetadataChanges() {
        let original = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["first"], caption: "First caption")
        )
        let updated = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["updated"], caption: "Updated caption")
        )
        var draft = InspectorMetadataDraft(asset: original)

        draft.sync(to: updated)

        XCTAssertEqual(draft.assetID, updated.id)
        XCTAssertEqual(draft.keywords, "updated")
        XCTAssertEqual(draft.caption, "Updated caption")
    }

    func testMetadataDraftTracksAppliedSameSelectionChangesForUndoRefresh() {
        let original = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["first"], caption: "First caption")
        )
        let applied = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["first"], caption: "Applied caption")
        )
        var draft = InspectorMetadataDraft(asset: original)
        draft.caption = "Applied caption"

        draft.sync(to: applied)
        draft.sync(to: original)

        XCTAssertEqual(draft.caption, "First caption")
    }

    private func makeAsset(
        id: String,
        originalURL: URL? = nil,
        availability: SourceAvailability = .online,
        metadata: AssetMetadata,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: originalURL ?? URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: availability,
            metadata: metadata,
            technicalMetadata: technicalMetadata
        )
    }
}
