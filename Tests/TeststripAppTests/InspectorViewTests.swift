import XCTest
import TeststripCore
@testable import TeststripApp

final class InspectorViewTests: XCTestCase {
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

    private func makeAsset(id: String, metadata: AssetMetadata) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: metadata
        )
    }
}
