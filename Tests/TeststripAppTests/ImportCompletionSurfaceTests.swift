import XCTest
@testable import TeststripCore
@testable import TeststripApp

// The completion moment's *model* surfaces, as opposed to the pure functions
// `ImportCompletionToastPresentationTests` and `ActivityCenterPresentationTests`
// already cover. Everything here is wiring: which query the bell receipts read,
// whether the toast really consults the session gate, and the three import
// verbs the sidebar context menu offers for any past import.
final class ImportCompletionSurfaceTests: XCTestCase {

    // MARK: - Bell receipts

    // An import that produced no output set gets no Imports sidebar row
    // (`importSectionRows` filters on `producedOutputSet`), so the bell
    // receipt is that import's only record. `recentWork` is
    // `workSessions(limit: 10)` across all thirteen work kinds, so ten later
    // culling/export sessions evict the import long before the display cap of
    // five bites. The kind-scoped, unbounded query
    // `refreshImportSourceSummaries()` already runs is the one that can keep
    // the promise.
    func testAnEmptyImportsReceiptSurvivesLaterWorkOfOtherKinds() throws {
        let directory = try makeTemporaryDirectory(named: "receipt-eviction")
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.save(makeImportSession(
            id: "import-empty",
            detail: "No photos imported from /Cards/CARD-A",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        for index in 0..<12 {
            try repository.save(makeWorkSession(
                id: "cull-\(index)",
                kind: .culling,
                title: "Cull the shoot",
                detail: "12 picks",
                createdAt: Date(timeIntervalSince1970: TimeInterval(2_000 + index * 100))
            ))
        }

        let model = try AppModel.load(catalog: catalog)

        XCTAssertFalse(
            model.recentWork.contains { $0.id == "import-empty" },
            "fixture check: the import must be outside the limit-10 recentWork window"
        )
        XCTAssertEqual(
            model.activityCenterPresentation.receipts.map(\.id),
            ["import-empty"],
            "the bell receipt is an empty import's only record — it must not be evicted by later work of other kinds"
        )
    }

    // The wiring itself: a completed import reaches `activityCenterPresentation`
    // as a receipt. Asserts only the identity and the culling affordance, which
    // survive whichever completed-ingest query the receipts end up reading.
    func testACompletedImportReachesTheActivityCenterAsAReceipt() throws {
        let directory = try makeTemporaryDirectory(named: "receipt-wiring")
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.save(makeImportSession(
            id: "import-1",
            detail: "Imported 3 photos from /Cards/CARD-A",
            createdAt: Date(timeIntervalSince1970: 1_000),
            completedUnitCount: 3,
            totalUnitCount: 3
        ))
        try repository.save(makeWorkSession(
            id: "cull-1",
            kind: .culling,
            title: "Cull the shoot",
            detail: "12 picks",
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))

        let model = try AppModel.load(catalog: catalog)

        let receipts = model.activityCenterPresentation.receipts
        XCTAssertEqual(receipts.map(\.id), ["import-1"], "only completed imports become receipts")
        XCTAssertEqual(receipts.first?.sessionID, WorkSessionID(rawValue: "import-1"))
        XCTAssertTrue(receipts.first?.canStartCulling ?? false)
    }

    // MARK: - The completion toast

    @MainActor
    func testTheCompletionToastAnnouncesAnImportRecordedInThisSession() async throws {
        let directory = try makeTemporaryDirectory(named: "toast-live-session")
        let fixture = try makeStubbedImportModel(in: directory)

        fixture.model.beginImportFolder(fixture.photoFolder)
        try await waitForCompletedImportActivity(in: fixture.model)

        let toast = try XCTUnwrap(fixture.model.importCompletionToast)
        XCTAssertEqual(toast.headline, "Imported 1 photo")
        XCTAssertTrue(toast.showsStartCulling)
    }

    // app-006's zombie panel: the toast must not come back on relaunch. The
    // mechanism is that `currentSessionActivityIDs` is written only by
    // `recordRecentActivity` and never repopulated from the catalog on load,
    // so a restored summary answers `false` to `isCurrentSessionActivity`.
    // The summary itself survives the relaunch — asserted below — so a
    // `importCompletionToast` that passed `isCurrentSessionActivity: true`
    // unconditionally would resurrect the panel.
    @MainActor
    func testTheCompletionToastDoesNotSurviveARelaunch() async throws {
        let directory = try makeTemporaryDirectory(named: "toast-relaunch")
        let fixture = try makeStubbedImportModel(in: directory)

        fixture.model.beginImportFolder(fixture.photoFolder)
        try await waitForCompletedImportActivity(in: fixture.model)
        XCTAssertNotNil(fixture.model.importCompletionToast, "fixture check: the live session announces the import")

        let relaunched = try AppModel.load(catalog: try AppCatalog.open(paths: fixture.paths))

        let restoredSummary = try XCTUnwrap(
            relaunched.latestImportCompletionSummary,
            "the summary must survive the relaunch — otherwise this test cannot tell the session gate from a missing summary"
        )
        XCTAssertFalse(relaunched.isCurrentSessionActivity(id: restoredSummary.activityID))
        XCTAssertNil(relaunched.importCompletionToast, "a summary restored from persisted history must never resurrect the toast")
    }

    // MARK: - startCullingImport

    func testStartCullingImportScopesTheCullToThatImport() throws {
        let directory = try makeTemporaryDirectory(named: "start-culling-import")
        let first = makeAsset(id: "card-a-first")
        let second = makeAsset(id: "card-a-second")
        let outsider = makeAsset(id: "not-in-the-import")
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.upsert([first, second, outsider])
        let sessionID = WorkSessionID(rawValue: "import-cullable")
        try saveImport(
            id: sessionID.rawValue,
            detail: "Imported 2 photos from /Cards/CARD-A",
            assetIDs: [first.id, second.id],
            in: repository
        )
        let model = try AppModel.load(catalog: catalog)

        let culling = try model.startCullingImport(sessionID: sessionID, title: "Card A Cull")

        XCTAssertEqual(culling.title, "Card A Cull")
        let inputSetID = try XCTUnwrap(culling.inputSetIDs.first)
        XCTAssertEqual(
            Set(assetIDs(in: try repository.assetSet(id: inputSetID))),
            Set([first.id, second.id]),
            "the cull input is the import's output set, not the whole catalog"
        )
        XCTAssertEqual(model.selectedView, .loupe, "the lens comes from beginCullingSession")
    }

    // Lens/source orthogonality: `startCullingImport` selects the source and
    // delegates the lens to `beginCullingSession`. An import with nothing to
    // cull makes that visible — `beginCullingSession` throws, and because
    // `startCullingImport` writes no lens of its own, the lens is unchanged
    // afterwards while the source has moved to the import. Starts from
    // `.timeline`, not Grid — Grid is also the zero-asset fallback
    // `LensRules.resolvedLens` lands on, so starting there couldn't tell
    // "wrote nothing" from "wrote Grid".
    func testStartCullingImportSelectsTheSourceWithoutWritingALensOfItsOwn() throws {
        let directory = try makeTemporaryDirectory(named: "start-culling-import-empty")
        let (catalog, repository) = try makeCatalog(in: directory)
        let sessionID = WorkSessionID(rawValue: "import-with-nothing-to-cull")
        try saveImport(
            id: sessionID.rawValue,
            detail: "Imported 0 photos from /Cards/CARD-B",
            assetIDs: [],
            in: repository
        )
        let model = try AppModel.load(catalog: catalog)
        model.selectLens(.timeline)
        XCTAssertEqual(model.selectedLens, .timeline, "fixture check")

        XCTAssertThrowsError(try model.startCullingImport(sessionID: sessionID, title: "Card B Cull"))

        XCTAssertEqual(model.selectedSource, LibrarySource.workSession(sessionID, titled: "Card B Cull"))
        XCTAssertEqual(model.selectedLens, .timeline, "startCullingImport must not write the lens itself")
    }

    // MARK: - beginStackCulling for a past import

    // The generalized primitive takes the import explicitly, so an older
    // import's "Cull stacks" verb must not record an intent claiming it is the
    // latest one.
    func testStackCullingAnOlderImportRecordsItAsThisImportNotTheLatest() throws {
        let directory = try makeTemporaryDirectory(named: "stack-cull-older-import")
        let capturedAt = Date(timeIntervalSince1970: 100)
        let stackLead = makeAsset(id: "older-stack-lead", capturedAt: capturedAt)
        let stackAlternate = makeAsset(id: "older-stack-alternate", capturedAt: capturedAt.addingTimeInterval(1))
        let newest = makeAsset(id: "newest-import-frame", capturedAt: capturedAt.addingTimeInterval(10_000))
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.upsert([stackLead, stackAlternate, newest])
        let olderID = WorkSessionID(rawValue: "import-older")
        try saveImport(
            id: olderID.rawValue,
            detail: "Imported 2 photos from /Cards/CARD-A",
            assetIDs: [stackLead.id, stackAlternate.id],
            createdAt: Date(timeIntervalSince1970: 1_000),
            in: repository
        )
        try saveImport(
            id: "import-newest",
            detail: "Imported 1 photo from /Cards/CARD-B",
            assetIDs: [newest.id],
            createdAt: Date(timeIntervalSince1970: 5_000),
            in: repository
        )
        let model = try AppModel.load(catalog: catalog)
        XCTAssertEqual(
            model.latestImportCompletionSummary?.activityID,
            "import-newest",
            "fixture check: the import being stack-culled must not be the latest one"
        )

        let session = try model.beginStackCulling(importSessionID: olderID, title: "Card A Stacks")

        XCTAssertEqual(session.intent, "Cull 1 stack from this import")
        let stackSetID = try XCTUnwrap(session.inputSetIDs.first)
        XCTAssertEqual(assetIDs(in: try repository.assetSet(id: stackSetID)), [stackLead.id, stackAlternate.id])
        XCTAssertEqual(model.selectedView, .loupe)
    }

    // MARK: - The import row's three context verbs

    // A work session outside `persistedWorkActivityIDs` (the limit-10
    // recent/starred window the Star verb is gated on) must still offer its
    // three context verbs: older imports are exactly the rows the Imports
    // section exists to serve.
    func testAnImportOutsideTheRecentWorkWindowStillOffersItsThreeVerbs() throws {
        let directory = try makeTemporaryDirectory(named: "import-verbs-outside-recent-work")
        let frame = makeAsset(id: "old-import-frame")
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.upsert([frame])
        let sessionID = WorkSessionID(rawValue: "import-old")
        try saveImport(
            id: sessionID.rawValue,
            detail: "Imported 1 photo from /Cards/CARD-A",
            assetIDs: [frame.id],
            createdAt: Date(timeIntervalSince1970: 1_000),
            in: repository
        )
        for index in 0..<12 {
            try repository.save(makeWorkSession(
                id: "cull-\(index)",
                kind: .culling,
                title: "Cull the shoot",
                detail: "12 picks",
                createdAt: Date(timeIntervalSince1970: TimeInterval(2_000 + index * 100))
            ))
        }
        let model = try AppModel.load(catalog: catalog)
        let row = try XCTUnwrap(importRow(for: sessionID, in: model))
        XCTAssertFalse(
            model.canToggleWorkSessionStarred(row),
            "fixture check: this import is outside the window the Star verb is gated on"
        )

        let actions = model.sidebarContextActions(for: row)

        XCTAssertEqual(actions.map(\.kind), [
            .cullImportStacks(sessionID),
            .evaluateImport(sessionID),
            .compareImport(sessionID)
        ])
        XCTAssertEqual(actions.map(\.title), [
            "Cull stacks",
            "Evaluate import",
            "Manual Compare over the import"
        ])
    }

    func testTheCullStacksVerbStartsAStackCullOverThatImport() throws {
        let directory = try makeTemporaryDirectory(named: "import-verb-cull-stacks")
        let capturedAt = Date(timeIntervalSince1970: 100)
        let stackLead = makeAsset(id: "verb-stack-lead", capturedAt: capturedAt)
        let stackAlternate = makeAsset(id: "verb-stack-alternate", capturedAt: capturedAt.addingTimeInterval(1))
        let outsider = makeAsset(id: "verb-outsider", capturedAt: capturedAt.addingTimeInterval(2))
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.upsert([stackLead, stackAlternate, outsider])
        let sessionID = WorkSessionID(rawValue: "import-with-stacks")
        try saveImport(
            id: sessionID.rawValue,
            detail: "Imported 2 photos from /Cards/CARD-A",
            assetIDs: [stackLead.id, stackAlternate.id],
            in: repository
        )
        let model = try AppModel.load(catalog: catalog)
        let action = try XCTUnwrap(contextAction(.cullImportStacks(sessionID), for: sessionID, in: model))

        try model.performSidebarContextAction(action)

        XCTAssertEqual(model.assets.map(\.id), [stackLead.id, stackAlternate.id])
        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.statusMessage, "Started stack cull with 1 stack")
    }

    func testTheManualCompareVerbScopesCompareToThatImport() throws {
        let directory = try makeTemporaryDirectory(named: "import-verb-compare")
        let first = makeAsset(id: "compare-verb-first")
        let second = makeAsset(id: "compare-verb-second")
        let outsider = makeAsset(id: "compare-verb-outsider")
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.upsert([first, second, outsider])
        let sessionID = WorkSessionID(rawValue: "import-comparable")
        try saveImport(
            id: sessionID.rawValue,
            detail: "Imported 2 photos from /Cards/CARD-A",
            assetIDs: [first.id, second.id],
            in: repository
        )
        let model = try AppModel.load(catalog: catalog)
        let action = try XCTUnwrap(contextAction(.compareImport(sessionID), for: sessionID, in: model))

        try model.performSidebarContextAction(action)

        XCTAssertEqual(model.selectedView, .compare)
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([first.id, second.id]))
        if case .workSession(let scopedID) = model.selectedSource.kind {
            XCTAssertEqual(scopedID, sessionID)
        } else {
            XCTFail("Manual Compare must scope the source to the import, got \(model.selectedSource.kind)")
        }
    }

