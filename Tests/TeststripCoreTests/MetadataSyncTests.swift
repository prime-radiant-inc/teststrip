import XCTest
@testable import TeststripCore

final class MetadataSyncTests: XCTestCase {
    func testXMPPacketParseThrowsForInvalidColorLabel() {
        assertParseInvalidState(
            xmpData("<colorLabel>orange</colorLabel>"),
            .invalidState("invalid XMP color label: orange")
        )
    }

    func testXMPPacketParseThrowsForInvalidFlag() {
        assertParseInvalidState(
            xmpData("<flag>favorite</flag>"),
            .invalidState("invalid XMP flag: favorite")
        )
    }

    func testXMPPacketParseThrowsForInvalidRootShape() {
        assertParseInvalidState(
            Data("<not-xmp/>".utf8),
            .invalidState("invalid XMP root element: not-xmp")
        )
    }

    func testXMPPacketParseThrowsForNonNumericRating() {
        assertParseInvalidState(
            xmpData("<rating>unrated</rating>"),
            .invalidState("invalid XMP rating: unrated")
        )
    }

    func testXMPPacketParseThrowsForOutOfRangeRating() {
        assertParseInvalidState(
            xmpData("<rating>9</rating>"),
            .invalidState("rating must be between 0 and 5")
        )
    }

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

    private func assertParseInvalidState(
        _ data: Data,
        _ expectedError: TeststripError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try XMPPacket.parse(data), file: file, line: line) { error in
            XCTAssertEqual(error as? TeststripError, expectedError, file: file, line: line)
        }
    }

    private func xmpData(_ body: String) -> Data {
        Data("<xmpmeta>\(body)</xmpmeta>".utf8)
    }
}
