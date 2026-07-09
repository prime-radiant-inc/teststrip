import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class AppDiagnosticsTests: XCTestCase {
    @MainActor
    func testDiagnosticsSnapshotIncludesCatalogWorkerQueueSourceAndFailureState() throws {
        let directory = try makeTemporaryDirectory(named: "app-diagnostics")
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let workerURL = directory.appendingPathComponent("TeststripWorker")
        let runningPreview = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "preview-running"),
            kind: .previewGeneration,
            title: "Generate previews",
            detail: "Rendering grid previews",
            status: .running,
            completedUnitCount: 4,
            totalUnitCount: 10
        )
        let queuedXMP = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "xmp-queued"),
            kind: .xmpSync,
            title: "Sync XMP",
            detail: "Writing sidecar",
            status: .queued,
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        let failedRecognition = BackgroundWorkItem(
            id: WorkSessionID(rawValue: "recognition-failed"),
            kind: .recognition,
            title: "Analyze photo",
            detail: "Local model timeout",
            status: .failed,
            completedUnitCount: 0,
            totalUnitCount: 1
        )
        let workerQueue = BackgroundWorkQueue(
            maxRunningCount: 2,
            items: [runningPreview, queuedXMP, failedRecognition]
        )
        let transport = AppDiagnosticsRecordingWorkerTransport()
        try transport.launch()
        let workerSupervisor = WorkerSupervisor(
            queue: workerQueue,
            transport: transport
        )
        let recentFailure = AppWorkActivity(
            id: "import-failed",
            kind: .ingest,
            status: .failed,
            title: "Import photos",
            detail: "NAS disconnected",
            completedUnitCount: 12,
            totalUnitCount: 80,
            failureCount: 1
        )
        let pendingSync = MetadataSyncItem(
            assetID: AssetID(rawValue: "pending-sync"),
            sidecarURL: directory.appendingPathComponent("pending.xmp"),
            catalogGeneration: 2,
            lastSyncedFingerprint: nil
        )
        let conflict = MetadataSyncItem(
            assetID: AssetID(rawValue: "conflict"),
            sidecarURL: directory.appendingPathComponent("conflict.xmp"),
            catalogGeneration: 3,
            lastSyncedFingerprint: "old"
        )
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [],
            totalAssetCount: 42,
            catalog: catalog,
            recentWork: [recentFailure],
            pendingMetadataSyncItems: [pendingSync],
            metadataSyncConflictItems: [conflict],
            backgroundWorkQueue: BackgroundWorkQueue(maxRunningCount: 1),
            sourceRoots: [
                CatalogSourceRoot(
                    path: "/Volumes/Archive",
                    name: "Archive",
                    assetCount: 20,
                    unavailableAssetCount: 7,
                    securityScopedBookmarkData: Data("bookmark".utf8)
                )
            ],
            sourceAvailabilitySummaries: [
                CatalogSourceAvailabilitySummary(availability: .online, assetCount: 35),
                CatalogSourceAvailabilitySummary(availability: .offline, assetCount: 7)
            ],
            workerSupervisor: workerSupervisor,
            workerExecutableURL: workerURL
        )

        let diagnostics = model.diagnosticsSnapshot

        XCTAssertEqual(diagnostics.catalogRootPath, paths.root.path)
        XCTAssertEqual(diagnostics.catalogDatabasePath, paths.catalogURL.path)
        XCTAssertEqual(diagnostics.previewCachePath, paths.previewCacheRoot.path)
        XCTAssertEqual(diagnostics.workerExecutablePath, workerURL.path)
        XCTAssertTrue(diagnostics.workerEnabled)
        XCTAssertTrue(diagnostics.workerProcessRunning)
        XCTAssertEqual(diagnostics.loadedAssetCount, 0)
        XCTAssertEqual(diagnostics.totalAssetCount, 42)
        XCTAssertEqual(diagnostics.pendingBackgroundWorkCount, 2)
        XCTAssertEqual(diagnostics.pendingMetadataSyncCount, 1)
        XCTAssertEqual(diagnostics.metadataSyncConflictCount, 1)
        XCTAssertEqual(diagnostics.backgroundWork.maxRunningCount, 2)
        XCTAssertEqual(diagnostics.backgroundWork.statusCounts, [
            AppDiagnosticsWorkStatusCount(status: .queued, count: 1),
            AppDiagnosticsWorkStatusCount(status: .running, count: 1),
            AppDiagnosticsWorkStatusCount(status: .failed, count: 1)
        ])
        XCTAssertEqual(diagnostics.backgroundWork.kindCounts, [
            AppDiagnosticsWorkKindCount(kind: .previewGeneration, count: 1),
            AppDiagnosticsWorkKindCount(kind: .recognition, count: 1),
            AppDiagnosticsWorkKindCount(kind: .xmpSync, count: 1)
        ])
        XCTAssertEqual(diagnostics.sourceAvailabilityCounts, [
            AppDiagnosticsSourceAvailabilityCount(availability: .offline, count: 7),
            AppDiagnosticsSourceAvailabilityCount(availability: .online, count: 35)
        ])
        XCTAssertEqual(diagnostics.sourceRoots, [
            AppDiagnosticsSourceRoot(
                path: "/Volumes/Archive",
                name: "Archive",
                assetCount: 20,
                unavailableAssetCount: 7,
                hasSecurityScopedBookmark: true,
                needsSecurityScopedBookmarkRepair: true
            )
        ])
        XCTAssertEqual(diagnostics.recentFailures, [
            AppDiagnosticsFailure(
                id: "recognition-failed",
                kind: .recognition,
                title: "Analyze photo",
                detail: "Local model timeout",
                failureCount: 0
            ),
            AppDiagnosticsFailure(
                id: "import-failed",
                kind: .ingest,
                title: "Import photos",
                detail: "NAS disconnected",
                failureCount: 1
            )
        ])
        XCTAssertTrue(model.diagnosticsReportText.contains("Catalog database: \(paths.catalogURL.path)"))
        XCTAssertTrue(model.diagnosticsReportText.contains("Worker process: running"))
        XCTAssertTrue(model.diagnosticsReportText.contains("XMP pending/conflicts: 1/1"))
        XCTAssertTrue(model.diagnosticsReportText.contains("bookmark repair needed"))
        XCTAssertTrue(model.diagnosticsReportText.contains("recognition recognition-failed: Local model timeout"))
    }

    @MainActor
    func testDiagnosticsSnapshotHandlesDemoModelWithoutCatalogOrWorker() {
        let diagnostics = AppModel.demo().diagnosticsSnapshot

        XCTAssertNil(diagnostics.catalogRootPath)
        XCTAssertNil(diagnostics.catalogDatabasePath)
        XCTAssertNil(diagnostics.previewCachePath)
        XCTAssertNil(diagnostics.workerExecutablePath)
        XCTAssertFalse(diagnostics.workerEnabled)
        XCTAssertFalse(diagnostics.workerProcessRunning)
        XCTAssertEqual(diagnostics.pendingBackgroundWorkCount, 0)
        XCTAssertEqual(diagnostics.recentFailures, [])
        XCTAssertTrue(AppModel.demo().diagnosticsReportText.contains("Catalog database: Unavailable"))
    }

    @MainActor
    func testDiagnosticsSnapshotDistinguishesConfiguredWorkerPathFromEnabledWorker() throws {
        let directory = try makeTemporaryDirectory(named: "app-diagnostics-missing-worker")
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let missingWorkerURL = directory.appendingPathComponent("missing-worker")

        let model = try AppCatalog.loadModel(paths: paths, workerExecutableURL: missingWorkerURL)
        let diagnostics = model.diagnosticsSnapshot

        XCTAssertEqual(diagnostics.workerExecutablePath, missingWorkerURL.path)
        XCTAssertTrue(diagnostics.workerConfigured)
        XCTAssertFalse(diagnostics.workerEnabled)
        XCTAssertFalse(diagnostics.workerProcessRunning)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class AppDiagnosticsRecordingWorkerTransport: WorkerTransport {
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
