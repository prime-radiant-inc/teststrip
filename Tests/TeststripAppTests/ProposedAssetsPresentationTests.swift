import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class ProposedAssetsPresentationTests: XCTestCase {
    func testLonePersonQueryPopulatesProposedPhotos() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let a2 = makeAsset(id: "a2", path: "/Photos/a2.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-lone-person", assets: [a1, a2])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        // a1 confirmed for the person; a2 only AI-proposed.
        try repository.assignAssets([AssetID(rawValue: "a1")], toPersonID: "p1")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a2"), faceIndex: 0, personID: "p1")

        try model.showPersonPhotos(named: "Dan Shapiro")

        XCTAssertEqual(model.assets.map(\.id), [AssetID(rawValue: "a1")])
        XCTAssertEqual(model.proposedPhotos.map(\.asset.id), [AssetID(rawValue: "a2")])
        XCTAssertEqual(model.proposedPhotos.first?.faces.map(\.faceIndex), [0])
    }

    func testNonPersonQueryClearsProposedPhotos() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-cleared", assets: [a1])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")

        try model.showPersonPhotos(named: "Dan Shapiro")
        XCTAssertEqual(model.proposedPhotos.count, 1)

        model.librarySearchText = "" // no predicate
        try model.reload()
        XCTAssertTrue(model.proposedPhotos.isEmpty)
    }

    func testConfirmProposedPhotoMovesItToConfirmed() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-confirm", assets: [a1])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        try model.showPersonPhotos(named: "Dan Shapiro")

        let photo = try XCTUnwrap(model.proposedPhotos.first)
        try model.confirmProposedPhoto(photo)

        XCTAssertTrue(model.proposedPhotos.isEmpty)
        XCTAssertEqual(model.assets.map(\.id), [AssetID(rawValue: "a1")]) // now confirmed
    }

    func testRejectProposedPhotoRemovesItStickily() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-reject", assets: [a1])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")
        try model.showPersonPhotos(named: "Dan Shapiro")

        let photo = try XCTUnwrap(model.proposedPhotos.first)
        try model.rejectProposedPhoto(photo)

        XCTAssertTrue(model.proposedPhotos.isEmpty)
        XCTAssertTrue(try repository.rejectedFacePeople().contains(
            RejectedFacePerson(assetID: AssetID(rawValue: "a1"), faceIndex: 0, personID: "p1")))
    }

    func testCompoundPersonQueryClearsProposedPhotos() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let a2 = makeAsset(id: "a2", path: "/Photos/a2.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-compound-query", assets: [a1, a2])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.assignAssets([AssetID(rawValue: "a1")], toPersonID: "p1")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a2"), faceIndex: 0, personID: "p1")

        try model.showPersonPhotos(named: "Dan Shapiro")
        XCTAssertEqual(model.proposedPhotos.count, 1) // lone person query populates it

        // A second active predicate (rating filter) alongside the person
        // search means the query is no longer a *lone* `.person` predicate,
        // so the gate must clear proposedPhotos even though a person search
        // is still present.
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()

        XCTAssertTrue(model.proposedPhotos.isEmpty)
    }

    func testExplicitAssetSetSelectionClearsProposedPhotosDespitePersonQuery() throws {
        let a1 = makeAsset(id: "a1", path: "/Photos/a1.jpg")
        let a2 = makeAsset(id: "a2", path: "/Photos/a2.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "proposed-explicit-set", assets: [a1, a2])
        try repository.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repository.assignAssets([AssetID(rawValue: "a1")], toPersonID: "p1")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a2"), faceIndex: 0, personID: "p1")

        try model.showPersonPhotos(named: "Dan Shapiro")
        XCTAssertEqual(model.proposedPhotos.count, 1) // lone person query populates it

        // Select an explicit/manual asset set directly on the model, the way
        // session restore does: it restores librarySearchText and
        // selectedAssetSetID independently, unlike applyAssetSet/
        // saveAndSelect which always clear the search text as a side effect.
        // Leaving the lone-.person query text untouched isolates the
        // selectedExplicitAssetIDs == nil clause of the gate, rather than the
        // "not a lone .person query" clause already covered above.
        let explicitSet = AssetSet(id: .new(), name: "Explicit", membership: .manual([AssetID(rawValue: "a1")]))
        model.savedAssetSets.append(explicitSet)
        model.selectedAssetSetID = explicitSet.id

        try model.reload()

        XCTAssertTrue(model.proposedPhotos.isEmpty)
    }

    // MARK: - Test helpers (copied from AppModelFilterPersistenceTests.swift:221-267)

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 0, colorLabel: nil, flag: nil, keywords: [])
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
