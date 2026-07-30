import Observation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-C Task 2: the cull loupe's per-frame request turns the Task 1 planner's
// warm set into gated queue requests (dedup against cache/exhausted attempts/
// availability), and a window slide cancels undispatched stragglers from the
// old window while leaving anything already in flight to finish.
final class CullPrefetchDriverTests: XCTestCase {
    private func id(_ raw: String) -> AssetID { AssetID(rawValue: raw) }

    // Shared fixture for every test: one burst of four (captures ~1s apart),
    // then three singletons 30s+ apart, then a final burst of two -- so the
    // stop sequence is [burst-1..4] [solo-1] [solo-2] [solo-3] [burst-5..6].
    // Returned fresh per call so a test can tweak one entry (e.g. an offline
    // sibling) without mutating shared state.
    private func makeFixtureAssets() -> [Asset] {
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        return [
            makeAsset(
                id: "burst-1",
                path: "/Photos/Job/burst-1.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
            ),
            makeAsset(
                id: "burst-2",
                path: "/Photos/Job/burst-2.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
            ),
            makeAsset(
                id: "burst-3",
                path: "/Photos/Job/burst-3.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
            ),
            makeAsset(
                id: "burst-4",
                path: "/Photos/Job/burst-4.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2.6))
            ),
            makeAsset(
                id: "solo-1",
                path: "/Photos/Job/solo-1.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(40))
            ),
            makeAsset(
                id: "solo-2",
                path: "/Photos/Job/solo-2.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(80))
            ),
            makeAsset(
                id: "solo-3",
                path: "/Photos/Job/solo-3.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(120))
            ),
            makeAsset(
                id: "burst-5",
                path: "/Photos/Job/burst-5.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(160))
            ),
            makeAsset(
                id: "burst-6",
                path: "/Photos/Job/burst-6.cr2",
                technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(161))
            )
        ]
    }

    func testCullPreviewRequestWarmsBurstSiblingsAndNextLandings() throws {
        let (model, _, _) = try makeModel(
            named: "cull-prefetch-warms-siblings",
            assets: makeFixtureAssets(),
            supervisor: WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: RecordingWorkerTransport())
        )

        try model.requestVisibleCullPreview(assetID: id("burst-2"))

        let previewItems = model.backgroundWorkQueue.items.filter { $0.kind == .previewGeneration }
        let itemIDs = Set(previewItems.map(\.id))
        // Siblings warm...
        XCTAssertTrue(itemIDs.contains(previewItemID("burst-3")))
        XCTAssertTrue(itemIDs.contains(previewItemID("burst-4")))
        XCTAssertTrue(itemIDs.contains(previewItemID("burst-1")))
        // ...and the next three stops' landings, plus no fourth-stop reach.
        XCTAssertTrue(itemIDs.contains(previewItemID("solo-1")))
        XCTAssertTrue(itemIDs.contains(previewItemID("solo-2")))
        XCTAssertTrue(itemIDs.contains(previewItemID("solo-3")))
        XCTAssertFalse(itemIDs.contains(previewItemID("burst-5")))
    }

    // Ambiguity note (see task-2-report.md): with `maxRunningCount: 1` and an
    // empty queue, the FIRST sibling the driver successfully requests claims
    // the sole running slot and stays there (RecordingWorkerTransport never
    // completes it). The planner's tested order (CullPrefetchPlannerTests)
    // radiates outward staged-forward-first, so for staged burst-2 that is
    // burst-3, burst-4, burst-1 in that order -- burst-3 is the one that
    // actually starts running, not burst-4/burst-1. The brief's sketch
    // asserted `.cancelled` for burst-3; empirically it is burst-1 (the
    // *third* item requested, forced to `.queued` behind burst-3) that joins
    // burst-4 as a cancelled straggler. Adapted below to assert the running
    // item's identity explicitly rather than weaken the check.
    func testWindowSlideCancelsUndispatchedOutOfWindowItems() throws {
        let (model, _, _) = try makeModel(
            named: "cull-prefetch-window-slide",
            assets: makeFixtureAssets(),
            supervisor: WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: RecordingWorkerTransport())
        )

        try model.requestVisibleCullPreview(assetID: id("burst-2"))
        // Slide far forward: burst-5 window no longer wants burst-1..4 warming.
        try model.requestVisibleCullPreview(assetID: id("burst-5"))

        let queue = model.backgroundWorkQueue
        // The straggler that claimed the sole running slot is left to finish...
        XCTAssertEqual(queue.item(id: previewItemID("burst-3"))?.status, .running)
        // ...the still-undispatched stragglers from the old window are cancelled...
        XCTAssertEqual(queue.item(id: previewItemID("burst-4"))?.status, .cancelled)
        XCTAssertEqual(queue.item(id: previewItemID("burst-1"))?.status, .cancelled)
        // ...only the one already running stays active (maxRunningCount 1 ran the first)...
        XCTAssertEqual(queue.runningItems.count, 1)
        // ...and the new window is queued.
        XCTAssertNotEqual(queue.item(id: previewItemID("burst-6"))?.status, .cancelled)
        XCTAssertNotNil(queue.item(id: previewItemID("burst-6")))
    }

    func testOfflineSiblingIsNeverRequested() throws {
        var assets = makeFixtureAssets()
        guard let burst3Index = assets.firstIndex(where: { $0.id == id("burst-3") }) else {
            return XCTFail("fixture is missing burst-3")
        }
        assets[burst3Index].availability = .offline
        let (model, _, _) = try makeModel(
            named: "cull-prefetch-offline-sibling",
            assets: assets,
            supervisor: WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: RecordingWorkerTransport())
        )

        try model.requestVisibleCullPreview(assetID: id("burst-2"))

        XCTAssertNil(model.backgroundWorkQueue.item(id: previewItemID("burst-3")))
    }

    func testAttemptExhaustedSiblingIsNeverRequested() throws {
        let (model, repository, _) = try makeModel(
            named: "cull-prefetch-exhausted-sibling",
            assets: makeFixtureAssets(),
            supervisor: WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: RecordingWorkerTransport())
        )
        for _ in 0..<3 {
            try repository.recordPreviewGenerationFailure(assetID: id("burst-3"), level: .large, errorMessage: "boom")
        }

        try model.requestVisibleCullPreview(assetID: id("burst-2"))

        XCTAssertNil(model.backgroundWorkQueue.item(id: previewItemID("burst-3")))
    }

    func testAlreadyCachedSiblingIsNeverRequested() throws {
        let (model, _, previewCache) = try makeModel(
            named: "cull-prefetch-cached-sibling",
            assets: makeFixtureAssets(),
            supervisor: WorkerSupervisor(queue: BackgroundWorkQueue(maxRunningCount: 1), transport: RecordingWorkerTransport())
        )
        try writePreviewPlaceholder(to: previewCache.url(for: PreviewCacheKey(assetID: id("burst-3"), level: .large)))

        try model.requestVisibleCullPreview(assetID: id("burst-2"))

        XCTAssertNil(model.backgroundWorkQueue.item(id: previewItemID("burst-3")))
    }

    // MARK: - Fixtures (mirrors StackDecisionTests' private helpers; kept local per file)

    private func makeAsset(
        id: String,
        path: String,
        technicalMetadata: AssetTechnicalMetadata? = nil,
        metadata: AssetMetadata = AssetMetadata()
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata,
            technicalMetadata: technicalMetadata
        )
    }

    private static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writePreviewPlaceholder(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: url)
    }

    private func makeModel(
        named name: String,
        assets: [Asset],
        supervisor: WorkerSupervisor
    ) throws -> (model: AppModel, repository: CatalogRepository, previewCache: PreviewCache) {
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
        let model = try AppModel.load(catalog: catalog, workerSupervisor: supervisor)
        return (model, repository, previewCache)
    }

    private func previewItemID(_ assetID: String) -> WorkSessionID {
        WorkSessionID(rawValue: "preview-\(assetID)-large")
    }
}

/// Records the JSON-lines commands `WorkerSupervisor` would send to the
/// out-of-process worker without ever completing them, so an enqueued preview
/// generation item stays exactly at whatever status the queue's own
/// running/queued bookkeeping assigned it -- letting these tests assert
/// dispatch order deterministically. Mirrors `AppModelTests`' private type of
/// the same name (kept local per file per Swift's file-private access).
private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    var terminationHandler: (() -> Void)?

    private(set) var lines: [String] = []
    private(set) var terminateCount = 0
    private(set) var isRunning = false

    func launch() throws {
        isRunning = true
    }

    func writeLine(_ line: String) throws {
        lines.append(line)
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func commands() throws -> [WorkerCommand] {
        try lines.map { try WorkerProtocolEncoder.decode($0) }
    }

    func emitOutputLine(_ line: String) {
        outputHandler?(line)
    }

    func emitErrorLine(_ line: String) {
        errorHandler?(line)
    }
}
