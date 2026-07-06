import Foundation
import TeststripCore

public struct WorkerRecoverySmokeResult: Equatable {
    public var assetCount: Int
    public var recoveredPreviewWorkCount: Int
    public var runningWorkCount: Int
    public var queuedWorkCount: Int
    public var dispatchedCommandCount: Int
    public var pendingPreviewCount: Int
    public var workerProcessStarted: Bool

    public init(
        assetCount: Int,
        recoveredPreviewWorkCount: Int,
        runningWorkCount: Int,
        queuedWorkCount: Int,
        dispatchedCommandCount: Int,
        pendingPreviewCount: Int,
        workerProcessStarted: Bool
    ) {
        self.assetCount = assetCount
        self.recoveredPreviewWorkCount = recoveredPreviewWorkCount
        self.runningWorkCount = runningWorkCount
        self.queuedWorkCount = queuedWorkCount
        self.dispatchedCommandCount = dispatchedCommandCount
        self.pendingPreviewCount = pendingPreviewCount
        self.workerProcessStarted = workerProcessStarted
    }
}

public struct WorkerRecoverySmoke {
    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = max(0, count)
        self.root = root
    }

    public func run() throws -> WorkerRecoverySmokeResult {
        let applicationSupportDirectory = root.appendingPathComponent("Application Support", isDirectory: true)
        let seedResult = try SmokeCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            count: count
        ).run()
        let database = try CatalogDatabase.open(at: seedResult.catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let recoveryAssets = try repository.allAssets(limit: count)
        let recoveryItems = recoveryAssets.map { PreviewGenerationItem(assetID: $0.id, level: .grid) }
        try repository.recordPreviewGenerationPending(recoveryItems)

        let transport = RecordingWorkerTransport()
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 1),
            transport: transport,
            commandTimeout: nil
        )
        try supervisor.enqueue(recoveryItems.map { pendingItem in
            (
                item: BackgroundWorkItem(
                    id: WorkSessionID(rawValue: "preview-\(pendingItem.assetID.rawValue)-\(pendingItem.level.rawValue)"),
                    kind: .previewGeneration,
                    title: "Generate \(pendingItem.level.rawValue) preview",
                    detail: pendingItem.assetID.rawValue,
                    completedUnitCount: 0,
                    totalUnitCount: 1
                ),
                command: WorkerCommand.generatePreview(assetID: pendingItem.assetID, level: pendingItem.level),
                placement: BackgroundWorkQueuePlacement.back
            )
        })
        let runningItems = supervisor.queue.runningItems
        let queuedItems = supervisor.queue.queuedItems

        return WorkerRecoverySmokeResult(
            assetCount: try repository.assetCount(),
            recoveredPreviewWorkCount: runningItems.count + queuedItems.count,
            runningWorkCount: runningItems.count,
            queuedWorkCount: queuedItems.count,
            dispatchedCommandCount: transport.lines.count,
            pendingPreviewCount: try repository.pendingPreviewGenerationItems().count,
            workerProcessStarted: transport.isRunning
        )
    }
}

private final class RecordingWorkerTransport: WorkerTransport {
    var outputHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?

    private(set) var lines: [String] = []
    private(set) var isRunning = false

    func launch() throws {
        isRunning = true
    }

    func writeLine(_ line: String) throws {
        lines.append(line)
    }

    func terminate() {
        isRunning = false
    }
}
