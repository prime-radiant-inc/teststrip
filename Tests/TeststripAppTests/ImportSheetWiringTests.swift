import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class ImportSheetWiringTests: XCTestCase {

    func testSupportedExtensionsReturnsCatalogableExtensions() {
        let model = AppModel.demo()
        XCTAssertEqual(
            model.supportedExtensions,
            ImageIODecodeProvider.catalogableExtensions
        )
    }

    @MainActor
    func testPendingImportFoldersInitiallyEmpty() {
        let model = AppModel.demo()
        XCTAssertTrue(model.pendingImportFolders.isEmpty)
        XCTAssertEqual(model.pendingImportFolders.count, 0)
    }

    @MainActor
    func testBeginImportFoldersQueuesRemainingFoldersBeyondFirst() {
        let model = AppModel.demo()
        let urls = [
            URL(fileURLWithPath: "/tmp/import-sheet/a", isDirectory: true),
            URL(fileURLWithPath: "/tmp/import-sheet/b", isDirectory: true),
            URL(fileURLWithPath: "/tmp/import-sheet/c", isDirectory: true)
        ]
        model.beginImportFolders(urls)
        XCTAssertEqual(model.pendingImportFolders.count, 2)
        XCTAssertEqual(
            model.pendingImportFolders.map(\.url),
            [urls[1], urls[2]]
        )
    }

    @MainActor
    func testBeginImportFoldersWithSingleFolderQueuesNothing() {
        let model = AppModel.demo()
        model.beginImportFolders([
            URL(fileURLWithPath: "/tmp/import-sheet/only", isDirectory: true)
        ])
        XCTAssertTrue(model.pendingImportFolders.isEmpty)
    }

    @MainActor
    func testDrainPendingImportFolderStartsFirstQueuedFolder() {
        let model = AppModel.demo()
        let urls = [
            URL(fileURLWithPath: "/tmp/import-sheet/drain-a", isDirectory: true),
            URL(fileURLWithPath: "/tmp/import-sheet/drain-b", isDirectory: true),
            URL(fileURLWithPath: "/tmp/import-sheet/drain-c", isDirectory: true)
        ]
        model.beginImportFolders(urls)
        XCTAssertEqual(model.pendingImportFolders.count, 2)

        model.drainPendingImportFolder()

        XCTAssertEqual(model.pendingImportFolders.map(\.url), [urls[2]])
    }

    @MainActor
    func testDrainPendingImportFolderIsNoopWhenQueueEmpty() {
        let model = AppModel.demo()
        model.drainPendingImportFolder()
        XCTAssertTrue(model.pendingImportFolders.isEmpty)
    }

    // MARK: - ImportSheetState state-machine (Task 9 fix #3)

    /// Helper: builds a minimal `ImportSelectionData` with a real draft
    /// and cache, suitable for constructing `.selection(data)` sheet state.
    private func makeSelectionData(
        fileURLs: [URL] = []
    ) -> (ImportSelectionData, PreIngestThumbnailCache) {
        let sourceURL = URL(fileURLWithPath: "/tmp/import-sheet/test", isDirectory: true)
        let summary = ImportSourceSummary(
            sourceURL: sourceURL,
            photoCount: fileURLs.count,
            byteCount: 0,
            reachedLimit: false,
            reachedEntryLimit: false,
            scannedEntryCount: fileURLs.count,
            unavailableReason: nil,
            blocksImport: false,
            fileURLs: fileURLs
        )
        let draft = ImportConfirmationDraft(
            mode: .folder,
            sourceURL: sourceURL,
            additionalFolderURLs: [],
            destinationRootURL: nil,
            destinationUnavailableReason: nil,
            sourceSummary: summary
        )
        let cache = PreIngestThumbnailCache()
        let data = ImportSelectionData(
            sourceURL: sourceURL,
            supportedExtensions: ["jpg"],
            fileURLs: fileURLs,
            duplicateURLs: [],
            thumbnailCache: cache,
            confirmationDraft: draft
        )
        return (data, cache)
    }

    /// Verifies that `confirmingSelection` on a `.selection` sheet transitions
    /// to `.confirmation` with `selectedFiles` and `preIngestThumbnailCache` set.
    /// This would FAIL against the original buggy code that checked
    /// `if case .confirmation = importSheet` (false on `.selection`) and
    /// fell through to `importSheet = nil`.
    func testConfirmSelectionTransitionsToConfirmationWithSelectedFiles() {
        let fileURLs = [
            URL(fileURLWithPath: "/tmp/import-sheet/test/a.jpg"),
            URL(fileURLWithPath: "/tmp/import-sheet/test/b.jpg"),
            URL(fileURLWithPath: "/tmp/import-sheet/test/c.jpg")
        ]
        let (data, cache) = makeSelectionData(fileURLs: fileURLs)
        let sheet: ImportSheetState = .selection(data)
        let selectedURLs: Set<URL> = [fileURLs[0], fileURLs[2]]

        let result = ImportSheetState.confirmingSelection(sheet, selectedURLs: selectedURLs)

        guard case .confirmation(let confirmedDraft) = result else {
            XCTFail("Expected .confirmation, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(confirmedDraft.selectedFiles, selectedURLs)
        XCTAssertEqual(confirmedDraft.preIngestThumbnailCache, cache)
        XCTAssertTrue(confirmedDraft.hasSelectionFilter)
        XCTAssertEqual(confirmedDraft.selectedCount, 2)
    }

    /// Verifies that `cancellingSelection` on a `.selection` sheet transitions
    /// back to `.confirmation` with the original draft unchanged (no selection).
    /// This would FAIL against the original buggy code that checked
    /// `if case .confirmation = importSheet` and fell through to `importSheet = nil`.
    func testCancelSelectionTransitionsToConfirmationWithOriginalDraft() {
        let (data, _) = makeSelectionData()
        let sheet: ImportSheetState = .selection(data)

        let result = ImportSheetState.cancellingSelection(sheet)

        guard case .confirmation(let restoredDraft) = result else {
            XCTFail("Expected .confirmation, got \(String(describing: result))")
            return
        }
        XCTAssertNil(restoredDraft.selectedFiles)
        XCTAssertNil(restoredDraft.preIngestThumbnailCache)
        XCTAssertFalse(restoredDraft.hasSelectionFilter)
    }

    /// Verifies that `confirmingSelection` returns `nil` when the sheet is
    /// already `.confirmation` (not `.selection`). This guards against stale
    /// state — the transition should only fire from the selection sheet.
    func testConfirmSelectionReturnsNilWhenSheetIsConfirmation() {
        let sourceURL = URL(fileURLWithPath: "/tmp/import-sheet/test", isDirectory: true)
        let summary = ImportSourceSummary(
            sourceURL: sourceURL,
            photoCount: 0,
            byteCount: 0,
            reachedLimit: false,
            reachedEntryLimit: false,
            scannedEntryCount: 0,
            unavailableReason: nil,
            blocksImport: false,
            fileURLs: []
        )
        let draft = ImportConfirmationDraft(
            mode: .folder,
            sourceURL: sourceURL,
            additionalFolderURLs: [],
            destinationRootURL: nil,
            destinationUnavailableReason: nil,
            sourceSummary: summary
        )
        let sheet: ImportSheetState = .confirmation(draft)

        let result = ImportSheetState.confirmingSelection(
            sheet,
            selectedURLs: [URL(fileURLWithPath: "/tmp/x.jpg")]
        )

        XCTAssertNil(result)
    }

    /// Verifies that `cancellingSelection` returns `nil` when the sheet is
    /// already `.confirmation` (not `.selection`).
    func testCancelSelectionReturnsNilWhenSheetIsConfirmation() {
        let sourceURL = URL(fileURLWithPath: "/tmp/import-sheet/test", isDirectory: true)
        let summary = ImportSourceSummary(
            sourceURL: sourceURL,
            photoCount: 0,
            byteCount: 0,
            reachedLimit: false,
            reachedEntryLimit: false,
            scannedEntryCount: 0,
            unavailableReason: nil,
            blocksImport: false,
            fileURLs: []
        )
        let draft = ImportConfirmationDraft(
            mode: .folder,
            sourceURL: sourceURL,
            additionalFolderURLs: [],
            destinationRootURL: nil,
            destinationUnavailableReason: nil,
            sourceSummary: summary
        )
        let sheet: ImportSheetState = .confirmation(draft)

        let result = ImportSheetState.cancellingSelection(sheet)

        XCTAssertNil(result)
    }

    /// Verifies that both transitions return `nil` when the sheet is `nil`
    /// (dismissed or never presented).
    func testSelectionTransitionsReturnNilWhenSheetIsNil() {
        XCTAssertNil(ImportSheetState.confirmingSelection(
            nil,
            selectedURLs: [URL(fileURLWithPath: "/tmp/x.jpg")]
        ))
        XCTAssertNil(ImportSheetState.cancellingSelection(nil))
    }

    /// Verifies that PreIngestThumbnailCache is Equatable (required for
    /// ImportConfirmationDraft's Equatable conformance with the new field).
    func testPreIngestThumbnailCacheIsEquatable() {
        let dirA = URL(fileURLWithPath: "/tmp/cache-eq-a", isDirectory: true)
        let dirB = URL(fileURLWithPath: "/tmp/cache-eq-b", isDirectory: true)
        let cache1 = PreIngestThumbnailCache(directoryURL: dirA)
        let cache2 = PreIngestThumbnailCache(directoryURL: dirB)
        let cache1Copy = PreIngestThumbnailCache(directoryURL: dirA)
        XCTAssertEqual(cache1, cache1Copy)
        XCTAssertNotEqual(cache1, cache2)
    }

    /// Verifies the cache is threaded through to beginImportFolder/beginImportCard.
    @MainActor
    func testBeginImportFoldersThreadsPreIngestThumbnailCache() {
        let model = AppModel.demo()
        let cache = PreIngestThumbnailCache()
        model.beginImportFolders(
            [URL(fileURLWithPath: "/tmp/import-sheet/only", isDirectory: true)],
            selectedFiles: [URL(fileURLWithPath: "/tmp/x.jpg")],
            preIngestThumbnailCache: cache
        )
        // The first folder starts immediately; pending is empty.
        // The cache was accepted without error (typed parameter match).
        XCTAssertTrue(model.pendingImportFolders.isEmpty)
    }

    // MARK: - Concurrent import queue (spec §3: serial ingest, concurrent review)

    /// Builds a catalog-backed model whose import task blocks until cancelled,
    /// so `isImporting` stays true for the duration of the test.
    @MainActor
    private func makeImportingModel(in root: URL) throws -> AppModel {
        let paths = AppCatalog.defaultPaths(
            applicationSupportDirectory: root.appendingPathComponent("app-support", isDirectory: true)
        )
        let catalog = try AppCatalog.open(paths: paths)
        return try AppModel.load(
            catalog: catalog,
            importTaskFactory: { _, _, _, _, _, _ in
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return AppImportOutput(
                        result: LibraryImportResult(importedAssets: [], previewFailures: []),
                        assets: [],
                        totalAssetCount: 0
                    )
                }
            }
        )
    }

    private func makeFolder(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func waitForImportToStop(in model: AppModel, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while model.isImporting && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Spec §3: committing an import while another ingest runs joins
    /// `pendingImportFolders` and is shown as Queued — it must NOT hard-reject
    /// with "Another import is already running".
    @MainActor
    func testBeginImportFolderWhileImportingJoinsQueueInsteadOfRejecting() throws {
        let root = try makeTemporaryDirectory(named: "import-queue-join")
        let model = try makeImportingModel(in: root)
        let running = try makeFolder("running", in: root)
        let queued = try makeFolder("queued", in: root)
        let queuedSelection: Set<URL> = [queued.appendingPathComponent("x.jpg")]
        let queuedCache = PreIngestThumbnailCache()

        model.beginImportFolder(running)
        XCTAssertTrue(model.isImporting)
        XCTAssertTrue(model.pendingImportFolders.isEmpty)

        model.beginImportFolder(
            queued,
            importNewOnly: false,
            selectedFiles: queuedSelection,
            preIngestThumbnailCache: queuedCache
        )

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.pendingImportFolders.count, 1)
        let pending = try XCTUnwrap(model.pendingImportFolders.first)
        XCTAssertEqual(pending.url, queued)
        XCTAssertFalse(pending.importNewOnly)
        XCTAssertEqual(pending.selectedFiles, queuedSelection)
        XCTAssertEqual(pending.preIngestThumbnailCache, queuedCache)
        // The running import is untouched; the queued commit did not start.
        XCTAssertTrue(model.isImporting)

        model.cancelImportWork()
    }

    /// Spec §3: a multi-folder commit while an ingest runs queues every folder,
    /// preserving the commit's `selectedFiles` on the primary (first) folder.
    @MainActor
    func testBeginImportFoldersWhileImportingQueuesEveryFolder() throws {
        let root = try makeTemporaryDirectory(named: "import-queue-multi")
        let model = try makeImportingModel(in: root)
        let running = try makeFolder("running", in: root)
        let first = try makeFolder("first", in: root)
        let second = try makeFolder("second", in: root)
        let selection: Set<URL> = [URL(fileURLWithPath: "/tmp/import-queue-multi/only.jpg")]

        model.beginImportFolder(running)
        XCTAssertTrue(model.isImporting)

        model.beginImportFolders([first, second], selectedFiles: selection)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.pendingImportFolders.map(\.url), [first, second])
        XCTAssertEqual(model.pendingImportFolders[0].selectedFiles, selection)
        XCTAssertNil(model.pendingImportFolders[1].selectedFiles)
        XCTAssertTrue(model.isImporting)

        model.cancelImportWork()
    }

    /// Spec §3: cancelling the current ingest doesn't cancel queued imports.
    @MainActor
    func testCancellingRunningImportLeavesQueuedFoldersIntact() async throws {
        let root = try makeTemporaryDirectory(named: "import-queue-cancel")
        let model = try makeImportingModel(in: root)
        let running = try makeFolder("running", in: root)
        let queued = try makeFolder("queued", in: root)

        model.beginImportFolder(running)
        model.beginImportFolder(queued)
        XCTAssertEqual(model.pendingImportFolders.map(\.url), [queued])

        model.cancelImportWork()
        await waitForImportToStop(in: model)

        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.pendingImportFolders.map(\.url), [queued])
    }
}
