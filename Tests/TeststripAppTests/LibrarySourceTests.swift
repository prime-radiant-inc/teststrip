import XCTest
@testable import TeststripCore
@testable import TeststripApp

// A source is a noun: the set of photos the sidebar (or a query) names. It is
// stored, not reconstructed from filter state, so the scope line can name it
// and a relaunch can restore it.
final class LibrarySourceTests: XCTestCase {
    func testDiagnosticSourcesAreExactlyTheOnesWithNothingCullable() {
        let session = WorkSessionID(rawValue: "import-1")

        XCTAssertTrue(LibrarySource.importChild(session: session, child: .skippedFiles).isDiagnostic)
        XCTAssertTrue(LibrarySource.importChild(session: session, child: .previewFailed).isDiagnostic)
        XCTAssertTrue(LibrarySource.smartCollection(.providerFailures).isDiagnostic)
        XCTAssertTrue(LibrarySource.metadataSyncConflicts.isDiagnostic)
        XCTAssertTrue(LibrarySource.sourceAvailability(.missing).isDiagnostic)

        XCTAssertFalse(LibrarySource.allPhotos.isDiagnostic)
        XCTAssertFalse(LibrarySource.smartCollection(.picks).isDiagnostic)
        XCTAssertFalse(LibrarySource.importChild(session: session, child: .stacks).isDiagnostic)
        XCTAssertFalse(LibrarySource.importChild(session: session, child: .likelyIssues).isDiagnostic)
        XCTAssertFalse(LibrarySource.importChild(session: session, child: .facesFound).isDiagnostic)
    }

    func testEverySourceRoundTripsThroughCodable() throws {
        let sources: [LibrarySource] = [
            .allPhotos,
            .search(SetQuery(predicates: [.likelyPick, .evaluationFailure]), titled: "Search results"),
            .smartCollection(.likelyIssues),
            .autopilotSuggestions,
            .folder("/Photos/2026"),
            .sourceAvailability(.offline),
            .evaluationKind(.focus, titled: "Focus"),
            .metadataSyncPending,
            .metadataSyncConflicts,
            .assetSet(AssetSetID(rawValue: "set-1"), titled: "Keepers"),
            .workSession(WorkSessionID(rawValue: "import-1"), titled: "Aug 7 · Imported from /Cards/A"),
            .importChild(session: WorkSessionID(rawValue: "import-1"), child: .previewFailed),
            .selection
        ]

        for source in sources {
            let data = try JSONEncoder().encode(source)
            XCTAssertEqual(try JSONDecoder().decode(LibrarySource.self, from: data), source, source.title)
        }
    }

    // The predicates the text serializer loses (.likelyPick, .likelyIssue,
    // .evaluationFailure, .withinGeoBounds) must survive a source round trip,
    // because a search source is exactly how "Cull these" travels.
    func testASearchSourcePreservesThePredicatesTheTextSerializerDrops() throws {
        let query = SetQuery(predicates: [
            .likelyPick,
            .likelyIssue,
            .evaluationFailure,
            .withinGeoBounds(GeoBounds(minLatitude: 1, maxLatitude: 2, minLongitude: 3, maxLongitude: 4))
        ])
        let source = LibrarySource.search(query, titled: "Search results")

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(LibrarySource.self, from: data)

        guard case .search(let decodedQuery) = decoded.kind else {
            return XCTFail("expected a search source")
        }
        XCTAssertEqual(decodedQuery, query)
    }

    func testSelectingASourceNeverChangesTheLens() throws {
        let inside = makeAsset(id: "source-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "source-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-keeps-lens", assets: [inside, outside])

        model.selectLens(.timeline)
        try model.selectSource(.folder("/Photos/Inside"))

        XCTAssertEqual(model.selectedLens, .timeline)
        XCTAssertEqual(model.selectedSource, LibrarySource.folder("/Photos/Inside"))
        XCTAssertEqual(model.assets.map(\.id), [inside.id])
    }

    func testSelectingADiagnosticSourceFallsTheCullLensBackToGrid() throws {
        let asset = makeAsset(id: "fallback", path: "/Photos/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-lens-fallback", assets: [asset])

        model.selectLens(.cull)
        XCTAssertEqual(model.selectedLens, .cull)

        try model.selectSource(.smartCollection(.providerFailures))

        XCTAssertEqual(model.selectedLens, .grid)
        XCTAssertEqual(model.selectedSource, LibrarySource.smartCollection(.providerFailures))
    }

    func testCullStaysDisabledOnAnEmptySource() throws {
        let asset = makeAsset(id: "empty-source", path: "/Photos/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-empty-cull", assets: [asset])

        try model.selectSource(.folder("/Photos/Nowhere"))

        XCTAssertTrue(model.assets.isEmpty)
        let cull = try XCTUnwrap(model.lensAvailabilities.first { $0.lens == .cull })
        XCTAssertFalse(cull.isEnabled)
        XCTAssertEqual(cull.disabledReason, "No photos to cull")
    }

    func testSelectingAllPhotosClearsTheScopeAndNamesTheSource() throws {
        let inside = makeAsset(id: "all-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "all-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-all-photos", assets: [inside, outside])
        try model.selectSource(.folder("/Photos/Inside"))

        try model.selectSource(.allPhotos)

        XCTAssertEqual(model.selectedSource.title, "All Photos")
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([inside.id, outside.id]))
        XCTAssertTrue(model.activeLibraryFilterChips.isEmpty)
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
            .appendingPathComponent("teststrip-library-source-\(name)-\(UUID().uuidString)", isDirectory: true)
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
