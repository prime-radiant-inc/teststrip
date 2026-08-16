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

    // Every applier reached through `applySource` — not just the two the
    // switcher's Grid-fallback path exercises — must leave the lens alone.
    // Timeline never disables (only Cull disables, and only on diagnostic or
    // empty sources), so if the lens moves here, an applier reintroduced a
    // hardcoded `selectedView` write rather than letting `LensRules` decide.
    func testSelectingAnySourceKindNeverChangesANonDisablingLens() throws {
        let picked = makeAsset(id: "source-kind-picked", path: "/Photos/Inside/picked.jpg")
        let focused = makeAsset(id: "source-kind-focused", path: "/Photos/Inside/focused.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "source-keeps-lens-every-kind",
            assets: [picked, focused]
        )
        try repository.updateMetadata(assetID: picked.id) { $0.flag = .pick }
        try repository.recordEvaluationSignals([
            EvaluationSignal(
                assetID: focused.id,
                kind: .focus,
                value: .score(0.5),
                confidence: 0.9,
                provenance: ProviderProvenance(provider: "local-http", model: "focus", version: "1", settingsHash: "default")
            )
        ])
        let setID = AssetSetID(rawValue: "source-kind-set")
        try repository.upsert(AssetSet.manual(id: setID, name: "Keepers", assetIDs: [picked.id]))

        // None of these four sources is diagnostic or empty, so Timeline —
        // which never disables in the first place — has no legitimate reason
        // to move.
        let sources: [LibrarySource] = [
            .folder("/Photos/Inside"),
            .smartCollection(.picks),
            .assetSet(setID, titled: "Keepers"),
            .evaluationKind(.focus, titled: "Focus")
        ]

        for source in sources {
            // Reset before each iteration so a later source can't pass on
            // lens state a prior one left behind.
            model.selectLens(.timeline)
            try model.selectSource(source)
            XCTAssertEqual(model.selectedLens, .timeline, "\(source.title) changed the lens")
            XCTAssertFalse(model.assets.isEmpty, "\(source.title) resolved to an empty source")
        }
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

    // Reachable entirely within the shipping UI: Activity Center's conflicts
    // row calls `revealConflicts`, which sets `selectedSource` to the
    // diagnostic `.metadataSyncConflicts` source directly. Clicking the "XMP
    // Conflicts" chip's ✕ clears the filter through a completely separate
    // path (`removeActiveLibraryFilter`) that used to leave `selectedSource`
    // stuck on the diagnostic value even after the view widened back to the
    // whole catalog — Cull stayed disabled ("Nothing here is cullable") over
    // photos that were, in fact, cullable.
    func testRemovingTheOnlyActiveFilterChipReturnsSelectedSourceToAllPhotosAndReenablesCull() throws {
        let first = makeAsset(id: "conflict-chip-first", path: "/Photos/first.jpg")
        let second = makeAsset(id: "conflict-chip-second", path: "/Photos/second.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-conflict-chip", assets: [first, second])

        try model.revealConflicts([first.id])

        XCTAssertEqual(model.selectedSource, .metadataSyncConflicts)
        XCTAssertEqual(model.assets.count, 0, "neither seeded asset has an actual sync conflict recorded")
        let disabledCull = try XCTUnwrap(model.lensAvailabilities.first { $0.lens == .cull })
        XCTAssertFalse(disabledCull.isEnabled)
        XCTAssertEqual(disabledCull.disabledReason, "Nothing here is cullable")

        let row = try XCTUnwrap(model.activeLibraryFilterRows.first { $0.title == "XMP Conflicts" })
        try model.removeActiveLibraryFilter(row)

        XCTAssertEqual(model.selectedSource, .allPhotos)
        XCTAssertFalse(model.hasActiveLibraryFilters)
        // The whole seeded library, not zero — proves this is specifically
        // the diagnostic-flag staleness fix, not just "an empty source
        // disables Cull".
        XCTAssertEqual(model.assets.count, 2)
        let reenabledCull = try XCTUnwrap(model.lensAvailabilities.first { $0.lens == .cull })
        XCTAssertTrue(reenabledCull.isEnabled)
        XCTAssertNil(reenabledCull.disabledReason)
    }

    // The same staleness, reached via the "Esc, Esc" / "Clear Filters" path
    // (`clearLibraryFilters`) instead of a single chip's ✕, and across more
    // than one diagnostic source to prove the reset isn't source-specific.
    func testClearingLibraryFiltersFromADiagnosticSourceReturnsSelectedSourceToAllPhotos() throws {
        let missing = makeAsset(id: "clear-filters-missing", path: "/Photos/missing.jpg", availability: .missing)
        let online = makeAsset(id: "clear-filters-online", path: "/Photos/online.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-clear-filters", assets: [missing, online])

        let diagnosticSources: [LibrarySource] = [
            .sourceAvailability(.missing),
            .smartCollection(.providerFailures)
        ]

        for source in diagnosticSources {
            try model.selectSource(source)

            XCTAssertEqual(model.selectedSource, source)
            let disabledCull = try XCTUnwrap(model.lensAvailabilities.first { $0.lens == .cull })
            XCTAssertFalse(disabledCull.isEnabled, "\(source.title) left Cull enabled")
            XCTAssertEqual(disabledCull.disabledReason, "Nothing here is cullable")

            try model.clearLibraryFilters()

            XCTAssertEqual(model.selectedSource, .allPhotos)
            // The whole seeded library, not zero — the same
            // diagnostic-flag-staleness distinction as the chip-removal test.
            XCTAssertEqual(model.assets.count, 2, "\(source.title) did not widen back to the whole seeded library")
            let reenabledCull = try XCTUnwrap(model.lensAvailabilities.first { $0.lens == .cull })
            XCTAssertTrue(reenabledCull.isEnabled, "\(source.title) left Cull disabled after clearing filters")
            XCTAssertNil(reenabledCull.disabledReason)
        }
    }

    // `saveSelectedAssetAsManualSet` (via `saveAndSelect`) bypasses
    // `applySource` entirely — it already holds the `AssetSet` it just
    // upserted — so it must own `selectedSource` itself rather than leaving
    // it whatever it was before the save.
    func testSavingASelectionAsAManualSetUpdatesSelectedSourceToTheNewSet() throws {
        let asset = makeAsset(id: "save-selection-source", path: "/Photos/save-selection.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-save-selection", assets: [asset])
        model.selectedAssetID = asset.id

        let saved = try model.saveSelectedAssetAsManualSet(named: "Keepers")

        XCTAssertEqual(model.selectedSource, .assetSet(saved.id, titled: "Keepers"))
    }

    // A set save crosses the repository, model caches, the loaded asset scope,
    // Map aggregates, and persisted browsing state. A late read failure must
    // leave every boundary at the state that was visible before the save.
    func testSaveAndSelectIsAtomicWhenMapRefreshFails() throws {
        var selected = makeAsset(
            id: "atomic-selected",
            path: "/Photos/Atomic/selected.jpg",
            technicalMetadata: Self.technicalMetadata(
                capturedAt: Date(timeIntervalSince1970: 10),
                latitude: 10,
                longitude: 20
            )
        )
        selected.metadata.rating = 5
        selected.metadata.flag = .pick
        var batchSelected = makeAsset(
            id: "atomic-batch-selected",
            path: "/Photos/Atomic/batch-selected.jpg",
            technicalMetadata: Self.technicalMetadata(
                capturedAt: Date(timeIntervalSince1970: 20),
                latitude: 40,
                longitude: 50
            )
        )
        batchSelected.metadata.rating = 5
        batchSelected.metadata.flag = .pick
        let outside = makeAsset(
            id: "atomic-outside",
            path: "/Photos/Outside/outside.jpg",
            technicalMetadata: Self.technicalMetadata(
                capturedAt: Date(timeIntervalSince1970: 30),
                latitude: -20,
                longitude: -30
            )
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-library-source-atomic-\(UUID().uuidString)", isDirectory: true)
        let paths = AppCatalog.defaultPaths(
            applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)
        )
        let catalog = try AppCatalog.open(paths: paths)
        let repository = catalog.repository
        try repository.upsert([selected, batchSelected, outside])

        let existingSet = AssetSet.manual(
            id: AssetSetID(rawValue: "atomic-existing-set"),
            name: "Existing Set",
            assetIDs: [selected.id, batchSelected.id]
        )
        try repository.upsert(existingSet)
        let workSession = WorkSession(
            id: WorkSessionID(rawValue: "atomic-existing-work"),
            kind: .culling,
            intent: "Review Atomic photos",
            title: "Atomic review",
            detail: "Existing Atomic work",
            status: .completed,
            inputSetIDs: [existingSet.id],
            outputSetIDs: [],
            completedUnitCount: 2,
            totalUnitCount: 2,
            createdAt: Date(timeIntervalSince1970: 40),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try repository.save(workSession)
        try repository.recordPlaceName(CatalogPlaceName(
            coordinateKey: GeocodeCoordinateKey.key(latitude: 10, longitude: 20),
            displayName: "Selected Place"
        ))
        try repository.recordPlaceName(CatalogPlaceName(
            coordinateKey: GeocodeCoordinateKey.key(latitude: 40, longitude: 50),
            displayName: "Batch Place"
        ))

        let defaultsSuite = "teststrip.library-source-atomic.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let model = try AppModel.load(
            catalog: catalog,
            workerSupervisor: nil,
            sessionRestoreDefaults: defaults
        )
        try model.selectSource(.smartCollection(.picks))
        model.librarySearchText = "Atomic"
        model.minimumRatingFilter = 4
        try model.applyLibraryFilters()
        model.selectLens(.map)
        try model.refreshPlaceData()
        model.select(selected.id)
        model.setBatchSelection(batchSelected.id, isSelected: true)
        model.statusMessage = "State before save"
        model.errorMessage = "Error before save"

        XCTAssertEqual(model.assets.map(\.id), [selected.id, batchSelected.id])
        XCTAssertEqual(Set(model.activeLibraryFilterChips), Set(["Pick", "Search: Atomic", "Rating >= 4"]))
        XCTAssertEqual(model.workHistorySearchResults.map(\.id), [workSession.id.rawValue])
        XCTAssertEqual(
            model.geotaggedCoverage,
            CatalogGeotaggedCoverage(geotaggedCount: 2, totalCount: 2)
        )
        XCTAssertEqual(model.catalogPlaceClusters.map(\.assetCount).reduce(0, +), 2)
        XCTAssertEqual(
            Set(model.catalogTopLocations.map(\.displayName)),
            Set(["Selected Place", "Batch Place"])
        )

        let stateBeforeSave = SaveAndSelectState(model: model)
        let repositorySetsBeforeSave = try repository.assetSets()
        let restoreStore = SessionRestoreStore(defaults: defaults, catalogRoot: paths.root)
        let persistedStateBeforeSave = try XCTUnwrap(restoreStore.load())

        var changedBatchAsset = try repository.asset(id: batchSelected.id)
        changedBatchAsset.metadata.rating = 1
        changedBatchAsset.technicalMetadata?.latitude = 70
        changedBatchAsset.technicalMetadata?.longitude = 80
        try repository.upsert(changedBatchAsset)
        XCTAssertEqual(SaveAndSelectState(model: model), stateBeforeSave)

        // Open the same on-disk catalog without migration: migrating after the
        // DROP would repair the failure seam instead of exercising it.
        let faultDatabase = try CatalogDatabase.open(at: paths.catalogURL)
        try faultDatabase.execute("DROP TABLE place_cache")

        XCTAssertThrowsError(try model.saveSelectedAssetAsManualSet(named: "Atomic Keepers")) { error in
            guard case CatalogError.sqlite(let message) = error else {
                return XCTFail("expected a late place-cache SQLite error, got \(error)")
            }
            XCTAssertTrue(
                message.contains("place_cache"),
                "expected the Map top-locations read to fail, got \(message)"
            )
        }

        XCTAssertEqual(try repository.assetSets(), repositorySetsBeforeSave)
        XCTAssertEqual(SaveAndSelectState(model: model), stateBeforeSave)
        XCTAssertEqual(restoreStore.load(), persistedStateBeforeSave)
    }

    // A failed dynamic save must retain both the prior single selection and
    // batch selection instead of publishing its pending membership prune.
    func testDynamicSaveAndSelectPreservesSelectionsWhenLateMapRefreshFails() throws {
        var keeper = makeAsset(
            id: "dynamic-map-keeper",
            path: "/Photos/Dynamic/keeper.jpg",
            technicalMetadata: Self.technicalMetadata(
                capturedAt: Date(timeIntervalSince1970: 10),
                latitude: 10,
                longitude: 20
            )
        )
        keeper.metadata.rating = 5
        var reject = makeAsset(
            id: "dynamic-map-reject",
            path: "/Photos/Dynamic/reject.jpg",
            technicalMetadata: Self.technicalMetadata(
                capturedAt: Date(timeIntervalSince1970: 20),
                latitude: 30,
                longitude: 40
            )
        )
        reject.metadata.rating = 1
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "dynamic-map-five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let fixture = try makeCatalogFixture(
            named: "save-select-dynamic-map-failure",
            assets: [keeper, reject]
        ) { repository in
            try repository.upsert(dynamicSet)
        }
        fixture.model.selectLens(.map)
        try fixture.model.refreshPlaceData()
        fixture.model.select(reject.id)
        fixture.model.setBatchSelection(keeper.id, isSelected: true)
        fixture.model.setBatchSelection(reject.id, isSelected: true)

        XCTAssertEqual(fixture.model.selectedAssetID, reject.id)
        XCTAssertEqual(
            fixture.model.selectedBatchAssetIDs,
            [keeper.id, reject.id]
        )
        let stateBeforeSave = SaveAndSelectState(model: fixture.model)
        let setsBeforeSave = try fixture.repository.assetSets()
        let faultDatabase = try CatalogDatabase.open(at: fixture.catalogURL)
        try faultDatabase.execute("DROP TABLE place_cache")

        XCTAssertThrowsError(
            try fixture.model.duplicateAssetSet(id: dynamicSet.id, named: "Five Stars Copy")
        ) { error in
            guard case CatalogError.sqlite(let message) = error else {
                return XCTFail("expected a late place-cache SQLite error, got \(error)")
            }
            XCTAssertTrue(message.contains("place_cache"))
        }

        XCTAssertEqual(try fixture.repository.assetSets(), setsBeforeSave)
        XCTAssertEqual(SaveAndSelectState(model: fixture.model), stateBeforeSave)
        XCTAssertEqual(fixture.model.selectedAssetID, reject.id)
        XCTAssertEqual(
            fixture.model.selectedBatchAssetIDs,
            [keeper.id, reject.id]
        )
    }

    // People refreshes are best effort on every other source-selection path.
    // Saving a set while People is visible must keep that contract: persist
    // and select the set, then publish an empty People snapshot with the error.
    func testSaveAndSelectSucceedsWhenThePeopleSnapshotReadFails() throws {
        let asset = makeAsset(id: "people-save-failure", path: "/Photos/People/ada.jpg")
        let unassignedFaceAsset = makeAsset(
            id: "people-save-failure-unassigned",
            path: "/Photos/People/unassigned.jpg"
        )
        let unavailableRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-people-save-unavailable-\(UUID().uuidString)", isDirectory: true)
        let fixture = try makeCatalogFixture(
            named: "save-select-people-read-failure",
            assets: [asset, unassignedFaceAsset]
        ) { repository in
            let provenance = AppleVisionEvaluationProvider.faceProvenance
            try repository.upsertPerson(id: "person-ada", name: "Ada")
            try repository.assignAssets([asset.id], toPersonID: "person-ada")
            try repository.recordSourceRoot(unavailableRoot)
            try repository.replaceFaceObservations(
                assetID: unassignedFaceAsset.id,
                provenance: provenance,
                with: [CatalogFaceObservation(
                    assetID: unassignedFaceAsset.id,
                    faceIndex: 0,
                    boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                    captureQuality: 0.9,
                    embedding: [1, 0, 0],
                    provenance: provenance
                ), CatalogFaceObservation(
                    assetID: unassignedFaceAsset.id,
                    faceIndex: 1,
                    boundingBox: FaceBoundingBox(x: 0.5, y: 0.1, width: 0.2, height: 0.2),
                    captureQuality: 0.8,
                    embedding: [1, 0, 0],
                    provenance: provenance
                )]
            )
            try repository.recordEvaluationSignals([
                EvaluationSignal(
                    assetID: unassignedFaceAsset.id,
                    kind: .faceCount,
                    value: .count(1),
                    confidence: 0.9,
                    provenance: provenance
                )
            ])
        }
        fixture.model.selectLens(.people)
        fixture.model.refreshPeopleFaceSuggestions()
        fixture.model.select(asset.id)

        XCTAssertEqual(fixture.model.selectedLens, .people)
        XCTAssertEqual(fixture.model.peopleInCurrentSource.map(\.name), ["Ada"])
        XCTAssertFalse(fixture.model.peopleFaceSuggestions.isEmpty)
        XCTAssertEqual(fixture.model.peopleFaceObservationAssetCount, 1)
        XCTAssertEqual(fixture.model.peopleEvaluationKindSummaries.count, 1)
        XCTAssertTrue(fixture.model.peopleHasUnavailableSources)

        let faultDatabase = try CatalogDatabase.open(at: fixture.catalogURL)
        try faultDatabase.execute("DROP TABLE face_observations")
        fixture.model.errorMessage = nil

        let saved = try fixture.model.saveSelectedAssetAsManualSet(named: "Ada Keepers")

        XCTAssertEqual(try fixture.repository.assetSet(id: saved.id), saved)
        XCTAssertEqual(fixture.model.selectedLens, .people)
        XCTAssertEqual(fixture.model.selectedSource, .assetSet(saved.id, titled: "Ada Keepers"))
        XCTAssertEqual(fixture.model.assets.map(\.id), [asset.id])
        XCTAssertEqual(fixture.model.peopleInCurrentSource, [])
        XCTAssertEqual(fixture.model.peopleFaceSuggestions, [])
        XCTAssertEqual(fixture.model.peopleFaceObservationAssetCount, 0)
        XCTAssertEqual(fixture.model.peopleEvaluationKindSummaries, [])
        XCTAssertFalse(fixture.model.peopleHasUnavailableSources)
        XCTAssertTrue(fixture.model.errorMessage?.contains("face_observations") == true)
    }

    // reload() treats folder discovery as best effort and retains both folder
    // and source-root caches when the folder query fails before either update.
    func testSaveAndSelectSucceedsWhenFolderDiscoveryFails() throws {
        let selected = makeAsset(id: "folder-failure-selected", path: "/Photos/Existing/selected.jpg")
        let fixture = try makeCatalogFixture(
            named: "save-select-folder-failure",
            assets: [selected]
        )
        fixture.model.select(selected.id)
        let foldersBeforeSave = fixture.model.catalogFolders
        let sourceRootsBeforeSave = fixture.model.sourceRoots
        XCTAssertFalse(foldersBeforeSave.isEmpty)
        let importedBehindModel = makeAsset(
            id: "folder-failure-imported",
            path: "/Photos/New/imported.jpg"
        )
        try fixture.repository.upsert(importedBehindModel)
        XCTAssertNotEqual(try fixture.repository.folders(), foldersBeforeSave)

        var didInjectFault = false
        var faultInjectionError: Error?
        fixture.database.rowQueryObserver = { sql in
            guard !didInjectFault,
                  sql.contains("rtrim(original_path, replace(original_path, '/', '')) AS folder_path") else { return }
            didInjectFault = true
            do {
                try fixture.database.execute(
                    "ALTER TABLE assets RENAME COLUMN original_path TO faulted_original_path"
                )
            } catch {
                faultInjectionError = error
            }
        }
        defer { fixture.database.rowQueryObserver = nil }
        fixture.model.errorMessage = nil

        let saved = try fixture.model.saveSelectedAssetAsManualSet(named: "Folder Fallback")

        XCTAssertTrue(didInjectFault)
        XCTAssertNil(faultInjectionError)
        XCTAssertEqual(try fixture.repository.assetSet(id: saved.id), saved)
        XCTAssertEqual(fixture.model.selectedSource, .assetSet(saved.id, titled: "Folder Fallback"))
        XCTAssertEqual(fixture.model.catalogFolders, foldersBeforeSave)
        XCTAssertEqual(fixture.model.sourceRoots, sourceRootsBeforeSave)
        XCTAssertTrue(fixture.model.errorMessage?.contains("original_path") == true)
        XCTAssertEqual(fixture.model.statusMessage, "Saved Folder Fallback")
    }

    // reload() retains the last source-root cache when its independent refresh
    // fails, while still completing the surrounding source transition.
    func testSaveAndSelectSucceedsWhenSourceRootDiscoveryFails() throws {
        let selected = makeAsset(id: "root-failure-selected", path: "/Photos/Existing/selected.jpg")
        let originalRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-root-failure-original-\(UUID().uuidString)", isDirectory: true)
        let addedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-root-failure-added-\(UUID().uuidString)", isDirectory: true)
        let fixture = try makeCatalogFixture(
            named: "save-select-root-failure",
            assets: [selected]
        ) { repository in
            try repository.recordSourceRoot(originalRoot)
        }
        fixture.model.select(selected.id)
        let foldersBeforeSave = fixture.model.catalogFolders
        let sourceRootsBeforeSave = fixture.model.sourceRoots
        XCTAssertFalse(sourceRootsBeforeSave.isEmpty)
        let importedBehindModel = makeAsset(
            id: "root-failure-imported",
            path: "/Photos/New/imported.jpg"
        )
        try fixture.repository.upsert(importedBehindModel)
        let foldersAfterImport = try fixture.repository.folders()
        XCTAssertNotEqual(foldersAfterImport, foldersBeforeSave)
        try fixture.repository.recordSourceRoot(addedRoot)
        XCTAssertNotEqual(try fixture.repository.sourceRoots(), sourceRootsBeforeSave)

        var didInjectFault = false
        var faultInjectionError: Error?
        fixture.database.rowQueryObserver = { sql in
            guard !didInjectFault,
                  sql.contains("SELECT path, name, security_scoped_bookmark_base64"),
                  sql.contains("FROM source_roots") else { return }
            didInjectFault = true
            do {
                try fixture.database.execute("DROP TABLE source_roots")
            } catch {
                faultInjectionError = error
            }
        }
        defer { fixture.database.rowQueryObserver = nil }
        fixture.model.errorMessage = nil

        let saved = try fixture.model.saveSelectedAssetAsManualSet(named: "Root Fallback")

        XCTAssertTrue(didInjectFault)
        XCTAssertNil(faultInjectionError)
        XCTAssertEqual(try fixture.repository.assetSet(id: saved.id), saved)
        XCTAssertEqual(fixture.model.selectedSource, .assetSet(saved.id, titled: "Root Fallback"))
        XCTAssertEqual(fixture.model.catalogFolders, foldersAfterImport)
        XCTAssertEqual(fixture.model.sourceRoots, sourceRootsBeforeSave)
        XCTAssertTrue(fixture.model.errorMessage?.contains("source_roots") == true)
        XCTAssertEqual(fixture.model.statusMessage, "Saved Root Fallback")
    }

    // Bond-badge discovery is best effort in reload(): failure retains the
    // last published primary-ID set instead of aborting the source transition.
    func testSaveAndSelectSucceedsWhenBondDiscoveryFails() throws {
        let primary = makeAsset(id: "bond-failure-primary", path: "/Photos/Bond/shot.cr2")
        let secondary = makeAsset(id: "bond-failure-secondary", path: "/Photos/Bond/shot.jpg")
        let fixture = try makeCatalogFixture(
            named: "save-select-bond-failure",
            assets: [primary, secondary]
        ) { repository in
            try repository.setBond(secondaryID: secondary.id, primaryID: primary.id)
        }
        fixture.model.select(primary.id)
        let bondedPrimaryIDsBeforeSave = fixture.model.assetIDsWithBondedSecondaries
        XCTAssertEqual(bondedPrimaryIDsBeforeSave, [primary.id])
        XCTAssertEqual(
            try fixture.repository.assetIDsWithBondedSecondaries(),
            bondedPrimaryIDsBeforeSave
        )

        var didInjectFault = false
        var faultInjectionError: Error?
        fixture.database.rowQueryObserver = { sql in
            guard !didInjectFault, sql.contains("SELECT DISTINCT bonded_to_asset_id") else { return }
            didInjectFault = true
            do {
                try fixture.database.execute(
                    "ALTER TABLE assets RENAME COLUMN bonded_to_asset_id TO faulted_bonded_to_asset_id"
                )
            } catch {
                faultInjectionError = error
            }
        }
        defer { fixture.database.rowQueryObserver = nil }
        fixture.model.errorMessage = nil

        let saved = try fixture.model.saveSelectedAssetAsManualSet(named: "Bond Fallback")

        XCTAssertTrue(didInjectFault)
        XCTAssertNil(faultInjectionError)
        XCTAssertEqual(try fixture.repository.assetSet(id: saved.id), saved)
        XCTAssertEqual(fixture.model.selectedSource, .assetSet(saved.id, titled: "Bond Fallback"))
        XCTAssertEqual(fixture.model.assetIDsWithBondedSecondaries, bondedPrimaryIDsBeforeSave)
        XCTAssertTrue(fixture.model.errorMessage?.contains("bonded_to_asset_id") == true)
        XCTAssertEqual(fixture.model.statusMessage, "Saved Bond Fallback")
    }

    // An empty dynamic query is the catalog-wide source: currentLibraryQuery()
    // canonicalizes it to nil. Save-and-select must use that same global People
    // scope instead of materializing all current asset IDs as a narrowed scope.
    func testSaveAndSelectTreatsAnEmptyDynamicQueryAsTheGlobalPeopleScope() throws {
        let asset = makeAsset(id: "empty-query-global", path: "/Photos/Global/photo.jpg")
        let unavailableEmptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-empty-query-unavailable-\(UUID().uuidString)", isDirectory: true)
        let globalSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "empty-query-global-set"),
            name: "Everything",
            query: SetQuery(predicates: [])
        )
        let fixture = try makeCatalogFixture(
            named: "save-select-empty-query-global",
            assets: [asset]
        ) { repository in
            try repository.recordSourceRoot(unavailableEmptyRoot)
            try repository.upsert(globalSet)
        }
        try fixture.model.applyAssetSet(id: globalSet.id)
        fixture.model.selectLens(.people)
        fixture.model.refreshPeopleFaceSuggestions()

        XCTAssertNil(try fixture.model.peopleScopeAssetIDs())
        XCTAssertTrue(fixture.model.peopleHasUnavailableSources)

        let duplicate = try fixture.model.duplicateAssetSet(id: globalSet.id, named: "Everything Copy")

        XCTAssertEqual(duplicate.membership, .dynamic(SetQuery(predicates: [])))
        XCTAssertEqual(fixture.model.selectedSource, .assetSet(duplicate.id, titled: "Everything Copy"))
        XCTAssertEqual(fixture.model.assets.map(\.id), [asset.id])
        XCTAssertEqual(fixture.model.totalAssetCount, 1)
        XCTAssertNil(try fixture.model.peopleScopeAssetIDs())
        XCTAssertTrue(
            fixture.model.peopleHasUnavailableSources,
            "the empty dynamic set should retain the catalog-wide unavailable-root projection"
        )
    }

    // Reload canonicalizes an empty dynamic query to the global nil scope,
    // which deliberately does not prune stale batch IDs. Save-and-select must
    // not turn the same source into a filtering query merely because it saves.
    func testSaveAndSelectDoesNotPruneBatchForAnEmptyDynamicGlobalScope() throws {
        let survivor = makeAsset(id: "empty-batch-survivor", path: "/Photos/survivor.jpg")
        let deleted = makeAsset(id: "empty-batch-deleted", path: "/Photos/deleted.jpg")
        let globalSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "empty-batch-global"),
            name: "Everything",
            query: SetQuery(predicates: [])
        )
        let fixture = try makeCatalogFixture(
            named: "save-select-empty-batch",
            assets: [survivor, deleted]
        ) { repository in
            try repository.upsert(globalSet)
        }
        try fixture.model.applyAssetSet(id: globalSet.id)
        fixture.model.setBatchSelection(survivor.id, isSelected: true)
        fixture.model.setBatchSelection(deleted.id, isSelected: true)
        try fixture.repository.deleteAsset(id: deleted.id)
        try fixture.model.reload()

        XCTAssertEqual(fixture.model.assets.map(\.id), [survivor.id])
        XCTAssertEqual(
            fixture.model.selectedBatchAssetIDsInCatalogOrder,
            [survivor.id, deleted.id]
        )

        let duplicate = try fixture.model.duplicateAssetSet(id: globalSet.id, named: "Everything Copy")

        XCTAssertEqual(duplicate.membership, .dynamic(SetQuery(predicates: [])))
        XCTAssertEqual(fixture.model.assets.map(\.id), [survivor.id])
        XCTAssertEqual(
            fixture.model.selectedBatchAssetIDsInCatalogOrder,
            [survivor.id, deleted.id]
        )
    }

    // A save projection spans multiple reads. A concurrent matching import may
    // be blocked by a read transaction or admitted and detected by a version
    // guard, but the published asset rows and source/sidebar counts must come
    // from one version.
    func testSaveAndSelectPublishesACoherentProjectionAcrossAConcurrentImport() throws {
        var existing = makeAsset(id: "coherent-existing", path: "/Photos/Coherent/existing.jpg")
        existing.metadata.rating = 5
        var imported = makeAsset(id: "coherent-imported", path: "/Photos/Coherent/imported.jpg")
        imported.metadata.rating = 5
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "coherent-five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let fixture = try makeCatalogFixture(
            named: "save-select-coherent-projection",
            assets: [existing]
        ) { repository in
            try repository.upsert(dynamicSet)
        }
        let importingDatabase = try CatalogDatabase.open(at: fixture.catalogURL)
        _ = try importingDatabase.rows("PRAGMA busy_timeout = 0")
        let importingRepository = CatalogRepository(database: importingDatabase)
        var didReadCandidateProjection = false
        var didAttemptImport = false
        var unexpectedImportError: Error?
        fixture.database.rowQueryObserver = { sql in
            if !didReadCandidateProjection,
               sql.contains("FROM assets"),
               sql.contains("rating") {
                didReadCandidateProjection = true
                return
            }
            guard didReadCandidateProjection, !didAttemptImport else { return }
            didAttemptImport = true
            do {
                try importingRepository.upsert(imported)
            } catch CatalogError.sqlite(let message) where
                message.contains("locked") || message.contains("busy") {
                // A read transaction is itself a valid coherent-snapshot fix.
            } catch {
                unexpectedImportError = error
            }
        }

        let duplicate = try fixture.model.duplicateAssetSet(id: dynamicSet.id, named: "Five Stars Copy")

        XCTAssertTrue(didAttemptImport, "the controlled import never reached the projection boundary")
        XCTAssertNil(unexpectedImportError)
        XCTAssertEqual(duplicate.membership, dynamicSet.membership)
        let projectedSmartCount = fixture.model.smartCollectionCounts[.fiveStars]
        let projectedSetCount = fixture.model.assetSetCounts[duplicate.id]
        let projectedFolderCount = fixture.model.catalogFolders.reduce(0) { $0 + $1.assetCount }
        let publishedBeforeImport = fixture.model.assets.map(\.id) == [existing.id]
            && fixture.model.totalAssetCount == 1
            && projectedSmartCount == 1
            && projectedSetCount == 1
            && projectedFolderCount == 1
        let publishedAfterImport = fixture.model.assets.map(\.id) == [existing.id, imported.id]
            && fixture.model.totalAssetCount == 2
            && projectedSmartCount == 2
            && projectedSetCount == 2
            && projectedFolderCount == 2
        XCTAssertTrue(
            publishedBeforeImport || publishedAfterImport,
            "published mixed catalog versions: ids=\(fixture.model.assets.map(\.id)), "
                + "count=\(fixture.model.totalAssetCount), smart=\(String(describing: projectedSmartCount)), "
                + "set=\(String(describing: projectedSetCount)), folder=\(projectedFolderCount)"
        )
    }

    // Both selected IDs exist in the old global scope, but only one matches
    // the dynamic set. A no-op prune would leave the hidden reject selected.
    func testSaveAndSelectPrunesBatchSelectionToTheDynamicSet() throws {
        var keeper = makeAsset(id: "dynamic-batch-keeper", path: "/Photos/Batch/keeper.jpg")
        keeper.metadata.rating = 5
        var reject = makeAsset(id: "dynamic-batch-reject", path: "/Photos/Batch/reject.jpg")
        reject.metadata.rating = 1
        let dynamicSet = AssetSet.dynamic(
            id: AssetSetID(rawValue: "dynamic-batch-five-stars"),
            name: "Five Stars",
            query: SetQuery(predicates: [.ratingAtLeast(5)])
        )
        let fixture = try makeCatalogFixture(
            named: "save-select-dynamic-batch-pruning",
            assets: [keeper, reject]
        ) { repository in
            try repository.upsert(dynamicSet)
        }
        fixture.model.setBatchSelection(keeper.id, isSelected: true)
        fixture.model.setBatchSelection(reject.id, isSelected: true)
        XCTAssertEqual(fixture.model.selectedBatchAssetIDsInCatalogOrder, [keeper.id, reject.id])

        let duplicate = try fixture.model.duplicateAssetSet(id: dynamicSet.id, named: "Five Stars Copy")

        XCTAssertEqual(duplicate.membership, dynamicSet.membership)
        XCTAssertEqual(fixture.model.assets.map(\.id), [keeper.id])
        XCTAssertEqual(fixture.model.selectedBatchAssetIDs, [keeper.id])
        XCTAssertEqual(fixture.model.selectedBatchAssetIDsInCatalogOrder, [keeper.id])
    }

    // Session restore is an observable boundary of save-and-select. Property
    // observers may write the final state more than once, but must never expose
    // a new set ID paired with the old source or partially cleared filters.
    func testSaveAndSelectOnlyPersistsTheFinalSessionState() throws {
        var asset = makeAsset(id: "atomic-session-state", path: "/Photos/Atomic/session-state.jpg")
        asset.metadata.rating = 5
        let defaultsSuite = "teststrip.save-select-session-state.\(UUID().uuidString)"
        let defaults = RecordingUserDefaults(suiteName: defaultsSuite)
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let fixture = try makeCatalogFixture(
            named: "save-select-session-state",
            assets: [asset],
            sessionRestoreDefaults: defaults
        )
        fixture.model.librarySearchText = "Atomic"
        fixture.model.minimumRatingFilter = 4
        try fixture.model.applyLibraryFilters()
        fixture.model.select(asset.id)
        let catalogRoot = fixture.catalogURL.deletingLastPathComponent()
        let restoreStore = SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot)
        defaults.beginRecording(key: SessionRestoreStore.key(forCatalogRoot: catalogRoot))

        let saved = try fixture.model.saveSelectedAssetAsManualSet(named: "Atomic Session")

        let finalState = try XCTUnwrap(restoreStore.load())
        let recordedStates = try defaults.recordedValues.map {
            try JSONDecoder().decode(SessionRestoreState.self, from: $0)
        }
        XCTAssertFalse(recordedStates.isEmpty)
        XCTAssertEqual(finalState.selectedAssetSetID, saved.id)
        XCTAssertEqual(finalState.source, .assetSet(saved.id, titled: "Atomic Session"))
        XCTAssertTrue(
            recordedStates.allSatisfy { $0 == finalState },
            "save-and-select persisted an intermediate browsing state"
        )
    }

    // Import-child selection resolves the persisted import before it can claim
    // that source identity. A singleton output is a real import scope but has
    // no multi-frame Stacks membership.
    func testSelectingAnImportChildSourceUpdatesSelectedSourceToMatch() throws {
        let asset = makeAsset(id: "import-child-source", path: "/Photos/Inside/a.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "source-import-child", assets: [asset])
        let sessionID = WorkSessionID(rawValue: "import-1")
        let outputSet = AssetSet.manual(
            id: AssetSetID(rawValue: "import-1-output"),
            name: "Imported photos",
            assetIDs: [asset.id]
        )
        try repository.upsert(outputSet)
        try repository.save(WorkSession(
            id: sessionID,
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported 1 photo from /Cards/CARD-A",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSet.id],
            completedUnitCount: 1,
            totalUnitCount: 1,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        ))
        XCTAssertEqual(try repository.assetSet(id: outputSet.id), outputSet)
        XCTAssertEqual(try model.importChildCounts(sessionID: sessionID).stacks, 0)

        try model.selectSource(.importChild(session: sessionID, child: .stacks))

        XCTAssertEqual(model.selectedSource, .importChild(session: sessionID, child: .stacks))
    }

    // Same masking as the import-child case above: `applySelectionSource`
    // owns `selectedSource` itself, but nothing currently proves it against
    // `applySource`'s blanket trailing write.
    func testSelectingTheSelectionSourceUpdatesSelectedSourceToMatch() throws {
        let asset = makeAsset(id: "selection-source", path: "/Photos/Inside/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-selection-source", assets: [asset])
        model.selectedAssetID = asset.id

        try model.selectSource(.selection)

        XCTAssertEqual(model.selectedSource, .selection)
    }

    // Selection's deterministic backing set is mutable so re-activating the
    // transient source can replace its contents. A work session must instead
    // retain the exact Selection membership it began with.
    func testCullingSelectionSourceSnapshotsItsInputBeforeSelectionChanges() throws {
        let first = makeAsset(id: "selection-cull-first", path: "/Photos/Inside/first.jpg")
        let second = makeAsset(id: "selection-cull-second", path: "/Photos/Inside/second.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "source-selection-cull-snapshot",
            assets: [first, second]
        )
        model.select(first.id)
        try model.selectSource(.selection)
        let transientSelectionSetID = try XCTUnwrap(model.selectedAssetSetID)
        XCTAssertEqual(model.assets.map(\.id), [first.id])

        let session = try model.cullCurrentResults()
        let inputSetID = try XCTUnwrap(session.inputSetIDs.first)

        XCTAssertNotEqual(inputSetID, transientSelectionSetID)
        XCTAssertTrue(inputSetID.rawValue.hasPrefix("work-input-\(session.id.rawValue)"))
        XCTAssertEqual(try repository.assetSet(id: inputSetID).membership, .snapshot([first.id]))

        try model.selectSource(.allPhotos)
        model.select(second.id)
        try model.selectSource(.selection)

        XCTAssertEqual(model.selectedSource, .selection)
        XCTAssertEqual(model.selectedAssetSetID, transientSelectionSetID)
        XCTAssertEqual(model.assets.map(\.id), [second.id])

        let storedSession = try repository.session(id: session.id)
        XCTAssertEqual(storedSession.inputSetIDs, [inputSetID])
        XCTAssertEqual(
            try repository.assetIDs(matching: SetQuery(predicates: [.workSession(session.id.rawValue)])),
            [first.id]
        )

        try model.applyWorkSession(id: session.id)

        XCTAssertEqual(model.selectedSource.kind, .workSession(session.id))
        XCTAssertEqual(model.assets.map(\.id), [first.id])
    }

    // Correction A9: `applySource`'s `.autopilotSuggestions` arm used to call
    // `beginAutopilotReview()`, which wrote `selectedView = .grid` directly —
    // violating orthogonality (selecting a source must never change the
    // lens). The lens fallback for AI Suggestions must run through the same
    // `LensRules` mechanism every other source uses, so a non-disabling lens
    // like Timeline survives selecting it, and the ghost scope — not
    // whatever was loaded before — is what actually lands in `assets`.
    func testSelectingAutopilotSuggestionsAppliesTheGhostScopeWithoutChangingANonDisablingLens() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let lead = makeAsset(
            id: "ai-suggestions-lead",
            path: "/Photos/Cull/ai-suggestions-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let alternate = makeAsset(
            id: "ai-suggestions-alt",
            path: "/Photos/Cull/ai-suggestions-alt.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "source-ai-suggestions",
            assets: [lead, alternate]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: lead.id, kind: .focus, value: .score(0.30), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: alternate.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
        ])
        try model.selectSource(.allPhotos)
        _ = try model.runAutopilotOnCurrentScope()
        let ghostIDs = model.autopilotGhostAssetIDs
        XCTAssertFalse(ghostIDs.isEmpty)

        model.selectLens(.timeline)
        try model.selectSource(.autopilotSuggestions)

        XCTAssertEqual(model.selectedLens, .timeline, "selecting AI Suggestions must not move the lens")
        XCTAssertEqual(model.selectedSource, .autopilotSuggestions)
        XCTAssertEqual(
            Set(model.assets.map(\.id)),
            Set(ghostIDs),
            "must scope to the ghost assets, not whatever was loaded before"
        )
    }

    // MARK: - Cull these

    // The handoff travels as a SetQuery. The text serializer silently drops
    // .likelyPick, .likelyIssue, .evaluationFailure, and .withinGeoBounds — a
    // handoff routed through librarySearchText would lose the scope.
    func testCullTheseHandsTheResultSetToTheCullLensAsASetQuery() throws {
        let pick = makeAsset(id: "cull-these-pick", path: "/Photos/a.jpg")
        let plain = makeAsset(id: "cull-these-plain", path: "/Photos/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "cull-these-handoff", assets: [pick, plain])
        try repository.updateMetadata(assetID: pick.id) { metadata in
            metadata.flag = .pick
        }
        try model.selectSource(.smartCollection(.picks))
        XCTAssertEqual(model.assets.map(\.id), [pick.id])

        _ = try model.cullCurrentResults()

        XCTAssertEqual(model.selectedLens, .cull)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])
        guard case .search(let query) = model.selectedSource.kind else {
            return XCTFail("expected the handed-off search to become the source, got \(model.selectedSource.kind)")
        }
        XCTAssertTrue(query.predicates.contains(.flag(.pick)))
    }

    func testCullTheseSurvivesThePredicatesTheTextSerializerWouldDrop() throws {
        let asset = makeAsset(id: "cull-these-lossy", path: "/Photos/a.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "cull-these-lossy", assets: [asset])
        // The asset must rank as a potential pick for the scope to be non-empty;
        // a focus score >= 0.8 (calibrated scale) is a strong read.
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: asset.id, kind: .focus, value: .score(0.9), confidence: 0.9, provenance: provenance)
        ])
        try model.selectSource(.smartCollection(.potentialPicks))
        XCTAssertEqual(model.assets.map(\.id), [asset.id], "asset must rank as a potential pick for the scope to be non-empty")

        // Exercise the reachable path: `cullCurrentResults()` is what the UI
        // calls. Using `try?` would silently swallow a throw and let the test
        // pass even if the handoff failed.
        let session = try model.cullCurrentResults()
        XCTAssertEqual(session.kind, .culling, "a cull session should have been started")
        XCTAssertEqual(model.selectedLens, .cull, "the lens should have switched to cull")

        guard case .search(let query) = model.selectedSource.kind else {
            return XCTFail("expected a search source")
        }
        XCTAssertTrue(
            query.predicates.contains(.likelyPick),
            "`.likelyPick` has no text form at all — routing the handoff through text loses it silently"
        )
    }

    // The scope must be non-empty going in, or `canCullCurrentResults` is
    // already `false` from `canBeginCullingSession`'s own `!assets.isEmpty`
    // guard, and the diagnostic check below it never gets exercised. Recording
    // a real failure row (rather than trusting an empty smart collection) is
    // what makes `!selectedSource.isDiagnostic` the sole reason this is false.
    func testCullTheseIsUnavailableOnADiagnosticSource() throws {
        let asset = makeAsset(id: "cull-these-diagnostic", path: "/Photos/a.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "cull-these-diagnostic", assets: [asset])
        try repository.recordEvaluationFailure(assetID: asset.id, provider: "local-http-model", message: "model timed out")

        try model.selectSource(.smartCollection(.providerFailures))
        XCTAssertEqual(model.assets.map(\.id), [asset.id], "scope must be non-empty for the diagnostic check below to be the deciding factor")

        XCTAssertFalse(model.canCullCurrentResults)
    }

    func testTheScopeLineNamesTheHandedOffSearch() throws {
        let pick = makeAsset(id: "scope-line-pick", path: "/Photos/a.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "cull-these-scope-line", assets: [pick])
        try repository.updateMetadata(assetID: pick.id) { metadata in
            metadata.flag = .pick
        }
        try model.selectSource(.smartCollection(.picks))

        _ = try model.cullCurrentResults()

        XCTAssertEqual(model.scopeLine.sourceTitle, "Pick")
    }

    /// `cullCurrentResults()` must re-scope BEFORE starting the culling session,
    /// not after. Inverting the order is worse than a guard failure:
    /// `applySource`'s `.search` arm calls `clearLibraryQueryFilters()`, which
    /// sets `activeCullingSessionID = nil` — so the just-started session would
    /// be immediately forgotten and the scope line would show no progress.
    /// We verify both halves: the scope is `.search(query)` AND the scope line
    /// shows cull progress (which requires `activeCullingSessionID != nil`).
    func testCullCurrentResultsScopesBeforeStartingSession() throws {
        let pick = makeAsset(id: "re-scope-pick", path: "/Photos/a.jpg")
        let plain = makeAsset(id: "re-scope-plain", path: "/Photos/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "re-scope-before-start", assets: [pick, plain])
        try repository.updateMetadata(assetID: pick.id) { $0.flag = .pick }
        try model.selectSource(.smartCollection(.picks))
        XCTAssertEqual(model.assets.map(\.id), [pick.id])

        let session = try model.cullCurrentResults()
        XCTAssertEqual(session.kind, .culling, "a cull session should have been started")

        // The scope must be set (re-scoped to .search with the pick predicate).
        guard case .search(let query) = model.selectedSource.kind else {
            return XCTFail("expected .search source, got \(model.selectedSource.kind)")
        }
        XCTAssertTrue(query.predicates.contains(.flag(.pick)),
                      "the handed-off scope must carry the pick predicate")

        // The session must still be active — if the order were inverted,
        // clearLibraryQueryFilters() would nil out activeCullingSessionID and
        // the scope line would fall back to resultCount (no ✓/left progress).
        XCTAssertTrue(model.scopeLine.statusText.contains("✓"),
                      "scope line should show cull progress, got \(model.scopeLine.statusText)")
        XCTAssertTrue(model.scopeLine.statusText.contains("left"),
                      "scope line should show remaining count, got \(model.scopeLine.statusText)")
    }

    // SP-D0: an unconfirmed AI pick is tentative, not a decision — the Picks
    // source still shows it (unconfirmed labels are visible, just marked),
    // but "Cull these" must not let it masquerade as an already-reviewed
    // frame in the handed-off session. `cullCurrentResults()` only re-scopes
    // (it snapshots asset ids, never touches metadata), so this pins the
    // read side: the confirmed-only decision count survives the handoff.
    func testCullCurrentResultsNeverCountsATentativePickAsDecided() throws {
        let confirmed = makeAsset(id: "cull-these-confirmed-pick", path: "/Photos/a.jpg")
        let tentative = makeAsset(id: "cull-these-tentative-pick", path: "/Photos/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "cull-these-tentative",
            assets: [confirmed, tentative]
        )
        try repository.updateMetadata(assetID: confirmed.id) { metadata in
            metadata.flag = .pick
        }
        try repository.updateMetadata(assetID: tentative.id) { metadata in
            metadata.flag = .pick
            metadata.aiUnconfirmedFields = [.flag]
        }
        try model.selectSource(.smartCollection(.picks))
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([confirmed.id, tentative.id]))

        _ = try model.cullCurrentResults()

        XCTAssertEqual(model.cullingProgressSummary.pickCount, 1)
        // The scope line is what the user actually sees under the toolbar —
        // pinning only `cullingProgressSummary` leaves `scopeLine` free to
        // build its own progress from raw asset flags without any test
        // noticing. Full-string equality rather than `contains("✓ 1")`,
        // which would also match "✓ 10".
        XCTAssertEqual(model.scopeLine.statusText, "2 photos · ✓ 1 · ✕ 0 · 1 left")
    }

    // SP: Task 7's fix gates `scopeLine`'s two cull-only catalog reads
    // (`cullingProgressSummary`'s confirmed pick/reject `COUNT`s and
    // `cullingStackListEntries()`'s per-stack/per-asset reads) behind
    // `selectedLens == .cull`, mirroring the gate `SidebarView` already puts
    // on its stack rows. This cannot be pinned by an output assertion:
    // `browseStatusText` (every non-Cull lens) never reads `cullProgress` or
    // `stackCount` at all, so evaluating them and discarding the result
    // renders identically to never evaluating them — a `statusText` assertion
    // would prove the value is unused, not that the query never ran. Only a
    // query-count assertion, via the real (non-mock) `CatalogDatabase.rowQueryObserver`
    // seam, proves the catalog was never touched. In this fixture
    // `cullingStackListEntries()` itself contributes no queries — it
    // guard-returns on `selectedAssetSetID == nil`, since a filter-scoped
    // cull session never calls `applyAssetSet` — so the positive contrast
    // below rests entirely on `cullingProgressSummary`'s two `COUNT`s.
    func testScopeLineDoesNotQueryTheCatalogOutsideTheCullLens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-library-source-scope-line-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "scope-line-gate", path: "/Photos/a.jpg")
        try repository.upsert([asset])
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

        _ = try model.beginCullingSession(named: "Scope Line Gate")
        XCTAssertEqual(model.selectedLens, .cull)
        XCTAssertTrue(
            model.scopeLine.statusText.contains("✓"),
            "expected a live run right after starting the session, got \"\(model.scopeLine.statusText)\""
        )

        model.selectedView = .grid
        XCTAssertEqual(model.selectedLens, .grid)

        var rowQueries: [String] = []
        database.rowQueryObserver = { sql in rowQueries.append(sql) }
        _ = model.scopeLine
        XCTAssertTrue(rowQueries.isEmpty, "browse lens scopeLine queried the catalog: \(rowQueries)")

        model.selectedView = .loupe
        XCTAssertEqual(model.selectedLens, .cull)
        XCTAssertTrue(
            model.scopeLine.statusText.contains("✓"),
            "visiting the browse lens must not have lost the session, got \"\(model.scopeLine.statusText)\""
        )

        // Positive contrast: without this, a miswired observer that never
        // fires would make the negative assertion above pass trivially even
        // if the gate were deleted entirely.
        rowQueries = []
        _ = model.scopeLine
        XCTAssertFalse(rowQueries.isEmpty, "Cull lens scopeLine should query the catalog for its progress counts")
    }

    // MARK: - Fixtures

    private func makeAsset(
        id: String,
        path: String,
        availability: SourceAvailability = .online,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: availability,
            metadata: AssetMetadata(),
            technicalMetadata: technicalMetadata
        )
    }

    private static func technicalMetadata(
        capturedAt: Date,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            latitude: latitude,
            longitude: longitude,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private struct SaveAndSelectState: Equatable {
        var sidebarSections: [SidebarSection]
        var savedAssetSets: [AssetSet]
        var assetSetCounts: [AssetSetID: Int]
        var smartCollectionCounts: [SmartCollection: Int]
        var workSessionScopeCounts: [WorkSessionID: Int]
        var importSourceSummaries: [ImportSidebarSummary]
        var completedImports: [AppWorkActivity]
        var expandedImportSessionIDs: Set<String>
        var importChildCountsBySessionID: [String: ImportChildCounts]
        var isShowingAllImports: Bool
        var catalogFolders: [CatalogFolder]
        var sourceRoots: [CatalogSourceRoot]
        var assetIDsWithBondedSecondaries: Set<AssetID>
        var autopilotGhostAssetIDs: [AssetID]
        var isAutopilotReviewActive: Bool
        var proposedPhotos: [ProposedPersonPhoto]
        var selectedSource: LibrarySource
        var selectedView: LibraryViewMode
        var selectedLens: LibraryLens
        var selectedAssetSetID: AssetSetID?
        var activeLibraryFilterRows: [ActiveLibraryFilterRow]
        var activeLibraryFilterChips: [String]
        var hasActiveLibraryFilters: Bool
        var assets: [Asset]
        var totalAssetCount: Int
        var selectedAssetID: AssetID?
        var selectedBatchAssetIDs: Set<AssetID>
        var selectedBatchAssetIDsInCatalogOrder: [AssetID]
        var catalogPlaceClusters: [CatalogPlaceCluster]
        var catalogTopLocations: [CatalogTopLocation]
        var geotaggedCoverage: CatalogGeotaggedCoverage
        var statusMessage: String?
        var errorMessage: String?
        var importError: String?
        var workHistorySearchResults: [AppWorkActivity]

        init(model: AppModel) {
            sidebarSections = model.sidebarSections
            savedAssetSets = model.savedAssetSets
            assetSetCounts = model.assetSetCounts
            smartCollectionCounts = model.smartCollectionCounts
            workSessionScopeCounts = model.workSessionScopeCounts
            importSourceSummaries = model.importSourceSummaries
            completedImports = model.completedImports
            expandedImportSessionIDs = model.expandedImportSessionIDs
            importChildCountsBySessionID = model.importChildCountsBySessionID
            isShowingAllImports = model.isShowingAllImports
            catalogFolders = model.catalogFolders
            sourceRoots = model.sourceRoots
            assetIDsWithBondedSecondaries = model.assetIDsWithBondedSecondaries
            autopilotGhostAssetIDs = model.autopilotGhostAssetIDs
            isAutopilotReviewActive = model.isAutopilotReviewActive
            proposedPhotos = model.proposedPhotos
            selectedSource = model.selectedSource
            selectedView = model.selectedView
            selectedLens = model.selectedLens
            selectedAssetSetID = model.selectedAssetSetID
            activeLibraryFilterRows = model.activeLibraryFilterRows
            activeLibraryFilterChips = model.activeLibraryFilterChips
            hasActiveLibraryFilters = model.hasActiveLibraryFilters
            assets = model.assets
            totalAssetCount = model.totalAssetCount
            selectedAssetID = model.selectedAssetID
            selectedBatchAssetIDs = model.selectedBatchAssetIDs
            selectedBatchAssetIDsInCatalogOrder = model.selectedBatchAssetIDsInCatalogOrder
            catalogPlaceClusters = model.catalogPlaceClusters
            catalogTopLocations = model.catalogTopLocations
            geotaggedCoverage = model.geotaggedCoverage
            statusMessage = model.statusMessage
            errorMessage = model.errorMessage
            importError = model.importError
            workHistorySearchResults = model.workHistorySearchResults
        }
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

    private func makeCatalogFixture(
        named name: String,
        assets: [Asset],
        sessionRestoreDefaults: UserDefaults? = nil,
        configureRepository: (CatalogRepository) throws -> Void = { _ in }
    ) throws -> (
        model: AppModel,
        repository: CatalogRepository,
        database: CatalogDatabase,
        catalogURL: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-library-source-\(name)-\(UUID().uuidString)", isDirectory: true)
        let paths = AppCatalog.defaultPaths(
            applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)
        )
        let database = try CatalogDatabase.open(at: paths.catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        try configureRepository(repository)
        let previewCache = PreviewCache(root: paths.previewCacheRoot)
        let catalog = AppCatalog(
            paths: paths,
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(
            catalog: catalog,
            workerSupervisor: nil,
            sessionRestoreDefaults: sessionRestoreDefaults
        )
        return (model, repository, database, paths.catalogURL)
    }

    private final class RecordingUserDefaults: UserDefaults {
        private(set) var recordedValues: [Data] = []
        private var keyToRecord: String?

        init(suiteName: String) {
            super.init(suiteName: suiteName)!
        }

        func beginRecording(key: String) {
            keyToRecord = key
            recordedValues = []
        }

        override func set(_ value: Any?, forKey defaultName: String) {
            super.set(value, forKey: defaultName)
            guard defaultName == keyToRecord,
                  let data = data(forKey: defaultName) else { return }
            recordedValues.append(data)
        }
    }
}