    // Only the import's own assets are dispatched, and only the ones with a
    // cached preview. The `.evaluateImport` context action gets there by
    // scoping the source (`selectSource(.workSession(sessionID:))`) before
    // calling the generalized `requestCurrentScopeAssetEvaluations()`.
    func testTheEvaluateImportVerbQueuesEvaluationsForThatImportsCachedAssetsOnly() throws {
        let directory = try makeTemporaryDirectory(named: "import-verb-evaluate")
        let inside = makeAsset(id: "evaluate-verb-cached")
        let insideUncached = makeAsset(id: "evaluate-verb-uncached")
        let outside = makeAsset(id: "evaluate-verb-outside")
        let (catalog, repository) = try makeCatalog(in: directory)
        try repository.upsert([inside, insideUncached, outside])
        let sessionID = WorkSessionID(rawValue: "import-evaluable")
        try saveImport(
            id: sessionID.rawValue,
            detail: "Imported 2 photos from /Cards/CARD-A",
            assetIDs: [inside.id, insideUncached.id],
            in: repository
        )
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: inside.id, level: .grid)))
        try writePreviewPlaceholder(to: catalog.previewCache.url(for: PreviewCacheKey(assetID: outside.id, level: .grid)))
        let model = try AppModel.load(
            catalog: catalog,
            workerSupervisor: WorkerSupervisor(
                queue: BackgroundWorkQueue(maxRunningCount: 4),
                transport: SilentWorkerTransport()
            )
        )
        let action = try XCTUnwrap(contextAction(.evaluateImport(sessionID), for: sessionID, in: model))

        try model.performSidebarContextAction(action)

        let queuedItemIDs = model.backgroundWorkQueue.items.map(\.id.rawValue)
        XCTAssertFalse(queuedItemIDs.isEmpty, "the verb must queue evaluations")
        XCTAssertTrue(
            queuedItemIDs.allSatisfy { $0.contains(inside.id.rawValue) },
            "Evaluate import scopes to the import, not the whole catalog: \(queuedItemIDs)"
        )
        XCTAssertFalse(queuedItemIDs.contains { $0.contains(outside.id.rawValue) })
        XCTAssertFalse(
            queuedItemIDs.contains { $0.contains(insideUncached.id.rawValue) },
            "an imported asset with no cached preview has nothing to read yet"
        )
    }

    // MARK: - Helpers

    private struct StubbedImportFixture {
        var model: AppModel
        var paths: AppCatalogPaths
        var photoFolder: URL
    }

    @MainActor
    private func makeStubbedImportModel(in directory: URL) throws -> StubbedImportFixture {
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let importedAsset = Asset(
            id: AssetID(rawValue: "stub-imported"),
            originalURL: photoFolder.appendingPathComponent("one.png"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { paths, _, _, _ in
                Task.detached {
                    let backgroundCatalog = try AppCatalog.open(paths: paths)
                    try backgroundCatalog.repository.upsert(importedAsset)
                    return AppImportOutput(
                        result: LibraryImportResult(
                            importedAssets: [importedAsset],
                            previewFailures: [],
                            skippedSourceFiles: [],
                            newAssetCount: 1,
                            existingAssetCount: 0
                        ),
                        assets: try backgroundCatalog.repository.allAssets(limit: 500),
                        totalAssetCount: try backgroundCatalog.repository.assetCount()
                    )
                }
            }
        )
        return StubbedImportFixture(model: model, paths: paths, photoFolder: photoFolder)
    }

    @MainActor
    private func waitForCompletedImportActivity(in model: AppModel) async throws {
        for _ in 0..<200 {
            if model.recentWork.first?.status == .completed {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for the import activity to complete")
    }

    private func importRow(for sessionID: WorkSessionID, in model: AppModel) -> SidebarRow? {
        model.sidebarSections
            .first { $0.title == UnifiedSidebarPresentation.importsSectionTitle }?
            .rows
            .first { $0.id == "import-\(sessionID.rawValue)" }
    }

    private func contextAction(
        _ kind: SidebarRowContextActionKind,
        for sessionID: WorkSessionID,
        in model: AppModel
    ) throws -> SidebarRowContextAction? {
        let row = try XCTUnwrap(importRow(for: sessionID, in: model), "no Imports row for \(sessionID.rawValue)")
        return model.sidebarContextActions(for: row).first { $0.kind == kind }
    }

    private func assetIDs(in assetSet: AssetSet) -> [AssetID] {
        switch assetSet.membership {
        case .manual(let ids), .snapshot(let ids):
            return ids
        case .dynamic:
            return []
        }
    }

    private func saveImport(
        id: String,
        detail: String,
        assetIDs: [AssetID],
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        in repository: CatalogRepository
    ) throws {
        let outputSetID = AssetSetID(rawValue: "work-output-\(id)")
        try repository.upsert(AssetSet.manual(id: outputSetID, name: detail, assetIDs: assetIDs))
        try repository.save(WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: detail,
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSetID],
            completedUnitCount: assetIDs.count,
            totalUnitCount: assetIDs.count,
            failureCount: 0,
            createdAt: createdAt,
            updatedAt: createdAt
        ))
    }

    private func makeImportSession(
        id: String,
        detail: String,
        createdAt: Date,
        completedUnitCount: Int = 0,
        totalUnitCount: Int? = nil
    ) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: detail,
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeWorkSession(
        id: String,
        kind: WorkSessionKind,
        title: String,
        detail: String,
        createdAt: Date
    ) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: kind,
            intent: detail,
            title: title,
            detail: detail,
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: 1,
            totalUnitCount: 1,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeAsset(id: String, capturedAt: Date? = nil) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/Import/\(id).cr2"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 0)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: capturedAt.map { date in
                AssetTechnicalMetadata(
                    pixelWidth: 6000,
                    pixelHeight: 4000,
                    capturedAt: date,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            }
        )
    }

    private func writePreviewPlaceholder(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: url)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-completion-surface", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeCatalog(in directory: URL) throws -> (AppCatalog, CatalogRepository) {
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
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
        return (catalog, repository)
    }
}

/// A worker transport that swallows everything. These tests only need the
/// supervisor to exist so `requestEvaluation` can enqueue; nothing here reads
/// the wire.
private final class SilentWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    var terminationHandler: (() -> Void)?
    private(set) var isRunning = false

    func launch() throws {
        isRunning = true
    }

    func writeLine(_ line: String) throws {}

    func terminate() {
        isRunning = false
    }
}
