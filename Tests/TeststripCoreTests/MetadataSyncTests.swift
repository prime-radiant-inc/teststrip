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

    func testSidecarStoreWritesPortableMetadataBesideOriginal() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "xmp-sidecar-write")
        let originalURL = directory.appendingPathComponent("frame.cr2")
        try Data("original raw bytes".utf8).write(to: originalURL)
        let metadata = AssetMetadata(rating: 4, colorLabel: .yellow, flag: .pick, keywords: ["cull"])
        let store = XMPSidecarStore()

        let result = try store.write(metadata: metadata, forOriginalAt: originalURL)

        XCTAssertEqual(result.sidecarURL, originalURL.appendingPathExtension("xmp"))
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original raw bytes".utf8))
        let sidecarData = try Data(contentsOf: result.sidecarURL)
        XCTAssertEqual(result.fingerprint, XMPSidecarStore.fingerprint(for: sidecarData))
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, metadata)
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

    func testCatalogPersistsPendingMetadataSyncItems() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "metadata-sync-queue")
        let catalogURL = directory.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let item = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Volumes/NAS/frame.cr2.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: "previous"
        )

        try repository.recordMetadataSyncPending(item)
        let reopenedDatabase = try CatalogDatabase.open(at: catalogURL)
        try reopenedDatabase.migrate()
        let reopenedRepository = CatalogRepository(database: reopenedDatabase)

        XCTAssertEqual(try reopenedRepository.pendingMetadataSyncItems(), [item])
    }

    func testCatalogMarksMetadataSyncCompleteWithLastFingerprint() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "metadata-sync-complete")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assetID = AssetID(rawValue: "asset-1")
        let sidecarURL = URL(fileURLWithPath: "/Volumes/NAS/frame.cr2.xmp")
        let pending = MetadataSyncItem(
            assetID: assetID,
            sidecarURL: sidecarURL,
            catalogGeneration: 3,
            lastSyncedFingerprint: nil
        )

        try repository.recordMetadataSyncPending(pending)
        try repository.markMetadataSynced(
            assetID: assetID,
            sidecarURL: sidecarURL,
            catalogGeneration: 3,
            fingerprint: "written"
        )

        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(try repository.lastMetadataSyncFingerprint(assetID: assetID), "written")
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
