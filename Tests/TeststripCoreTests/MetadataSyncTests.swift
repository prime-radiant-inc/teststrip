import XCTest
@testable import TeststripCore

final class MetadataSyncTests: XCTestCase {
    func testXMPPacketRoundTripsPortableMetadata() throws {
        let metadata = AssetMetadata(
            rating: 5,
            colorLabel: .green,
            flag: .pick,
            keywords: ["Patagonia", "mountains"],
            caption: "Fitz Roy sunrise",
            creator: "Jesse",
            copyright: "Copyright Jesse"
        )

        let xml = try XMPPacket(metadata: metadata).xmlData()
        let parsed = try XMPPacket.parse(xml)

        XCTAssertEqual(parsed.metadata.rating, 5)
        XCTAssertEqual(parsed.metadata.colorLabel, .green)
        XCTAssertEqual(parsed.metadata.flag, .pick)
        XCTAssertEqual(parsed.metadata.keywords, ["Patagonia", "mountains"])
        XCTAssertEqual(parsed.metadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(parsed.metadata.creator, "Jesse")
        XCTAssertEqual(parsed.metadata.copyright, "Copyright Jesse")
    }

    func testSyncQueueTracksPendingWriteWithCatalogGeneration() {
        let item = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.xmp"),
            catalogGeneration: 7,
            lastSyncedFingerprint: "old"
        )

        XCTAssertEqual(item.catalogGeneration, 7)
        XCTAssertEqual(item.lastSyncedFingerprint, "old")
    }
}
