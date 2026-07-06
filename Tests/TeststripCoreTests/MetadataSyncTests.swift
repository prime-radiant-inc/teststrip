import XCTest
@testable import TeststripCore

final class MetadataSyncTests: XCTestCase {
    func testXMPPacketParseThrowsForInvalidColorLabel() {
        assertParseInvalidState(
            standardXMP(attributes: "xmp:Label=\"Orange\""),
            .invalidState("invalid XMP color label: Orange")
        )
    }

    func testXMPPacketParseThrowsForInvalidFlag() {
        assertParseInvalidState(
            standardXMP(attributes: "ts:Pick=\"favorite\""),
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
            standardXMP(attributes: "xmp:Rating=\"unrated\""),
            .invalidState("invalid XMP rating: unrated")
        )
    }

    func testXMPPacketParseThrowsForOutOfRangeRating() {
        assertParseInvalidState(
            standardXMP(attributes: "xmp:Rating=\"9\""),
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

    func testXMPPacketParsesStandardRDFSidecarMetadata() throws {
        let xml = standardXMP(
            attributes: "xmp:Rating=\"5\" xmp:Label=\"Green\" ts:Pick=\"pick\"",
            body: """
            <dc:subject>
              <rdf:Bag>
                <rdf:li>Patagonia</rdf:li>
                <rdf:li>mountains</rdf:li>
              </rdf:Bag>
            </dc:subject>
            <dc:description>
              <rdf:Alt>
                <rdf:li xml:lang="x-default">Fitz Roy sunrise</rdf:li>
              </rdf:Alt>
            </dc:description>
            <dc:creator>
              <rdf:Seq>
                <rdf:li>Jesse</rdf:li>
              </rdf:Seq>
            </dc:creator>
            <dc:rights>
              <rdf:Alt>
                <rdf:li xml:lang="x-default">Copyright Jesse</rdf:li>
              </rdf:Alt>
            </dc:rights>
            """
        )

        let parsed = try XMPPacket.parse(xml)

        XCTAssertEqual(parsed.metadata.rating, 5)
        XCTAssertEqual(parsed.metadata.colorLabel, .green)
        XCTAssertEqual(parsed.metadata.flag, .pick)
        XCTAssertEqual(parsed.metadata.keywords, ["Patagonia", "mountains"])
        XCTAssertEqual(parsed.metadata.caption, "Fitz Roy sunrise")
        XCTAssertEqual(parsed.metadata.creator, "Jesse")
        XCTAssertEqual(parsed.metadata.copyright, "Copyright Jesse")
    }

    func testXMPPacketWritesAdobeCompatibleRDFProperties() throws {
        let metadata = AssetMetadata(
            rating: 5,
            colorLabel: .green,
            flag: .reject,
            keywords: ["Patagonia", "mountains"],
            caption: "Fitz Roy sunrise",
            creator: "Jesse",
            copyright: "Copyright Jesse"
        )

        let xml = try XMPPacket(metadata: metadata).xmlData()
        let document = try XMLDocument(data: xml)
        let root = try XCTUnwrap(document.rootElement())
        let description = try rdfDescription(in: document)

        XCTAssertEqual(root.localName, "xmpmeta")
        XCTAssertEqual(root.uri, xmpMetaNamespace)
        XCTAssertEqual(attribute(description, localName: "Rating", uri: xmpNamespace), "5")
        XCTAssertEqual(attribute(description, localName: "Label", uri: xmpNamespace), "Green")
        XCTAssertEqual(attribute(description, localName: "Pick", uri: teststripNamespace), "reject")
        XCTAssertEqual(rdfContainerValues(in: description, propertyLocalName: "subject", containerLocalName: "Bag"), ["Patagonia", "mountains"])
        XCTAssertEqual(rdfContainerValues(in: description, propertyLocalName: "description", containerLocalName: "Alt"), ["Fitz Roy sunrise"])
        XCTAssertEqual(rdfContainerValues(in: description, propertyLocalName: "creator", containerLocalName: "Seq"), ["Jesse"])
        XCTAssertEqual(rdfContainerValues(in: description, propertyLocalName: "rights", containerLocalName: "Alt"), ["Copyright Jesse"])
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

    func testSidecarStoreWritesIntoExistingAdobeStyleSidecarWhenUnambiguous() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "xmp-sidecar-adobe-style")
        let originalURL = directory.appendingPathComponent("frame.cr2")
        let sidecarURL = directory.appendingPathComponent("frame.xmp")
        try Data("original raw bytes".utf8).write(to: originalURL)
        try XMPPacket(metadata: AssetMetadata(rating: 1, keywords: ["external"])).xmlData().write(to: sidecarURL)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])

