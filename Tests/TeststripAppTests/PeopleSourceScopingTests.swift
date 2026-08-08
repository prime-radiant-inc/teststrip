import XCTest
@testable import TeststripCore
@testable import TeststripApp

// No lens ignores the nouns: the People lens over a narrowed source shows that
// source's people and that source's grouping queue. All Photos is the global
// queue, and naming/merge identity stays catalog-wide so a photographer can
// still name someone who is not in the current shoot.
final class PeopleSourceScopingTests: XCTestCase {
    func testPeopleScopeIsNilForAnUnfilteredCatalog() throws {
        let first = makeAsset(id: "scope-a", path: "/Photos/A/a.jpg")
        let second = makeAsset(id: "scope-b", path: "/Photos/B/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "people-scope-nil", assets: [first, second])

        XCTAssertNil(try model.peopleScopeAssetIDs())
    }

    func testPeopleScopeNarrowsWithTheSelectedSource() throws {
        let inside = makeAsset(id: "scope-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "scope-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-scope-folder",
            assets: [inside, outside]
        )

        try model.selectSidebarTarget(.folder("/Photos/Inside"))

        XCTAssertEqual(try model.peopleScopeAssetIDs(), [inside.id])
    }

    func testPeopleInCurrentSourceOnlyListsPeopleInThatSource() throws {
        let inside = makeAsset(id: "people-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "people-outside", path: "/Photos/Outside/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "people-in-source",
            assets: [inside, outside]
        )
        try repository.upsertPerson(id: "person-inside", name: "Ada")
        try repository.upsertPerson(id: "person-outside", name: "Grace")
        try repository.assignAssets([inside.id], toPersonID: "person-inside")
        try repository.assignAssets([outside.id], toPersonID: "person-outside")

        try model.selectSidebarTarget(.folder("/Photos/Inside"))
        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(model.peopleInCurrentSource.map(\.name), ["Ada"])
        // Identity stays catalog-wide: naming and merging must still see Grace.
        XCTAssertEqual(Set(model.catalogPeople.map(\.name)), Set(["Ada", "Grace"]))
    }

    func testPeopleOverAllPhotosIsTheGlobalQueue() throws {
        let inside = makeAsset(id: "global-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "global-outside", path: "/Photos/Outside/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "people-global",
            assets: [inside, outside]
        )
        try repository.upsertPerson(id: "person-inside", name: "Ada")
        try repository.upsertPerson(id: "person-outside", name: "Grace")
        try repository.assignAssets([inside.id], toPersonID: "person-inside")
        try repository.assignAssets([outside.id], toPersonID: "person-outside")

        try model.selectSidebarTarget(.folder("/Photos/Inside"))
        model.refreshPeopleFaceSuggestions()
        try model.selectSidebarTarget(.allPhotographs)
        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(Set(model.peopleInCurrentSource.map(\.name)), Set(["Ada", "Grace"]))
    }

    // MARK: - Fixtures

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-people-scoping-\(name)-\(UUID().uuidString)", isDirectory: true)
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
