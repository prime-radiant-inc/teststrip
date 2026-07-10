import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Covers `AppModel.sidebarSections(for:)` - the per-workspace sidebar shape
/// introduced in Task 7: Library is navigation only (Collections/Saved
/// Sets/Folders), Cull and People get their own sidebar content in later
/// tasks (empty for now).
final class SidebarSectionsTests: XCTestCase {
    func testLibrarySidebarSectionsAreExactlyCollectionsSavedSetsFolders() throws {
        let asset = makeAsset(id: "hero", path: "/Photos/hero.jpg", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "sidebar-sections-library", assets: [asset])
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        _ = try model.saveCurrentLibraryQuery(named: "Five Stars", starred: false)
        model.catalogFolders = [CatalogFolder(path: "photos", name: "photos", assetCount: 1)]

        let sections = model.sidebarSections(for: .library)

        XCTAssertEqual(sections.map(\.title), ["Collections", "Saved Sets", "Folders"])

        let collections = try XCTUnwrap(sections.first { $0.title == "Collections" })
        XCTAssertEqual(collections.rows.first?.id, "library-all")
        XCTAssertEqual(collections.rows.first?.target, .allPhotographs)

        let savedSets = try XCTUnwrap(sections.first { $0.title == "Saved Sets" })
        XCTAssertEqual(savedSets.rowTitles, ["Five Stars"])

        let folders = try XCTUnwrap(sections.first { $0.title == "Folders" })
        XCTAssertEqual(folders.rowTitles, ["photos"])
    }

    func testPeopleAndCullSidebarSectionsAreEmpty() {
        let model = AppModel.demo()

        XCTAssertEqual(model.sidebarSections(for: .people), [])
        XCTAssertEqual(model.sidebarSections(for: .cull), [])
    }

    func testSidebarSectionsTrackTheCurrentWorkspaceAsSelectedViewChanges() {
        let model = AppModel.demo()
        XCTAssertEqual(model.selectedWorkspace, .library)
        XCTAssertEqual(model.sidebarSections.map(\.title), ["Collections"])

        model.selectWorkspace(.cull)
        XCTAssertEqual(model.sidebarSections, [])

        model.selectWorkspace(.people)
        XCTAssertEqual(model.sidebarSections, [])

        model.selectWorkspace(.library)
        XCTAssertEqual(model.sidebarSections.map(\.title), ["Collections"])
    }

    func testSavedSetContextMenuActionsStillResolveUnderTheNewSidebarShape() throws {
        let asset = makeAsset(id: "hero", path: "/Photos/hero.jpg", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "sidebar-sections-context-menu", assets: [asset])
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        let savedSet = try model.saveCurrentLibraryQuery(named: "Five Stars", starred: true)

        let collections = try XCTUnwrap(model.sidebarSections(for: .library).first { $0.title == "Collections" })
        let starredRow = try XCTUnwrap(collections.rows.first { $0.target == .assetSet(savedSet.id) })
        let actions = model.sidebarContextActions(for: starredRow)

        XCTAssertTrue(actions.contains { $0.kind == .renameAssetSet(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .duplicateAssetSet(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .freezeAssetSetSnapshot(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .toggleAssetSetStarred(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .deleteAssetSet(savedSet.id) })
    }

    // MARK: - Test support

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
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
        let model = try AppModel.load(catalog: catalog)
        return (model, repository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-sidebar-sections-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeAsset(id: String, path: String, rating: Int) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Test",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: rating)
        )
    }
}