        let result = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: originalURL)

        XCTAssertEqual(result.sidecarURL, sidecarURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.appendingPathExtension("xmp").path))
        let sidecarData = try Data(contentsOf: sidecarURL)
        XCTAssertEqual(result.fingerprint, XMPSidecarStore.fingerprint(for: sidecarData))
        XCTAssertEqual(try XMPPacket.parse(sidecarData).metadata, metadata)
    }

    func testSidecarStoreDoesNotUseAdobeStyleSidecarForAmbiguousBasename() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "xmp-sidecar-ambiguous-adobe-style")
        let originalURL = directory.appendingPathComponent("frame.cr2")
        let siblingURL = directory.appendingPathComponent("frame.jpg")
        let adobeStyleSidecarURL = directory.appendingPathComponent("frame.xmp")
        try Data("original raw bytes".utf8).write(to: originalURL)
        try Data("sibling jpg bytes".utf8).write(to: siblingURL)
        try XMPPacket(metadata: AssetMetadata(rating: 1, keywords: ["external"])).xmlData().write(to: adobeStyleSidecarURL)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])

        let result = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: originalURL)

        XCTAssertEqual(result.sidecarURL, originalURL.appendingPathExtension("xmp"))
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: adobeStyleSidecarURL)).metadata.rating, 1)
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: result.sidecarURL)).metadata, metadata)
    }

    func testSidecarStoreUsesAmbiguousAdobeStyleSidecarWhenSidecarForExtensionMatchesOriginal() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "xmp-sidecar-ambiguous-claimed")
        let originalURL = directory.appendingPathComponent("frame.RAF")
        let siblingURL = directory.appendingPathComponent("frame.JPG")
        let adobeStyleSidecarURL = directory.appendingPathComponent("frame.xmp")
        try Data("original raw bytes".utf8).write(to: originalURL)
        try Data("sibling jpg bytes".utf8).write(to: siblingURL)
        try standardXMP(
            attributes: "xmp:Rating=\"1\" photoshop:SidecarForExtension=\"raf\"",
            extraDescriptionNamespaces: "xmlns:photoshop=\"\(photoshopNamespace)\""
        ).write(to: adobeStyleSidecarURL)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])

        let result = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: originalURL)

        XCTAssertEqual(result.sidecarURL, adobeStyleSidecarURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.appendingPathExtension("xmp").path))
        let document = try XMLDocument(data: Data(contentsOf: adobeStyleSidecarURL))
        let description = try rdfDescription(in: document)
        XCTAssertEqual(attribute(description, localName: "SidecarForExtension", uri: photoshopNamespace), "raf")
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: adobeStyleSidecarURL)).metadata, metadata)
    }

    func testSidecarStoreIgnoresAmbiguousAdobeStyleSidecarWhenSidecarForExtensionNamesOtherOriginal() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "xmp-sidecar-ambiguous-other-claim")
        let rawURL = directory.appendingPathComponent("frame.RAF")
        let jpegURL = directory.appendingPathComponent("frame.JPG")
        let adobeStyleSidecarURL = directory.appendingPathComponent("frame.xmp")
        try Data("original raw bytes".utf8).write(to: rawURL)
        try Data("sibling jpg bytes".utf8).write(to: jpegURL)
        try standardXMP(
            attributes: "xmp:Rating=\"1\" photoshop:SidecarForExtension=\"raf\"",
            extraDescriptionNamespaces: "xmlns:photoshop=\"\(photoshopNamespace)\""
        ).write(to: adobeStyleSidecarURL)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])

        let result = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: jpegURL)

        XCTAssertEqual(result.sidecarURL, jpegURL.appendingPathExtension("xmp"))
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: adobeStyleSidecarURL)).metadata.rating, 1)
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: result.sidecarURL)).metadata, metadata)
    }

    func testSidecarStoreIgnoresAmbiguousAdobeStyleSidecarThatCannotBeParsed() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "xmp-sidecar-ambiguous-unparsable")
        let originalURL = directory.appendingPathComponent("frame.RAF")
        let siblingURL = directory.appendingPathComponent("frame.JPG")
        let adobeStyleSidecarURL = directory.appendingPathComponent("frame.xmp")
        try Data("original raw bytes".utf8).write(to: originalURL)
        try Data("sibling jpg bytes".utf8).write(to: siblingURL)
        try Data("not xml".utf8).write(to: adobeStyleSidecarURL)
        let metadata = AssetMetadata(rating: 5, colorLabel: .green, flag: .pick, keywords: ["keeper"])

        let result = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: originalURL)

        XCTAssertEqual(result.sidecarURL, originalURL.appendingPathExtension("xmp"))
        XCTAssertEqual(try Data(contentsOf: adobeStyleSidecarURL), Data("not xml".utf8))
        XCTAssertEqual(try XMPPacket.parse(Data(contentsOf: result.sidecarURL)).metadata, metadata)
    }

    func testSidecarStorePreservesUnmanagedXMPPropertiesWhenWritingPortableMetadata() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "xmp-sidecar-merge")
        let originalURL = directory.appendingPathComponent("frame.cr2")
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        try Data("original raw bytes".utf8).write(to: originalURL)
        try standardXMP(
            attributes: """
            xmp:Rating="1" xmp:Label="Red" ts:Pick="reject" photoshop:DateCreated="2024-01-02T03:04:05"
            """,
            body: """
            <dc:title>
              <rdf:Alt>
                <rdf:li xml:lang="x-default">External title</rdf:li>
              </rdf:Alt>
            </dc:title>
            <dc:subject>
              <rdf:Bag>
                <rdf:li>stale-keyword</rdf:li>
              </rdf:Bag>
            </dc:subject>
            """,
            extraDescriptionNamespaces: "xmlns:photoshop=\"\(photoshopNamespace)\""
        ).write(to: sidecarURL)
        let metadata = AssetMetadata(
            rating: 4,
            colorLabel: .green,
            flag: .pick,
            keywords: ["keeper"],
            caption: "Catalog caption"
        )

        _ = try XMPSidecarStore().write(metadata: metadata, forOriginalAt: originalURL)

        let document = try XMLDocument(data: Data(contentsOf: sidecarURL))
        let description = try rdfDescription(in: document)
        XCTAssertEqual(attribute(description, localName: "DateCreated", uri: photoshopNamespace), "2024-01-02T03:04:05")
        XCTAssertEqual(rdfContainerValues(in: description, propertyLocalName: "title", containerLocalName: "Alt"), ["External title"])
        XCTAssertEqual(attribute(description, localName: "Rating", uri: xmpNamespace), "4")
        XCTAssertEqual(attribute(description, localName: "Label", uri: xmpNamespace), "Green")
        XCTAssertEqual(attribute(description, localName: "Pick", uri: teststripNamespace), "pick")
        XCTAssertEqual(rdfContainerValues(in: description, propertyLocalName: "subject", containerLocalName: "Bag"), ["keeper"])
        XCTAssertEqual(rdfContainerValues(in: description, propertyLocalName: "description", containerLocalName: "Alt"), ["Catalog caption"])
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
        let beforeSync = Date()

        try repository.recordMetadataSyncPending(pending)
        try repository.markMetadataSynced(
            assetID: assetID,
            sidecarURL: sidecarURL,
            catalogGeneration: 3,
            fingerprint: "written"
        )
        let afterSync = Date()

        XCTAssertEqual(try repository.pendingMetadataSyncItems(), [])
        XCTAssertEqual(try repository.lastMetadataSyncFingerprint(assetID: assetID), "written")
        let syncedItem = try XCTUnwrap(try repository.metadataSyncItem(assetID: assetID))
        let lastSyncedAt = try XCTUnwrap(syncedItem.lastSyncedAt)
        XCTAssertGreaterThanOrEqual(lastSyncedAt.timeIntervalSince1970, beforeSync.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(lastSyncedAt.timeIntervalSince1970, afterSync.timeIntervalSince1970)
    }

    func testPlannerImportsSidecarWhenOnlySidecarChanged() throws {
        let catalogMetadata = AssetMetadata(rating: 2)
        let sidecarMetadata = AssetMetadata(rating: 5, keywords: ["external"])
        let previousSidecarData = try XMPPacket(metadata: catalogMetadata).xmlData()
        let currentSidecarData = try XMPPacket(metadata: sidecarMetadata).xmlData()
        let lastSynced = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.cr2.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: XMPSidecarStore.fingerprint(for: previousSidecarData)
        )

        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: catalogMetadata,
            catalogGeneration: 3,
            lastSynced: lastSynced,
            sidecarData: currentSidecarData
        )

        XCTAssertEqual(decision, .importSidecar(sidecarMetadata))
    }

    func testPlannerImportsSidecarWhenSidecarModificationDateIsNewerThanCheckpoint() throws {
        let metadata = AssetMetadata(rating: 4, keywords: ["external"])
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        let lastSynced = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.cr2.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: XMPSidecarStore.fingerprint(for: sidecarData),
            lastSyncedAt: Date(timeIntervalSince1970: 100)
        )

        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: metadata,
            catalogGeneration: 3,
            lastSynced: lastSynced,
            sidecarData: sidecarData,
            sidecarModificationDate: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(decision, .importSidecar(metadata))
    }

    func testPlannerWritesCatalogWhenOnlyCatalogGenerationChanged() throws {
        let metadata = AssetMetadata(rating: 4)
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        let lastSynced = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.cr2.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )

        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: metadata,
            catalogGeneration: 4,
            lastSynced: lastSynced,
            sidecarData: sidecarData
        )

        XCTAssertEqual(decision, .writeCatalog)
    }

    func testPlannerWritesCatalogWhenCatalogChangedAndSidecarOnlyHasNewerTimestamp() throws {
        let previousMetadata = AssetMetadata(rating: 2)
        let catalogMetadata = AssetMetadata(rating: 5)
        let sidecarData = try XMPPacket(metadata: previousMetadata).xmlData()
        let lastSynced = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.cr2.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: XMPSidecarStore.fingerprint(for: sidecarData),
            lastSyncedAt: Date(timeIntervalSince1970: 100)
        )

        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: catalogMetadata,
            catalogGeneration: 4,
            lastSynced: lastSynced,
            sidecarData: sidecarData,
            sidecarModificationDate: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(decision, .writeCatalog)
    }

    func testPlannerReportsConflictWhenCatalogAndSidecarChanged() throws {
        let catalogMetadata = AssetMetadata(rating: 4)
        let previousMetadata = AssetMetadata(rating: 2)
        let sidecarMetadata = AssetMetadata(rating: 5)
        let previousSidecarData = try XMPPacket(metadata: previousMetadata).xmlData()
        let currentSidecarData = try XMPPacket(metadata: sidecarMetadata).xmlData()
        let lastSynced = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.cr2.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: XMPSidecarStore.fingerprint(for: previousSidecarData)
        )

        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: catalogMetadata,
            catalogGeneration: 4,
            lastSynced: lastSynced,
            sidecarData: currentSidecarData
        )

        XCTAssertEqual(decision, .conflict(catalogMetadata: catalogMetadata, sidecarMetadata: sidecarMetadata))
    }

    func testPlannerTreatsMatchingGenerationAndFingerprintAsUpToDate() throws {
        let metadata = AssetMetadata(rating: 3)
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        let lastSynced = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.cr2.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )

        let decision = try MetadataSyncPlanner().decision(
            catalogMetadata: metadata,
            catalogGeneration: 3,
            lastSynced: lastSynced,
            sidecarData: sidecarData
        )

        XCTAssertEqual(decision, .upToDate)
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

    private func standardXMP(
        attributes: String = "",
        body: String = "",
        extraDescriptionNamespaces: String = ""
    ) -> Data {
        Data("""
        <x:xmpmeta xmlns:x="\(xmpMetaNamespace)">
          <rdf:RDF xmlns:rdf="\(rdfNamespace)">
            <rdf:Description rdf:about=""
              xmlns:xmp="\(xmpNamespace)"
              xmlns:dc="\(dcNamespace)"
              xmlns:ts="\(teststripNamespace)"
              \(extraDescriptionNamespaces)
              \(attributes)>
              \(body)
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
    }

    private var xmpMetaNamespace: String { "adobe:ns:meta/" }
    private var rdfNamespace: String { "http://www.w3.org/1999/02/22-rdf-syntax-ns#" }
    private var xmpNamespace: String { "http://ns.adobe.com/xap/1.0/" }
    private var dcNamespace: String { "http://purl.org/dc/elements/1.1/" }
    private var teststripNamespace: String { "https://teststrip.app/xmp/1.0/" }
    private var photoshopNamespace: String { "http://ns.adobe.com/photoshop/1.0/" }

    private func rdfDescription(in document: XMLDocument) throws -> XMLElement {
        let root = try XCTUnwrap(document.rootElement())
        let rdf = try XCTUnwrap(child(root, localName: "RDF", uri: rdfNamespace))
        return try XCTUnwrap(child(rdf, localName: "Description", uri: rdfNamespace))
    }

    private func child(_ element: XMLElement, localName: String, uri: String? = nil) -> XMLElement? {
        element.children?.compactMap { $0 as? XMLElement }.first {
            $0.localName == localName && (uri == nil || $0.uri == uri)
        }
    }

    private func attribute(_ element: XMLElement, localName: String, uri: String) -> String? {
        element.attributes?.first {
            $0.localName == localName && $0.uri == uri
        }?.stringValue
    }

    private func rdfContainerValues(
        in description: XMLElement,
        propertyLocalName: String,
        containerLocalName: String
    ) -> [String] {
        guard let property = child(description, localName: propertyLocalName, uri: dcNamespace),
              let container = child(property, localName: containerLocalName, uri: rdfNamespace)
        else {
            return []
        }
        return container.children?.compactMap { child in
            guard let element = child as? XMLElement,
                  element.localName == "li",
                  element.uri == rdfNamespace
            else {
                return nil
            }
            return element.stringValue
        } ?? []
    }
}
